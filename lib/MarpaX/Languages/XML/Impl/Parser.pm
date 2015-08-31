package MarpaX::Languages::XML::Impl::Parser;
use Marpa::R2;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Impl::Encoding;
use MarpaX::Languages::XML::Impl::Grammar;
use MarpaX::Languages::XML::Impl::IO;
use MarpaX::Languages::XML::Impl::Logger;
use Moo;
use MooX::late;
use Scalar::Util qw/reftype/;
use Try::Tiny;

# ABSTRACT: MarpaX::Languages::XML::Role::parser implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is a parser implementation of MarpaX::Languages::XML::Role::Parser.

=cut

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

sub _open {
  my ($self, $source, $encoding) = @_;
  #
  # Read the first five bytes if any. Supported encodings at those
  # mentionned at https://en.wikipedia.org/wiki/Byte_order_mark
  #
  my $io = MarpaX::Languages::XML::Impl::IO->new(source => $source);
  $io->block_size(1024)->read;
  if ($io->length <= 0) {
    $self->_exception('EOF when reading first bytes');
  }
  my $buffer = ${$io->buffer};

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

  $io->encoding($found_encoding);

  #
  # Make sure we are positionned at the beginning of the buffer and at correct
  # source position. This is inefficient for everything that is not seekable.
  #
  $io->clear->pos($byte_start);

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
  return ($io, $bom_encoding, $guess_encoding, $found_encoding, $byte_start);
}

our %LEXEMES = (
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
                CHARDATAMANY                  => qr{\G(?<!\]\]>)[^<&]+}, # Exclude string ']]>'
                COMMENTCHARMANY               => qr{\G(?<!\-\-)[\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]+},  # Char minus '--'
                PITARGET                      => qr/(?<!xml|xmL|xMl|xML|Xml|XmL|XMl|XML)[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*/,  # NAME without /xml/i, though perl support negative look-behind only for fixed strings
                CDATAMANY                     => qr{\G(?<!\]\]>)[\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]+},  # Char minus ']]>'
                PICHARDATAMANY                => qr{\G(?<!\?>)[\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]+},  # Char minus '?>'
                IGNOREMANY                    => qr{\G(?<!<!\[|\]\]>)[\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]+},  # Char minus '<![' or ']]>'
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

our %LEXEME_EVENTS = (
                      #
                      # These are the lexemes of unknown size
                      #
                      '^NAME'                          => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'NAME' },
                      '^NMTOKENMANY'                   => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'NMTOKENMANY' },
                      '^ENTITYVALUEINTERIORDQUOTEUNIT' => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'ENTITYVALUEINTERIORDQUOTEUNIT' },
                      '^ENTITYVALUEINTERIORSQUOTEUNIT' => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'ENTITYVALUEINTERIORSQUOTEUNIT' },
                      '^ATTVALUEINTERIORDQUOTEUNIT'    => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'ATTVALUEINTERIORDQUOTEUNIT' },
                      '^ATTVALUEINTERIORSQUOTEUNIT'    => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'ATTVALUEINTERIORSQUOTEUNIT' },
                      '^NOT_DQUOTEMANY'                => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'NOT_DQUOTEMANY' },
                      '^NOT_SQUOTEMANY'                => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'NOT_SQUOTEMANY' },
                      '^PUBIDCHARDQUOTE'               => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'PUBIDCHARDQUOTE' },
                      '^PUBIDCHARSQUOTE'               => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'PUBIDCHARSQUOTE' },
                      '^CHARDATAMANY'                  => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'CHARDATAMANY' },
                      '^COMMENTCHARMANY'               => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'COMMENTCHARMANY' },
                      '^PITARGET'                      => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'PITARGET' },
                      '^CDATAMANY'                     => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'CDATAMANY' },
                      '^PICHARDATAMANY'                => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'PICHARDATAMANY' },
                      '^IGNOREMANY'                    => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'IGNOREMANY' },
                      '^DIGITMANY'                     => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'DIGITMANY' },
                      '^ALPHAMANY'                     => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'ALPHAMANY' },
                      '^ENCNAME'                       => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'ENCNAME' },
                      '^S'                             => { lexeme => 1, fixed_length => 0, end_of_grammar => 0, type => 'before', symbol_name => 'S' },
                      #
                      # These are the lexemes of predicted size
                      #
                      '^SPACE'                         => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'SPACE' },
                      '^DQUOTE'                        => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'DQUOTE' },
                      '^SQUOTE'                        => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'SQUOTE' },
                      '^COMMENT_START'                 => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'COMMENT_START' },
                      '^COMMENT_END'                   => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'COMMENT_END' },
                      '^PI_START'                      => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'PI_START' },
                      '^PI_END'                        => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'PI_END' },
                      '^CDATA_START'                   => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'CDATA_START' },
                      '^CDATA_END'                     => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'CDATA_END' },
                      '^XMLDECL_START'                 => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'XMLDECL_START' },
                      '^XMLDECL_END'                   => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'XMLDECL_END' },
                      '^VERSION'                       => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'VERSION' },
                      '^EQUAL'                         => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'EQUAL' },
                      '^VERSIONNUM'                    => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'VERSIONNUM' },
                      '^DOCTYPE_START'                 => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'DOCTYPE_START' },
                      '^DOCTYPE_END'                   => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'DOCTYPE_END' },
                      '^LBRACKET'                      => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'LBRACKET' },
                      '^RBRACKET'                      => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'RBRACKET' },
                      '^STANDALONE'                    => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'STANDALONE' },
                      '^YES'                           => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'YES' },
                      '^NO'                            => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'NO' },
                      '^ELEMENT_START'                 => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ELEMENT_START' },
                      '^ELEMENT_END'                   => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ELEMENT_END' },
                      '^ETAG_START'                    => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ETAG_START' },
                      '^ETAG_END'                      => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ETAG_END' },
                      '^EMPTYELEM_START'               => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'EMPTYELEM_START' },
                      '^EMPTYELEM_END'                 => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'EMPTYELEM_END' },
                      '^ELEMENTDECL_START'             => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ELEMENTDECL_START' },
                      '^ELEMENTDECL_END'               => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ELEMENTDECL_END' },
                      '^EMPTY'                         => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'EMPTY' },
                      '^ANY'                           => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ANY' },
                      '^QUESTIONMARK'                  => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'QUESTIONMARK' },
                      '^STAR'                          => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'STAR' },
                      '^PLUS'                          => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'PLUS' },
                      '^OR'                            => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'OR' },
                      '^CHOICE_START'                  => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'CHOICE_START' },
                      '^CHOICE_END'                    => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'CHOICE_END' },
                      '^SEQ_START'                     => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'SEQ_START' },
                      '^SEQ_END'                       => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'SEQ_END' },
                      '^MIXED_START1'                  => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'MIXED_START1' },
                      '^MIXED_END1'                    => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'MIXED_END1' },
                      '^MIXED_START2'                  => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'MIXED_START2' },
                      '^MIXED_END2'                    => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'MIXED_END2' },
                      '^COMMA'                         => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'COMMA' },
                      '^PCDATA'                        => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'PCDATA' },
                      '^ATTLIST_START'                 => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ATTLIST_START' },
                      '^ATTLIST_END'                   => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ATTLIST_END' },
                      '^CDATA'                         => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'CDATA' },
                      '^ID'                            => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ID' },
                      '^IDREF'                         => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'IDREF' },
                      '^IDREFS'                        => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'IDREFS' },
                      '^ENTITY'                        => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ENTITY' },
                      '^ENTITIES'                      => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ENTITIES' },
                      '^NMTOKEN'                       => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'NMTOKEN' },
                      '^NMTOKENS'                      => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'NMTOKENS' },
                      '^NOTATION'                      => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'NOTATION' },
                      '^NOTATION_START'                => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'NOTATION_START' },
                      '^NOTATION_END'                  => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'NOTATION_END' },
                      '^ENUMERATION_START'             => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ENUMERATION_START' },
                      '^ENUMERATION_END'               => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ENUMERATION_END' },
                      '^REQUIRED'                      => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'REQUIRED' },
                      '^IMPLIED'                       => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'IMPLIED' },
                      '^FIXED'                         => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'FIXED' },
                      '^INCLUDE'                       => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'INCLUDE' },
                      '^IGNORE'                        => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'IGNORE' },
                      '^INCLUDESECT_START'             => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'INCLUDESECT_START' },
                      '^INCLUDESECT_END'               => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'INCLUDESECT_END' },
                      '^IGNORESECT_START'              => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'IGNORESECT_START' },
                      '^IGNORESECT_END'                => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'IGNORESECT_END' },
                      '^IGNORESECTCONTENTSUNIT_START'  => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'IGNORESECTCONTENTSUNIT_START' },
                      '^IGNORESECTCONTENTSUNIT_END'    => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'IGNORESECTCONTENTSUNIT_END' },
                      '^CHARREF_START1'                => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'CHARREF_START1' },
                      '^CHARREF_END1'                  => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'CHARREF_END1' },
                      '^CHARREF_START2'                => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'CHARREF_START2' },
                      '^CHARREF_END2'                  => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'CHARREF_END2' },
                      '^ENTITYREF_START'               => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ENTITYREF_START' },
                      '^ENTITYREF_END'                 => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ENTITYREF_END' },
                      '^PEREFERENCE_START'             => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'PEREFERENCE_START' },
                      '^PEREFERENCE_END'               => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'PEREFERENCE_END' },
                      '^ENTITY_START'                  => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ENTITY_START' },
                      '^ENTITY_END'                    => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ENTITY_END' },
                      '^PERCENT'                       => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'PERCENT' },
                      '^SYSTEM'                        => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'SYSTEM' },
                      '^PUBLIC'                        => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'PUBLIC' },
                      '^NDATA'                         => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'NDATA' },
                      '^TEXTDECL_START'                => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'TEXTDECL_START' },
                      '^TEXTDECL_END'                  => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'TEXTDECL_END' },
                      '^ENCODING'                      => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'ENCODING' },
                      '^NOTATIONDECL_START'            => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'NOTATIONDECL_START' },
                      '^NOTATIONDECL_END'              => { lexeme => 1, fixed_length => 1, type => 'before', symbol_name => 'NOTATIONDECL_END' },
                     );
#
# It is assumed that caller ONLY USE completed or nulled events
# The predicted events are RESERVED for lexeme prediction.
#
sub _generic_parse {
  #
  # buffer is accessed using $_[2] for no COW
  #
  my ($self,
      $io, undef,
      $pos, $global_pos,
      $line, $global_line,
      $column, $global_column,
      $grammars_ref, $hash_ref, $parse_opts_ref, $start_symbol, $end_event_name, $internal_events_ref, $switches_ref, $recursion_level) = @_;

  $recursion_level //= 0;

  if (! defined($grammars_ref->{$start_symbol})) {
    my %internal_events = (%LEXEME_EVENTS, %{$internal_events_ref});
    $grammars_ref->{$start_symbol} //= MarpaX::Languages::XML::Impl::Grammar->new->compile(%{$hash_ref},
                                                                                           start => $start_symbol,
                                                                                           internal_events => \%internal_events
                                                                                          );
  }
  #
  # Create a recognizer
  #
  $self->_logger->debugf('[%3d] Instanciating a %s recognizer', $recursion_level, $start_symbol);
  my $r = Marpa::R2::Scanless::R->new({%{$parse_opts_ref},
                                       grammar => $grammars_ref->{$start_symbol},
                                       trace_file_handle => $MARPA_TRACE_FILE_HANDLE,
                                      });
  my $length = $io->length;
  $self->_logger->debugf('[%3d] Buffer length: %d', $recursion_level, $length);
  for (
       do {
         $self->_logger->debugf('[%3d] Reading at (pos, line, column) = (%d, %d, %d), (global_pos, global_line, global_column) = (%d, %d, %d)',
                                $recursion_level,
                                $pos, $line, $column,
                                $global_pos, $global_line, $global_column);
         #
         # The buffer for Marpa is not of importance here, but two bytes at least for the length to avoid exhaustion
         #
         $r->read(\'  ');
       };
       $pos < $length;
       do {
         $self->_logger->debugf('[%3d] Resuming at (pos, line, column) = (%d, %d, %d), (global_pos, global_line, global_column) = (%d, %d, %d)',
                                $recursion_level,
                                $pos, $line, $column,
                                $global_pos, $global_line, $global_column);
         $r->resume();
       }
      ) {
    $self->_logger->tracef('[%3d] Stopped at internal position %d, internal buffer length is %d', $recursion_level, $pos, $length);
    $self->_logger->tracef('[%3d] Progress:', $recursion_level, $r->show_progress());
    foreach (split(/\n/, $r->show_progress())) {
      $self->_logger->tracef('[%3d] %s', $recursion_level, $_);
    }
    my $can_stop;
    my $previous_can_stop;
  again:
    my @event_names = map { $_->[0] } @{$r->events()};
    #
    # We rely entirely on events
    #
    if (! @event_names) {
      next;
    }
    $self->_logger->debugf('[%3d] Events: %s', $recursion_level, \@event_names);
    $self->_logger->debugf('[%3d] Data@%d: %s', $recursion_level, $pos, substr($_[2], $pos));
    #
    # Predicted events always come first -;
    #
    my $have_prediction = 0;
    my $more_data = 0;
    my $stop = 0;
    my $data;
    my %length = ();
    my $max_length = 0;
    foreach (@event_names) {
      if (exists($LEXEME_EVENTS{$_})) {
        $have_prediction = 1;
        my $symbol_name = $LEXEME_EVENTS{$_}->{symbol_name};
        #
        # Check if this variable length lexeme is reaching the end of the buffer.
        #
        pos($_[2]) = $pos;
        if ($_[2] =~ $LEXEMES{$symbol_name}) {
          if (($+[0] >= $length) && ! $LEXEMES{fixed_length}) {
            $self->_logger->debugf('[%3d] Lexeme %s match but end-of-buffer', $recursion_level, $_);
            $more_data = 1;
          }
          $length{$symbol_name} = $+[0] - $-[0];
          $self->_logger->debugf('[%3d] %s match of length %d, current max_length %d', $recursion_level, $_, $length{$symbol_name}, $max_length);
          if ((! $max_length) || ($length{$symbol_name} > $max_length)) {
            $data = substr($_[2], $-[0], $+[0] - $-[0]);
            $max_length = $length{$symbol_name};
          }
        } else {
          $self->_logger->debugf('[%3d] Lexeme %s: no match', $recursion_level, $_);
        }
      } else {
        #
        # Sanity check - code to be removed OOTD
        #
        if (substr($_, 0, 1) eq '^') {
          $self->_logger->warnf('[%3d] Unknown internal event %s', $recursion_level, $_);
        }
        if ($_ eq $end_event_name) {
          $can_stop = 1;
          $self->_logger->debugf('[%3d] Grammar end event %s', $recursion_level, $_);
        } else {
          $can_stop = 0;
        }
        #
        # Any other event is a callback
        #
        my $code = $switches_ref->{$_};
        my $rc_switch = defined($code) ? $self->$code($recursion_level) : 1;
        #
        # Any false return value mean immediate stop
        #
        if (! $rc_switch) {
          $self->_logger->debugf('[%3d] Event callback %s says to stop', $recursion_level, $_);
          $stop = 1;
          last;
        }
      }
    }
    if ($stop) {
      last;
    }
    $self->_logger->debugf('[%3d] more data %d have_prediction %d can_stop %d previous_can_stop %d length %s', $recursion_level, $more_data, $have_prediction, $can_stop, $previous_can_stop, \%length);
    if ($more_data || ($have_prediction && ! %length)) {
      #
      # Crunch previous data
      #
      if ($pos > 0) {
        $self->_logger->debugf('[%3d] Removing first %d characters', $recursion_level, $pos);
        substr($_[2], 0, $pos, '');
        $length -= $pos;
        $pos = 0;
      }
      #
      # Read more data
      #
      my $new_length = $self->_read($io, $length, $recursion_level, ! $can_stop);
      if ($new_length <= $length) {
        if ($can_stop) {
          $self->_logger->debugf('[%3d] No more data but grammar says it can stop', $recursion_level);
          last;
        } else {
          $self->_exception(sprintf('[%3d] EOF', $recursion_level));
        }
      }
      $length = $new_length;
      $self->_logger->debugf('[%3d] New buffer length: %d', $recursion_level, $length);
      #
      # Try again
      #
      goto again;
    }
    if ((! $more_data) && ($have_prediction && ($can_stop || $previous_can_stop) && (! %length))) {
      $self->_logger->debugf('[%3d] No more data wanted, no predicted lexeme found but grammar says it can stop', $recursion_level);
      last;
    }
    #
    # Lexeme's read the predicted lexemes
    #
    if ($max_length) {
      #
      # Count lines and columns
      #
      my $linebreaks = () = $data =~ /\R/g;
      if ($linebreaks) {
        $line += $linebreaks;
        $column = 1;
      } else {
        $column += $max_length;
      }
      my @alternatives = grep { $length{$_} == $max_length } keys %length;
      $self->_logger->debugf('[%3d] Matches %s (length %d, linebreaks %d)', $recursion_level, \@alternatives, $max_length, $linebreaks);
      foreach (@alternatives) {
        $self->_logger->debugf('[%3d] Lexeme alternative %s', $recursion_level, $_);
        $r->lexeme_alternative($_);
      }
      $self->_logger->debugf('[%3d] Lexeme complete of length %d', $recursion_level, $max_length);
      #
      # Position 0 and length 1: the Marpa input buffer is virtual
      #
      $r->lexeme_complete(0, 1);
      $pos += $max_length;
      #
      # lexeme complete can generate events
      #
      goto again;
    }
    $previous_can_stop = $can_stop;
  }
}

sub _read {
  my ($self, $io, $current_length, $recursion_level, $eof_is_fatal) = @_;

  $eof_is_fatal //= 1;

  $io->read;
  my $new_length;
  if (($new_length = $io->length) <= $current_length) {
    if ($eof_is_fatal) {
      $self->_exception(sprintf('[%3d] EOF', $recursion_level));
    } else {
      $self->_logger->debugf('[%3d] EOF', $recursion_level);
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

sub parse {
  my ($self, %hash) = @_;

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

  my $parse_opts_ref = $hash{parse_opts} || {};
  if ((reftype($parse_opts_ref) || '') ne 'HASH') {
    $self->_exception('parse_opts must be a ref to HASH');
  }

  try {
    #
    # Encoding object instance
    #
    my $encoding = MarpaX::Languages::XML::Impl::Encoding->new();
    #
    # Guess the encoding
    #
    my ($io, $bom_encoding, $guess_encoding, $orig_encoding, $byte_start) = $self->_open($source, $encoding);
    #
    # We want to handle buffer direcly with no COW
    #
    my $buffer;
    $io->buffer($buffer);
    #
    # Very initial block size and read
    #
    $io->block_size($block_size)->read;
    #
    # Go
    #
    my %internal_events = (
                           'prolog$'  => { lexeme => 0, fixed_length => 0, end_of_grammar => 1, type => 'completed', symbol_name => 'prolog' },
                           );
    my %switches = (
                   );
    $self->_generic_parse(
                          $io,               # io
                          $buffer,           # buffer
                          0,                 # pos
                          0,                 # global_pos
                          0,                 # line
                          1,                 # global_line
                          0,                 # column
                          1,                 # global_column
                          {},                # grammars_ref
                          \%hash,            # $hash_ref
                          $parse_opts_ref,   # parse_opts_ref
                          'prolog',          # start_symbol
                          'prolog$',         # end_event_name
                          \%internal_events, # internal_events_ref,
                          \%switches,        # switches
                          0 # recursion_level
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
    my ($io, $bom_encoding, $guess_encoding, $orig_encoding, $byte_start) = $self->_open($source, $encoding);
    #
    # Very initial block size
    #
    $io->block_size($block_size);
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
    $io->buffer($buffer);
    #
    # First the prolog.
    #
    $io->read;
    if ($io->length <= 0) {
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
        my $previous_length = $io->length;
        $io->block_size($block_size)->read;
        if ($io->length <= $previous_length) {
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
      $io->encoding($final_encoding)->clear->pos($byte_start);
      $orig_encoding = $final_encoding;
      $io->read;
      if ($io->length <= 0) {
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
        my $previous_length = $io->length;
        $io->block_size($block_size)->clear->pos($byte_start);
        $io->read;
        if ($io->length <= $previous_length) {
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
    $pos = $self->_element_loop($io, $block_size, $parse_opts, \%hash, $buffer, $root_element_pos, $root_line, $root_column);
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
  my ($self, $io, $block_size, $parse_opts, $hash_ref, undef, $pos, $line, $column, $element) = @_;

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
      my $previous_length = $io->length;
      $block_size *= 2;
      $io->block_size($block_size)->read;
      if ($io->length <= $previous_length) {
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
        $pos = $self->_element_loop($io, $block_size, $parse_opts, $hash_ref, $_[5], $pos, $line, $column);
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
        my $previous_length = $io->length;
        $block_size *= 2;
        $io->block_size($block_size)->read;
        if ($io->length <= $previous_length) {
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
      my $previous_length = $io->length;
      $block_size *= 2;
      $io->block_size($block_size)->read;
      if ($io->length <= $previous_length) {
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
