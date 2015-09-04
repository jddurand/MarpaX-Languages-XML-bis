package MarpaX::Languages::XML::Impl::Parser;
use Marpa::R2;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Impl::Encoding;
use MarpaX::Languages::XML::Impl::Grammar;
use MarpaX::Languages::XML::Impl::Logger;
use Moo;
use MooX::HandlesVia;
use MooX::late;
use Scalar::Util qw/reftype/;
use Try::Tiny;
use Types::Standard qw/Int ConsumerOf InstanceOf HashRef/;
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
# Offset position in the internal buffer
#
has _offset => (
                is          => 'rw',
                isa         => PositiveOrZeroInt,
                default     => 0,
                handles_via => 'Number',
                handles     => {
                                _set__offset => 'set',
                                _add__offset => 'add',
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
#
has io => (
           is          => 'rw',
           isa         => ConsumerOf['MarpaX::Languages::XML::Role::IO'],
          );

has offset => (                                 # Global offset position
            is => 'ro',
            isa => PositiveOrZeroInt,
            default => 0,
            handles_via => 'Number',
            handles     => {
                            _set_offset => 'set',
                            _add_offset => 'add',
                           },
           );
our $MARPA_TRACE_FILE_HANDLE;
our $MARPA_TRACE_BUFFER;

sub BEGIN {
    #
    ## We do not want Marpa to pollute STDERR
    #
    ## Autovivify a new file handle
    #
    open($MARPA_TRACE_FILE_HANDLE, '>', \$MARPA_TRACE_BUFFER);
    if (! defined($MARPA_TRACE_FILE_HANDLE)) {
      MarpaX::Languages::XML::Exception->throw("Cannot create temporary file handle to tie Marpa logging, $!");
    } else {
      if (! tie ${$MARPA_TRACE_FILE_HANDLE}, 'MarpaX::Languages::XML::Impl::Logger') {
        MarpaX::Languages::XML::Exception->throw("Cannot tie $MARPA_TRACE_FILE_HANDLE, $!");
        if (! close($MARPA_TRACE_FILE_HANDLE)) {
          MarpaX::Languages::XML::Exception->throw("Cannot close temporary file handle, $!");
        }
        $MARPA_TRACE_FILE_HANDLE = undef;
      }
    }
}

=head1 SEE ALSO

L<IO::All>, L<Marpa::R2>

=cut

sub _exception {
  my ($self, $message, $r) = @_;

  $message //= '';
  if ($self->_logger->is_debug() && $r) {
    $message .= "\n" . $r->show_progress();
  }

  MarpaX::Languages::XML::Exception->throw($message);
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
      $self->_logger->debugf('Assuming relaxed (perl) utf8 encoding');
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
                NAME                          => qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*},
                NMTOKENMANY                   => qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]+},
                ENTITYVALUEINTERIORDQUOTEUNIT => qr{\G[^%&"]+},
                ENTITYVALUEINTERIORSQUOTEUNIT => qr{\G[^%&']+},
                ATTVALUEINTERIORDQUOTEUNIT    => qr{\G[^<&"]+},
                ATTVALUEINTERIORSQUOTEUNIT    => qr{\G[^<&']+},
                NOT_DQUOTEMANY                => qr{\G[^"]+},
                NOT_SQUOTEMANY                => qr{\G[^']+},
                PUBIDCHARDQUOTE               => qr{\G[a-zA-Z0-9\-'()+,./:=?;!*#@\$_%\x{20}\x{D}\x{A}]},
                PUBIDCHARSQUOTE               => qr{\G[a-zA-Z0-9\-()+,./:=?;!*#@\$_%\x{20}\x{D}\x{A}]},
                CHARDATAMANY                  => qr{\G(?:[^<&\]]|(?:\](?!\]>)))+}, # [^<&]+ without ']]>'
                COMMENTCHARMANY               => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{2C}\x{2E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\-(?!\-)))+},  # Char* without '--'
                PITARGET                      => qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*},  # NAME but /xml/i
                CDATAMANY                     => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{5C}\x{5E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\](?!\]>)))+},  # Char* minus ']]>'
                PICHARDATAMANY                => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{3E}\x{40}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\?(?!>)))+},  # Char* minus '?>'
                IGNOREMANY                    => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{3B}\x{3D}-\x{5C}\x{5E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:<(?!!\[))|(?:\](?!\]>)))+},  # Char minus* ('<![' or ']]>')
                DIGITMANY                     => qr{\G[0-9]+},
                ALPHAMANY                     => qr{\G[0-9a-fA-F]+},
                ENCNAME                       => qr{\G[A-Za-z][A-Za-z0-9._\-]*},
                S                             => qr{\G[\x{20}\x{9}\x{D}\x{A}]+},
                #
                # These are the lexemes of predicted size
                #
                SPACE                         => qr{\G\x{20}},
                DQUOTE                        => qr{\G"},
                SQUOTE                        => qr{\G'},
                COMMENT_START                 => qr{\G<!\-\-},
                COMMENT_END                   => qr{\G\-\->},
                PI_START                      => qr{\G<\?},
                PI_END                        => qr{\G\?>},
                CDATA_START                   => qr{\G<!\[CDATA\[},
                CDATA_END                     => qr{\G\]\]>},
                XMLDECL_START                 => qr{\G<\?xml},
                XMLDECL_END                   => qr{\G\?>},
                VERSION                       => qr{\Gversion},
                EQUAL                         => qr{\G=},
                VERSIONNUM                    => qr{\G1\.0},
                DOCTYPE_START                 => qr{\G<!DOCTYPE},
                DOCTYPE_END                   => qr{\G>},
                LBRACKET                      => qr{\G\[},
                RBRACKET                      => qr{\G\]},
                STANDALONE                    => qr{\Gstandalone},
                YES                           => qr{\Gyes},
                NO                            => qr{\Gno},
                ELEMENT_START                 => qr{\G<},
                ELEMENT_END                   => qr{\G>},
                ETAG_START                    => qr{\G</},
                ETAG_END                      => qr{\G>},
                EMPTYELEM_START               => qr{\G<},
                EMPTYELEM_END                 => qr{\G/>},
                ELEMENTDECL_START             => qr{\G<!ELEMENT},
                ELEMENTDECL_END               => qr{\G>},
                EMPTY                         => qr{\GEMPTY},
                ANY                           => qr{\GANY},
                QUESTIONMARK                  => qr{\G\?},
                STAR                          => qr{\G\*},
                PLUS                          => qr{\G\+},
                OR                            => qr{\G\|},
                CHOICE_START                  => qr{\G\(},
                CHOICE_END                    => qr{\G\)},
                SEQ_START                     => qr{\G\(},
                SEQ_END                       => qr{\G\)},
                MIXED_START1                  => qr{\G\(},
                MIXED_END1                    => qr{\G\)\*},
                MIXED_START2                  => qr{\G\(},
                MIXED_END2                    => qr{\G\)},
                COMMA                         => qr{\G,},
                PCDATA                        => qr{\G#PCDATA},
                ATTLIST_START                 => qr{\G<!ATTLIST},
                ATTLIST_END                   => qr{\G>},
                CDATA                         => qr{\GCDATA},
                ID                            => qr{\GID},
                IDREF                         => qr{\GIDREF},
                IDREFS                        => qr{\GIDREFS},
                ENTITY                        => qr{\GENTITY},
                ENTITIES                      => qr{\GENTITIES},
                NMTOKEN                       => qr{\GNMTOKEN},
                NMTOKENS                      => qr{\GNMTOKENS},
                NOTATION                      => qr{\GNOTATION},
                NOTATION_START                => qr{\G\(},
                NOTATION_END                  => qr{\G\)},
                ENUMERATION_START             => qr{\G\(},
                ENUMERATION_END               => qr{\G\)},
                REQUIRED                      => qr{\G#REQUIRED},
                IMPLIED                       => qr{\G#IMPLIED},
                FIXED                         => qr{\G#FIXED},
                INCLUDE                       => qr{\GINCLUDE},
                IGNORE                        => qr{\GIGNORE},
                INCLUDESECT_START             => qr{\G<!\[},
                INCLUDESECT_END               => qr{\G\]\]>},
                IGNORESECT_START              => qr{\G<!\[},
                IGNORESECT_END                => qr{\G\]\]>},
                IGNORESECTCONTENTSUNIT_START  => qr{\G<!\[},
                IGNORESECTCONTENTSUNIT_END    => qr{\G\]\]>},
                CHARREF_START1                => qr{\G&#},
                CHARREF_END1                  => qr{\G;},
                CHARREF_START2                => qr{\G&#x},
                CHARREF_END2                  => qr{\G;},
                ENTITYREF_START               => qr{\G&},
                ENTITYREF_END                 => qr{\G;},
                PEREFERENCE_START             => qr{\G%},
                PEREFERENCE_END               => qr{\G;},
                ENTITY_START                  => qr{\G<!ENTITY},
                ENTITY_END                    => qr{\G>},
                PERCENT                       => qr{\G%},
                SYSTEM                        => qr{\GSYSTEM},
                PUBLIC                        => qr{\GPUBLIC},
                NDATA                         => qr{\GNDATA},
                TEXTDECL_START                => qr{\G<\?xml},
                TEXTDECL_END                  => qr{\G?>},
                ENCODING                      => qr{\Gencoding},
                NOTATIONDECL_START            => qr{\G<!NOTATION},
                NOTATIONDECL_END              => qr{\G>},
               );

our %G1_DESCRIPTIONS = (
                       #
                       # These are the lexemes of unknown size
                       #
                      '^NAME'                          => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'NAME' },
                      '^NMTOKENMANY'                   => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'NMTOKENMANY' },
                      '^ENTITYVALUEINTERIORDQUOTEUNIT' => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITYVALUEINTERIORDQUOTEUNIT' },
                      '^ENTITYVALUEINTERIORSQUOTEUNIT' => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITYVALUEINTERIORSQUOTEUNIT' },
                      '^ATTVALUEINTERIORDQUOTEUNIT'    => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ATTVALUEINTERIORDQUOTEUNIT' },
                      '^ATTVALUEINTERIORSQUOTEUNIT'    => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ATTVALUEINTERIORSQUOTEUNIT' },
                      '^NOT_DQUOTEMANY'                => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'NOT_DQUOTEMANY' },
                      '^NOT_SQUOTEMANY'                => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'NOT_SQUOTEMANY' },
                      '^PUBIDCHARDQUOTE'               => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'PUBIDCHARDQUOTE' },
                      '^PUBIDCHARSQUOTE'               => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'PUBIDCHARSQUOTE' },
                      '^CHARDATAMANY'                  => { fixed_length => 0, type => 'predicted', min_chars =>  3, symbol_name => 'CHARDATAMANY' },    # [^<&]+ without ']]>'
                      '^COMMENTCHARMANY'               => { fixed_length => 0, type => 'predicted', min_chars =>  2, symbol_name => 'COMMENTCHARMANY' }, # Char* without '--'
                      '^PITARGET'                      => { fixed_length => 0, type => 'predicted', min_chars =>  3, symbol_name => 'PITARGET' },        # NAME but /xml/i
                      '^CDATAMANY'                     => { fixed_length => 0, type => 'predicted', min_chars =>  3, symbol_name => 'CDATAMANY' },       # Char* minus ']]>'
                      '^PICHARDATAMANY'                => { fixed_length => 0, type => 'predicted', min_chars =>  2, symbol_name => 'PICHARDATAMANY' },  # Char* minus '?>'
                      '^IGNOREMANY'                    => { fixed_length => 0, type => 'predicted', min_chars =>  3, symbol_name => 'IGNOREMANY' },      # Char minus* ('<![' or ']]>')
                      '^DIGITMANY'                     => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'DIGITMANY' },
                      '^ALPHAMANY'                     => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ALPHAMANY' },
                      '^ENCNAME'                       => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'ENCNAME' },
                      '^S'                             => { fixed_length => 0, type => 'predicted', min_chars =>  1, symbol_name => 'S' },
                      #
                      # These are the lexemes of predicted size
                      #
                      '^SPACE'                         => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'SPACE' },
                      '^DQUOTE'                        => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'DQUOTE' },
                      '^SQUOTE'                        => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'SQUOTE' },
                      '^COMMENT_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  4, symbol_name => 'COMMENT_START' },
                      '^COMMENT_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'COMMENT_END' },
                      '^PI_START'                      => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'PI_START' },
                      '^PI_END'                        => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'PI_END' },
                      '^CDATA_START'                   => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'CDATA_START' },
                      '^CDATA_END'                     => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'CDATA_END' },
                      '^XMLDECL_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'XMLDECL_START' },
                      '^XMLDECL_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'XMLDECL_END' },
                      '^VERSION'                       => { fixed_length => 1, type => 'predicted', min_chars =>  7, symbol_name => 'VERSION' },
                      '^EQUAL'                         => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'EQUAL' },
                      '^VERSIONNUM'                    => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'VERSIONNUM' },
                      '^DOCTYPE_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'DOCTYPE_START' },
                      '^DOCTYPE_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'DOCTYPE_END' },
                      '^LBRACKET'                      => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'LBRACKET' },
                      '^RBRACKET'                      => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'RBRACKET' },
                      '^STANDALONE'                    => { fixed_length => 1, type => 'predicted', min_chars => 10, symbol_name => 'STANDALONE' },
                      '^YES'                           => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'YES' },
                      '^NO'                            => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'NO' },
                      '^ELEMENT_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ELEMENT_START' },
                      '^ELEMENT_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ELEMENT_END' },
                      '^ETAG_START'                    => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'ETAG_START' },
                      '^ETAG_END'                      => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ETAG_END' },
                      '^EMPTYELEM_START'               => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'EMPTYELEM_START' },
                      '^EMPTYELEM_END'                 => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'EMPTYELEM_END' },
                      '^ELEMENTDECL_START'             => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'ELEMENTDECL_START' },
                      '^ELEMENTDECL_END'               => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ELEMENTDECL_END' },
                      '^EMPTY'                         => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'EMPTY' },
                      '^ANY'                           => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'ANY' },
                      '^QUESTIONMARK'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'QUESTIONMARK' },
                      '^STAR'                          => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'STAR' },
                      '^PLUS'                          => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'PLUS' },
                      '^OR'                            => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'OR' },
                      '^CHOICE_START'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'CHOICE_START' },
                      '^CHOICE_END'                    => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'CHOICE_END' },
                      '^SEQ_START'                     => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'SEQ_START' },
                      '^SEQ_END'                       => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'SEQ_END' },
                      '^MIXED_START1'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'MIXED_START1' },
                      '^MIXED_END1'                    => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'MIXED_END1' },
                      '^MIXED_START2'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'MIXED_START2' },
                      '^MIXED_END2'                    => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'MIXED_END2' },
                      '^COMMA'                         => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'COMMA' },
                      '^PCDATA'                        => { fixed_length => 1, type => 'predicted', min_chars =>  7, symbol_name => 'PCDATA' },
                      '^ATTLIST_START'                 => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'ATTLIST_START' },
                      '^ATTLIST_END'                   => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ATTLIST_END' },
                      '^CDATA'                         => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'CDATA' },
                      '^ID'                            => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'ID' },
                      '^IDREF'                         => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'IDREF' },
                      '^IDREFS'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'IDREFS' },
                      '^ENTITY'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'ENTITY' },
                      '^ENTITIES'                      => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'ENTITIES' },
                      '^NMTOKEN'                       => { fixed_length => 1, type => 'predicted', min_chars =>  7, symbol_name => 'NMTOKEN' },
                      '^NMTOKENS'                      => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'NMTOKENS' },
                      '^NOTATION'                      => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'NOTATION' },
                      '^NOTATION_START'                => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'NOTATION_START' },
                      '^NOTATION_END'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'NOTATION_END' },
                      '^ENUMERATION_START'             => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENUMERATION_START' },
                      '^ENUMERATION_END'               => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENUMERATION_END' },
                      '^REQUIRED'                      => { fixed_length => 1, type => 'predicted', min_chars =>  9, symbol_name => 'REQUIRED' },
                      '^IMPLIED'                       => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'IMPLIED' },
                      '^FIXED'                         => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'FIXED' },
                      '^INCLUDE'                       => { fixed_length => 1, type => 'predicted', min_chars =>  7, symbol_name => 'INCLUDE' },
                      '^IGNORE'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'IGNORE' },
                      '^INCLUDESECT_START'             => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'INCLUDESECT_START' },
                      '^INCLUDESECT_END'               => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'INCLUDESECT_END' },
                      '^IGNORESECT_START'              => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'IGNORESECT_START' },
                      '^IGNORESECT_END'                => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'IGNORESECT_END' },
                      '^IGNORESECTCONTENTSUNIT_START'  => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'IGNORESECTCONTENTSUNIT_START' },
                      '^IGNORESECTCONTENTSUNIT_END'    => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'IGNORESECTCONTENTSUNIT_END' },
                      '^CHARREF_START1'                => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'CHARREF_START1' },
                      '^CHARREF_END1'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'CHARREF_END1' },
                      '^CHARREF_START2'                => { fixed_length => 1, type => 'predicted', min_chars =>  3, symbol_name => 'CHARREF_START2' },
                      '^CHARREF_END2'                  => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'CHARREF_END2' },
                      '^ENTITYREF_START'               => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITYREF_START' },
                      '^ENTITYREF_END'                 => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITYREF_END' },
                      '^PEREFERENCE_START'             => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'PEREFERENCE_START' },
                      '^PEREFERENCE_END'               => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'PEREFERENCE_END' },
                      '^ENTITY_START'                  => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'ENTITY_START' },
                      '^ENTITY_END'                    => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'ENTITY_END' },
                      '^PERCENT'                       => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'PERCENT' },
                      '^SYSTEM'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'SYSTEM' },
                      '^PUBLIC'                        => { fixed_length => 1, type => 'predicted', min_chars =>  6, symbol_name => 'PUBLIC' },
                      '^NDATA'                         => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'NDATA' },
                      '^TEXTDECL_START'                => { fixed_length => 1, type => 'predicted', min_chars =>  5, symbol_name => 'TEXTDECL_START' },
                      '^TEXTDECL_END'                  => { fixed_length => 1, type => 'predicted', min_chars =>  2, symbol_name => 'TEXTDECL_END' },
                      '^ENCODING'                      => { fixed_length => 1, type => 'predicted', min_chars =>  8, symbol_name => 'ENCODING' },
                      '^NOTATIONDECL_START'            => { fixed_length => 1, type => 'predicted', min_chars => 10, symbol_name => 'NOTATIONDECL_START' },
                      '^NOTATIONDECL_END'              => { fixed_length => 1, type => 'predicted', min_chars =>  1, symbol_name => 'NOTATIONDECL_END' },
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
      $recursion_level,
      $start_symbol, $end_event_name,
      $lengthp,
      $posp, $global_posp,
      $global_linep,
      $global_columnp,
      $hash_ref,
      $parse_opts_ref,
      $internal_events_ref, $switches_ref) = @_;

  $recursion_level //= 0;

  my $length = ${$lengthp};
  my $pos = ${$posp};
  my $global_pos = ${$global_posp};
  my $global_line = ${$global_linep};
  my $global_column = ${$global_columnp};
  my $remaining = $length - $pos;

  #
  # Create grammar if necesssary
  #
  my $g = $self->_exists__grammar($start_symbol) ?
    $self->_get__grammar($start_symbol)
    :
    $self->_set__grammar($start_symbol, MarpaX::Languages::XML::Impl::Grammar->new->compile(%{$hash_ref},
                                                                                            start => $start_symbol,
                                                                                            internal_events => {%G1_DESCRIPTIONS, %{$internal_events_ref}}
                                                                                           ));
  ;

  #
  # Create a recognizer
  #
  my $r = Marpa::R2::Scanless::R->new({%{$parse_opts_ref},
                                       grammar => $g,
                                       trace_file_handle => $MARPA_TRACE_FILE_HANDLE,
                                      });

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
       $pos < $length
       ;
       #
       # Resume will croak if grammar is exhausted. We handle this case ourself (absence of prediction + remaining chargs)
       #
       $r->resume()
      ) {
    my $can_stop = 0;
    my @event_names = map { $_->[0] } @{$r->events()};
    $self->_logger->tracef('[%2d][%d:%d] Events: %s', $recursion_level, $global_line, $global_column, \@event_names);

  manage_events:
    # $self->_logger->tracef('[%2d][%d:%d] Data: %s', $recursion_level, $global_line, $global_column, substr($_[1], $pos));
    # if ($remaining) {
    # } else {
    #   $self->_logger->tracef('[%2d][%d:%d] Data[%d..%d]: %s', $recursion_level, $global_line, $global_column, $pos, $length - 1, substr($_[1], $pos));
    # }
    #
    # Predicted events always come first -;
    #
    my $have_prediction = 0;
    my $data;
    my %length = ();
    my $max_length = 0;
    foreach (@event_names) {
      if (exists($G1_DESCRIPTIONS{$_})) {
        $have_prediction = 1;
        my $symbol_name = $G1_DESCRIPTIONS{$_}->{symbol_name};
        #
        # Check if the decision about this lexeme can be done
        #
        if ($G1_DESCRIPTIONS{$_}->{min_chars} > $remaining) {
          my $old_remaining = $remaining;
          $self->_logger->tracef('[%2d][%d:%d] Lexeme %s requires %d chars > %d remaining for decidability', $recursion_level, $global_line, $global_column, $symbol_name, $G1_DESCRIPTIONS{$_}->{min_chars}, $remaining);
          $remaining = $length = ${$lengthp} = $self->_reduceAndRead($pos, $_[1], $length, $recursion_level, 0, $global_line, $global_column);
          $pos = 0;
          if ($remaining > $old_remaining) {
            #
            # Something was read
            #
            goto manage_events;
          } else {
            $self->_logger->debugf('[%2d][%d:%d] Nothing more read', $recursion_level, $global_line, $global_column);
          }
        }
        #
        # Check if this variable length lexeme is reaching the end of the buffer.
        #
        pos($_[1]) = $pos;
        if ($_[1] =~ $LEXEME_REGEXPS{$symbol_name}) {
          my $matched_data = substr($_[1], $-[0], $+[0] - $-[0]);
          if (exists($LEXEME_EXCLUSIONS{$symbol_name}) && ($matched_data =~ $LEXEME_EXCLUSIONS{$symbol_name})) {
            $self->_logger->tracef('[%2d][%d:%d] Lexeme %s match excluded', $recursion_level, $global_line, $global_column, $symbol_name);
          } else {
            if (($+[0] >= $length) && ! $G1_DESCRIPTIONS{$_}->{fixed_length}) {
              $self->_logger->tracef('[%2d][%d:%d] Lexeme %s match but end-of-buffer', $recursion_level, $global_line, $global_column, $symbol_name);
              my $old_remaining = $remaining;
              $self->_logger->tracef('[%2d][%d:%d] Lexeme %s is of unpredicted size and currently reaches end-of-buffer', $recursion_level, $global_line, $global_column, $symbol_name);
              $remaining = $length = ${$lengthp} = $self->_reduceAndRead($pos, $_[1], $length, $recursion_level, 0, $global_line, $global_column);
              $pos = 0;
              if ($remaining > $old_remaining) {
                #
                # Something was read
                #
                goto manage_events;
              } else {
                $self->_logger->debugf('[%2d][%d:%d] Nothing more read', $recursion_level, $global_line, $global_column);
              }
            }
            my $lexeme_name = '_' . $symbol_name;
            $length{$lexeme_name} = $+[0] - $-[0];
            $self->_logger->tracef('[%2d][%d:%d] %s: match of length %d', $recursion_level, $global_line, $global_column, $symbol_name, $length{$lexeme_name});
            if ((! $max_length) || ($length{$lexeme_name} > $max_length)) {
              $data = $matched_data;
              $max_length = $length{$lexeme_name};
            }
          }
        } else {
          $self->_logger->tracef('[%2d][%d:%d] %s: no match', $recursion_level, $global_line, $global_column, $symbol_name);
        }
      } else {
        #
        # Sanity check - code to be removed OOTD
        #
        if (substr($_, 0, 1) eq '^') {
          $self->_logger->warnf('[%2d][%d:%d] Unknown internal event %s', $recursion_level, $global_line, $global_column, $_);
        }
        if ($_ eq $end_event_name) {
          $can_stop = 1;
          $self->_logger->debugf('[%2d][%d:%d] Grammar end event %s', $recursion_level, $global_line, $global_column, $_);
        }
        #
        # Event callback ?
        #
        my $code = $switches_ref->{$_};
        my $rc_switch = defined($code) ? $self->$code() : 1;
        #
        # Any false return value mean immediate stop
        #
        if (! $rc_switch) {
          $self->_logger->debugf('[%2d][%d:%d] Event callback %s says to stop', $recursion_level, $global_line, $global_column, $_);
          return;
        }
      }
    }
    $self->_logger->tracef('[%2d][%d:%d] have_prediction %d can_stop %d length %s', $recursion_level, $global_line, $global_column, $have_prediction, $can_stop, \%length);
    if ($have_prediction) {
      if (! $max_length) {
        if ($can_stop) {
          $self->_logger->tracef('[%2d][%d:%d] No predicted lexeme found but grammar end flag is on', $recursion_level, $global_line, $global_column);
          return;
        } else {
          $self->_exception(sprintf('[%2d][%d:%d] No predicted lexeme found', $recursion_level, $global_line, $global_column));
        }
      } else {
        my @alternatives = grep { $length{$_} == $max_length } keys %length;
        $self->_logger->debugf('[%2d][%d:%d] Lexeme alternative %s', $recursion_level, $global_line, $global_column, \@alternatives);
        foreach (@alternatives) {
          #
          # Callback on lexeme prediction
          #
          my $code = $switches_ref->{"^$_"};
          my $rc_switch = defined($code) ? $self->$code($recursion_level, $data) : 1;
          if (! $rc_switch) {
            $self->_logger->debugf('[%2d][%d:%d] Event callback %s says to stop', $recursion_level, $global_line, $global_column, "^$_");
            return;
          }
          #
          # Push alternative
          #
          $r->lexeme_alternative($_);
          #
          # Callback on lexeme completion
          #
          $code = $switches_ref->{"$_\$"};
          $rc_switch = defined($code) ? $self->$code($recursion_level, $data) : 1;
          if (! $rc_switch) {
            $self->_logger->debugf('[%2d][%d:%d] Event callback %s says to stop', $recursion_level, $global_line, $global_column, "$_\$");
            return;
          }
        }
        $self->_logger->tracef('[%2d][%d:%d] Lexeme complete of length %d', $recursion_level, $global_line, $global_column, $max_length);
        #
        # Position 0 and length 1: the Marpa input buffer is virtual
        #
        $r->lexeme_complete(0, 1);
        #
        # Update position and remaining chars in internal buffer, global line and column numbers
        #
        my $linebreaks = () = $data =~ /\R/g;
        if ($linebreaks) {
          $global_line = ${$global_linep} += $linebreaks;
          $global_column = ${$global_columnp} = 1;
        } else {
          $global_column = ${$global_columnp} += $max_length;
        }
        ${$posp} = $pos += $max_length;
        $global_pos = ${$global_posp} += $max_length;
        $remaining -= $max_length;
        #
        # lexeme complete can generate new events: handle them before eventually resuming
        #
        @event_names = map { $_->[0] } @{$r->events()};
        $self->_logger->tracef('[%2d][%d:%d] Events: %s', $recursion_level, $global_line, $global_column, \@event_names);
        goto manage_events;
      }
    } else {
      #
      # No prediction: this is ok only if grammar end_of_grammar flag is set
      #
      if ($can_stop) {
        $self->_logger->tracef('[%2d][%d:%d] No prediction and grammar end flag is on', $recursion_level, $global_line, $global_column);
        return;
      } else {
        $self->_exception(sprintf('[%2d][%d:%d] No prediction and grammar end flag is not set', $recursion_level, $global_line, $global_column));
      }
    }
  }

  return;
}

sub _reduceAndRead {
  my ($self, $pos, undef, $length, $recursion_level, $eof_is_fatal, $global_line, $global_column) = @_;
  #
  # Crunch previous data
  #
  if ($pos > 0) {
    #
    # Faster like this -;
    #
    if ($pos >= $length) {
      $self->_logger->debugf('[%2d][%d:%d] Rolling-out buffer', $recursion_level, $global_line, $global_column);
      $_[2] = '';
    } else {
      $self->_logger->debugf('[%2d][%d:%d] Removing first %d characters', $recursion_level, $global_line, $global_column, $pos);
      substr($_[2], 0, $pos, '');
    }
  }
  #
  # Read more data
  #
  $self->_logger->tracef('[%2d][%d:%d] Reading data', $recursion_level, $global_line, $global_column);
  return $self->_read($recursion_level, $eof_is_fatal, $global_line, $global_column);
}

sub _read {
  my ($self, $recursion_level, $eof_is_fatal, $global_line, $global_column) = @_;

  $eof_is_fatal //= 1;

  $self->io->read;
  my $new_length;
  if (($new_length = $self->io->length) <= 0) {
    if ($eof_is_fatal) {
      $self->_exception(sprintf('[%2d][%d:%d] EOF', $recursion_level, $global_line, $global_column));
    } else {
      $self->_logger->debugf('[%2d][%d:%d] EOF', $recursion_level, $global_line, $global_column);
    }
  }
  return $new_length;
}

sub _get_literal {
  my ($self, $r, $non_terminal) = @_;

  my ($start, $length) = $r->last_completed_span($non_terminal);
  return $r->literal($start, $length);
}

sub _get_lexeme_line_column {
  my ($self, $r) = @_;

  my ($start, $length) = $r->pause_span();
  return $r->line_column($start);
}

sub _get_literal_line_column {
  my ($self, $r, $non_terminal) = @_;

  my ($start, $length) = $r->last_completed_span($non_terminal);
  return $r->line_column($start);
}

sub _get_line_column {
  my ($self, $r, $lexeme, $non_terminal) = @_;

  return $lexeme ? $self->_get_lexeme_line_column($r) : $self->_get_literal_line_column($r, $non_terminal);
}

sub _start_document {
  my ($self, $user_code, $recursion_level, $global_line, $global_column, @args) = @_;

  $self->_logger->debugf('[%2d][%d:%d] SAX event start_document', $recursion_level, $global_line, $global_column);
  #
  # No argument for start_document
  #
  $self->$user_code(@args);
  return 1;
}

sub parse {
  my ($self, $hash_ref) = @_;

  $hash_ref //= {};

  #
  # Sanity checks
  #
  my $block_size = $hash_ref->{block_size} || 11;
  if (reftype($block_size)) {
    $self->_exception('block_size must be a SCALAR');
  }

  my $parse_opts_ref = $hash_ref->{parse_opts} || {};
  if ((reftype($parse_opts_ref) || '') ne 'HASH') {
    $self->_exception('parse_opts must be a ref to HASH');
  }

  my $sax_handlers_ref = $hash_ref->{sax_handlers} || {};
  if ((reftype($sax_handlers_ref) || '') ne 'HASH') {
    $self->_exception('SAX handlers must be a ref to HASH');
  }

  try {
    # ------------------
    # "Global variables"
    # ------------------
    my $recursion_level = 0;
    my $global_line = 1;
    my $global_column = 1;
    #
    # ------------
    # Parse prolog
    # ------------
    #
    # Encoding object instance
    #
    my $encoding = MarpaX::Languages::XML::Impl::Encoding->new();
    my ($bom_encoding, $guess_encoding, $orig_encoding, $byte_start)  = $self->_encoding($encoding);
    $self->_logger->debugf('[%2d][%d:%d] BOM and/or guess gives encoding %s and byte offset %d', $recursion_level, $global_line, $global_column, $orig_encoding, $byte_start);
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
                           '^_ELEMENT_START'  => { end_of_grammar => 0, type => 'before', symbol_name => '_ELEMENT_START', lexeme => 1 },
                          );
    my %switches = (
                    '_ENCNAME$'  => sub {
                      my ($self, $recursion_level, $encname) = @_;
                      #
                      # Encoding is composed only of ASCII codepoints, so uc is ok
                      #
                      my $xml_encoding = uc($encname);
                      $self->_logger->debugf('[%2d][%d:%d] XML says encoding %s', $recursion_level, $global_line, $global_column, $xml_encoding);
                      #
                      # Check eventual encoding v.s. endianness. Algorithm vaguely taken from
                      # https://blogs.oracle.com/tucu/entry/detecting_xml_charset_encoding_again
                      #
                      $final_encoding = $encoding->final($bom_encoding, $guess_encoding, $xml_encoding);
                      return ($final_encoding eq $orig_encoding);
                    },
                    '^_ELEMENT_START'  => sub {
                      return 0;
                    }
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
          return $self->_start_document($user_code, $recursion_level, $global_line, $global_column);
        };
      }
    }
    my $global_pos = $byte_start;
    my $pos = 0;
    my $length = $self->io->length;
    #
    # From now on, there are a lot of arguments that are always the same. Make it an array
    # for readability.
    #
    my @generic_parse_common_args = (
                                     \$length,          # buffer length
                                     \$pos,             # posp
                                     \$global_pos,      # global_posp
                                     \$global_line,     # global_linep
                                     \$global_column,   # global_columnp
                                     $hash_ref,         # $hash_ref
                                     $parse_opts_ref,   # parse_opts_ref
                                     \%internal_events, # internal_events_ref,
                                     \%switches,        # switches
                                    );
    $self->_generic_parse(
                          $buffer,           # buffer
                          $recursion_level,  # recursion_level
                          'document',        # start_symbol
                          'prolog$',         # end_event_name
                          @generic_parse_common_args
                         );
    if ($final_encoding ne $orig_encoding) {
      $self->_logger->debugf('[%2d][%d:%d] Redoing parse using encoding %s instead of %s', $recursion_level, $global_line, $global_column, $final_encoding, $orig_encoding);
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
        goto retry_because_of_encoding;
      } else {
        MarpaX::Languages::XML::Exception->throw("Two many retries because of encoding difference beween BOM, guess and XML");
      }
    }
    # -------------
    # Parse element - we use a stack free implementation because perl is(was?) not very good at recursion performance
    # -------------
    %internal_events = (
                        'element$' => { fixed_length => 0, end_of_grammar => 1, type => 'completed', symbol_name => 'element' },
                       );
    $self->_generic_parse(
                          $buffer,           # buffer
                          $recursion_level,  # recursion_level
                          'element',         # start_symbol
                          'element$',        # end_event_name
                          @generic_parse_common_args
                         );
  } catch {
    $self->_exception("$_");
    return;
  };

}

sub orig_parse {
  my ($self, %hash) = @_;

  my $value;

  #
  # Sanity checks
  #
  my $source = $hash{source} || '';
  if (reftype($source)) {
    $self->_exception('source must be a SCALAR');
  }

  my $block_size = $hash{block_size} || 11;
  if (reftype($block_size)) {
    $self->_exception('block_size must be a SCALAR');
  }

  my $parse_opts = $hash{parse_opts} || {};
  if ((reftype($parse_opts) || '') ne 'HASH') {
    $self->_exception('parse_opts must be a ref to HASH');
  }

  #
  # Get grammars
  #
  my $document = MarpaX::Languages::XML::Impl::Grammar->new->compile(%hash,
                                                                     start => 'document',
                                                                     internal_events =>
                                                                     {
                                                                      G1 =>
                                                                      {
                                                                       EncodingDecl => { type => 'completed', name => 'EncodingDecl$' }
                                                                      },
                                                                      L0 =>
                                                                      {
                                                                       STAG_START => { type => 'before', name => '^STAG_START' }
                                                                      }
                                                                     }
                                                                    );
  my $misc_any = MarpaX::Languages::XML::Impl::Grammar->new->compile(%hash,
                                                                     start => 'MiscAny',
                                                                     internal_events =>
                                                                     {
                                                                     }
                                                                    );

  my $encoding = MarpaX::Languages::XML::Impl::Encoding->new();

  try {
    #
    # Guess the encoding
    #
    my ($bom_encoding, $guess_encoding, $orig_encoding, $byte_start) = $self->_open($source, $encoding);
    #
    # Very initial block size
    #
    $self->io->block_size($block_size);
    #
    # $xml_encoding will hold the encoding as per the XML itself
    #
    my $xml_encoding = '';
    my $root_element_pos = -1;
    my $root_line;
    my $root_column;
    my $nb_first_read = 0;
    my $pos;
    my @events;
    my $r;
    #
    # We prefer to have a direct access to the buffer
    #
    my $buffer = '';
    $self->io->buffer($buffer);
    #
    # First the prolog.
    #
    $self->io->read;
    if ($self->io->length <= 0) {
      $self->_exception('EOF when parsing prolog');
    }
  parse_prolog:
    do {
      $self->_logger->debugf('Instanciating a document recognizer');
      $r = Marpa::R2::Scanless::R->new({%{$parse_opts},
                                        grammar => $document,
                                        trace_file_handle => $MARPA_TRACE_FILE_HANDLE,
                                       });
      #
      # We accept a failure if buffer is too small
      #
      try {
        $self->_logger->debugf('Parsing buffer');
        $pos = $r->read(\$buffer);
      };
      @events = map { $_->[0] } @{$r->events()};
      #
      # We expect either ^STAG_START or EncodingDecl$.
      # Why ^STAG_START ? Because an XML document must have at least one element.
      #
      if (! @events) {
        $self->_logger->debugf('No event');
        $block_size *= 2;
        my $previous_length = $self->io->length;
        $self->io->block_size($block_size);
        $self->io->read;
        if ($self->io->length <= $previous_length) {
          #
          # Nothing more to read: prolog is buggy.
          #
          $self->_exception('EOF when parsing prolog', $r);
        }
      } else {
        foreach (@events) {
          $self->_logger->debugf('Got parse event \'%s\' at position %d', $_, $pos);
          if ($_ eq 'EncodingDecl$') {
            #
            # Remember encoding as given in the XML
            #
            $xml_encoding = uc($self->_get_literal($r, 'EncName'));
            $self->_logger->debugf('XML says encoding is: \'%s\'', $xml_encoding);
          }
          elsif ($_ eq '^STAG_START') {
            $root_element_pos = $pos;
            ($root_line, $root_column) = $self->_get_lexeme_line_column($r);
          }
        }
      }
    } while ((! $xml_encoding) && ($root_element_pos < 0));
    #
    # Check eventual encoding v.s. endianness. Algorithm vaguely taken from
    # https://blogs.oracle.com/tucu/entry/detecting_xml_charset_encoding_again
    #
    my $final_encoding = $encoding->final($bom_encoding, $guess_encoding, $xml_encoding, $orig_encoding);
    if ($final_encoding ne $orig_encoding) {
      $self->_logger->debugf('Encoding is \'%s\' != \'%s\': redo initial read', $final_encoding, $orig_encoding);
      #
      # We have to retry. Per def we will (should) not enter again in this if block.
      #
      $self->io->encoding($final_encoding);
      $self->io->clear;
      $self->io->pos($byte_start);
      $orig_encoding = $final_encoding;
      $self->io->read;
      if ($self->io->length <= 0) {
        $self->_exception('EOF when parsing prolog', $r);
      }
      goto parse_prolog;
    } else {
      $self->_logger->debugf('Encoding match on \'%s\': continuing', $final_encoding);
    }
    #
    # At this point the the root element may not have been reached. In such a case, force it.
    # This will croak if prolog is buggy or if there is no root element, or if initial buffer
    # is too small.
    #
    if ($root_element_pos < 0) {
      $self->_logger->debugf('Resuming document regonizer at position %d', $pos);
      @events = ();
      try {
        $pos = $r->resume($pos);
        @events = map { $_->[0] } @{$r->events()};
      };
      foreach (@events) {
        $self->_logger->debugf('Got parse event \'%s\' at position %d', $_, $pos);
        if ($_ eq '^STAG_START') {
          $root_element_pos = $pos;
          my ($start, $length) = $r->pause_span();
          ($root_line, $root_column) = $r->line_column($start);
        }
      }
      if ($root_element_pos < 0) {
        #
        # Bad luck
        #
        $self->_logger->debugf('No tag start');
        $block_size *= 2;
        my $previous_length = $self->io->length;
        $self->io->block_size($block_size);
        $self->io->clear;
        $self->io->pos($byte_start);
        $self->io->read;
        if ($self->io->length <= $previous_length) {
          #
          # Nothing more to read: prolog is buggy.
          #
          $self->_exception('EOF when parsing prolog', $r);
        }
        goto parse_prolog;
      }
    }
    #
    # From now on we can loop on element grammar.
    # It is assumed that the block_size is enough to catch at least one element
    # up to parsing failure or exhaustion. If that is not the case, we re-read
    # until EOF.
    # Buffer itself is circular and move as parsing is moving.
    # Note that the grammar guarantees that end_element event is always set.
    #
    $pos = $self->_element_loop($block_size, $parse_opts, \%hash, $buffer, $root_element_pos, $root_line, $root_column);
    #
    # document rule is:
    # document ::= (start_document) prolog element MiscAny
    #
    # and we have parsed element. So we continue at MiscAny
    #

    my $ambiguous = $r->ambiguous();
    if ($ambiguous) {
      $self->_exception("Parse of the input is ambiguous: $ambiguous", $r);
    }
    my $value_ref = $r->value || $self->_exception('No parse', $r);
    $value = ${$value_ref} || $self->_exception('No parse value', $r);
  } catch {
    #
    # We do "$_" to force an eventual stringification
    #
    $self->_exception("$_");
    return;                          # Will never be executed
  };

  return $value;
}

sub _element_loop {
  #
  # We will INTENTIONNALLY use $_[5] to manipulate $buffer, in order to avoid COW
  #
  my ($self, $block_size, $parse_opts, $hash_ref, undef, $pos, $line, $column, $element) = @_;

  $self->_logger->debugf('Parsing element at line %d column %d', $line, $column);
  if ($pos > 0) {
    substr($_[5], 0, $pos, '');
  }

  $element //= MarpaX::Languages::XML::Impl::Grammar->new->compile(%{$hash_ref},
                                                                   start => 'element',
                                                                   internal_events =>
                                                                   {
                                                                    G1 =>
                                                                    {
                                                                     Attribute => { type => 'completed', name => 'Attribute$' },
                                                                     element => { type => 'completed', name => 'element$' }
                                                                    },
                                                                    L0 =>
                                                                    {
                                                                     STAG_START => { type => 'before', name => '^STAG_START' },
                                                                     STAG_END   => { type => 'after', name => 'STAG_END$' }
                                                                    }
                                                                   }
                                                                  );

parse_element:
  my $r;
  my @events;
  my %attributes;
  do {
    $self->_logger->debugf('Instanciating an element recognizer');
    $r = Marpa::R2::Scanless::R->new({%{$parse_opts},
                                      grammar => $element,
                                      exhaustion => 'event',
                                      trace_file_handle => $MARPA_TRACE_FILE_HANDLE,
                                     });
    #
    # Very first character is always predictable we guarantee that it is the lexeme STAG_START
    #
    $self->_logger->debugf('Disabling %s event', '^STAG_START');
    $r->activate('^STAG_START', 0);
    $self->_logger->debugf('Doing first read');
    #
    # Implicitely starting at position 0
    #
    $pos = $r->read(\$_[5]);
    $self->_logger->debugf('Enabling %s event', '^STAG_START');
    $r->activate('^STAG_START', 1);
    #
    # After the first read, we expect to be paused by either:
    # - ^STAG_START : a new element
    # - STAG_END$   : end of current element
    # - Attribute$  : end of an attribute in current element
    # - 'exhausted  : parsing exhausted
    #
    @events = map { $_->[0] } @{$r->events()};
    if (! @events) {
      $self->_logger->debugf('No event');
      my $previous_length = $self->io->length;
      $block_size *= 2;
      $self->io->block_size($block_size)->read;
      if ($self->io->length <= $previous_length) {
        #
        # Nothing more to read: element is buggy.
        #
        $self->_exception('EOF when parsing element');
      }
    }
  } while (! @events);

  while (1) {
    my $completed;
    foreach (@events) {
      $self->_logger->debugf('Got parse event \'%s\' at position %d', $_, $pos);
      if ($_ eq '^STAG_START') {
        my ($line, $column) = $self->_get_lexeme_line_column($r);
        $pos = $self->_element_loop($self->io, $block_size, $parse_opts, $hash_ref, $_[5], $pos, $line, $column);
      }
      elsif ($_ eq 'Attribute$') {
        my $name  = $self->_get_literal($r, 'AttributeName');
        my $value = $self->_get_literal($r, 'AttValue');
        $self->_logger->debugf('Got attribute: %s = %s', $name, $value);
        #
        # Per def AttValue is quoted (single or double)
        #
        substr($value,  0, 1, '');
        substr($value, -1, 1, '');
        $attributes{$name} = $value;
      }
      elsif ($_ eq 'element$') {
        $completed = 1;
        last;
      }
      elsif ($_ eq '\'exhausted') {
        my $previous_length = $self->io->length;
        $block_size *= 2;
        $self->io->block_size($block_size)->read;
        if ($self->io->length <= $previous_length) {
          #
          # Nothing more to read: element is buggy.
          #
          $self->_exception('EOF when parsing element');
        }
        goto parse_element;
      }
    }
    if ($completed) {
      last;
    }
    #
    # Here we guarantee that STAG_END was not reached
    # We do not want to have a resume failure because this will
    # end the recognizer.
    #
    my $resume_ok = 0;
    try {
      $self->_logger->debugf('Resuming element recognizer at position %d', $pos);
      $pos = $r->resume($pos);
      @events = map { $_->[0] } @{$r->events()};
    } catch {
      $self->_logger->debugf('%s', "$_");
    };
    if (! @events) {
      $self->_logger->debugf('No event');
      my $previous_length = $self->io->length;
      $block_size *= 2;
      $self->io->block_size($block_size)->read;
      if ($self->io->length <= $previous_length) {
        #
        # Nothing more to read: element is buggy.
        #
        $self->_exception('EOF when parsing element');
      }
      goto parse_element;
    };
  }

  return $pos;
}


extends 'MarpaX::Languages::XML::Impl::Logger';
with 'MarpaX::Languages::XML::Role::Parser';

1;
