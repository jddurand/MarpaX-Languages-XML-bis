package MarpaX::Languages::XML::Impl::Parser;
use Marpa::R2;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Impl::Encoding;
use MarpaX::Languages::XML::Impl::Grammar;
use Moo;
use MooX::late;
use MooX::HandlesVia;
use MooX::Role::Logger;
use Scalar::Util qw/reftype/;
use Try::Tiny;
use Types::Standard qw/Int Str ConsumerOf InstanceOf HashRef/;
use Types::Common::Numeric qw/PositiveOrZeroInt/;

# ABSTRACT: MarpaX::Languages::XML::Role::parser implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is an implementation of MarpaX::Languages::XML::Role::Parser.

=cut

#
# Internal attributes
# -------------------

#
# Last lexemes
#
has _last_lexeme => (
                     is          => 'rw',
                     isa         => HashRef[Str],
                     default     => sub { {} },
                     handles_via => 'Hash',
                     handles     => {
                                     _get__last_lexeme => 'get',
                                     _set__last_lexeme => 'set',
                                    },
                    );

#
# Grammars (cached because of element recursivity)
#
has _grammars => (
                  is          => 'rw',
                  isa         => HashRef[InstanceOf['Marpa::R2::Scanless::G']],
                  handles_via => 'Hash',
                  default     => sub { {} },
                  handles     => {
                                  _exists__grammar => 'exists',
                                  _get__grammar    => 'get',
                                  _set__grammar    => 'set',
                                 },
                 );
#
# External attributes
# -------------------

has io => (
           is          => 'ro',
           isa         => ConsumerOf['MarpaX::Languages::XML::Role::IO'],
           required    => 1
          );

has LineNumber => (
                   is => 'ro',
                   isa => PositiveOrZeroInt,
                   writer => '_set_LineNumber',
                   default => 1
                  );

has ColumnNumber => (
                   is => 'ro',
                   isa => PositiveOrZeroInt,
                   writer => '_set_ColumnNumber',
                   default => 1
                  );

=head1 SEE ALSO

L<IO::All>, L<Marpa::R2>

=cut

sub _exception {
  my ($self, $message, $r) = @_;

  my %hash = (
              Message      => $message || '',
              LineNumber   => $self->LineNumber,
              ColumnNumber => $self->ColumnNumber
             );
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace && $r) {
    $hash{Progress} = $r->show_progress();
  }

  MarpaX::Languages::XML::Exception->throw(%hash);
}

sub _encoding {
  my ($self, $encoding) = @_;
  #
  # Read the first bytes. 1024 is far enough.
  #
  my $old_block_size = $self->io->block_size_value();
  if ($old_block_size != 1024) {
    $self->io->block_size(1024);
  }
  $self->io->read;
  if ($self->io->length <= 0) {
    $self->_exception('EOF when reading first bytes');
  }
  my $buffer = ${$self->io->buffer};

  my $bom_encoding = '';
  my $guess_encoding = '';

  my ($found_encoding, $byte_start) = $encoding->bom($buffer);
  if (length($found_encoding) <= 0) {
    $found_encoding = $encoding->guess($buffer);
    if (length($found_encoding) <= 0) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
        $self->_logger->debugf('Assuming relaxed (perl) utf8 encoding');
      }
      $found_encoding = 'UTF8';  # == utf8 == perl relaxed unicode
    } else {
      $guess_encoding = uc($found_encoding);
    }
    $byte_start = 0;
  } else {
    $bom_encoding = uc($found_encoding);
  }

  $self->io->encoding($found_encoding);

  #
  # Make sure we are positionned at the beginning of the buffer and at correct
  # source position. This is inefficient for everything that is not seekable.
  #
  $self->io->clear;
  $self->io->pos($byte_start);

  #
  # Restore original block size
  #
  if ($old_block_size != 1024) {
    $self->io->block_size($old_block_size);
  }

  #
  # The stream is supposed to be opened with the correct encoding, if any
  # If there was no guess from the BOM, default will be UTF-8. Nevertheless we
  # do NOT set it immediately: if it UTF-8, the beginning of the XML file will
  # start with one byte chars only, which is compatible with binary mode.
  # And if it is not UTF-8, the first chars will tell us more.
  # If the encoding is setted to something else but what the BOM eventually says
  # this will be handled by a callback from the grammar.
  #
  # An XML processor SHOULD work with case-insensitive encoding name. So we uc()
  # (note: per def an encoding name contains only Latin1 character, i.e. uc() is ok)
  #
  return ($bom_encoding, $guess_encoding, $found_encoding, $byte_start);
}

#
# Exclusions applied on the MATCHED DATA, not the original input
#
our %LEXEME_EXCLUSIONS = (
                          _PITARGET => qr{^xml$}i,
                         );

our %LEXEME_REGEXPS = (
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

our %G1_DESCRIPTIONS = (
                       #
                       # These G1 events are lexemes predictions, but BEFORE the input stream is tentatively read by Marpa
                       #
                      '^NAME'                          => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'NAME', lexeme_name => '_NAME' },
                      '^NMTOKENMANY'                   => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'NMTOKENMANY', lexeme_name => '_NMTOKENMANY' },
                      '^ENTITYVALUEINTERIORDQUOTEUNIT' => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITYVALUEINTERIORDQUOTEUNIT', lexeme_name => '_ENTITYVALUEINTERIORDQUOTEUNIT' },
                      '^ENTITYVALUEINTERIORSQUOTEUNIT' => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITYVALUEINTERIORSQUOTEUNIT', lexeme_name => '_ENTITYVALUEINTERIORSQUOTEUNIT' },
                      '^ATTVALUEINTERIORDQUOTEUNIT'    => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ATTVALUEINTERIORDQUOTEUNIT', lexeme_name => '_ATTVALUEINTERIORDQUOTEUNIT' },
                      '^ATTVALUEINTERIORSQUOTEUNIT'    => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ATTVALUEINTERIORSQUOTEUNIT', lexeme_name => '_ATTVALUEINTERIORSQUOTEUNIT' },
                      '^NOT_DQUOTEMANY'                => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'NOT_DQUOTEMANY', lexeme_name => '_NOT_DQUOTEMANY' },
                      '^NOT_SQUOTEMANY'                => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'NOT_SQUOTEMANY', lexeme_name => '_NOT_SQUOTEMANY' },
                      '^PUBIDCHARDQUOTE'               => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'PUBIDCHARDQUOTE', lexeme_name => '_PUBIDCHARDQUOTE' },
                      '^PUBIDCHARSQUOTE'               => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'PUBIDCHARSQUOTE', lexeme_name => '_PUBIDCHARSQUOTE' },
                      '^CHARDATAMANY'                  => { fixed_length => 0, type => 'predicted', min_chars =>  3, symbol_name => 'CHARDATAMANY', lexeme_name => '_CHARDATAMANY' },    # [^<&]+ without ']]>'
                      '^COMMENTCHARMANY'               => { fixed_length => 0, type => 'predicted', min_chars =>  2, symbol_name => 'COMMENTCHARMANY', lexeme_name => '_COMMENTCHARMANY' }, # Char* without '--'
                      '^PITARGET'                      => { fixed_length => 0, type => 'predicted', min_chars =>  3, symbol_name => 'PITARGET', lexeme_name => '_PITARGET' },        # NAME but /xml/i
                      '^CDATAMANY'                     => { fixed_length => 0, type => 'predicted', min_chars =>  3, symbol_name => 'CDATAMANY', lexeme_name => '_CDATAMANY' },       # Char* minus ']]>'
                      '^PICHARDATAMANY'                => { fixed_length => 0, type => 'predicted', min_chars =>  2, symbol_name => 'PICHARDATAMANY', lexeme_name => '_PICHARDATAMANY' },  # Char* minus '?>'
                      '^IGNOREMANY'                    => { fixed_length => 0, type => 'predicted', min_chars =>  3, symbol_name => 'IGNOREMANY', lexeme_name => '_IGNOREMANY' },      # Char minus* ('<![' or ']]>')
                      '^DIGITMANY'                     => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'DIGITMANY', lexeme_name => '_DIGITMANY' },
                      '^ALPHAMANY'                     => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ALPHAMANY', lexeme_name => '_ALPHAMANY' },
                      '^ENCNAME'                       => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ENCNAME', lexeme_name => '_ENCNAME' },
                      '^S'                             => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'S', lexeme_name => '_S' },
                      #
                      # These are the lexemes of predicted size
                      #
                      '^SPACE'                         => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'SPACE', lexeme_name => '_SPACE' },
                      '^DQUOTE'                        => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'DQUOTE', lexeme_name => '_DQUOTE' },
                      '^SQUOTE'                        => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'SQUOTE', lexeme_name => '_SQUOTE' },
                      '^COMMENT_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  4, symbol_name => 'COMMENT_START', lexeme_name => '_COMMENT_START' },
                      '^COMMENT_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'COMMENT_END', lexeme_name => '_COMMENT_END' },
                      '^PI_START'                      => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'PI_START', lexeme_name => '_PI_START' },
                      '^PI_END'                        => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'PI_END', lexeme_name => '_PI_END' },
                      '^CDATA_START'                   => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'CDATA_START', lexeme_name => '_CDATA_START' },
                      '^CDATA_END'                     => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'CDATA_END', lexeme_name => '_CDATA_END' },
                      '^XMLDECL_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'XMLDECL_START', lexeme_name => '_XMLDECL_START' },
                      '^XMLDECL_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'XMLDECL_END', lexeme_name => '_XMLDECL_END' },
                      '^VERSION'                       => { fixed_length => 1, type => 'predicted', min_chars =>  7, symbol_name => 'VERSION', lexeme_name => '_VERSION' },
                      '^EQUAL'                         => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'EQUAL', lexeme_name => '_EQUAL' },
                      '^VERSIONNUM'                    => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'VERSIONNUM', lexeme_name => '_VERSIONNUM' },
                      '^DOCTYPE_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'DOCTYPE_START', lexeme_name => '_DOCTYPE_START' },
                      '^DOCTYPE_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'DOCTYPE_END', lexeme_name => '_DOCTYPE_END' },
                      '^LBRACKET'                      => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'LBRACKET', lexeme_name => '_LBRACKET' },
                      '^RBRACKET'                      => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'RBRACKET', lexeme_name => '_RBRACKET' },
                      '^STANDALONE'                    => { fixed_length => 1, type => 'predicted', min_chars => 10, symbol_name => 'STANDALONE', lexeme_name => '_STANDALONE' },
                      '^YES'                           => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'YES', lexeme_name => '_YES' },
                      '^NO'                            => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'NO', lexeme_name => '_NO' },
                      '^ELEMENT_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ELEMENT_START', lexeme_name => '_ELEMENT_START' },
                      '^ELEMENT_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ELEMENT_END', lexeme_name => '_ELEMENT_END' },
                      '^ETAG_START'                    => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'ETAG_START', lexeme_name => '_ETAG_START' },
                      '^ETAG_END'                      => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ETAG_END', lexeme_name => '_ETAG_END' },
                      '^EMPTYELEM_END'                 => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'EMPTYELEM_END', lexeme_name => '_EMPTYELEM_END' },
                      '^ELEMENTDECL_START'             => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'ELEMENTDECL_START', lexeme_name => '_ELEMENTDECL_START' },
                      '^ELEMENTDECL_END'               => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ELEMENTDECL_END', lexeme_name => '_ELEMENTDECL_END' },
                      '^EMPTY'                         => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'EMPTY', lexeme_name => '_EMPTY' },
                      '^ANY'                           => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'ANY', lexeme_name => '_ANY' },
                      '^QUESTIONMARK'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'QUESTIONMARK', lexeme_name => '_QUESTIONMARK' },
                      '^STAR'                          => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'STAR', lexeme_name => '_STAR' },
                      '^PLUS'                          => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'PLUS', lexeme_name => '_PLUS' },
                      '^OR'                            => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'OR', lexeme_name => '_OR' },
                      '^CHOICE_START'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'CHOICE_START', lexeme_name => '_CHOICE_START' },
                      '^CHOICE_END'                    => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'CHOICE_END', lexeme_name => '_CHOICE_END' },
                      '^SEQ_START'                     => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'SEQ_START', lexeme_name => '_SEQ_START' },
                      '^SEQ_END'                       => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'SEQ_END', lexeme_name => '_SEQ_END' },
                      '^MIXED_START1'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'MIXED_START1', lexeme_name => '_MIXED_START1' },
                      '^MIXED_END1'                    => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'MIXED_END1', lexeme_name => '_MIXED_END1' },
                      '^MIXED_START2'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'MIXED_START2', lexeme_name => '_MIXED_START2' },
                      '^MIXED_END2'                    => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'MIXED_END2', lexeme_name => '_MIXED_END2' },
                      '^COMMA'                         => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'COMMA', lexeme_name => '_COMMA' },
                      '^PCDATA'                        => { fixed_length => 1, type => 'predicted', min_chars =>  7, symbol_name => 'PCDATA', lexeme_name => '_PCDATA' },
                      '^ATTLIST_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'ATTLIST_START', lexeme_name => '_ATTLIST_START' },
                      '^ATTLIST_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ATTLIST_END', lexeme_name => '_ATTLIST_END' },
                      '^CDATA'                         => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'CDATA', lexeme_name => '_CDATA' },
                      '^ID'                            => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'ID', lexeme_name => '_ID' },
                      '^IDREF'                         => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'IDREF', lexeme_name => '_IDREF' },
                      '^IDREFS'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'IDREFS', lexeme_name => '_IDREFS' },
                      '^ENTITY'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'ENTITY', lexeme_name => '_ENTITY' },
                      '^ENTITIES'                      => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'ENTITIES', lexeme_name => '_ENTITIES' },
                      '^NMTOKEN'                       => { fixed_length => 1, type => 'predicted', min_chars =>  7, symbol_name => 'NMTOKEN', lexeme_name => '_NMTOKEN' },
                      '^NMTOKENS'                      => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'NMTOKENS', lexeme_name => '_NMTOKENS' },
                      '^NOTATION'                      => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'NOTATION', lexeme_name => '_NOTATION' },
                      '^NOTATION_START'                => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'NOTATION_START', lexeme_name => '_NOTATION_START' },
                      '^NOTATION_END'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'NOTATION_END', lexeme_name => '_NOTATION_END' },
                      '^ENUMERATION_START'             => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENUMERATION_START', lexeme_name => '_ENUMERATION_START' },
                      '^ENUMERATION_END'               => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENUMERATION_END', lexeme_name => '_ENUMERATION_END' },
                      '^REQUIRED'                      => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'REQUIRED', lexeme_name => '_REQUIRED' },
                      '^IMPLIED'                       => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'IMPLIED', lexeme_name => '_IMPLIED' },
                      '^FIXED'                         => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'FIXED', lexeme_name => '_FIXED' },
                      '^INCLUDE'                       => { fixed_length => 1, type => 'predicted', min_chars =>  7, symbol_name => 'INCLUDE', lexeme_name => '_INCLUDE' },
                      '^IGNORE'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'IGNORE', lexeme_name => '_IGNORE' },
                      '^INCLUDESECT_START'             => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'INCLUDESECT_START', lexeme_name => '_INCLUDESECT_START' },
                      '^INCLUDESECT_END'               => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'INCLUDESECT_END', lexeme_name => '_INCLUDESECT_END' },
                      '^IGNORESECT_START'              => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'IGNORESECT_START', lexeme_name => '_IGNORESECT_START' },
                      '^IGNORESECT_END'                => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'IGNORESECT_END', lexeme_name => '_IGNORESECT_END' },
                      '^IGNORESECTCONTENTSUNIT_START'  => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'IGNORESECTCONTENTSUNIT_START', lexeme_name => '_IGNORESECTCONTENTSUNIT_START' },
                      '^IGNORESECTCONTENTSUNIT_END'    => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'IGNORESECTCONTENTSUNIT_END', lexeme_name => '_IGNORESECTCONTENTSUNIT_END' },
                      '^CHARREF_START1'                => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'CHARREF_START1', lexeme_name => '_CHARREF_START1' },
                      '^CHARREF_END1'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'CHARREF_END1', lexeme_name => '_CHARREF_END1' },
                      '^CHARREF_START2'                => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'CHARREF_START2', lexeme_name => '_CHARREF_START2' },
                      '^CHARREF_END2'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'CHARREF_END2', lexeme_name => '_CHARREF_END2' },
                      '^ENTITYREF_START'               => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITYREF_START', lexeme_name => '_ENTITYREF_START' },
                      '^ENTITYREF_END'                 => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITYREF_END', lexeme_name => '_ENTITYREF_END' },
                      '^PEREFERENCE_START'             => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'PEREFERENCE_START', lexeme_name => '_PEREFERENCE_START' },
                      '^PEREFERENCE_END'               => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'PEREFERENCE_END', lexeme_name => '_PEREFERENCE_END' },
                      '^ENTITY_START'                  => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'ENTITY_START', lexeme_name => '_ENTITY_START' },
                      '^ENTITY_END'                    => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITY_END', lexeme_name => '_ENTITY_END' },
                      '^PERCENT'                       => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'PERCENT', lexeme_name => '_PERCENT' },
                      '^SYSTEM'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'SYSTEM', lexeme_name => '_SYSTEM' },
                      '^PUBLIC'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'PUBLIC', lexeme_name => '_PUBLIC' },
                      '^NDATA'                         => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'NDATA', lexeme_name => '_NDATA' },
                      '^TEXTDECL_START'                => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'TEXTDECL_START', lexeme_name => '_TEXTDECL_START' },
                      '^TEXTDECL_END'                  => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'TEXTDECL_END', lexeme_name => '_TEXTDECL_END' },
                      '^ENCODING'                      => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'ENCODING', lexeme_name => '_ENCODING' },
                      '^NOTATIONDECL_START'            => { fixed_length => 1, type => 'predicted', min_chars => 10, symbol_name => 'NOTATIONDECL_START', lexeme_name => '_NOTATIONDECL_START' },
                      '^NOTATIONDECL_END'              => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'NOTATIONDECL_END', lexeme_name => '_NOTATIONDECL_END' },
                     );

#
# It is assumed that caller ONLY USE completed or nulled events
# The predicted events are RESERVED for lexeme prediction.
#
sub _generic_parse {
  #
  # buffer is accessed using $_[1] to avoid dereferencing $self->io->buffer everytime
  #
  my ($self,
      undef,
      $start_symbol, $end_event_name,
      $lengthp,
      $posp, $global_posp,
      $hash_ref,
      $internal_events_ref, $switches_ref) = @_;

  my $length = ${$lengthp};
  my $pos = ${$posp};
  my $global_pos = ${$global_posp};
  my $remaining = $length - $pos;

  #
  # Create grammar if necesssary
  #
  my $g = $self->_exists__grammar($start_symbol) ?
    $self->_get__grammar($start_symbol)
    :
    $self->_set__grammar($start_symbol, MarpaX::Languages::XML::Impl::Grammar->new->compile(%{$hash_ref},
                                                                                            start => $start_symbol,
                                                                                            #
                                                                                            # G1_DESCRIPTIONS have priority over $internal_events_ref:
                                                                                            # If $internal_events_ref is using a lexeme prediction event
                                                                                            # we will fake it
                                                                                            #
                                                                                            internal_events => {
                                                                                                                %G1_DESCRIPTIONS,
                                                                                                                map { $_ => $internal_events_ref->{$_} } grep {! exists($G1_DESCRIPTIONS{$_})} keys %{$internal_events_ref}
                                                                                                               }
                                                                                           ));
  ;

  #
  # Create a recognizer
  #
  my $r = Marpa::R2::Scanless::R->new({ grammar => $g });

  #
  # Loop on input
  #
  for (
       #
       # The buffer for Marpa is not of importance here, but two bytes at least for the length to avoid exhaustion.
       # Since we pause on everything, read() and resume() always never change position in the virtual buffer
       #
       $r->read(\'  ')
       ;
       ;
       #
       # Resume will croak if grammar is exhausted. We handle this case ourself (absence of prediction + remaining chargs)
       #
       $r->resume()
      ) {
    my $can_stop = 0;
    my @event_names = map { $_->[0] } @{$r->events()};
    if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
      $self->_logger->tracef('[%d:%d] Events: %s', $self->LineNumber, $self->ColumnNumber, \@event_names);
    }

  manage_events:
    #
    # Predicted events always come first -;
    #
    my $have_prediction = 0;
    my $data;
    my %length = ();
    my $max_length = 0;
    my @predicted_lexemes = ();
    foreach (@event_names) {
      if (exists($G1_DESCRIPTIONS{$_})) {
        #
        # INTERNAL PREDICTION EVENTS
        # --------------------------
        $have_prediction = 1;
        my $lexeme_name = $G1_DESCRIPTIONS{$_}->{lexeme_name};
        push(@predicted_lexemes, $lexeme_name);
        #
        # Check if the decision about this lexeme can be done
        #
        if ($G1_DESCRIPTIONS{$_}->{min_chars} > $remaining) {
          my $old_remaining = $remaining;
          if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
            $self->_logger->tracef('[%d:%d] Lexeme %s requires %d chars > %d remaining for decidability', $self->LineNumber, $self->ColumnNumber, $lexeme_name, $G1_DESCRIPTIONS{$_}->{min_chars}, $remaining);
          }
          $remaining = $length = ${$lengthp} = $self->_reduceAndRead($pos, $_[1], $length, 0, $r);
          ${$posp} = $pos = 0;
          if ($remaining > $old_remaining) {
            #
            # Something was read
            #
            goto manage_events;
          } else {
            if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
              $self->_logger->debugf('[%d:%d] Nothing more read', $self->LineNumber, $self->ColumnNumber);
            }
          }
        }
        #
        # Check if this variable length lexeme is reaching the end of the buffer.
        #
        pos($_[1]) = $pos;
        if ($_[1] =~ $LEXEME_REGEXPS{$lexeme_name}) {
          my $matched_data = substr($_[1], $-[0], $+[0] - $-[0]);
          if (exists($LEXEME_EXCLUSIONS{$lexeme_name}) && ($matched_data =~ $LEXEME_EXCLUSIONS{$lexeme_name})) {
            if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
              $self->_logger->tracef('[%d:%d] Lexeme %s match excluded', $self->LineNumber, $self->ColumnNumber, $lexeme_name);
            }
          } else {
            if (($+[0] >= $length) && ! $G1_DESCRIPTIONS{$_}->{fixed_length}) {
              if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
                $self->_logger->tracef('[%d:%d] Lexeme %s is of unpredicted size and currently reaches end-of-buffer', $self->LineNumber, $self->ColumnNumber, $lexeme_name);
              }
              my $old_remaining = $remaining;
              $remaining = $length = ${$lengthp} = $self->_reduceAndRead($pos, $_[1], $length, 0, $r);
              ${$posp} = $pos = 0;
              if ($remaining > $old_remaining) {
                #
                # Something was read
                #
                goto manage_events;
              } else {
                if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                  $self->_logger->debugf('[%d:%d] Nothing more read', $self->LineNumber, $self->ColumnNumber);
                }
              }
            }
            $length{$lexeme_name} = $+[0] - $-[0];
            if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
              $self->_logger->tracef('[%d:%d] %s: match of length %d', $self->LineNumber, $self->ColumnNumber, $lexeme_name, $length{$lexeme_name});
            }
            if ((! $max_length) || ($length{$lexeme_name} > $max_length)) {
              $data = $matched_data;
              $max_length = $length{$lexeme_name};
            }
          }
        } else {
          if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
            $self->_logger->tracef('[%d:%d] %s: no match', $self->LineNumber, $self->ColumnNumber, $lexeme_name);
          }
        }
      } else {
        #
        # ANY OTHER EVENT
        # ---------------
        if ($_ eq $end_event_name) {
          $can_stop = 1;
          if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
            $self->_logger->debugf('[%d:%d] Grammar end event %s', $self->LineNumber, $self->ColumnNumber, $_);
          }
        }
        #
        # Callback ?
        #
        my $code = $switches_ref->{$_};
        my $rc_switch = defined($code) ? $self->$code() : 1;
        #
        # Any false return value mean immediate stop
        #
        if (! $rc_switch) {
          if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
            $self->_logger->debugf('[%d:%d] Event callback %s says to stop', $self->LineNumber, $self->ColumnNumber, $_);
          }
          return;
        }
      }
    }
    if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
      $self->_logger->tracef('[%d:%d] have_prediction %d can_stop %d length %s', $self->LineNumber, $self->ColumnNumber, $have_prediction, $can_stop, \%length);
    }
    if ($have_prediction) {
      if (! $max_length) {
        if ($can_stop) {
          if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
            $self->_logger->tracef('[%d:%d] No predicted lexeme found but grammar end flag is on', $self->LineNumber, $self->ColumnNumber);
          }
          return;
        } else {
          $self->_exception(sprintf('No predicted lexeme found: %s', join(', ', @predicted_lexemes)), $r);
        }
      } else {
        my @alternatives = grep { $length{$_} == $max_length } keys %length;
        if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
          $self->_logger->debugf('[%d:%d] Lexeme alternative %s', $self->LineNumber, $self->ColumnNumber, \@alternatives);
        }
        my @lexeme_complete_events = ();
        my ($next_global_line, $next_global_column, $next_global_pos, $next_pos) = ($self->LineNumber, $self->ColumnNumber, $global_pos, $pos);
        #
        # Update position and remaining chars in internal buffer, global line and column numbers. Wou might think it is too early, but
        # this is to have the expected next positions when doing predicted lexeme callbacks.
        #
        my $linebreaks = () = $data =~ /\R/g;
        if ($linebreaks) {
          $next_global_line += $linebreaks;
          $next_global_column = 1;
        } else {
          $next_global_column += $max_length;
        }
        $next_pos        += $max_length;
        $next_global_pos += $max_length;
        foreach (@alternatives) {
          #
          # Callback on lexeme prediction
          #
          my $code = $switches_ref->{"^$_"};
          my $rc_switch = defined($code) ? $self->$code($data, $global_pos, $pos, $next_global_line, $next_global_column, $next_global_pos, $next_pos) : 1;
          if (! $rc_switch) {
            if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
              $self->_logger->debugf('[%d:%d] Event callback %s says to stop', $self->LineNumber, $self->ColumnNumber, "^$_");
            }
            return;
          }
          #
          # Push alternative
          #
          $r->lexeme_alternative($_);
          $self->_set__last_lexeme($_, $data);
          #
          # Our stream is virtual, i.e. Marpa will never see the lexemes.
          # So we handle ourself the callbacks on lexeme completion.
          #
          push(@lexeme_complete_events, "$_\$");
        }
        if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
          $self->_logger->tracef('[%d:%d->%d:%d] Lexeme complete of length %d', $self->LineNumber, $self->ColumnNumber, $next_global_line, $next_global_column, $max_length);
        }
        #
        # Position 0 and length 1: the Marpa input buffer is virtual
        #
        $r->lexeme_complete(0, 1);
        #
        # Fake the lexeme completion events
        #
        foreach (@lexeme_complete_events) {
          my $code = $switches_ref->{$_};
          my $rc_switch = defined($code) ? $self->$code($data, $global_pos, $pos, $next_global_line, $next_global_column, $next_global_pos, $next_pos) : 1;
          if (! $rc_switch) {
            if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
              $self->_logger->debugf('[%d:%d] Event callback %s says to stop', $self->LineNumber, $self->ColumnNumber, $_);
            }
            return;
          }
        }
        $self->_set_LineNumber($next_global_line);
        $self->_set_ColumnNumber($next_global_column);
        ${$global_posp}    = $global_pos    = $next_global_pos;
        ${$posp}           = $pos           = $next_pos;
        $remaining -= $max_length;
        #
        # lexeme complete can generate new events: handle them before eventually resuming
        #
        @event_names = map { $_->[0] } @{$r->events()};
        if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
          $self->_logger->tracef('[%d:%d] Events: %s', $self->LineNumber, $self->ColumnNumber, \@event_names);
        }
        goto manage_events;
      }
    } else {
      #
      # No prediction: this is ok only if grammar end_of_grammar flag is set
      #
      if ($can_stop) {
        if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
          $self->_logger->tracef('[%d:%d] No prediction and grammar end flag is on', $self->LineNumber, $self->ColumnNumber);
        }
        return;
      } else {
        $self->_exception('No prediction and grammar end flag is not set', $r);
      }
    }
  }

  return;
}

sub _reduceAndRead {
  my ($self, $pos, undef, $length, $eof_is_fatal, $r) = @_;
  #
  # Crunch previous data
  #
  if ($pos > 0) {
    #
    # Faster like this -;
    #
    if ($pos >= $length) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
        $self->_logger->debugf('[%d:%d] Rolling-out buffer', $self->LineNumber, $self->ColumnNumber);
      }
      $_[2] = '';
    } else {
      if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
        $self->_logger->debugf('[%d:%d] Rolling-out %d characters', $self->LineNumber, $self->ColumnNumber, $pos);
      }
      substr($_[2], 0, $pos, '');
    }
  }
  #
  # Read more data
  #
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('[%d:%d] Reading data', $self->LineNumber, $self->ColumnNumber);
  }
  return $self->_read($eof_is_fatal, $r);
}

sub _read {
  my ($self, $eof_is_fatal, $r) = @_;

  $eof_is_fatal //= 1;

  $self->io->read;
  my $new_length;
  if (($new_length = $self->io->length) <= 0) {
    if ($eof_is_fatal) {
      $self->_exception('EOF', $r);
    } else {
      if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
        $self->_logger->debugf('[%d:%d] EOF', $self->LineNumber, $self->ColumnNumber);
      }
    }
  }
  return $new_length;
}

sub _start_document {
  my ($self, $user_code, @args) = @_;

  if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
    $self->_logger->debugf('[%d:%d] SAX event start_document', $self->LineNumber, $self->ColumnNumber);
  }
  #
  # No argument for start_document
  #
  $self->$user_code(@args);
  return 1;
}

sub parse {
  my ($self, $hash_ref) = @_;

  #
  # Localized variables
  #
  local $MarpaX::Languages::XML::Impl::Parser::is_trace = $self->_logger->is_trace;
  local $MarpaX::Languages::XML::Impl::Parser::is_debug = $self->_logger->is_debug;
  local $MarpaX::Languages::XML::Impl::Parser::is_warn  = $self->_logger->is_warn;

  $hash_ref //= {};

  #
  # Sanity checks
  #
  my $block_size = $hash_ref->{block_size} || 11;
  if (reftype($block_size)) {
    $self->_exception('block_size must be a SCALAR');
  }

  my $sax_handlers_ref = $hash_ref->{sax_handlers} || {};
  if ((reftype($sax_handlers_ref) || '') ne 'HASH') {
    $self->_exception('SAX handlers must be a ref to HASH');
  }

  try {
    # ------------------
    # "Global variables"
    # ------------------
    my $pos = 0;
    my $global_pos = 0;
    #
    # ------------
    # Parse prolog
    # ------------
    #
    # Encoding object instance
    #
    my $encoding = MarpaX::Languages::XML::Impl::Encoding->new();
    my ($bom_encoding, $guess_encoding, $orig_encoding, $byte_start)  = $self->_encoding($encoding);
    if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
      $self->_logger->debugf('[%d:%d] BOM and/or guess gives encoding %s and byte offset %d', $self->LineNumber, $self->ColumnNumber, $orig_encoding, $byte_start);
    }
    my $nb_retry_because_of_encoding = 0;
  retry_because_of_encoding:
    #
    # We want to handle buffer direcly with no COW
    #
    my $buffer;
    $self->io->buffer($buffer);
    #
    # Very initial block size and read
    #
    $self->io->block_size($block_size);
    $self->io->read;
    #
    # Go
    #
    my $final_encoding = $orig_encoding;
    my %internal_events = (
                           'prolog$'          => { end_of_grammar => 1, type => 'completed', symbol_name => 'prolog' },
                          );
    my %switches = (
                    '^_ENCNAME'  => sub {
                      my ($self, $data, $global_pos, $pos, $next_global_line, $next_global_column, $next_global_pos, $next_pos) = @_;
                      #
                      # Encoding is composed only of ASCII codepoints, so uc is ok
                      #
                      my $xml_encoding = uc($data);
                      if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                        $self->_logger->debugf('[%d:%d] XML says encoding %s', $self->LineNumber, $self->ColumnNumber, $xml_encoding);
                      }
                      #
                      # Check eventual encoding v.s. endianness. Algorithm vaguely taken from
                      # https://blogs.oracle.com/tucu/entry/detecting_xml_charset_encoding_again
                      #
                      $final_encoding = $encoding->final($bom_encoding, $guess_encoding, $xml_encoding);
                      return ($final_encoding eq $orig_encoding);
                    },
                    '^_ELEMENT_START'  => sub {
                      my ($self, $data, $global_pos, $pos, $next_global_line, $next_global_column, $next_global_pos, $next_pos) = @_;
                      if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                        $self->_logger->debugf('[%d:%d->%d:%d] ELEMENT_START lexeme prediction event', $self->LineNumber, $self->ColumnNumber, $next_global_line, $next_global_column);
                      }
                      return 0;
                    },
                   );
    #
    # Add events and internal switches for SAX events
    #
    foreach (keys %{$sax_handlers_ref}) {
      my $user_code = $sax_handlers_ref->{$_};
      #
      # At this step only start_document is supported
      #
      if ($_ eq 'start_document') {
        $switches{$_} = sub {
          my ($self) = @_;
          #
          # No argument for start_document
          #
          return $self->_start_document($user_code);
        };
      }
    }
    $global_pos = $byte_start;
    my $length = $self->io->length;
    #
    # From now on, there are a lot of arguments that are always the same. Make it an array
    # for readability.
    #
    my @generic_parse_common_args = (
                                     \$length,          # buffer length
                                     \$pos,             # posp
                                     \$global_pos,      # global_posp
                                     $hash_ref,         # $hash_ref
                                     \%internal_events, # internal_events_ref,
                                     \%switches,        # switches
                                    );
    $self->_generic_parse(
                          $buffer,           # buffer
                          'document',        # start_symbol
                          'prolog$',         # end_event_name
                          @generic_parse_common_args
                         );
    if ($final_encoding ne $orig_encoding) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
        $self->_logger->debugf('[%d:%d] Redoing parse using encoding %s instead of %s', $self->LineNumber, $self->ColumnNumber, $final_encoding, $orig_encoding);
      }
      #
      # Set encoding
      #
      $self->io->encoding($final_encoding);
      #
      # Clear buffer
      #
      $self->io->clear;
      #
      # If there was a recognized BOM, maintain byte_start
      #
      $self->io->pos($byte_start);
      if (++$nb_retry_because_of_encoding == 1) {
        $orig_encoding = $final_encoding;
        $pos = 0;
        $self->_set_LineNumber(1);
        $self->_set_ColumnNumber(1);
        $global_pos = $byte_start;
        goto retry_because_of_encoding;
      } else {
        MarpaX::Languages::XML::Exception->throw("Two many retries because of encoding difference beween BOM, guess and XML");
      }
    }

    # -------------
    # Parse element - we use a stack free implementation because perl is(was?) not very good at recursion
    # -------------
    %internal_events = (
                        'element$'       => { fixed_length => 0, end_of_grammar => 1, type => 'completed', symbol_name => 'element' },
                        'AttributeName$' => { fixed_length => 0, end_of_grammar => 0, type => 'completed', symbol_name => 'AttributeName' },
                       );
    %switches = (
                 '^_ELEMENT_START'  => sub {
                   my ($self, $data, $global_pos, $pos, $next_global_line, $next_global_column, $next_global_pos, $next_pos) = @_;
                   #
                   # Inner element -> new recognizer
                   #
                   if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                     $self->_logger->debugf('[%d:%d->%d:%d] ELEMENT_START lexeme prediction event', $self->LineNumber, $self->ColumnNumber, $next_global_line, $next_global_column);
                   }
                   return 0;
                 },
                 'AttributeName$'  => sub {
                   my ($self) = @_;
                   my $AttributeName = $self->_get__last_lexeme('_NAME');
                   if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                     $self->_logger->debugf('[%d:%d] Attribute %s', $AttributeName);
                   }
                   return 1;
                 }
                );
    $self->_generic_parse(
                          $buffer,           # buffer
                          'element',         # start_symbol
                          'element$',        # end_event_name
                          @generic_parse_common_args
                         );
  } catch {
    $self->_exception("$_");
    return;
  };

}

with 'MooX::Role::Logger';
with 'MarpaX::Languages::XML::Role::Parser';

1;
