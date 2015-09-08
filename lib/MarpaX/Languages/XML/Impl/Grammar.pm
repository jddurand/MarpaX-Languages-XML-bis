package MarpaX::Languages::XML::Impl::Grammar;
use Carp qw/croak/;
use Data::Section -setup;
use Marpa::R2;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Type::GrammarEvent -all;
use MarpaX::Languages::XML::Type::XmlVersion -all;
use MarpaX::Languages::XML::Type::CharacterAndEntityReferences -all;
use Moo;
use MooX::late;
use MooX::Role::Logger;
use MooX::HandlesVia;
use Scalar::Util qw/blessed reftype/;
use Types::Standard -all;

# ABSTRACT: MarpaX::Languages::XML::Role::Grammar implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is an implementation of MarpaX::Languages::XML::Role::Grammar. It provides Marpa::R2::Scanless::G's class attributes for XML versions 1.0 and 1.1.

=cut

has _attvalue => (
                  is     => 'ro',
                  isa    => HashRef[CodeRef],
                  default => sub {
                    {
                      '1.0' => \&_attvalue_xml10,
                      '1.1' => \&_attvalue_xml11
                      }
                  },
                  handles_via => 'Hash',
                  handles => {
                              _get__attvalue  => 'get'
                             }
                 );

has _eol => (
             is     => 'ro',
             isa    => HashRef[CodeRef],
             default => sub {
               {
                 '1.0' => \&_eol_xml10,
                 '1.1' => \&_eol_xml11
                 }
             },
             handles_via => 'Hash',
             handles => {
                         _get__eol  => 'get'
                        }
            );

has scanless => (
                 is     => 'ro',
                 isa    => InstanceOf['Marpa::R2::Scanless::G'],
                 lazy  => 1,
                 builder => '_build_scanless'
                );

has lexeme_regexp => (
                      is  => 'ro',
                      isa => HashRef[RegexpRef],
                      lazy  => 1,
                      builder => '_build_lexeme_regexp',
                      handles_via => 'Hash',
                      handles => {
                                  elements_lexeme_regexp  => 'elements',
                                  keys_lexeme_regexp      => 'keys',
                                  set_lexeme_regexp       => 'set',
                                  get_lexeme_regexp       => 'get',
                                  exists_lexeme_regexp    => 'exists'
                                 }
                      );

has lexeme_exclusion => (
                         is  => 'ro',
                         isa => HashRef[RegexpRef],
                         lazy  => 1,
                         builder => '_build_lexeme_exclusion',
                         handles_via => 'Hash',
                         handles => {
                                     elements_lexeme_exclusion => 'elements',
                                     keys_lexeme_exclusion     => 'keys',
                                     set_lexeme_exclusion      => 'set',
                                     get_lexeme_exclusion      => 'get',
                                     exists_lexeme_exclusion   => 'exists'
                                    }
                         );
has grammar_event => (
                      is  => 'ro',
                      isa => HashRef[GrammarEvent],
                      default => sub { {} },
                      handles_via => 'Hash',
                      handles => {
                                  elements_grammar_event => 'elements',
                                  keys_grammar_event     => 'keys',
                                  set_grammar_event      => 'set',
                                  get_grammar_event      => 'get',
                                  exists_grammar_event   => 'exists'
                                 }
                      );

has xml_version => (
                    is  => 'ro',
                    isa => XmlVersion,
                    default => '1.0'
                   );

has start => (
              is  => 'ro',
              isa => Str,
              default => 'document'
             );

our %XMLBNF = (
               '1.0' => __PACKAGE__->section_data('xml10'),
               '1.1' => __PACKAGE__->section_data('xml10')
              );
our %GRAMMAR_EVENT_COMMON =
  (
   #
   # These G1 events are lexemes predictions, but BEFORE the input stream is tentatively read by Marpa
   #
   '^NAME'                          => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'NAME',                          lexeme => '_NAME' },
   '^NMTOKENMANY'                   => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'NMTOKENMANY',                   lexeme => '_NMTOKENMANY' },
   '^ENTITYVALUEINTERIORDQUOTEUNIT' => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITYVALUEINTERIORDQUOTEUNIT', lexeme => '_ENTITYVALUEINTERIORDQUOTEUNIT' },
   '^ENTITYVALUEINTERIORSQUOTEUNIT' => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITYVALUEINTERIORSQUOTEUNIT', lexeme => '_ENTITYVALUEINTERIORSQUOTEUNIT' },
   '^ATTVALUEINTERIORDQUOTEUNIT'    => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ATTVALUEINTERIORDQUOTEUNIT',    lexeme => '_ATTVALUEINTERIORDQUOTEUNIT' },
   '^ATTVALUEINTERIORSQUOTEUNIT'    => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ATTVALUEINTERIORSQUOTEUNIT',    lexeme => '_ATTVALUEINTERIORSQUOTEUNIT' },
   '^NOT_DQUOTEMANY'                => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'NOT_DQUOTEMANY',                lexeme => '_NOT_DQUOTEMANY' },
   '^NOT_SQUOTEMANY'                => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'NOT_SQUOTEMANY',                lexeme => '_NOT_SQUOTEMANY' },
   '^PUBIDCHARDQUOTE'               => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'PUBIDCHARDQUOTE',               lexeme => '_PUBIDCHARDQUOTE' },
   '^PUBIDCHARSQUOTE'               => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'PUBIDCHARSQUOTE',               lexeme => '_PUBIDCHARSQUOTE' },
   '^CHARDATAMANY'                  => { fixed_length => 0, type => 'predicted', min_chars =>  3, symbol_name => 'CHARDATAMANY',                  lexeme => '_CHARDATAMANY' },    # [^<&]+ without ']]>'
   '^COMMENTCHARMANY'               => { fixed_length => 0, type => 'predicted', min_chars =>  2, symbol_name => 'COMMENTCHARMANY',               lexeme => '_COMMENTCHARMANY' }, # Char* without '--'
   '^PITARGET'                      => { fixed_length => 0, type => 'predicted', min_chars =>  3, symbol_name => 'PITARGET',                      lexeme => '_PITARGET' },        # NAME but /xml/i
   '^CDATAMANY'                     => { fixed_length => 0, type => 'predicted', min_chars =>  3, symbol_name => 'CDATAMANY',                     lexeme => '_CDATAMANY' },       # Char* minus ']]>'
   '^PICHARDATAMANY'                => { fixed_length => 0, type => 'predicted', min_chars =>  2, symbol_name => 'PICHARDATAMANY',                lexeme => '_PICHARDATAMANY' },  # Char* minus '?>'
   '^IGNOREMANY'                    => { fixed_length => 0, type => 'predicted', min_chars =>  3, symbol_name => 'IGNOREMANY',                    lexeme => '_IGNOREMANY' },      # Char minus* ('<![' or ']]>')
   '^DIGITMANY'                     => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'DIGITMANY',                     lexeme => '_DIGITMANY' },
   '^ALPHAMANY'                     => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ALPHAMANY',                     lexeme => '_ALPHAMANY' },
   '^ENCNAME'                       => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ENCNAME',                       lexeme => '_ENCNAME' },
   '^S'                             => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'S',                             lexeme => '_S' },
   #
   # These are the lexemes of predicted size
   #
   '^SPACE'                         => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'SPACE',                        lexeme => '_SPACE' },
   '^DQUOTE'                        => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'DQUOTE',                       lexeme => '_DQUOTE' },
   '^SQUOTE'                        => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'SQUOTE',                       lexeme => '_SQUOTE' },
   '^COMMENT_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  4, symbol_name => 'COMMENT_START',                lexeme => '_COMMENT_START' },
   '^COMMENT_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'COMMENT_END',                  lexeme => '_COMMENT_END' },
   '^PI_START'                      => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'PI_START',                     lexeme => '_PI_START' },
   '^PI_END'                        => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'PI_END',                       lexeme => '_PI_END' },
   '^CDATA_START'                   => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'CDATA_START',                  lexeme => '_CDATA_START' },
   '^CDATA_END'                     => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'CDATA_END',                    lexeme => '_CDATA_END' },
   '^XMLDECL_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'XMLDECL_START',                lexeme => '_XMLDECL_START' },
   '^XMLDECL_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'XMLDECL_END',                  lexeme => '_XMLDECL_END' },
   '^VERSION'                       => { fixed_length => 1, type => 'predicted', min_chars =>  7, symbol_name => 'VERSION',                      lexeme => '_VERSION' },
   '^EQUAL'                         => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'EQUAL',                        lexeme => '_EQUAL' },
   '^VERSIONNUM'                    => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'VERSIONNUM',                   lexeme => '_VERSIONNUM' },
   '^DOCTYPE_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'DOCTYPE_START',                lexeme => '_DOCTYPE_START' },
   '^DOCTYPE_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'DOCTYPE_END',                  lexeme => '_DOCTYPE_END' },
   '^LBRACKET'                      => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'LBRACKET',                     lexeme => '_LBRACKET' },
   '^RBRACKET'                      => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'RBRACKET',                     lexeme => '_RBRACKET' },
   '^STANDALONE'                    => { fixed_length => 1, type => 'predicted', min_chars => 10, symbol_name => 'STANDALONE',                   lexeme => '_STANDALONE' },
   '^YES'                           => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'YES',                          lexeme => '_YES' },
   '^NO'                            => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'NO',                           lexeme => '_NO' },
   '^ELEMENT_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ELEMENT_START',                lexeme => '_ELEMENT_START' },
   '^ELEMENT_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ELEMENT_END',                  lexeme => '_ELEMENT_END' },
   '^ETAG_START'                    => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'ETAG_START',                   lexeme => '_ETAG_START' },
   '^ETAG_END'                      => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ETAG_END',                     lexeme => '_ETAG_END' },
   '^EMPTYELEM_END'                 => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'EMPTYELEM_END',                lexeme => '_EMPTYELEM_END' },
   '^ELEMENTDECL_START'             => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'ELEMENTDECL_START',            lexeme => '_ELEMENTDECL_START' },
   '^ELEMENTDECL_END'               => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ELEMENTDECL_END',              lexeme => '_ELEMENTDECL_END' },
   '^EMPTY'                         => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'EMPTY',                        lexeme => '_EMPTY' },
   '^ANY'                           => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'ANY',                          lexeme => '_ANY' },
   '^QUESTIONMARK'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'QUESTIONMARK',                 lexeme => '_QUESTIONMARK' },
   '^STAR'                          => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'STAR',                         lexeme => '_STAR' },
   '^PLUS'                          => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'PLUS',                         lexeme => '_PLUS' },
   '^OR'                            => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'OR',                           lexeme => '_OR' },
   '^CHOICE_START'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'CHOICE_START',                 lexeme => '_CHOICE_START' },
   '^CHOICE_END'                    => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'CHOICE_END',                   lexeme => '_CHOICE_END' },
   '^SEQ_START'                     => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'SEQ_START',                    lexeme => '_SEQ_START' },
   '^SEQ_END'                       => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'SEQ_END',                      lexeme => '_SEQ_END' },
   '^MIXED_START1'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'MIXED_START1',                 lexeme => '_MIXED_START1' },
   '^MIXED_END1'                    => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'MIXED_END1',                   lexeme => '_MIXED_END1' },
   '^MIXED_START2'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'MIXED_START2',                 lexeme => '_MIXED_START2' },
   '^MIXED_END2'                    => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'MIXED_END2',                   lexeme => '_MIXED_END2' },
   '^COMMA'                         => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'COMMA',                        lexeme => '_COMMA' },
   '^PCDATA'                        => { fixed_length => 1, type => 'predicted', min_chars =>  7, symbol_name => 'PCDATA',                       lexeme => '_PCDATA' },
   '^ATTLIST_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'ATTLIST_START',                lexeme => '_ATTLIST_START' },
   '^ATTLIST_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ATTLIST_END',                  lexeme => '_ATTLIST_END' },
   '^CDATA'                         => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'CDATA',                        lexeme => '_CDATA' },
   '^ID'                            => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'ID',                           lexeme => '_ID' },
   '^IDREF'                         => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'IDREF',                        lexeme => '_IDREF' },
   '^IDREFS'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'IDREFS',                       lexeme => '_IDREFS' },
   '^ENTITY'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'ENTITY',                       lexeme => '_ENTITY' },
   '^ENTITIES'                      => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'ENTITIES',                     lexeme => '_ENTITIES' },
   '^NMTOKEN'                       => { fixed_length => 1, type => 'predicted', min_chars =>  7, symbol_name => 'NMTOKEN',                      lexeme => '_NMTOKEN' },
   '^NMTOKENS'                      => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'NMTOKENS',                     lexeme => '_NMTOKENS' },
   '^NOTATION'                      => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'NOTATION',                     lexeme => '_NOTATION' },
   '^NOTATION_START'                => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'NOTATION_START',               lexeme => '_NOTATION_START' },
   '^NOTATION_END'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'NOTATION_END',                 lexeme => '_NOTATION_END' },
   '^ENUMERATION_START'             => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENUMERATION_START',            lexeme => '_ENUMERATION_START' },
   '^ENUMERATION_END'               => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENUMERATION_END',              lexeme => '_ENUMERATION_END' },
   '^REQUIRED'                      => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'REQUIRED',                     lexeme => '_REQUIRED' },
   '^IMPLIED'                       => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'IMPLIED',                      lexeme => '_IMPLIED' },
   '^FIXED'                         => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'FIXED',                        lexeme => '_FIXED' },
   '^INCLUDE'                       => { fixed_length => 1, type => 'predicted', min_chars =>  7, symbol_name => 'INCLUDE',                      lexeme => '_INCLUDE' },
   '^IGNORE'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'IGNORE',                       lexeme => '_IGNORE' },
   '^INCLUDESECT_START'             => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'INCLUDESECT_START',            lexeme => '_INCLUDESECT_START' },
   '^INCLUDESECT_END'               => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'INCLUDESECT_END',              lexeme => '_INCLUDESECT_END' },
   '^IGNORESECT_START'              => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'IGNORESECT_START',             lexeme => '_IGNORESECT_START' },
   '^IGNORESECT_END'                => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'IGNORESECT_END',               lexeme => '_IGNORESECT_END' },
   '^IGNORESECTCONTENTSUNIT_START'  => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'IGNORESECTCONTENTSUNIT_START', lexeme => '_IGNORESECTCONTENTSUNIT_START' },
   '^IGNORESECTCONTENTSUNIT_END'    => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'IGNORESECTCONTENTSUNIT_END',   lexeme => '_IGNORESECTCONTENTSUNIT_END' },
   '^CHARREF_START1'                => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'CHARREF_START1',               lexeme => '_CHARREF_START1' },
   '^CHARREF_END1'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'CHARREF_END1',                 lexeme => '_CHARREF_END1' },
   '^CHARREF_START2'                => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'CHARREF_START2',               lexeme => '_CHARREF_START2' },
   '^CHARREF_END2'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'CHARREF_END2',                 lexeme => '_CHARREF_END2' },
   '^ENTITYREF_START'               => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITYREF_START',              lexeme => '_ENTITYREF_START' },
   '^ENTITYREF_END'                 => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITYREF_END',                lexeme => '_ENTITYREF_END' },
   '^PEREFERENCE_START'             => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'PEREFERENCE_START',            lexeme => '_PEREFERENCE_START' },
   '^PEREFERENCE_END'               => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'PEREFERENCE_END',              lexeme => '_PEREFERENCE_END' },
   '^ENTITY_START'                  => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'ENTITY_START',                 lexeme => '_ENTITY_START' },
   '^ENTITY_END'                    => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITY_END',                   lexeme => '_ENTITY_END' },
   '^PERCENT'                       => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'PERCENT',                      lexeme => '_PERCENT' },
   '^SYSTEM'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'SYSTEM',                       lexeme => '_SYSTEM' },
   '^PUBLIC'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'PUBLIC',                       lexeme => '_PUBLIC' },
   '^NDATA'                         => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'NDATA',                        lexeme => '_NDATA' },
   '^TEXTDECL_START'                => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'TEXTDECL_START',               lexeme => '_TEXTDECL_START' },
   '^TEXTDECL_END'                  => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'TEXTDECL_END',                 lexeme => '_TEXTDECL_END' },
   '^ENCODING'                      => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'ENCODING',                     lexeme => '_ENCODING' },
   '^NOTATIONDECL_START'            => { fixed_length => 1, type => 'predicted', min_chars => 10, symbol_name => 'NOTATIONDECL_START',           lexeme => '_NOTATIONDECL_START' },
   '^NOTATIONDECL_END'              => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'NOTATIONDECL_END',             lexeme => '_NOTATIONDECL_END' },
                            );

our %GRAMMAR_EVENT =
  (
   '1.0' => \%GRAMMAR_EVENT_COMMON,
   '1.1' => \%GRAMMAR_EVENT_COMMON
  );

our %LEXEME_REGEXP_COMMON =
  (
   #
   # These are the lexemes of unknown size
   #
   _NAME                          => qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*},
   _NMTOKENMANY                   => qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]+},
   _ENTITYVALUEINTERIORDQUOTEUNIT => qr{\G[^%&"]+},
   _ENTITYVALUEINTERIORSQUOTEUNIT => qr{\G[^%&']+},
   _ATTVALUEINTERIORDQUOTEUNIT    => qr{\G[^<&"]+},
   _ATTVALUEINTERIORSQUOTEUNIT    => qr{\G[^<&']+},
   _NOT_DQUOTEMANY                => qr{\G[^"]+},
   _NOT_SQUOTEMANY                => qr{\G[^']+},
   _PUBIDCHARDQUOTE               => qr{\G[a-zA-Z0-9\-'()+,./:=?;!*#@\$_%\x{20}\x{D}\x{A}]},
   _PUBIDCHARSQUOTE               => qr{\G[a-zA-Z0-9\-()+,./:=?;!*#@\$_%\x{20}\x{D}\x{A}]},
   _CHARDATAMANY                  => qr{\G(?:[^<&\]]|(?:\](?!\]>)))+}, # [^<&]+ without ']]>'
   _COMMENTCHARMANY               => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{2C}\x{2E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\-(?!\-)))+},  # Char* without '--'
   _PITARGET                      => qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*},  # NAME but /xml/i
   _CDATAMANY                     => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{5C}\x{5E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\](?!\]>)))+},  # Char* minus ']]>'
   _PICHARDATAMANY                => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{3E}\x{40}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\?(?!>)))+},  # Char* minus '?>'
   _IGNOREMANY                    => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{3B}\x{3D}-\x{5C}\x{5E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:<(?!!\[))|(?:\](?!\]>)))+},  # Char minus* ('<![' or ']]>')
   _DIGITMANY                     => qr{\G[0-9]+},
   _ALPHAMANY                     => qr{\G[0-9a-fA-F]+},
   _ENCNAME                       => qr{\G[A-Za-z][A-Za-z0-9._\-]*},
   _S                             => qr{\G[\x{20}\x{9}\x{D}\x{A}]+},
   #
   # These are the lexemes of predicted size
   #
   _SPACE                         => qr{\G\x{20}},
   _DQUOTE                        => qr{\G"},
   _SQUOTE                        => qr{\G'},
   _COMMENT_START                 => qr{\G<!\-\-},
   _COMMENT_END                   => qr{\G\-\->},
   _PI_START                      => qr{\G<\?},
   _PI_END                        => qr{\G\?>},
   _CDATA_START                   => qr{\G<!\[CDATA\[},
   _CDATA_END                     => qr{\G\]\]>},
   _XMLDECL_START                 => qr{\G<\?xml},
   _XMLDECL_END                   => qr{\G\?>},
   _VERSION                       => qr{\Gversion},
   _EQUAL                         => qr{\G=},
   _VERSIONNUM                    => qr{\G1\.0},
   _DOCTYPE_START                 => qr{\G<!DOCTYPE},
   _DOCTYPE_END                   => qr{\G>},
   _LBRACKET                      => qr{\G\[},
   _RBRACKET                      => qr{\G\]},
   _STANDALONE                    => qr{\Gstandalone},
   _YES                           => qr{\Gyes},
   _NO                            => qr{\Gno},
   _ELEMENT_START                 => qr{\G<},
   _ELEMENT_END                   => qr{\G>},
   _ETAG_START                    => qr{\G</},
   _ETAG_END                      => qr{\G>},
   _EMPTYELEM_END                 => qr{\G/>},
   _ELEMENTDECL_START             => qr{\G<!ELEMENT},
   _ELEMENTDECL_END               => qr{\G>},
   _EMPTY                         => qr{\GEMPTY},
   _ANY                           => qr{\GANY},
   _QUESTIONMARK                  => qr{\G\?},
   _STAR                          => qr{\G\*},
   _PLUS                          => qr{\G\+},
   _OR                            => qr{\G\|},
   _CHOICE_START                  => qr{\G\(},
   _CHOICE_END                    => qr{\G\)},
   _SEQ_START                     => qr{\G\(},
   _SEQ_END                       => qr{\G\)},
   _MIXED_START1                  => qr{\G\(},
   _MIXED_END1                    => qr{\G\)\*},
   _MIXED_START2                  => qr{\G\(},
   _MIXED_END2                    => qr{\G\)},
   _COMMA                         => qr{\G,},
   _PCDATA                        => qr{\G#PCDATA},
   _ATTLIST_START                 => qr{\G<!ATTLIST},
   _ATTLIST_END                   => qr{\G>},
   _CDATA                         => qr{\GCDATA},
   _ID                            => qr{\GID},
   _IDREF                         => qr{\GIDREF},
   _IDREFS                        => qr{\GIDREFS},
   _ENTITY                        => qr{\GENTITY},
   _ENTITIES                      => qr{\GENTITIES},
   _NMTOKEN                       => qr{\GNMTOKEN},
   _NMTOKENS                      => qr{\GNMTOKENS},
   _NOTATION                      => qr{\GNOTATION},
   _NOTATION_START                => qr{\G\(},
   _NOTATION_END                  => qr{\G\)},
   _ENUMERATION_START             => qr{\G\(},
   _ENUMERATION_END               => qr{\G\)},
   _REQUIRED                      => qr{\G#REQUIRED},
   _IMPLIED                       => qr{\G#IMPLIED},
   _FIXED                         => qr{\G#FIXED},
   _INCLUDE                       => qr{\GINCLUDE},
   _IGNORE                        => qr{\GIGNORE},
   _INCLUDESECT_START             => qr{\G<!\[},
   _INCLUDESECT_END               => qr{\G\]\]>},
   _IGNORESECT_START              => qr{\G<!\[},
   _IGNORESECT_END                => qr{\G\]\]>},
   _IGNORESECTCONTENTSUNIT_START  => qr{\G<!\[},
   _IGNORESECTCONTENTSUNIT_END    => qr{\G\]\]>},
   _CHARREF_START1                => qr{\G&#},
   _CHARREF_END1                  => qr{\G;},
   _CHARREF_START2                => qr{\G&#x},
   _CHARREF_END2                  => qr{\G;},
   _ENTITYREF_START               => qr{\G&},
   _ENTITYREF_END                 => qr{\G;},
   _PEREFERENCE_START             => qr{\G%},
   _PEREFERENCE_END               => qr{\G;},
   _ENTITY_START                  => qr{\G<!ENTITY},
   _ENTITY_END                    => qr{\G>},
   _PERCENT                       => qr{\G%},
   _SYSTEM                        => qr{\GSYSTEM},
   _PUBLIC                        => qr{\GPUBLIC},
   _NDATA                         => qr{\GNDATA},
   _TEXTDECL_START                => qr{\G<\?xml},
   _TEXTDECL_END                  => qr{\G?>},
   _ENCODING                      => qr{\Gencoding},
   _NOTATIONDECL_START            => qr{\G<!NOTATION},
   _NOTATIONDECL_END              => qr{\G>},
  );

our %LEXEME_REGEXP=
  (
   '1.0' => \%LEXEME_REGEXP_COMMON,
   '1.1' => \%LEXEME_REGEXP_COMMON,
  );

our %LEXEME_EXCLUSION_COMMON =
  (
   _PITARGET => qr{^xml$}i,
  );


our %LEXEME_EXCLUSION =
  (
   '1.0' => \%LEXEME_EXCLUSION_COMMON,
   '1.1' => \%LEXEME_EXCLUSION_COMMON,
  );

sub _build_lexeme_regexp {
  my ($self) = @_;

  return $LEXEME_REGEXP{$self->xml_version};
}

sub _build_lexeme_exclusion {
  my ($self) = @_;

  return $LEXEME_EXCLUSION{$self->xml_version};
}

sub _build_scanless {
  my ($self) = @_;

  #
  # Manipulate DATA section: revisit the start
  #
  my $data = ${$XMLBNF{$self->xml_version}};
  my $start = $self->start;
  $data =~ s/\$START/$start/sxmg;
  #
  # Add events
  #
  my %events = (%{$GRAMMAR_EVENT{$self->xml_version}}, $self->elements_grammar_event);
  foreach (keys %events) {
    #
    # If the user is using the same event name than an internal one, Marpa::R2 will croak
    #
    my $symbol_name = $events{$_}->{symbol_name};
    my $type        = $events{$_}->{type};
    if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
      $self->_logger->tracef('[%s/%s] Adding %s %s event', $self->xml_version, $self->start, $_, $type);
    }
    $data .= "event '$_' = $type <$symbol_name>\n";
    if (! $self->exists_grammar_event($_)) {
      $self->set_grammar_event($_, $events{$_});
    }
  }
  #
  # Generate the grammar
  #
  if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
    $self->_logger->debugf('[%s/%s] Instanciating grammar', $self->xml_version, $self->start);
  }

  return Marpa::R2::Scanless::G->new({source => \$data});
}

#
# End-of-line handling: XML1.0 and XML1.1 share the same algorithm
# ----------------------------------------------------------------
sub _eol_xml10 {
  my ($self, undef, $eof, $decl, $error_message_ref) = @_;
  # Buffer is in $_[1]

  #
  # If last character is a \x{D} this is undecidable unless eof flag
  #
  if (substr($_[1], -1, 1) eq "\x{D}") {
    if (! $eof) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
        $self->_logger->tracef('[%s/%s] Last character in buffer is \\x{D} and requires another read', $self->xml_version, $self->start);
      }
      return 0;
    }
  }
  $_[1] =~ s/\x{D}\x{A}/\x{A}/g;
  $_[1] =~ s/\x{D}/\x{A}/g;

  return length($_[1]);
}

sub _eol_xml11 {
  my ($self, undef, $eof, $decl, $error_message_ref) = @_; # Buffer is in $_[1]

  if ($decl && ($_[1] =~ /[\x{85}\x{2028}]/)) {
    ${$error_message_ref} = "Invalid character \\x{" . sprintf('%X', ord(substr($_[1], $+[0], $+[0] - $-[0]))) . "}";
    return -1;
  }
  #
  # If last character is a \x{D} this is undecidable unless eof flag
  #
  if (substr($_[1], -1, 1) eq "\x{D}") {
    if (! $eof) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
        $self->_logger->tracef('[%s/%s] Last character in buffer is \\x{D} and requires another read', $self->xml_version, $self->start);
      }
      return 0;
    }
  }
  $_[1] =~ s/\x{D}\x{A}/\x{A}/g;
  $_[1] =~ s/\x{D}\x{85}/\x{A}/g;
  $_[1] =~ s/\x{85}/\x{A}/g;
  $_[1] =~ s/\x{2028}/\x{A}/g;
  $_[1] =~ s/\x{D}/\x{A}/g;

  return length($_[1]);
}

#
# Note: it is expected that the caller never call eol on an empty buffer.
# Then it is guaranteed that eol never returns a value <= 0.
#
sub eol {
  #
  # Here is how I would do params validation
  # CORE::state $check = compile(ConsumerOf['MarpaX::Languages::XML::Role::Grammar'],
  #                                       Str,
  #                                       Bool,
  #                                       Str,
  #                                       ScalarRef);
  # $check->(@_);
  my $self = shift;
  my $coderef = $self->_get__eol($self->xml_version);
  return $self->$coderef(@_);
}

#
# Normalization: XML1.0 and XML1.1 share the same algorithm
# ---------------------------------------------------------
sub _attvalue_common {
  my $self = shift;
  my $cdata = shift;
  my $charref = shift;
  my $entityref = shift;
  #
  # @_ is an array describing attvalue:
  # if not a ref, this is char
  # if a ref, this is a reference to an array like: [ type, content ]
  # where type is either 'charref', 'entityref'
  #
  # 1. All line breaks must have been normalized on input to #xA as described in 2.11 End-of-Line Handling, so the rest of this algorithm operates on text normalized in this way.
  #
  # 2. Begin with a normalized value consisting of the empty string.
  #
  my $attvalue = '';
  #
  # 3. For each character, entity reference, or character reference in the unnormalized attribute value, beginning with the first and continuing to the last, do the following:
  #
  foreach (@_) {
    if (is_CharRef($_)) {
      #
      # For a character reference, append the referenced character to the normalized value.
      #
      $attvalue .= $_;
    } elsif (is_EntityRef($_)) {
      #
      # For an entity reference, recursively apply step 3 of this algorithm to the replacement text of the entity.
      # EntityRef case.
      #
      $attvalue .= $self->attvalue($cdata, $entityref, $_);
    } elsif (reftype($_)) {
      croak 'Internal error in attribute value normalization, expecting a CharRef, and EntityRef or a char, got ' . reftype($_);
    } elsif (($_ eq "\x{20}") || ($_ eq "\x{D}") || ($_ eq "\x{A}") || ($_ eq "\x{9}")) {
      #
      # For a white space character (#x20, #xD, #xA, #x9), append a space character (#x20) to the normalized value.
      #
      $attvalue .= "\x{20}";
    } else {
      #
      # For another character, append the character to the normalized value.
      #
      $attvalue .= $_;
    }
  }
  #
  # If the attribute type is not CDATA, then the XML processor must further process the normalized attribute value by discarding any leading and trailing space (#x20) characters, and by replacing sequences of space (#x20) characters by a single space (#x20) character.
  #
  if (! $cdata) {
    $attvalue =~ s/\A\x{20}*//;
    $attvalue =~ s/\x{20}*\z//;
    $attvalue =~ s/\x{20}+/\x{20}/g;
  }

  return $attvalue;
}

sub _attvalue_xml10 {
  my $self = shift;
  return $self->_attvalue_common(@_);
}
sub _attvalue_xml11 {
  my $self = shift;
  return $self->_attvalue_common(@_);
}
sub attvalue {
  my $self = shift;
  my $coderef = $self->_get__attvalue($self->xml_version);
  return $self->$coderef(@_);
}

=head1 SEE ALSO

L<Marpa::R2>, L<XML1.0|http://www.w3.org/TR/xml/>, L<XML1.1|http://www.w3.org/TR/xml11/>

=cut

with 'MooX::Role::Logger';
with 'MarpaX::Languages::XML::Role::Grammar';

1;

__DATA__
__[ xml10 ]__
inaccessible is ok by default
:default ::= action => [values]
lexeme default = action => [start,length,value,name] forgiving => 1

# start                         ::= document | extParsedEnt | extSubset
start                         ::= $START
MiscAny                       ::= Misc*
# Note: end_document is when either we abandoned parsing or reached the end of input of the 'document' grammar
document                      ::= (start_document) prolog element MiscAny
Name                          ::= NAME
Names                         ::= Name+ separator => SPACE proper => 1
Nmtoken                       ::= NMTOKENMANY
Nmtokens                      ::= Nmtoken+ separator => SPACE proper => 1

EntityValue                   ::= DQUOTE EntityValueInteriorDquote DQUOTE
                                | SQUOTE EntityValueInteriorSquote SQUOTE
EntityValueInteriorDquoteUnit ::= ENTITYVALUEINTERIORDQUOTEUNIT
PEReferenceMany               ::= PEReference+
EntityValueInteriorDquoteUnit ::= PEReferenceMany
ReferenceMany                 ::= Reference+
EntityValueInteriorDquoteUnit ::= ReferenceMany
EntityValueInteriorDquote     ::= EntityValueInteriorDquoteUnit*
EntityValueInteriorSquoteUnit ::= ENTITYVALUEINTERIORSQUOTEUNIT
EntityValueInteriorSquoteUnit ::= ReferenceMany
EntityValueInteriorSquoteUnit ::= PEReferenceMany
EntityValueInteriorSquote     ::= EntityValueInteriorSquoteUnit*

AttValue                      ::=  DQUOTE AttValueInteriorDquote DQUOTE
                                |  SQUOTE AttValueInteriorSquote SQUOTE
AttValueInteriorDquoteUnit    ::= ATTVALUEINTERIORDQUOTEUNIT
AttValueInteriorDquoteUnit    ::= ReferenceMany
AttValueInteriorDquote        ::= AttValueInteriorDquoteUnit*
AttValueInteriorSquoteUnit    ::= ATTVALUEINTERIORSQUOTEUNIT
AttValueInteriorSquoteUnit    ::= ReferenceMany
AttValueInteriorSquote        ::= AttValueInteriorSquoteUnit*

SystemLiteral                 ::= DQUOTE NOT_DQUOTEMANY DQUOTE
                                | DQUOTE                DQUOTE
                                | SQUOTE NOT_SQUOTEMANY SQUOTE
                                | SQUOTE                SQUOTE
PubidCharDquoteAny            ::= PubidCharDquote*
PubidCharSquoteAny            ::= PubidCharSquote*
PubidLiteral                  ::= DQUOTE PubidCharDquoteAny DQUOTE
                                | SQUOTE PubidCharSquoteAny SQUOTE

PubidCharDquote               ::= PUBIDCHARDQUOTE
PubidCharSquote               ::= PUBIDCHARSQUOTE

CharData                      ::= CHARDATAMANY

CommentCharAny                ::= COMMENTCHARMANY
CommentCharAny                ::=
Comment                       ::= COMMENT_START CommentCharAny (comment) COMMENT_END

PI                            ::= PI_START PITarget S PICHARDATAMANY PI_END
                                | PI_START PITarget S                PI_END
                                | PI_START PITarget                  PI_END

PITarget                      ::= PITARGET
CDSect                        ::= CDStart CData CDEnd
CDStart                       ::= CDATA_START
CData                         ::= CDATAMANY
CData                         ::=
CDEnd                         ::= CDATA_END
XMLDeclMaybe                  ::= XMLDecl
XMLDeclMaybe                  ::=
prolog                        ::= XMLDeclMaybe MiscAny
prolog                        ::= XMLDeclMaybe MiscAny doctypedecl MiscAny
EncodingDeclMaybe             ::= EncodingDecl
EncodingDeclMaybe             ::=
SDDeclMaybe                   ::= SDDecl
SDDeclMaybe                   ::=
SMaybe                        ::= S
SMaybe                        ::=
XMLDecl                       ::= XMLDECL_START VersionInfo EncodingDeclMaybe SDDeclMaybe SMaybe XMLDECL_END
VersionInfo                   ::= S VERSION Eq SQUOTE VersionNum SQUOTE
VersionInfo                   ::= S VERSION Eq DQUOTE VersionNum DQUOTE
Eq                            ::= SMaybe EQUAL SMaybe
VersionNum                    ::= VERSIONNUM
Misc                          ::= Comment | PI | S
doctypedecl                   ::= DOCTYPE_START S Name              SMaybe LBRACKET intSubset RBRACKET SMaybe DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
                                | DOCTYPE_START S Name              SMaybe                                    DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
                                | DOCTYPE_START S Name S ExternalID SMaybe LBRACKET intSubset RBRACKET SMaybe DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
                                | DOCTYPE_START S Name S ExternalID SMaybe                                    DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
DeclSep                       ::= PEReference   # [WFC: PE Between Declarations]
                                | S
intSubsetUnit                 ::= markupdecl | DeclSep
intSubset                     ::= intSubsetUnit*
markupdecl                    ::= elementdecl  # [VC: Proper Declaration/PE Nesting] [WFC: PEs in Internal Subset]
                                | AttlistDecl  # [VC: Proper Declaration/PE Nesting] [WFC: PEs in Internal Subset]
                                | EntityDecl   # [VC: Proper Declaration/PE Nesting] [WFC: PEs in Internal Subset]
                                | NotationDecl # [VC: Proper Declaration/PE Nesting] [WFC: PEs in Internal Subset]
                                | PI           # [VC: Proper Declaration/PE Nesting] [WFC: PEs in Internal Subset]
                                | Comment      # [VC: Proper Declaration/PE Nesting] [WFC: PEs in Internal Subset]
TextDeclMaybe                 ::= TextDecl
TextDeclMaybe                 ::=
extSubset                     ::= TextDeclMaybe extSubsetDecl
extSubsetDeclUnit             ::= markupdecl | conditionalSect | DeclSep
extSubsetDecl                 ::= extSubsetDeclUnit*
SDDecl                        ::= S STANDALONE Eq SQUOTE YES SQUOTE # [VC: Standalone Document Declaration]
                                | S STANDALONE Eq SQUOTE  NO SQUOTE  # [VC: Standalone Document Declaration]
                                | S STANDALONE Eq DQUOTE YES DQUOTE  # [VC: Standalone Document Declaration]
                                | S STANDALONE Eq DQUOTE  NO DQUOTE  # [VC: Standalone Document Declaration]
element                       ::= EmptyElemTag (start_element) (end_element)
                                | STag (start_element) content ETag (end_element) # [WFC: Element Type Match] [VC: Element Valid]
STagUnit                      ::= S Attribute
STagUnitAny                   ::= STagUnit*
STagName                      ::= Name
STag                          ::= ELEMENT_START STagName STagUnitAny SMaybe ELEMENT_END # [WFC: Unique Att Spec]
AttributeName                 ::= Name
Attribute                     ::= AttributeName Eq AttValue  # [VC: Attribute Value Type] [WFC: No External Entity References] [WFC: No < in Attribute Values]
ETag                          ::= ETAG_START Name SMaybe ETAG_END
CharDataMaybe                 ::= CharData
CharDataMaybe                 ::=
contentUnit                   ::= element CharDataMaybe
                                | Reference CharDataMaybe
                                | CDSect CharDataMaybe
                                | PI CharDataMaybe
                                | Comment CharDataMaybe
contentUnitAny                ::= contentUnit*
content                       ::= CharDataMaybe contentUnitAny
EmptyElemTagUnit              ::= S Attribute
EmptyElemTagUnitAny           ::= EmptyElemTagUnit*
EmptyElemTag                  ::= ELEMENT_START Name EmptyElemTagUnitAny SMaybe EMPTYELEM_END   # [WFC: Unique Att Spec]
elementdecl                   ::= ELEMENTDECL_START S Name S contentspec SMaybe ELEMENTDECL_END # [VC: Unique Element Type Declaration]
contentspec                   ::= EMPTY | ANY | Mixed | children
ChoiceOrSeq                   ::= choice | seq
children                      ::= ChoiceOrSeq
                                | ChoiceOrSeq QUESTIONMARK
                                | ChoiceOrSeq STAR
                                | ChoiceOrSeq PLUS
NameOrChoiceOrSeq             ::= Name | choice | seq
cp                            ::= NameOrChoiceOrSeq
                                | NameOrChoiceOrSeq QUESTIONMARK
                                | NameOrChoiceOrSeq STAR
                                | NameOrChoiceOrSeq PLUS
choiceUnit                    ::= SMaybe OR SMaybe cp
choiceUnitMany                ::= choiceUnit+
choice                        ::= CHOICE_START SMaybe cp choiceUnitMany SMaybe CHOICE_END # [VC: Proper Group/PE Nesting]
seqUnit                       ::= SMaybe COMMA SMaybe cp
seqUnitAny                    ::= seqUnit*
seq                           ::= SEQ_START SMaybe cp seqUnitAny SMaybe SEQ_END # [VC: Proper Group/PE Nesting]
MixedUnit                     ::= SMaybe OR SMaybe Name
MixedUnitAny                  ::= MixedUnit*
Mixed                         ::= MIXED_START1 SMaybe PCDATA MixedUnitAny SMaybe MIXED_END1 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START2 SMaybe PCDATA              SMaybe MIXED_END2 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
AttlistDecl                   ::= ATTLIST_START S Name AttDefAny SMaybe ATTLIST_END
AttDefAny                     ::= AttDef*
AttDef                        ::= S Name S AttType S DefaultDecl
AttType                       ::= StringType | TokenizedType | EnumeratedType
StringType                    ::= CDATA
TokenizedType                 ::= ID                 # [VC: ID] [VC: One ID per Element Type] [VC: ID Attribute Default]
                                | IDREF              # [VC: IDREF]
                                | IDREFS             # [VC: IDREF]
                                | ENTITY             # [VC: Entity Name]
                                | ENTITIES           # [VC: Entity Name]
                                | NMTOKEN            # [VC: Name Token]
                                | NMTOKENS           # [VC: Name Token]
EnumeratedType                ::= NotationType | Enumeration
NotationTypeUnit              ::= SMaybe OR SMaybe Name
NotationTypeUnitAny           ::= NotationTypeUnit*
NotationType                  ::= NOTATION S NOTATION_START SMaybe Name NotationTypeUnitAny SMaybe NOTATION_END # [VC: Notation Attributes] [VC: One Notation Per Element Type] [VC: No Notation on Empty Element] [VC: No Duplicate Tokens]
EnumerationUnit               ::= SMaybe OR SMaybe Nmtoken
EnumerationUnitAny            ::= EnumerationUnit*
Enumeration                   ::= ENUMERATION_START SMaybe Nmtoken EnumerationUnitAny SMaybe ENUMERATION_END # [VC: Enumeration] [VC: No Duplicate Tokens]
DefaultDecl                   ::= REQUIRED | IMPLIED
                                |            AttValue                              # [VC: Required Attribute] [VC: Attribute Default Value Syntactically Correct] [WFC: No < in Attribute Values] [VC: Fixed Attribute Default] [WFC: No External Entity References]
                                | FIXED S AttValue                              # [VC: Required Attribute] [VC: Attribute Default Value Syntactically Correct] [WFC: No < in Attribute Values] [VC: Fixed Attribute Default] [WFC: No External Entity References]
conditionalSect               ::= includeSect | ignoreSect
includeSect                   ::= INCLUDESECT_START SMaybe INCLUDE SMaybe LBRACKET extSubsetDecl          INCLUDESECT_END # [VC: Proper Conditional Section/PE Nesting]
ignoreSect                    ::= IGNORESECT_START SMaybe  IGNORE SMaybe LBRACKET ignoreSectContentsAny  IGNORESECT_END
                                | IGNORESECT_START SMaybe  IGNORE SMaybe LBRACKET                        IGNORESECT_END # [VC: Proper Conditional Section/PE Nesting]
ignoreSectContentsAny         ::= ignoreSectContents*
ignoreSectContentsUnit        ::= IGNORESECTCONTENTSUNIT_START ignoreSectContents IGNORESECTCONTENTSUNIT_END Ignore
ignoreSectContentsUnit        ::= IGNORESECTCONTENTSUNIT_START                    IGNORESECTCONTENTSUNIT_END Ignore
ignoreSectContentsUnitAny     ::= ignoreSectContentsUnit*
ignoreSectContents            ::= Ignore ignoreSectContentsUnitAny
Ignore                        ::= IGNOREMANY
CharRef                       ::= CHARREF_START1 DIGITMANY CHARREF_END1
                                | CHARREF_START2 ALPHAMANY CHARREF_END2 # [WFC: Legal Character]
Reference                     ::= EntityRef | CharRef
EntityRef                     ::= ENTITYREF_START Name ENTITYREF_END # [WFC: Entity Declared] [VC: Entity Declared] [WFC: Parsed Entity] [WFC: No Recursion]
PEReference                   ::= PEREFERENCE_START Name PEREFERENCE_END # [VC: Entity Declared] [WFC: No Recursion] [WFC: In DTD]
EntityDecl                    ::= GEDecl | PEDecl
GEDecl                        ::= ENTITY_START S           Name S EntityDef SMaybe ENTITY_END
PEDecl                        ::= ENTITY_START S PERCENT S Name S PEDef     SMaybe ENTITY_END
EntityDef                     ::= EntityValue
                                | ExternalID
                                | ExternalID NDataDecl
PEDef                         ::= EntityValue
                                | ExternalID
ExternalID                    ::= SYSTEM S                SystemLiteral
                                | PUBLIC S PubidLiteral S SystemLiteral
NDataDecl                     ::= S NDATA S Name  # [VC: Notation Declared]
VersionInfoMaybe              ::= VersionInfo
VersionInfoMaybe              ::=
TextDecl                      ::= TEXTDECL_START VersionInfoMaybe EncodingDecl SMaybe TEXTDECL_END
extParsedEnt                  ::= TextDeclMaybe content
EncodingDecl                  ::= S ENCODING Eq DQUOTE EncName DQUOTE
EncodingDecl                  ::= S ENCODING Eq SQUOTE EncName SQUOTE
EncName                       ::= ENCNAME
NotationDecl                  ::= NOTATIONDECL_START S Name S ExternalID SMaybe NOTATIONDECL_END # [VC: Unique Notation Name]
NotationDecl                  ::= NOTATIONDECL_START S Name S   PublicID SMaybe NOTATIONDECL_END # [VC: Unique Notation Name]
PublicID                      ::= PUBLIC S PubidLiteral
#
# Generic internal token matching anything
#
__ANYTHING ~ [\s\S]
_NAME ~ __ANYTHING
_NMTOKENMANY ~ __ANYTHING
_ENTITYVALUEINTERIORDQUOTEUNIT ~ __ANYTHING
_ENTITYVALUEINTERIORSQUOTEUNIT ~ __ANYTHING
_ATTVALUEINTERIORDQUOTEUNIT ~ __ANYTHING
_ATTVALUEINTERIORSQUOTEUNIT ~ __ANYTHING
_NOT_DQUOTEMANY ~ __ANYTHING
_NOT_SQUOTEMANY ~ __ANYTHING
_PUBIDCHARDQUOTE ~ __ANYTHING
_PUBIDCHARSQUOTE ~ __ANYTHING
_CHARDATAMANY ~ __ANYTHING
_COMMENTCHARMANY ~ __ANYTHING
_PITARGET ~ __ANYTHING
_CDATAMANY ~ __ANYTHING
_PICHARDATAMANY ~ __ANYTHING
_IGNOREMANY ~ __ANYTHING
_DIGITMANY ~ __ANYTHING
_ALPHAMANY ~ __ANYTHING
_ENCNAME ~ __ANYTHING
_S ~ __ANYTHING
_SPACE ~ __ANYTHING
_DQUOTE ~ __ANYTHING
_SQUOTE ~ __ANYTHING
_COMMENT_START ~ __ANYTHING
_COMMENT_END ~ __ANYTHING
_PI_START ~ __ANYTHING
_PI_END ~ __ANYTHING
_CDATA_START ~ __ANYTHING
_CDATA_END ~ __ANYTHING
_XMLDECL_START ~ __ANYTHING
_XMLDECL_END ~ __ANYTHING
_VERSION ~ __ANYTHING
_EQUAL ~ __ANYTHING
_VERSIONNUM ~ __ANYTHING
_DOCTYPE_START ~ __ANYTHING
_DOCTYPE_END ~ __ANYTHING
_LBRACKET ~ __ANYTHING
_RBRACKET ~ __ANYTHING
_STANDALONE ~ __ANYTHING
_YES ~ __ANYTHING
_NO ~ __ANYTHING
_ELEMENT_START ~ __ANYTHING
_ELEMENT_END ~ __ANYTHING
_ETAG_START ~ __ANYTHING
_ETAG_END ~ __ANYTHING
_EMPTYELEM_END ~ __ANYTHING
_ELEMENTDECL_START ~ __ANYTHING
_ELEMENTDECL_END ~ __ANYTHING
_EMPTY ~ __ANYTHING
_ANY ~ __ANYTHING
_QUESTIONMARK ~ __ANYTHING
_STAR ~ __ANYTHING
_PLUS ~ __ANYTHING
_OR ~ __ANYTHING
_CHOICE_START ~ __ANYTHING
_CHOICE_END ~ __ANYTHING
_SEQ_START ~ __ANYTHING
_SEQ_END ~ __ANYTHING
_MIXED_START1 ~ __ANYTHING
_MIXED_END1 ~ __ANYTHING
_MIXED_START2 ~ __ANYTHING
_MIXED_END2 ~ __ANYTHING
_COMMA ~ __ANYTHING
_PCDATA ~ __ANYTHING
_ATTLIST_START ~ __ANYTHING
_ATTLIST_END ~ __ANYTHING
_CDATA ~ __ANYTHING
_ID ~ __ANYTHING
_IDREF ~ __ANYTHING
_IDREFS ~ __ANYTHING
_ENTITY ~ __ANYTHING
_ENTITIES ~ __ANYTHING
_NMTOKEN ~ __ANYTHING
_NMTOKENS ~ __ANYTHING
_NOTATION ~ __ANYTHING
_NOTATION_START ~ __ANYTHING
_NOTATION_END ~ __ANYTHING
_ENUMERATION_START ~ __ANYTHING
_ENUMERATION_END ~ __ANYTHING
_REQUIRED ~ __ANYTHING
_IMPLIED ~ __ANYTHING
_FIXED ~ __ANYTHING
_INCLUDE ~ __ANYTHING
_IGNORE ~ __ANYTHING
_INCLUDESECT_START ~ __ANYTHING
_INCLUDESECT_END ~ __ANYTHING
_IGNORESECT_START ~ __ANYTHING
_IGNORESECT_END ~ __ANYTHING
_IGNORESECTCONTENTSUNIT_START ~ __ANYTHING
_IGNORESECTCONTENTSUNIT_END ~ __ANYTHING
_CHARREF_START1 ~ __ANYTHING
_CHARREF_END1 ~ __ANYTHING
_CHARREF_START2 ~ __ANYTHING
_CHARREF_END2 ~ __ANYTHING
_ENTITYREF_START ~ __ANYTHING
_ENTITYREF_END ~ __ANYTHING
_PEREFERENCE_START ~ __ANYTHING
_PEREFERENCE_END ~ __ANYTHING
_ENTITY_START ~ __ANYTHING
_ENTITY_END ~ __ANYTHING
_PERCENT ~ __ANYTHING
_SYSTEM ~ __ANYTHING
_PUBLIC ~ __ANYTHING
_NDATA ~ __ANYTHING
_TEXTDECL_START ~ __ANYTHING
_TEXTDECL_END ~ __ANYTHING
_ENCODING ~ __ANYTHING
_NOTATIONDECL_START ~ __ANYTHING
_NOTATIONDECL_END ~ __ANYTHING

NAME ::= _NAME
NMTOKENMANY ::= _NMTOKENMANY
ENTITYVALUEINTERIORDQUOTEUNIT ::= _ENTITYVALUEINTERIORDQUOTEUNIT
ENTITYVALUEINTERIORSQUOTEUNIT ::= _ENTITYVALUEINTERIORSQUOTEUNIT
ATTVALUEINTERIORDQUOTEUNIT ::= _ATTVALUEINTERIORDQUOTEUNIT
ATTVALUEINTERIORSQUOTEUNIT ::= _ATTVALUEINTERIORSQUOTEUNIT
NOT_DQUOTEMANY ::= _NOT_DQUOTEMANY
NOT_SQUOTEMANY ::= _NOT_SQUOTEMANY
PUBIDCHARDQUOTE ::= _PUBIDCHARDQUOTE
PUBIDCHARSQUOTE ::= _PUBIDCHARSQUOTE
CHARDATAMANY ::= _CHARDATAMANY
COMMENTCHARMANY ::= _COMMENTCHARMANY
PITARGET ::= _PITARGET
CDATAMANY ::= _CDATAMANY
PICHARDATAMANY ::= _PICHARDATAMANY
IGNOREMANY ::= _IGNOREMANY
DIGITMANY ::= _DIGITMANY
ALPHAMANY ::= _ALPHAMANY
ENCNAME ::= _ENCNAME
S ::= _S
SPACE ::= _SPACE
DQUOTE ::= _DQUOTE
SQUOTE ::= _SQUOTE
COMMENT_START ::= _COMMENT_START
COMMENT_END ::= _COMMENT_END
PI_START ::= _PI_START
PI_END ::= _PI_END
CDATA_START ::= _CDATA_START
CDATA_END ::= _CDATA_END
XMLDECL_START ::= _XMLDECL_START
XMLDECL_END ::= _XMLDECL_END
VERSION ::= _VERSION
EQUAL ::= _EQUAL
VERSIONNUM ::= _VERSIONNUM
DOCTYPE_START ::= _DOCTYPE_START
DOCTYPE_END ::= _DOCTYPE_END
LBRACKET ::= _LBRACKET
RBRACKET ::= _RBRACKET
STANDALONE ::= _STANDALONE
YES ::= _YES
NO ::= _NO
ELEMENT_START ::= _ELEMENT_START
ELEMENT_END ::= _ELEMENT_END
ETAG_START ::= _ETAG_START
ETAG_END ::= _ETAG_END
EMPTYELEM_END ::= _EMPTYELEM_END
ELEMENTDECL_START ::= _ELEMENTDECL_START
ELEMENTDECL_END ::= _ELEMENTDECL_END
EMPTY ::= _EMPTY
ANY ::= _ANY
QUESTIONMARK ::= _QUESTIONMARK
STAR ::= _STAR
PLUS ::= _PLUS
OR ::= _OR
CHOICE_START ::= _CHOICE_START
CHOICE_END ::= _CHOICE_END
SEQ_START ::= _SEQ_START
SEQ_END ::= _SEQ_END
MIXED_START1 ::= _MIXED_START1
MIXED_END1 ::= _MIXED_END1
MIXED_START2 ::= _MIXED_START2
MIXED_END2 ::= _MIXED_END2
COMMA ::= _COMMA
PCDATA ::= _PCDATA
ATTLIST_START ::= _ATTLIST_START
ATTLIST_END ::= _ATTLIST_END
CDATA ::= _CDATA
ID ::= _ID
IDREF ::= _IDREF
IDREFS ::= _IDREFS
ENTITY ::= _ENTITY
ENTITIES ::= _ENTITIES
NMTOKEN ::= _NMTOKEN
NMTOKENS ::= _NMTOKENS
NOTATION ::= _NOTATION
NOTATION_START ::= _NOTATION_START
NOTATION_END ::= _NOTATION_END
ENUMERATION_START ::= _ENUMERATION_START
ENUMERATION_END ::= _ENUMERATION_END
REQUIRED ::= _REQUIRED
IMPLIED ::= _IMPLIED
FIXED ::= _FIXED
INCLUDE ::= _INCLUDE
IGNORE ::= _IGNORE
INCLUDESECT_START ::= _INCLUDESECT_START
INCLUDESECT_END ::= _INCLUDESECT_END
IGNORESECT_START ::= _IGNORESECT_START
IGNORESECT_END ::= _IGNORESECT_END
IGNORESECTCONTENTSUNIT_START ::= _IGNORESECTCONTENTSUNIT_START
IGNORESECTCONTENTSUNIT_END ::= _IGNORESECTCONTENTSUNIT_END
CHARREF_START1 ::= _CHARREF_START1
CHARREF_END1 ::= _CHARREF_END1
CHARREF_START2 ::= _CHARREF_START2
CHARREF_END2 ::= _CHARREF_END2
ENTITYREF_START ::= _ENTITYREF_START
ENTITYREF_END ::= _ENTITYREF_END
PEREFERENCE_START ::= _PEREFERENCE_START
PEREFERENCE_END ::= _PEREFERENCE_END
ENTITY_START ::= _ENTITY_START
ENTITY_END ::= _ENTITY_END
PERCENT ::= _PERCENT
SYSTEM ::= _SYSTEM
PUBLIC ::= _PUBLIC
NDATA ::= _NDATA
TEXTDECL_START ::= _TEXTDECL_START
TEXTDECL_END ::= _TEXTDECL_END
ENCODING ::= _ENCODING
NOTATIONDECL_START ::= _NOTATIONDECL_START
NOTATIONDECL_END ::= _NOTATIONDECL_END

#
# SAX nullable rules
#
start_document ::= ;
start_element  ::= ;
end_element    ::= ;
comment        ::= ;
#
# Events are added on-the-fly
#
