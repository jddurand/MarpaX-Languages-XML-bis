package MarpaX::Languages::XML::Impl::Grammar;
use Carp qw/croak/;
use Data::Section -setup;
use Marpa::R2;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::XS;
use MarpaX::Languages::XML::Type::GrammarEvent -all;
use MarpaX::Languages::XML::Type::XmlVersion -all;
use MarpaX::Languages::XML::Type::XmlSupport -all;
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

has _eol_decl => (
                  is     => 'ro',
                  isa    => HashRef[CodeRef],
                  default => sub {
                    {
                      '1.0' => \&_eol_decl_xml10,
                      '1.1' => \&_eol_decl_xml11
                    }
                  },
                  handles_via => 'Hash',
                  handles => {
                              _get__eol_decl  => 'get'
                             }
            );

has scanless => (
                 is     => 'ro',
                 isa    => InstanceOf['Marpa::R2::Scanless::G'],
                 lazy  => 1,
                 builder => '_build_scanless'
                );

has xml_scanless => (
                     is     => 'ro',
                     isa    => InstanceOf['Marpa::R2::Scanless::G'],
                     lazy  => 1,
                     builder => '_build_xml_scanless'
                );

has xmlns_scanless => (
                       is     => 'ro',
                       isa    => InstanceOf['Marpa::R2::Scanless::G'],
                       lazy  => 1,
                       builder => '_build_xmlns_scanless'
                );

has xml_or_xmlns_scanless => (
                           is     => 'ro',
                           isa    => InstanceOf['Marpa::R2::Scanless::G'],
                           lazy  => 1,
                           builder => '_build_xml_or_xmlns_scanless'
                          );

has lexeme_match => (
                      is  => 'ro',
                      isa => HashRef[RegexpRef|Str],
                      lazy  => 1,
                      builder => '_build_lexeme_match',
                      handles_via => 'Hash',
                      handles => {
                                  elements_lexeme_match  => 'elements',
                                  keys_lexeme_match      => 'keys',
                                  set_lexeme_match       => 'set',
                                  get_lexeme_match       => 'get',
                                  exists_lexeme_match    => 'exists'
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

has xml_support => (
                    is  => 'ro',
                    isa => XmlSupport,
                    default => 'xml_or_xmlns'
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

#
# xmlns parts are special in the __DATA__ section: they contain code that should be eval'ed
#
our %XMLNSBNF = (
               '1.0' => __PACKAGE__->section_data('xmlns10'),
               '1.1' => __PACKAGE__->section_data('xmlns10')
              );
our %XMLNSBNF_ADD = (
               '1.0' => __PACKAGE__->section_data('xmlns10:add'),
               '1.1' => __PACKAGE__->section_data('xmlns10:add')
              );
our %XMLNSBNF_REPLACE = (
               '1.0' => __PACKAGE__->section_data('xmlns10:replace'),
               '1.1' => __PACKAGE__->section_data('xmlns10:replace')
              );
our %XMLNSBNF_AND = (
               '1.0' => __PACKAGE__->section_data('xmlns10:or'),
               '1.1' => __PACKAGE__->section_data('xmlns10:or')
              );

our %GRAMMAR_EVENT_COMMON =
  (
   #
   # These are the lexemes of unknown predicted size
   #
   '^NAME'                          => { type => 'predicted',                         symbol_name => 'NAME',                          lexeme => '_NAME' },
   '^NMTOKENMANY'                   => { type => 'predicted',                         symbol_name => 'NMTOKENMANY',                   lexeme => '_NMTOKENMANY' },
   '^ENTITYVALUEINTERIORDQUOTEUNIT' => { type => 'predicted',                         symbol_name => 'ENTITYVALUEINTERIORDQUOTEUNIT', lexeme => '_ENTITYVALUEINTERIORDQUOTEUNIT' },
   '^ENTITYVALUEINTERIORSQUOTEUNIT' => { type => 'predicted',                         symbol_name => 'ENTITYVALUEINTERIORSQUOTEUNIT', lexeme => '_ENTITYVALUEINTERIORSQUOTEUNIT' },
   '^ATTVALUEINTERIORDQUOTEUNIT'    => { type => 'predicted',                         symbol_name => 'ATTVALUEINTERIORDQUOTEUNIT',    lexeme => '_ATTVALUEINTERIORDQUOTEUNIT' },
   '^ATTVALUEINTERIORSQUOTEUNIT'    => { type => 'predicted',                         symbol_name => 'ATTVALUEINTERIORSQUOTEUNIT',    lexeme => '_ATTVALUEINTERIORSQUOTEUNIT' },
   '^NOT_DQUOTEMANY'                => { type => 'predicted',                         symbol_name => 'NOT_DQUOTEMANY',                lexeme => '_NOT_DQUOTEMANY' },
   '^NOT_SQUOTEMANY'                => { type => 'predicted',                         symbol_name => 'NOT_SQUOTEMANY',                lexeme => '_NOT_SQUOTEMANY' },
   '^CHARDATAMANY'                  => { type => 'predicted',                         symbol_name => 'CHARDATAMANY',                  lexeme => '_CHARDATAMANY' },    # [^<&]+ without ']]>'
   '^COMMENTCHARMANY'               => { type => 'predicted',                         symbol_name => 'COMMENTCHARMANY',               lexeme => '_COMMENTCHARMANY' }, # Char* without '--'
   '^PITARGET'                      => { type => 'predicted',                         symbol_name => 'PITARGET',                      lexeme => '_PITARGET' },        # NAME but /xml/i
   '^CDATAMANY'                     => { type => 'predicted',                         symbol_name => 'CDATAMANY',                     lexeme => '_CDATAMANY' },       # Char* minus ']]>'
   '^PICHARDATAMANY'                => { type => 'predicted',                         symbol_name => 'PICHARDATAMANY',                lexeme => '_PICHARDATAMANY' },  # Char* minus '?>'
   '^IGNOREMANY'                    => { type => 'predicted',                         symbol_name => 'IGNOREMANY',                    lexeme => '_IGNOREMANY' },      # Char minus* ('<![' or ']]>')
   '^DIGITMANY'                     => { type => 'predicted',                         symbol_name => 'DIGITMANY',                     lexeme => '_DIGITMANY' },
   '^ALPHAMANY'                     => { type => 'predicted',                         symbol_name => 'ALPHAMANY',                     lexeme => '_ALPHAMANY' },
   '^ENCNAME'                       => { type => 'predicted',                         symbol_name => 'ENCNAME',                       lexeme => '_ENCNAME' },
   '^S'                             => { type => 'predicted',                         symbol_name => 'S',                             lexeme => '_S' },
   #
   # These are the lexemes of predicted size
   #
   '^PUBIDCHARDQUOTEMANY'           => { type => 'predicted', predicted_length =>  1, symbol_name => 'PUBIDCHARDQUOTEMANY',              lexeme => '_PUBIDCHARDQUOTEMANY' },
   '^PUBIDCHARSQUOTEMANY'           => { type => 'predicted', predicted_length =>  1, symbol_name => 'PUBIDCHARSQUOTEMANY',              lexeme => '_PUBIDCHARSQUOTEMANY' },
   '^SPACE'                         => { type => 'predicted', predicted_length =>  1, symbol_name => 'SPACE',                        lexeme => '_SPACE', index => 1 },
   '^DQUOTE'                        => { type => 'predicted', predicted_length =>  1, symbol_name => 'DQUOTE',                       lexeme => '_DQUOTE', index => 1 },
   '^SQUOTE'                        => { type => 'predicted', predicted_length =>  1, symbol_name => 'SQUOTE',                       lexeme => '_SQUOTE', index => 1 },
   '^COMMENT_START'                 => { type => 'predicted', predicted_length =>  4, symbol_name => 'COMMENT_START',                lexeme => '_COMMENT_START', index => 1 },
   '^COMMENT_END'                   => { type => 'predicted', predicted_length =>  3, symbol_name => 'COMMENT_END',                  lexeme => '_COMMENT_END', index => 1 },
   '^PI_START'                      => { type => 'predicted', predicted_length =>  2, symbol_name => 'PI_START',                     lexeme => '_PI_START', index => 1 },
   '^PI_END'                        => { type => 'predicted', predicted_length =>  2, symbol_name => 'PI_END',                       lexeme => '_PI_END', index => 1 },
   '^CDATA_START'                   => { type => 'predicted', predicted_length =>  9, symbol_name => 'CDATA_START',                  lexeme => '_CDATA_START', index => 1 },
   '^CDATA_END'                     => { type => 'predicted', predicted_length =>  3, symbol_name => 'CDATA_END',                    lexeme => '_CDATA_END', index => 1 },
   '^XMLDECL_START'                 => { type => 'predicted', predicted_length =>  5, symbol_name => 'XMLDECL_START',                lexeme => '_XMLDECL_START', index => 1 },
   '^XMLDECL_END'                   => { type => 'predicted', predicted_length =>  2, symbol_name => 'XMLDECL_END',                  lexeme => '_XMLDECL_END', index => 1 },
   '^VERSION'                       => { type => 'predicted', predicted_length =>  7, symbol_name => 'VERSION',                      lexeme => '_VERSION', index => 1 },
   '^EQUAL'                         => { type => 'predicted', predicted_length =>  1, symbol_name => 'EQUAL',                        lexeme => '_EQUAL', index => 1 },
   '^VERSIONNUM'                    => { type => 'predicted', predicted_length =>  3, symbol_name => 'VERSIONNUM',                   lexeme => '_VERSIONNUM', index => 1 },
   '^DOCTYPE_START'                 => { type => 'predicted', predicted_length =>  9, symbol_name => 'DOCTYPE_START',                lexeme => '_DOCTYPE_START', index => 1 },
   '^DOCTYPE_END'                   => { type => 'predicted', predicted_length =>  1, symbol_name => 'DOCTYPE_END',                  lexeme => '_DOCTYPE_END', index => 1 },
   '^LBRACKET'                      => { type => 'predicted', predicted_length =>  1, symbol_name => 'LBRACKET',                     lexeme => '_LBRACKET', index => 1 },
   '^RBRACKET'                      => { type => 'predicted', predicted_length =>  1, symbol_name => 'RBRACKET',                     lexeme => '_RBRACKET', index => 1 },
   '^STANDALONE'                    => { type => 'predicted', predicted_length => 10, symbol_name => 'STANDALONE',                   lexeme => '_STANDALONE', index => 1 },
   '^YES'                           => { type => 'predicted', predicted_length =>  3, symbol_name => 'YES',                          lexeme => '_YES', index => 1 },
   '^NO'                            => { type => 'predicted', predicted_length =>  2, symbol_name => 'NO',                           lexeme => '_NO', index => 1 },
   '^ELEMENT_START'                 => { type => 'predicted', predicted_length =>  1, symbol_name => 'ELEMENT_START',                lexeme => '_ELEMENT_START', index => 1 },
   '^ELEMENT_END'                   => { type => 'predicted', predicted_length =>  1, symbol_name => 'ELEMENT_END',                  lexeme => '_ELEMENT_END', index => 1 },
   '^ETAG_START'                    => { type => 'predicted', predicted_length =>  2, symbol_name => 'ETAG_START',                   lexeme => '_ETAG_START', index => 1 },
   '^ETAG_END'                      => { type => 'predicted', predicted_length =>  1, symbol_name => 'ETAG_END',                     lexeme => '_ETAG_END', index => 1 },
   '^EMPTYELEM_END'                 => { type => 'predicted', predicted_length =>  2, symbol_name => 'EMPTYELEM_END',                lexeme => '_EMPTYELEM_END', index => 1 },
   '^ELEMENTDECL_START'             => { type => 'predicted', predicted_length =>  9, symbol_name => 'ELEMENTDECL_START',            lexeme => '_ELEMENTDECL_START', index => 1 },
   '^ELEMENTDECL_END'               => { type => 'predicted', predicted_length =>  1, symbol_name => 'ELEMENTDECL_END',              lexeme => '_ELEMENTDECL_END', index => 1 },
   '^EMPTY'                         => { type => 'predicted', predicted_length =>  5, symbol_name => 'EMPTY',                        lexeme => '_EMPTY', index => 1 },
   '^ANY'                           => { type => 'predicted', predicted_length =>  3, symbol_name => 'ANY',                          lexeme => '_ANY', index => 1 },
   '^QUESTIONMARK'                  => { type => 'predicted', predicted_length =>  1, symbol_name => 'QUESTIONMARK',                 lexeme => '_QUESTIONMARK', index => 1 },
   '^STAR'                          => { type => 'predicted', predicted_length =>  1, symbol_name => 'STAR',                         lexeme => '_STAR', index => 1 },
   '^PLUS'                          => { type => 'predicted', predicted_length =>  1, symbol_name => 'PLUS',                         lexeme => '_PLUS', index => 1 },
   '^OR'                            => { type => 'predicted', predicted_length =>  1, symbol_name => 'OR',                           lexeme => '_OR', index => 1 },
   '^CHOICE_START'                  => { type => 'predicted', predicted_length =>  1, symbol_name => 'CHOICE_START',                 lexeme => '_CHOICE_START', index => 1 },
   '^CHOICE_END'                    => { type => 'predicted', predicted_length =>  1, symbol_name => 'CHOICE_END',                   lexeme => '_CHOICE_END', index => 1 },
   '^SEQ_START'                     => { type => 'predicted', predicted_length =>  1, symbol_name => 'SEQ_START',                    lexeme => '_SEQ_START', index => 1 },
   '^SEQ_END'                       => { type => 'predicted', predicted_length =>  1, symbol_name => 'SEQ_END',                      lexeme => '_SEQ_END', index => 1 },
   '^MIXED_START'                   => { type => 'predicted', predicted_length =>  1, symbol_name => 'MIXED_START',                  lexeme => '_MIXED_START', index => 1 },
   '^MIXED_END1'                    => { type => 'predicted', predicted_length =>  2, symbol_name => 'MIXED_END1',                   lexeme => '_MIXED_END1', index => 1 },
   '^MIXED_END2'                    => { type => 'predicted', predicted_length =>  1, symbol_name => 'MIXED_END2',                   lexeme => '_MIXED_END2', index => 1 },
   '^COMMA'                         => { type => 'predicted', predicted_length =>  1, symbol_name => 'COMMA',                        lexeme => '_COMMA', index => 1 },
   '^PCDATA'                        => { type => 'predicted', predicted_length =>  7, symbol_name => 'PCDATA',                       lexeme => '_PCDATA', index => 1 },
   '^ATTLIST_START'                 => { type => 'predicted', predicted_length =>  9, symbol_name => 'ATTLIST_START',                lexeme => '_ATTLIST_START', index => 1 },
   '^ATTLIST_END'                   => { type => 'predicted', predicted_length =>  1, symbol_name => 'ATTLIST_END',                  lexeme => '_ATTLIST_END', index => 1 },
   '^CDATA'                         => { type => 'predicted', predicted_length =>  5, symbol_name => 'CDATA',                        lexeme => '_CDATA', index => 1 },
   '^ID'                            => { type => 'predicted', predicted_length =>  2, symbol_name => 'ID',                           lexeme => '_ID', index => 1 },
   '^IDREF'                         => { type => 'predicted', predicted_length =>  5, symbol_name => 'IDREF',                        lexeme => '_IDREF', index => 1 },
   '^IDREFS'                        => { type => 'predicted', predicted_length =>  6, symbol_name => 'IDREFS',                       lexeme => '_IDREFS', index => 1 },
   '^ENTITY'                        => { type => 'predicted', predicted_length =>  6, symbol_name => 'ENTITY',                       lexeme => '_ENTITY', index => 1 },
   '^ENTITIES'                      => { type => 'predicted', predicted_length =>  8, symbol_name => 'ENTITIES',                     lexeme => '_ENTITIES', index => 1 },
   '^NMTOKEN'                       => { type => 'predicted', predicted_length =>  7, symbol_name => 'NMTOKEN',                      lexeme => '_NMTOKEN', index => 1 },
   '^NMTOKENS'                      => { type => 'predicted', predicted_length =>  8, symbol_name => 'NMTOKENS',                     lexeme => '_NMTOKENS', index => 1 },
   '^NOTATION'                      => { type => 'predicted', predicted_length =>  8, symbol_name => 'NOTATION',                     lexeme => '_NOTATION', index => 1 },
   '^NOTATION_START'                => { type => 'predicted', predicted_length =>  1, symbol_name => 'NOTATION_START',               lexeme => '_NOTATION_START', index => 1 },
   '^NOTATION_END'                  => { type => 'predicted', predicted_length =>  1, symbol_name => 'NOTATION_END',                 lexeme => '_NOTATION_END', index => 1 },
   '^ENUMERATION_START'             => { type => 'predicted', predicted_length =>  1, symbol_name => 'ENUMERATION_START',            lexeme => '_ENUMERATION_START', index => 1 },
   '^ENUMERATION_END'               => { type => 'predicted', predicted_length =>  1, symbol_name => 'ENUMERATION_END',              lexeme => '_ENUMERATION_END', index => 1 },
   '^REQUIRED'                      => { type => 'predicted', predicted_length =>  9, symbol_name => 'REQUIRED',                     lexeme => '_REQUIRED', index => 1 },
   '^IMPLIED'                       => { type => 'predicted', predicted_length =>  8, symbol_name => 'IMPLIED',                      lexeme => '_IMPLIED', index => 1 },
   '^FIXED'                         => { type => 'predicted', predicted_length =>  6, symbol_name => 'FIXED',                        lexeme => '_FIXED', index => 1 },
   '^INCLUDE'                       => { type => 'predicted', predicted_length =>  7, symbol_name => 'INCLUDE',                      lexeme => '_INCLUDE', index => 1 },
   '^IGNORE'                        => { type => 'predicted', predicted_length =>  6, symbol_name => 'IGNORE',                       lexeme => '_IGNORE', index => 1 },
   '^INCLUDESECT_START'             => { type => 'predicted', predicted_length =>  3, symbol_name => 'INCLUDESECT_START',            lexeme => '_INCLUDESECT_START', index => 1 },
   '^INCLUDESECT_END'               => { type => 'predicted', predicted_length =>  3, symbol_name => 'INCLUDESECT_END',              lexeme => '_INCLUDESECT_END', index => 1 },
   '^IGNORESECT_START'              => { type => 'predicted', predicted_length =>  3, symbol_name => 'IGNORESECT_START',             lexeme => '_IGNORESECT_START', index => 1 },
   '^IGNORESECT_END'                => { type => 'predicted', predicted_length =>  3, symbol_name => 'IGNORESECT_END',               lexeme => '_IGNORESECT_END', index => 1 },
   '^IGNORESECTCONTENTSUNIT_START'  => { type => 'predicted', predicted_length =>  3, symbol_name => 'IGNORESECTCONTENTSUNIT_START', lexeme => '_IGNORESECTCONTENTSUNIT_START', index => 1 },
   '^IGNORESECTCONTENTSUNIT_END'    => { type => 'predicted', predicted_length =>  3, symbol_name => 'IGNORESECTCONTENTSUNIT_END',   lexeme => '_IGNORESECTCONTENTSUNIT_END', index => 1 },
   '^CHARREF_START1'                => { type => 'predicted', predicted_length =>  2, symbol_name => 'CHARREF_START1',               lexeme => '_CHARREF_START1', index => 1 },
   '^CHARREF_END1'                  => { type => 'predicted', predicted_length =>  1, symbol_name => 'CHARREF_END1',                 lexeme => '_CHARREF_END1', index => 1 },
   '^CHARREF_START2'                => { type => 'predicted', predicted_length =>  3, symbol_name => 'CHARREF_START2',               lexeme => '_CHARREF_START2', index => 1 },
   '^CHARREF_END2'                  => { type => 'predicted', predicted_length =>  1, symbol_name => 'CHARREF_END2',                 lexeme => '_CHARREF_END2', index => 1 },
   '^ENTITYREF_START'               => { type => 'predicted', predicted_length =>  1, symbol_name => 'ENTITYREF_START',              lexeme => '_ENTITYREF_START', index => 1 },
   '^ENTITYREF_END'                 => { type => 'predicted', predicted_length =>  1, symbol_name => 'ENTITYREF_END',                lexeme => '_ENTITYREF_END', index => 1 },
   '^PEREFERENCE_START'             => { type => 'predicted', predicted_length =>  1, symbol_name => 'PEREFERENCE_START',            lexeme => '_PEREFERENCE_START', index => 1 },
   '^PEREFERENCE_END'               => { type => 'predicted', predicted_length =>  1, symbol_name => 'PEREFERENCE_END',              lexeme => '_PEREFERENCE_END', index => 1 },
   '^ENTITY_START'                  => { type => 'predicted', predicted_length =>  8, symbol_name => 'ENTITY_START',                 lexeme => '_ENTITY_START', index => 1 },
   '^ENTITY_END'                    => { type => 'predicted', predicted_length =>  1, symbol_name => 'ENTITY_END',                   lexeme => '_ENTITY_END', index => 1 },
   '^PERCENT'                       => { type => 'predicted', predicted_length =>  1, symbol_name => 'PERCENT',                      lexeme => '_PERCENT', index => 1 },
   '^SYSTEM'                        => { type => 'predicted', predicted_length =>  6, symbol_name => 'SYSTEM',                       lexeme => '_SYSTEM', index => 1 },
   '^PUBLIC'                        => { type => 'predicted', predicted_length =>  6, symbol_name => 'PUBLIC',                       lexeme => '_PUBLIC', index => 1 },
   '^NDATA'                         => { type => 'predicted', predicted_length =>  5, symbol_name => 'NDATA',                        lexeme => '_NDATA', index => 1 },
   '^TEXTDECL_START'                => { type => 'predicted', predicted_length =>  5, symbol_name => 'TEXTDECL_START',               lexeme => '_TEXTDECL_START', index => 1 },
   '^TEXTDECL_END'                  => { type => 'predicted', predicted_length =>  2, symbol_name => 'TEXTDECL_END',                 lexeme => '_TEXTDECL_END', index => 1 },
   '^ENCODING'                      => { type => 'predicted', predicted_length =>  8, symbol_name => 'ENCODING',                     lexeme => '_ENCODING', index => 1 },
   '^NOTATIONDECL_START'            => { type => 'predicted', predicted_length => 10, symbol_name => 'NOTATIONDECL_START',           lexeme => '_NOTATIONDECL_START', index => 1 },
   '^NOTATIONDECL_END'              => { type => 'predicted', predicted_length =>  1, symbol_name => 'NOTATIONDECL_END',             lexeme => '_NOTATIONDECL_END', index => 1 },
   '^COLON'                         => { type => 'predicted', predicted_length =>  1, symbol_name => 'COLON',                        lexeme => '_COLON', index => 1 },
   #
   # xmlns lexemes are using predicted_length < 0, even if at the end, except for PREFIX and NCNAME, the length is predictable.
   # When length is < 0, the predicted size is abs(predicted_length).
   #
   '^NCNAME'                        => { type => 'predicted',                         symbol_name => 'NCNAME',                       lexeme => '_NCNAME', priority => 1 },
   '^PREFIX'                        => { type => 'predicted',                         symbol_name => 'PREFIX',                       lexeme => '_PREFIX', priority => 1 },
   '^XMLNSCOLON'                    => { type => 'predicted', predicted_length => -6, symbol_name => 'XMLNSCOLON',                   lexeme => '_XMLNSCOLON', priority => 2 },
   '^XMLNS'                         => { type => 'predicted', predicted_length => -5, symbol_name => 'XMLNS',                        lexeme => '_XMLNS', priority => 2 },
  );

our %GRAMMAR_EVENT =
  (
   '1.0' => \%GRAMMAR_EVENT_COMMON,
   '1.1' => \%GRAMMAR_EVENT_COMMON
  );

# Regexps:
# -------
# The *+ is important: it means match zero or more times and give nothing back
# The ++ is important: it means match one  or more times and give nothing back
# I could not avoid the calls to regcomp even with /o modifier. This is why
# some regexp contain a commented version with interpolation, and the uncommented version
# with explicit cut/paste.
#
#
# We reuse these regexp for look-forward
#
our $_NAME_TRAILER_REGEXP = qr{[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]};
our $_NAME_WITHOUT_COLON_REGEXP = qr{[A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+};

our %LEXEME_MATCH_COMMON =
  (
   #
   # These are the lexemes of unknown size
   #
   # _NAME                          => qr/\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}]${_NAME_TRAILER_REGEXP}*+/op,    # <======= /o modifier
   _NAME                          => qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+}p,
   _NMTOKENMANY                   => qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]++}p,
   _ENTITYVALUEINTERIORDQUOTEUNIT => qr{\G[^%&"]++}p,
   _ENTITYVALUEINTERIORSQUOTEUNIT => qr{\G[^%&']++}p,
   _ATTVALUEINTERIORDQUOTEUNIT    => qr{\G[^<&"]++}p,
   _ATTVALUEINTERIORSQUOTEUNIT    => qr{\G[^<&']++}p,
   _NOT_DQUOTEMANY                => qr{\G[^"]++}p,
   _NOT_SQUOTEMANY                => qr{\G[^']++}p,
   _CHARDATAMANY                  => qr{\G(?:[^<&\]]|(?:\](?!\]>)))++}p, # [^<&]+ without ']]>'
   _COMMENTCHARMANY               => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{2C}\x{2E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\-(?!\-)))++}p,  # Char* without '--'
   _PITARGET                      => qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+}p,  # NAME but /xml/i - c.f. exclusion hash
   _CDATAMANY                     => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{5C}\x{5E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\](?!\]>)))++}p,  # Char* minus ']]>'
   _PICHARDATAMANY                => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{3E}\x{40}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\?(?!>)))++}p,  # Char* minus '?>'
   _IGNOREMANY                    => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{3B}\x{3D}-\x{5C}\x{5E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:<(?!!\[))|(?:\](?!\]>)))++}p,  # Char minus* ('<![' or ']]>')
   _DIGITMANY                     => qr{\G[0-9]++}p,
   _ALPHAMANY                     => qr{\G[0-9a-fA-F]++}p,
   _ENCNAME                       => qr{\G[A-Za-z][A-Za-z0-9._\-]*+}p,
   _S                             => qr{\G[\x{20}\x{9}\x{D}\x{A}]++}p,
   #
   # An NCNAME is ok only if it is eventually followed by ":_NAME_WITHOUT_COLON", and not terminated by ":"
   # An alternation is fast than the '?' quantifier -;
   # The grammar imposes that a NCNAME cannot be the end of the input, so we can use [^:] instead of (?!:)
   #
   # _NCNAME                        => qr/\G${_NAME_WITHOUT_COLON_REGEXP}(?=(?::${_NAME_WITHOUT_COLON_REGEXP}[^:])|[^:])/op,    # <======= /o modifier
   _NCNAME                        => qr{\G[A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+(?=(?::[A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+[^:])|[^:])}p,
   #
   # These are the lexemes of predicted size
   #
   _PUBIDCHARDQUOTEMANY           => qr{\G[a-zA-Z0-9\-'()+,./:=?;!*#@\$_%\x{20}\x{D}\x{A}]++}p,
   _PUBIDCHARSQUOTEMANY           => qr{\G[a-zA-Z0-9\-()+,./:=?;!*#@\$_%\x{20}\x{D}\x{A}]++}p,
   _SPACE                         => "\x{20}",
   _DQUOTE                        => '"',
   _SQUOTE                        => "'",
   _COMMENT_START                 => '<!--',
   _COMMENT_END                   => '-->',
   _PI_START                      => '<?',
   _PI_END                        => '?>',
   _CDATA_START                   => '![CDATA[',
   _CDATA_END                     => ']]>',
   _XMLDECL_START                 => '<?xml',
   _XMLDECL_END                   => '?>',
   _VERSION                       => 'version',
   _EQUAL                         => '=',
   _VERSIONNUM                    => '1.0',
   _DOCTYPE_START                 => '<!DOCTYPE',
   _DOCTYPE_END                   => '>',
   _LBRACKET                      => '[',
   _RBRACKET                      => ']',
   _STANDALONE                    => 'standalone',
   _YES                           => 'yes',
   _NO                            => 'no',
   _ELEMENT_START                 => '<',
   _ELEMENT_END                   => '>',
   _ETAG_START                    => '</',
   _ETAG_END                      => '>',
   _EMPTYELEM_END                 => '/>',
   _ELEMENTDECL_START             => '<!ELEMENT',
   _ELEMENTDECL_END               => '>',
   _EMPTY                         => 'EMPTY',
   _ANY                           => 'ANY',
   _QUESTIONMARK                  => '?',
   _STAR                          => '*',
   _PLUS                          => '+',
   _OR                            => '|',
   _CHOICE_START                  => '(',
   _CHOICE_END                    => ')',
   _SEQ_START                     => '(',
   _SEQ_END                       => ')',
   _MIXED_START                   => '(',
   _MIXED_END1                    => ')*',
   _MIXED_END2                    => ')',
   _COMMA                         => ',',
   _PCDATA                        => '#PCDATA',
   _ATTLIST_START                 => '<!ATTLIST',
   _ATTLIST_END                   => '>',
   _CDATA                         => 'CDATA',
   _ID                            => 'ID',
   _IDREF                         => 'IDREF',
   _IDREFS                        => 'IDREFS',
   _ENTITY                        => 'ENTITY',
   _ENTITIES                      => 'ENTITIES',
   _NMTOKEN                       => 'NMTOKEN',
   _NMTOKENS                      => 'NMTOKENS',
   _NOTATION                      => 'NOTATION',
   _NOTATION_START                => '(',
   _NOTATION_END                  => ')',
   _ENUMERATION_START             => '(',
   _ENUMERATION_END               => ')',
   _REQUIRED                      => '#REQUIRED',
   _IMPLIED                       => '#IMPLIED',
   _FIXED                         => '#FIXED',
   _INCLUDE                       => 'INCLUDE',
   _IGNORE                        => 'IGNORE',
   _INCLUDESECT_START             => '<![',
   _INCLUDESECT_END               => ']]>',
   _IGNORESECT_START              => '<![',
   _IGNORESECT_END                => ']]>',
   _IGNORESECTCONTENTSUNIT_START  => '<![',
   _IGNORESECTCONTENTSUNIT_END    => ']]>',
   _CHARREF_START1                => '&#',
   _CHARREF_END1                  => ';',
   _CHARREF_START2                => '&#x',
   _CHARREF_END2                  => ';',
   _ENTITYREF_START               => '&',
   _ENTITYREF_END                 => ';',
   _PEREFERENCE_START             => '%',
   _PEREFERENCE_END               => ';',
   _ENTITY_START                  => '<!ENTITY',
   _ENTITY_END                    => '>',
   _PERCENT                       => '%',
   _SYSTEM                        => 'SYSTEM',
   _PUBLIC                        => 'PUBLIC',
   _NDATA                         => 'NDATA',
   _TEXTDECL_START                => '<?xml',
   _TEXTDECL_END                  => '?>',
   _ENCODING                      => 'encoding',
   _NOTATIONDECL_START            => '<!NOTATION',
   _NOTATIONDECL_END              => '>',
   _COLON                         => ':',
   #
   # Regexps using predicted_length < 0 : they a zero-witdh look ahead
   #
   #
   # A PREFIX is the case of _NAME_WITHOUT_COLON followed by :_NAME_WITHOUT_COLON not followed by a ":"
   # I.e. this is just a more restrictive view of NCNAME
   #
   # _PREFIX                        => qr/\G${_NAME_WITHOUT_COLON_REGEXP}(?=:${_NAME_WITHOUT_COLON_REGEXP}[^:])/op,    # <======= /o modifier
   _PREFIX                        => qr{\G[A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+(?=:[A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+[^:])}p,
   #
   # An XMLNSCOLON is ok only if it is followed by a name without colon and then a "="
   #
   # _XMLNSCOLON                    => qr/\Gxmlns:(?=${_NAME_WITHOUT_COLON_REGEXP}=)/op,    # <======= /o modifier
   _XMLNSCOLON                    => qr/\Gxmlns:(?=[A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+=)/p,
   #
   # An XMLNSCOLON is ok only if it is followed by a "="
   #
   _XMLNS                         => qr/\Gxmlns(?==)/p,
  );

our %LEXEME_MATCH=
  (
   '1.0' => \%LEXEME_MATCH_COMMON,
   '1.1' => \%LEXEME_MATCH_COMMON,
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

sub _build_lexeme_match {
  my ($self) = @_;

  return $LEXEME_MATCH{$self->xml_version};
}

sub _build_lexeme_exclusion {
  my ($self) = @_;

  return $LEXEME_EXCLUSION{$self->xml_version};
}

sub _build_xmlns_scanless {
  my ($self) = @_;

  #
  # Manipulate DATA section: revisit the start
  #
  my $data = ${$XMLBNF{$self->xml_version}};
  my $start = $self->start;
  $data =~ s/\$START/$start/sxmg;
  #
  # Apply xmlns specific transformations. This should never croak.
  #
  my $add     = ${$XMLNSBNF_ADD{$self->xml_version}};
  my $replace = ${$XMLNSBNF_REPLACE{$self->xml_version}};
  #
  # Every rule in the $replace is removed from $data
  #
  my @rules_to_remove = ();
  while ($replace =~ m/^\w+/mgp) {
    push(@rules_to_remove, ${^MATCH});
  }
  foreach (@rules_to_remove) {
    $data =~ s/^$_\s*::=.*$//mg;
  }
  #
  # Add everything
  #
  $data .= $add;
  $data .= $replace;

  return $self->_scanless($data, 'xmlns');
}

sub _build_xml_or_xmlns_scanless {
  my ($self) = @_;

  #
  # Manipulate DATA section: revisit the start
  #
  my $data = ${$XMLBNF{$self->xml_version}};
  my $start = $self->start;
  $data =~ s/\$START/$start/sxmg;
  #
  # Apply xmlns specific transformations. This should never croak.
  #
  my $add = ${$XMLNSBNF_ADD{$self->xml_version}};
  my $and = ${$XMLNSBNF_AND{$self->xml_version}};
  #
  # Add everything
  #
  $data .= $add;
  $data .= $and;

  return $self->_scanless($data, 'xml_or_xmlns');
}

sub _scanless {
  my ($self, $data, $spec) = @_;
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
      $self->_logger->tracef('%s/%s/%s: Adding %s %s event', $spec, $self->xml_version, $self->start, $_, $type);
    }
    $data .= "event '$_' = $type <$symbol_name>\n";
    if (! $self->exists_grammar_event($_)) {
      $self->set_grammar_event($_, $events{$_});
    }
    #
    # Systematically set is_prediction
    #
    $events{$_}->{is_prediction} = $type eq 'predicted';
    #
    # Make sure predicted_length is defined
    #
    $events{$_}->{predicted_length} //= 0;
    #
    # Make sure priority is defined
    #
    $events{$_}->{priority} //= 0;
  }
  #
  # Generate the grammar
  #
  if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
    $self->_logger->debugf('%s/%s/%s: Instanciating grammar', $spec, $self->xml_version, $self->start);
  }

  return Marpa::R2::Scanless::G->new({source => \$data});
}

sub _build_xml_scanless {
  my ($self) = @_;

  #
  # Manipulate DATA section: revisit the start
  #
  my $data = ${$XMLBNF{$self->xml_version}};
  my $start = $self->start;
  $data =~ s/\$START/$start/sxmg;

  return $self->_scanless($data, 'xml');
}

sub _build_scanless {
  my $self = shift;

  my $xml_support = $self->xml_support;
  my $method = $xml_support . '_scanless';

  return $self->$method(@_);
}

#
# End-of-line handling in a declaration
# --------------------------------------
sub _eol_decl_xml10 {
  #
  # XML 1.0 has no decl dependency
  #
  my $self = shift;
  return $self->_eol_xml10(@_);
}

sub _eol_decl_xml11 {
  my ($self, undef, $eof, $error_message_ref) = @_; # Buffer is in $_[1]

  if ($_[1] =~ /[\x{85}\x{2028}]/) {
    ${$error_message_ref} = "Invalid character \\x{" . sprintf('%X', ord(substr($_[1], $+[0], $+[0] - $-[0]))) . "}";
    return -1;
  }

  #
  # The rest is shared between decl and non decl modes
  #
  return $self->_eol_xml11($_[1], $eof, $error_message_ref);
}

#
# Note: it is expected that the caller never call eol on an empty buffer.
# Then it is guaranteed that eol never returns a value <= 0.
#
sub eol_decl {
  my $self = shift;
  my $coderef = $self->_get__eol_decl($self->xml_version);
  return $self->$coderef(@_);
}

#
# End-of-line handling outside of a declaration
# ---------------------------------------------
sub _eol_xml10 {
  my ($self, undef, $eof, $error_message_ref) = @_;
  # Buffer is in $_[1]

  #
  # If last character is a \x{D} this is undecidable unless eof flag
  #
  if (substr($_[1], -1, 1) eq "\x{D}") {
    if (! $eof) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
        $self->_logger->tracef('%s/%s: Last character in buffer is \\x{D} and requires another read', $self->xml_version, $self->start);
      }
      return 0;
    }
  }
  $_[1] =~ s/\x{D}\x{A}/\x{A}/g;
  $_[1] =~ s/\x{D}/\x{A}/g;

  return length($_[1]);
}

sub _eol_xml11 {
  my ($self, undef, $eof, $error_message_ref) = @_; # Buffer is in $_[1]

  #
  # If last character is a \x{D} this is undecidable unless eof flag
  #
  if (substr($_[1], -1, 1) eq "\x{D}") {
    if (! $eof) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
        $self->_logger->tracef('%s/%s: Last character in buffer is \\x{D} and requires another read', $self->xml_version, $self->start);
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
    #
    # For a character reference, append the referenced character to the normalized value.
    # In our case this is done by the parser when pushing.
    #
    if (ref($_)) { # ref() is faster
      #
      # For an entity reference, recursively apply step 3 of this algorithm to the replacement text of the entity.
      # EntityRef case.
      #
      $attvalue .= $self->attvalue($cdata, $entityref, $entityref->get($_));
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
PubidCharDquoteMany           ::= PUBIDCHARDQUOTEMANY
PubidCharSquoteMany           ::= PUBIDCHARSQUOTEMANY
PubidLiteral                  ::= DQUOTE PubidCharDquoteMany DQUOTE
                                | DQUOTE                     DQUOTE
                                | SQUOTE PubidCharSquoteMany SQUOTE
                                | SQUOTE                     SQUOTE

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
prolog                        ::= XMLDecl MiscAny
prolog                        ::=         MiscAny
prolog                        ::= XMLDecl MiscAny doctypedecl MiscAny
prolog                        ::=         MiscAny doctypedecl MiscAny
XMLDecl                       ::= XMLDECL_START VersionInfo EncodingDecl SDDecl S XMLDECL_END
XMLDecl                       ::= XMLDECL_START VersionInfo EncodingDecl SDDecl   XMLDECL_END
XMLDecl                       ::= XMLDECL_START VersionInfo EncodingDecl        S XMLDECL_END
XMLDecl                       ::= XMLDECL_START VersionInfo EncodingDecl          XMLDECL_END
XMLDecl                       ::= XMLDECL_START VersionInfo              SDDecl S XMLDECL_END
XMLDecl                       ::= XMLDECL_START VersionInfo              SDDecl   XMLDECL_END
XMLDecl                       ::= XMLDECL_START VersionInfo                     S XMLDECL_END
XMLDecl                       ::= XMLDECL_START VersionInfo                       XMLDECL_END
VersionInfo                   ::= S VERSION Eq SQUOTE VersionNum SQUOTE
VersionInfo                   ::= S VERSION Eq DQUOTE VersionNum DQUOTE
Eq                            ::= S EQUAL S
Eq                            ::= S EQUAL
Eq                            ::=   EQUAL S
Eq                            ::=   EQUAL
VersionNum                    ::= VERSIONNUM
Misc                          ::= Comment | PI | S
doctypedecl                   ::= DOCTYPE_START S Name              S LBRACKET intSubset RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name              S LBRACKET intSubset RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name                LBRACKET intSubset RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name                LBRACKET intSubset RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name              S                               DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name                                              DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name S ExternalID S LBRACKET intSubset RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name S ExternalID S LBRACKET intSubset RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name S ExternalID   LBRACKET intSubset RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name S ExternalID   LBRACKET intSubset RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name S ExternalID S                               DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name S ExternalID                                 DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
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
extSubset                     ::= TextDecl extSubsetDecl
extSubset                     ::=          extSubsetDecl
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
STag                          ::= ELEMENT_START STagName STagUnitAny S ELEMENT_END # [WFC: Unique Att Spec]
STag                          ::= ELEMENT_START STagName STagUnitAny   ELEMENT_END # [WFC: Unique Att Spec]
AttributeName                 ::= Name
Attribute                     ::= AttributeName Eq AttValue  # [VC: Attribute Value Type] [WFC: No External Entity References] [WFC: No < in Attribute Values]
ETag                          ::= ETAG_START Name S ETAG_END
ETag                          ::= ETAG_START Name   ETAG_END
contentUnit                   ::= element CharData
                                | element
                                | Reference CharData
                                | Reference
                                | CDSect CharData
                                | CDSect
                                | PI CharData
                                | PI
                                | Comment CharData
                                | Comment
contentUnitAny                ::= contentUnit*
content                       ::= CharData contentUnitAny
content                       ::=          contentUnitAny
EmptyElemTagUnit              ::= S Attribute
EmptyElemTagUnitAny           ::= EmptyElemTagUnit*
EmptyElemTag                  ::= ELEMENT_START Name EmptyElemTagUnitAny S EMPTYELEM_END   # [WFC: Unique Att Spec]
EmptyElemTag                  ::= ELEMENT_START Name EmptyElemTagUnitAny   EMPTYELEM_END   # [WFC: Unique Att Spec]
elementdecl                   ::= ELEMENTDECL_START S Name S contentspec S ELEMENTDECL_END # [VC: Unique Element Type Declaration]
elementdecl                   ::= ELEMENTDECL_START S Name S contentspec   ELEMENTDECL_END # [VC: Unique Element Type Declaration]
contentspec                   ::= EMPTY | ANY | Mixed | children
ChoiceOrSeq                   ::= choice | seq
children                      ::= ChoiceOrSeq
                                | ChoiceOrSeq QUESTIONMARK
                                | ChoiceOrSeq STAR
                                | ChoiceOrSeq PLUS
#
# Writen like this for the merged of XML+NS
#
NameOrChoiceOrSeq             ::= Name
NameOrChoiceOrSeq             ::= choice
NameOrChoiceOrSeq             ::= seq
cp                            ::= NameOrChoiceOrSeq
                                | NameOrChoiceOrSeq QUESTIONMARK
                                | NameOrChoiceOrSeq STAR
                                | NameOrChoiceOrSeq PLUS
choiceUnit                    ::= S OR S cp
choiceUnit                    ::= S OR   cp
choiceUnit                    ::=   OR S cp
choiceUnit                    ::=   OR   cp
choiceUnitMany                ::= choiceUnit+
choice                        ::= CHOICE_START S cp choiceUnitMany S CHOICE_END # [VC: Proper Group/PE Nesting]
choice                        ::= CHOICE_START S cp choiceUnitMany   CHOICE_END # [VC: Proper Group/PE Nesting]
choice                        ::= CHOICE_START   cp choiceUnitMany S CHOICE_END # [VC: Proper Group/PE Nesting]
choice                        ::= CHOICE_START   cp choiceUnitMany   CHOICE_END # [VC: Proper Group/PE Nesting]
seqUnit                       ::= S COMMA S cp
seqUnit                       ::= S COMMA   cp
seqUnit                       ::=   COMMA S cp
seqUnit                       ::=   COMMA   cp
seqUnitAny                    ::= seqUnit*
seq                           ::= SEQ_START S cp seqUnitAny S SEQ_END # [VC: Proper Group/PE Nesting]
seq                           ::= SEQ_START S cp seqUnitAny   SEQ_END # [VC: Proper Group/PE Nesting]
seq                           ::= SEQ_START   cp seqUnitAny S SEQ_END # [VC: Proper Group/PE Nesting]
seq                           ::= SEQ_START   cp seqUnitAny   SEQ_END # [VC: Proper Group/PE Nesting]
MixedUnit                     ::= S OR S Name
MixedUnit                     ::= S OR   Name
MixedUnit                     ::=   OR S Name
MixedUnit                     ::=   OR   Name
MixedUnitAny                  ::= MixedUnit*
Mixed                         ::= MIXED_START S PCDATA MixedUnitAny S MIXED_END1 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START S PCDATA MixedUnitAny   MIXED_END1 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START   PCDATA MixedUnitAny S MIXED_END1 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START   PCDATA MixedUnitAny   MIXED_END1 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START S PCDATA              S MIXED_END2 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START S PCDATA                MIXED_END2 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START   PCDATA              S MIXED_END2 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START   PCDATA                MIXED_END2 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
AttlistDecl                   ::= ATTLIST_START S Name AttDefAny S ATTLIST_END
AttlistDecl                   ::= ATTLIST_START S Name AttDefAny   ATTLIST_END
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
NotationTypeUnit              ::= S OR S Name
NotationTypeUnit              ::= S OR   Name
NotationTypeUnit              ::=   OR S Name
NotationTypeUnit              ::=   OR   Name
NotationTypeUnitAny           ::= NotationTypeUnit*
NotationType                  ::= NOTATION S NOTATION_START S Name NotationTypeUnitAny S NOTATION_END # [VC: Notation Attributes] [VC: One Notation Per Element Type] [VC: No Notation on Empty Element] [VC: No Duplicate Tokens]
NotationType                  ::= NOTATION S NOTATION_START S Name NotationTypeUnitAny   NOTATION_END # [VC: Notation Attributes] [VC: One Notation Per Element Type] [VC: No Notation on Empty Element] [VC: No Duplicate Tokens]
NotationType                  ::= NOTATION S NOTATION_START   Name NotationTypeUnitAny S NOTATION_END # [VC: Notation Attributes] [VC: One Notation Per Element Type] [VC: No Notation on Empty Element] [VC: No Duplicate Tokens]
NotationType                  ::= NOTATION S NOTATION_START   Name NotationTypeUnitAny   NOTATION_END # [VC: Notation Attributes] [VC: One Notation Per Element Type] [VC: No Notation on Empty Element] [VC: No Duplicate Tokens]
EnumerationUnit               ::= S OR S Nmtoken
EnumerationUnit               ::= S OR   Nmtoken
EnumerationUnit               ::=   OR S Nmtoken
EnumerationUnit               ::=   OR   Nmtoken
EnumerationUnitAny            ::= EnumerationUnit*
Enumeration                   ::= ENUMERATION_START S Nmtoken EnumerationUnitAny S ENUMERATION_END # [VC: Enumeration] [VC: No Duplicate Tokens]
Enumeration                   ::= ENUMERATION_START S Nmtoken EnumerationUnitAny   ENUMERATION_END # [VC: Enumeration] [VC: No Duplicate Tokens]
Enumeration                   ::= ENUMERATION_START   Nmtoken EnumerationUnitAny S ENUMERATION_END # [VC: Enumeration] [VC: No Duplicate Tokens]
Enumeration                   ::= ENUMERATION_START   Nmtoken EnumerationUnitAny   ENUMERATION_END # [VC: Enumeration] [VC: No Duplicate Tokens]
DefaultDecl                   ::= REQUIRED | IMPLIED
                                |            AttValue                              # [VC: Required Attribute] [VC: Attribute Default Value Syntactically Correct] [WFC: No < in Attribute Values] [VC: Fixed Attribute Default] [WFC: No External Entity References]
                                | FIXED S AttValue                              # [VC: Required Attribute] [VC: Attribute Default Value Syntactically Correct] [WFC: No < in Attribute Values] [VC: Fixed Attribute Default] [WFC: No External Entity References]
conditionalSect               ::= includeSect | ignoreSect
includeSect                   ::= INCLUDESECT_START S INCLUDE S LBRACKET extSubsetDecl          INCLUDESECT_END # [VC: Proper Conditional Section/PE Nesting]
includeSect                   ::= INCLUDESECT_START S INCLUDE   LBRACKET extSubsetDecl          INCLUDESECT_END # [VC: Proper Conditional Section/PE Nesting]
includeSect                   ::= INCLUDESECT_START   INCLUDE S LBRACKET extSubsetDecl          INCLUDESECT_END # [VC: Proper Conditional Section/PE Nesting]
includeSect                   ::= INCLUDESECT_START   INCLUDE   LBRACKET extSubsetDecl          INCLUDESECT_END # [VC: Proper Conditional Section/PE Nesting]
ignoreSect                    ::= IGNORESECT_START S  IGNORE  S LBRACKET ignoreSectContentsAny  IGNORESECT_END
                                | IGNORESECT_START S  IGNORE    LBRACKET ignoreSectContentsAny  IGNORESECT_END
                                | IGNORESECT_START    IGNORE  S LBRACKET ignoreSectContentsAny  IGNORESECT_END
                                | IGNORESECT_START    IGNORE    LBRACKET ignoreSectContentsAny  IGNORESECT_END
                                | IGNORESECT_START S  IGNORE  S LBRACKET                        IGNORESECT_END # [VC: Proper Conditional Section/PE Nesting]
                                | IGNORESECT_START S  IGNORE    LBRACKET                        IGNORESECT_END # [VC: Proper Conditional Section/PE Nesting]
                                | IGNORESECT_START    IGNORE  S LBRACKET                        IGNORESECT_END # [VC: Proper Conditional Section/PE Nesting]
                                | IGNORESECT_START    IGNORE    LBRACKET                        IGNORESECT_END # [VC: Proper Conditional Section/PE Nesting]
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
GEDecl                        ::= ENTITY_START S           Name S EntityDef S ENTITY_END
GEDecl                        ::= ENTITY_START S           Name S EntityDef   ENTITY_END
PEDecl                        ::= ENTITY_START S PERCENT S Name S PEDef     S ENTITY_END
PEDecl                        ::= ENTITY_START S PERCENT S Name S PEDef       ENTITY_END
EntityDef                     ::= EntityValue
                                | ExternalID
                                | ExternalID NDataDecl
PEDef                         ::= EntityValue
                                | ExternalID
ExternalID                    ::= SYSTEM S                SystemLiteral
                                | PUBLIC S PubidLiteral S SystemLiteral
NDataDecl                     ::= S NDATA S Name  # [VC: Notation Declared]
TextDecl                      ::= TEXTDECL_START VersionInfo EncodingDecl S TEXTDECL_END
TextDecl                      ::= TEXTDECL_START VersionInfo EncodingDecl   TEXTDECL_END
TextDecl                      ::= TEXTDECL_START             EncodingDecl S TEXTDECL_END
TextDecl                      ::= TEXTDECL_START             EncodingDecl   TEXTDECL_END
extParsedEnt                  ::= TextDecl content
extParsedEnt                  ::=          content
EncodingDecl                  ::= S ENCODING Eq DQUOTE EncName DQUOTE
EncodingDecl                  ::= S ENCODING Eq SQUOTE EncName SQUOTE
EncName                       ::= ENCNAME
NotationDecl                  ::= NOTATIONDECL_START S Name S ExternalID S NOTATIONDECL_END # [VC: Unique Notation Name]
NotationDecl                  ::= NOTATIONDECL_START S Name S ExternalID   NOTATIONDECL_END # [VC: Unique Notation Name]
NotationDecl                  ::= NOTATIONDECL_START S Name S   PublicID S NOTATIONDECL_END # [VC: Unique Notation Name]
NotationDecl                  ::= NOTATIONDECL_START S Name S   PublicID   NOTATIONDECL_END # [VC: Unique Notation Name]
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
_NCNAME ~ __ANYTHING
_PREFIX ~ __ANYTHING
_PUBIDCHARDQUOTEMANY ~ __ANYTHING
_PUBIDCHARSQUOTEMANY ~ __ANYTHING
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
_MIXED_START ~ __ANYTHING
_MIXED_END1 ~ __ANYTHING
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
_XMLNSCOLON ~ __ANYTHING
_XMLNS ~ __ANYTHING
_COLON ~ __ANYTHING

NAME ::= _NAME
NMTOKENMANY ::= _NMTOKENMANY
ENTITYVALUEINTERIORDQUOTEUNIT ::= _ENTITYVALUEINTERIORDQUOTEUNIT
ENTITYVALUEINTERIORSQUOTEUNIT ::= _ENTITYVALUEINTERIORSQUOTEUNIT
ATTVALUEINTERIORDQUOTEUNIT ::= _ATTVALUEINTERIORDQUOTEUNIT
ATTVALUEINTERIORSQUOTEUNIT ::= _ATTVALUEINTERIORSQUOTEUNIT
NOT_DQUOTEMANY ::= _NOT_DQUOTEMANY
NOT_SQUOTEMANY ::= _NOT_SQUOTEMANY
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
NCNAME ::= _NCNAME
PREFIX ::= _PREFIX
PUBIDCHARDQUOTEMANY ::= _PUBIDCHARDQUOTEMANY
PUBIDCHARSQUOTEMANY ::= _PUBIDCHARSQUOTEMANY
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
MIXED_START ::= _MIXED_START
MIXED_END1 ::= _MIXED_END1
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
XMLNSCOLON ::= _XMLNSCOLON
XMLNS ::= _XMLNS
COLON ::= _COLON

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
__[ xmlns10 ]__
#
# This will be evaled to return a transform entry point
#
sub {
    my ($self, $data) = @_;

    my $add     = ${$XMLNSBNF_ADD{$self->xml_version}};
    my $replace = ${$XMLNSBNF_REPLACE{$self->xml_version}};

    return $data;
}
__[ xmlns10:add ]__
#
# We do NOT want 
NSAttName	   ::= PrefixedAttName
                     | DefaultAttName
PrefixedAttName    ::= XMLNSCOLON NCName # [NSC: Reserved Prefixes and Namespace Names]
DefaultAttName     ::= XMLNS
NCName             ::= NCNAME            # Name - (Char* ':' Char*) /* An XML Name, minus the ":" */
QName              ::= PrefixedName
                     | UnprefixedName
PrefixedName       ::= Prefix COLON LocalPart
UnprefixedName     ::= LocalPart
Prefix             ::= PREFIX
LocalPart          ::= NCName

__[ xmlns10:replace ]__
STag               ::= ELEMENT_START QName STagUnitAny S ELEMENT_END           # [NSC: Prefix Declared]
STag               ::= ELEMENT_START QName STagUnitAny   ELEMENT_END           # [NSC: Prefix Declared]
ETag               ::= ETAG_START QName S ETAG_END                             # [NSC: Prefix Declared]
ETag               ::= ETAG_START QName   ETAG_END                             # [NSC: Prefix Declared]
EmptyElemTag       ::= ELEMENT_START QName EmptyElemTagUnitAny S EMPTYELEM_END # [NSC: Prefix Declared]
EmptyElemTag       ::= ELEMENT_START QName EmptyElemTagUnitAny   EMPTYELEM_END # [NSC: Prefix Declared]
Attribute          ::= NSAttName Eq AttValue
Attribute          ::= QName Eq AttValue                                            # [NSC: Prefix Declared][NSC: No Prefix Undeclaring][NSC: Attributes Unique]
doctypedeclUnit    ::= markupdecl | PEReference | S
doctypedeclUnitAny ::= doctypedeclUnit*
doctypedecl        ::= DOCTYPE_START S QName              S LBRACKET doctypedeclUnitAny RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName              S LBRACKET doctypedeclUnitAny RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName                LBRACKET doctypedeclUnitAny RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName                LBRACKET doctypedeclUnitAny RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName              S                                        DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName                                                       DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID S LBRACKET doctypedeclUnitAny RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID S LBRACKET doctypedeclUnitAny RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID   LBRACKET doctypedeclUnitAny RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID   LBRACKET doctypedeclUnitAny RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID S                                        DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID                                          DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
elementdecl        ::= ELEMENTDECL_START S QName S contentspec S ELEMENTDECL_END
elementdecl        ::= ELEMENTDECL_START S QName S contentspec   ELEMENTDECL_END
NameOrChoiceOrSeq  ::= QName
NameOrChoiceOrSeq  ::= choice
NameOrChoiceOrSeq  ::= seq
MixedUnit          ::= S OR S QName
MixedUnit          ::= S OR   QName
MixedUnit          ::=   OR S QName
MixedUnit          ::=   OR   QName
AttlistDecl        ::= ATTLIST_START S QName AttDefAny S ATTLIST_END
AttlistDecl        ::= ATTLIST_START S QName AttDefAny   ATTLIST_END
AttDef             ::= S QName     S AttType S DefaultDecl
AttDef             ::= S NSAttName S AttType S DefaultDecl

__[ xmlns10:or ]__
STag               ::= ELEMENT_START QName STagUnitAny S ELEMENT_END           # [NSC: Prefix Declared]  # xml standard also setted STag          ::= ELEMENT_START STagName STagUnitAny S ELEMENT_END
STag               ::= ELEMENT_START QName STagUnitAny   ELEMENT_END           # [NSC: Prefix Declared]  # xml standard also setted STag          ::= ELEMENT_START STagName STagUnitAny   ELEMENT_END
ETag               ::= ETAG_START QName S ETAG_END                             # [NSC: Prefix Declared]  # xml standard also setted ETag          ::= ETAG_START Name S? ETAG_END
ETag               ::= ETAG_START QName   ETAG_END                             # [NSC: Prefix Declared]  # xml standard also setted ETag          ::= ETAG_START Name S? ETAG_END
EmptyElemTag       ::= ELEMENT_START QName EmptyElemTagUnitAny S EMPTYELEM_END # [NSC: Prefix Declared]  # xml standard also setted EmptyElemTag  ::= ELEMENT_START Name EmptyElemTagUnitAny S EMPTYELEM_END
EmptyElemTag       ::= ELEMENT_START QName EmptyElemTagUnitAny   EMPTYELEM_END # [NSC: Prefix Declared]  # xml standard also setted EmptyElemTag  ::= ELEMENT_START Name EmptyElemTagUnitAny   EMPTYELEM_END
Attribute          ::= NSAttName Eq AttValue                                        # xml standard also setted Attribute ::= AttributeName Eq AttValue
                     | QName Eq AttValue                                            # [NSC: Prefix Declared][NSC: No Prefix Undeclaring][NSC: Attributes Unique]
doctypedeclUnit    ::= markupdecl | PEReference | S
doctypedeclUnitAny ::= doctypedeclUnit*
#
# xml standard also setted:
# doctypedecl                   ::= DOCTYPE_START S Name              S? LBRACKET intSubset RBRACKET S? DOCTYPE_END
# doctypedecl                   ::= DOCTYPE_START S Name              S?                                DOCTYPE_END
# doctypedecl                   ::= DOCTYPE_START S Name S ExternalID S? LBRACKET intSubset RBRACKET S? DOCTYPE_END
# doctypedecl                   ::= DOCTYPE_START S Name S ExternalID S?                                DOCTYPE_END
doctypedecl        ::= DOCTYPE_START S QName              S LBRACKET doctypedeclUnitAny RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName              S LBRACKET doctypedeclUnitAny RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName                LBRACKET doctypedeclUnitAny RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName                LBRACKET doctypedeclUnitAny RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName              S                                        DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName                                                       DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID S LBRACKET doctypedeclUnitAny RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID S LBRACKET doctypedeclUnitAny RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID   LBRACKET doctypedeclUnitAny RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID   LBRACKET doctypedeclUnitAny RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID S                                        DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID                                          DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
elementdecl        ::= ELEMENTDECL_START S QName S contentspec S ELEMENTDECL_END # xml standard also setted elementdecl ::= ELEMENTDECL_START S Name S contentspec S? ELEMENTDECL_END
elementdecl        ::= ELEMENTDECL_START S QName S contentspec   ELEMENTDECL_END # xml standard also setted elementdecl ::= ELEMENTDECL_START S Name S contentspec S? ELEMENTDECL_END
#
# This is HERE that there is a difference between the 'and' and the 'replace' sections
#
NameOrChoiceOrSeq  ::= QName                                                # xml standard also setted NameOrChoiceOrSeq ::= Name | choice | seq
MixedUnit          ::= S OR S QName                               # xml standard also setted MixedUnit         ::= S? OR S? Name
MixedUnit          ::= S OR   QName                               # xml standard also setted MixedUnit         ::= S? OR S? Name
MixedUnit          ::=   OR S QName                               # xml standard also setted MixedUnit         ::= S? OR S? Name
MixedUnit          ::=   OR   QName                               # xml standard also setted MixedUnit         ::= S? OR S? Name
AttlistDecl        ::= ATTLIST_START S QName AttDefAny S ATTLIST_END   # xml standard also setted AttlistDecl       ::= ATTLIST_START S Name AttDefAny S? ATTLIST_END
AttlistDecl        ::= ATTLIST_START S QName AttDefAny   ATTLIST_END   # xml standard also setted AttlistDecl       ::= ATTLIST_START S Name AttDefAny S? ATTLIST_END
AttDef             ::= S QName     S AttType S DefaultDecl                  # xml standard also setted AttDef            ::= S Name S AttType S DefaultDecl
                     | S NSAttName S AttType S DefaultDecl
