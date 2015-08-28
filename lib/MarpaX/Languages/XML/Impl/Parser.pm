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

sub _read {
  my ($self, $io, $current_length, $recursion_level) = @_;

  $io->read;
  my $new_length;
  if (($new_length = $io->length) <= $current_length) {
    $self->_exception('[%3d] EOF', $recursion_level);
  }
  return $new_length;
}

#
# Generic routine doing a parse using a top grammar and switching to eventual sub-grammars, using a shared buffer in input.
# It is assumed that, at $pos, the grammar will STOP at any possible first lexeme.
#
# For example the document grammar must stop at either:
# '<?xml'    (which is optional)
# '<'        (which is required)
#
# We rely on the fact that the XML grammar has NO discard event. Therefore a parsing failure can
# occur only if:
# - there is no more input
# - input is wrong
#
# We have to distinguish between lexemes of variable size (sequences) and those of fixed size
# This is the reason of this constant declaration (note that XML1.0 and XML1.1 share the same
# lexeme names and their "fixed_length" value):
#
our %LEXEME_INTERNAL_EVENTS = (
                               '^NAME'                          => { fixed_length => 0, lexeme => 1, type => 'before', symbol_name => 'NAME'        },
                               '^NMTOKENMANY'                   => { fixed_length => 0, lexeme => 1, type => 'before', symbol_name => 'NMTOKENMANY' },
                               '^SPACE'                         => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'SPACE' },
                               '^DQUOTE'                        => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'DQUOTE' },
                               '^SQUOTE'                        => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'SQUOTE' },
                               '^ENTITYVALUEINTERIORDQUOTEUNIT' => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ENTITYVALUEINTERIORDQUOTEUNIT' },
                               '^ENTITYVALUEINTERIORSQUOTEUNIT' => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ENTITYVALUEINTERIORSQUOTEUNIT' },
                               '^ATTVALUEINTERIORDQUOTEUNIT'    => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ATTVALUEINTERIORDQUOTEUNIT' },
                               '^ATTVALUEINTERIORSQUOTEUNIT'    => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ATTVALUEINTERIORSQUOTEUNIT' },
                               '^NOT_DQUOTEMANY'                => { fixed_length => 0, lexeme => 1, type => 'before', symbol_name => 'NOT_DQUOTEMANY' },
                               '^NOT_SQUOTEMANY'                => { fixed_length => 0, lexeme => 1, type => 'before', symbol_name => 'NOT_SQUOTEMANY' },
                               '^PUBIDCHARDQUOTE'               => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'PUBIDCHARDQUOTE' },
                               '^PUBIDCHARSQUOTE'               => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'PUBIDCHARSQUOTE' },
                               '^CHARDATAMANY'                  => { fixed_length => 0, lexeme => 1, type => 'before', symbol_name => 'CHARDATAMANY' },
                               '^COMMENTCHARMANY'               => { fixed_length => 0, lexeme => 1, type => 'before', symbol_name => 'COMMENTCHARMANY' },
                               '^COMMENT_START'                 => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'COMMENT_START' },
                               '^COMMENT_END'                   => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'COMMENT_END' },
                               '^PI_START'                      => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'PI_START' },
                               '^PI_END'                        => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'PI_END' },
                               '^PITARGET'                      => { fixed_length => 0, lexeme => 1, type => 'before', symbol_name => 'PITARGET' },
                               '^CDATA_START'                   => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'CDATA_START' },
                               '^CDATA_END'                     => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'CDATA_END' },
                               '^CDATAMANY'                     => { fixed_length => 0, lexeme => 1, type => 'before', symbol_name => 'CDATAMANY' },
                               '^XMLDECL_START'                 => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'XMLDECL_START' },
                               '^XMLDECL_END'                   => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'XMLDECL_END' },
                               '^VERSION'                       => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'VERSION' },
                               '^EQUAL'                         => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'EQUAL' },
                               '^VERSIONNUM'                    => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'VERSIONNUM' },
                               '^DOCTYPE_START'                 => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'DOCTYPE_START' },
                               '^DOCTYPE_END'                   => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'DOCTYPE_END' },
                               '^LBRACKET'                      => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'LBRACKET' },
                               '^RBRACKET'                      => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'RBRACKET' },
                               '^STANDALONE'                    => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'STANDALONE' },
                               '^YES'                           => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'YES' },
                               '^NO'                            => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'NO' },
                               '^ELEMENT_START'                 => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ELEMENT_START' },
                               '^ELEMENT_END'                   => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ELEMENT_END' },
                               '^ETAG_START'                    => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ETAG_START' },
                               '^ETAG_END'                      => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ETAG_END' },
                               '^S'                             => { fixed_length => 0, lexeme => 1, type => 'before', symbol_name => 'S' },
                               '^EMPTYELEM_START'               => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ELEMENT_START' },
                               '^EMPTYELEM_END'                 => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ELEMENT_END' },
                               '^EMPTY'                         => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'EMPTY' },
                               '^ANY'                           => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ANY' },
                               '^QUESTIONMARK_OR_STAR_OR_PLUS'  => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'QUESTIONMARK_OR_STAR_OR_PLUS' },
                               '^OR'                            => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'OR' },
                               '^CHOICE_START'                  => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'CHOICE_START' },
                               '^CHOICE_END'                    => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'CHOICE_END' },
                               '^SEQ_START'                     => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'SEQ_START' },
                               '^SEQ_END'                       => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'SEQ_END' },
                               '^MIXED_START1'                  => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'MIXED_START1' },
                               '^MIXED_END1'                    => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'MIXED_END1' },
                               '^MIXED_START2'                  => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'MIXED_START2' },
                               '^MIXED_END2'                    => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'MIXED_END2' },
                               '^COMMA'                         => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'COMMA' },
                               '^PCDATA'                        => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'PCDATA' },
                               '^ATTLIST_START'                 => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ATTLIST_START' },
                               '^ATTLIST_END'                   => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ATTLIST_END' },
                               '^CDATA'                         => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'CDATA' },
                               '^ID'                            => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ID' },
                               '^IDREF'                         => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'IDREF' },
                               '^IDREFS'                        => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'IDREFS' },
                               '^ENTITY'                        => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ENTITY' },
                               '^ENTITIES'                      => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ENTITIES' },
                               '^NMTOKEN'                       => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'NMTOKEN' },
                               '^NMTOKENS'                      => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'NMTOKENS' },
                               '^NOTATION'                      => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'NOTATION' },
                               '^NOTATION_START'                => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'NOTATION_START' },
                               '^NOTATION_END'                  => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'NOTATION_END' },
                               '^ENUMERATION_START'             => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ENUMERATION_START' },
                               '^ENUMERATION_END'               => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ENUMERATION_END' },
                               '^REQUIRED'                      => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'REQUIRED' },
                               '^IMPLIED'                       => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'IMPLIED' },
                               '^FIXED'                         => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'FIXED' },
                               '^INCLUDE'                       => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'INCLUDE' },
                               '^IGNORE'                        => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'IGNORE' },
                               '^INCLUDESECT_START'             => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'INCLUDESECT_START' },
                               '^INCLUDESECT_END'               => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'INCLUDESECT_END' },
                               '^IGNORESECTCONTENTSUNIT_START'  => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'IGNORESECTCONTENTSUNIT_START' },
                               '^IGNORESECTCONTENTSUNIT_END'    => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'IGNORESECTCONTENTSUNIT_END' },
                               '^CHARREF_START1'                => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'CHARREF_START1' },
                               '^CHARREF_END1'                  => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'CHARREF_END1' },
                               '^CHARREF_START2'                => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'CHARREF_START2' },
                               '^CHARREF_END2'                  => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'CHARREF_END2' },
                               '^ENTITYREF_START'               => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ENTITYREF_START' },
                               '^ENTITYREF_END'                 => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'ENTITYREF_END' },
                               '^PEREFERENCE_START'             => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'PEREFERENCE_START' },
                               '^PEREFERENCE_END'               => { fixed_length => 1, lexeme => 1, type => 'before', symbol_name => 'PEREFERENCE_END' },
                              );

#
sub _generic_parse {
  my ($self, $io, $pos, $global_pos, $global_line, $global_column, $grammars_ref, $hash_ref, $parse_opts_ref, $start_symbol, $end_event_name, $internal_events_ref, $switches_ref, $recursion_level) = @_;

  $recursion_level //= 0;

  $grammars_ref->{$start_symbol} //= MarpaX::Languages::XML::Impl::Grammar->new->compile(%{$hash_ref},
                                                                                         start => $start_symbol,
                                                                                         internal_events => $internal_events_ref
                                                                                        );
  #
  # Get the list of required events
  #
  my %required_event_names = map { $_ => 0 } grep { $internal_events_ref->{$_}->{required} } keys %{$internal_events_ref};

  my $redo_first_read;
  my @events;
  my $length = $io->length;
  my $next_pos;
  my $r;

  do {
    $redo_first_read = 0;
    @events = ();
    $self->_logger->debugf('[%3d] Instanciating a %s recognizer', $recursion_level, $start_symbol);
    $r = Marpa::R2::Scanless::R->new({%{$parse_opts_ref},
                                      grammar => $grammars_ref->{$start_symbol},
                                      trace_file_handle => $MARPA_TRACE_FILE_HANDLE,
                                     });
    try {
      $self->_logger->debugf('[%3d] Reading at internal position %d global position %d line %d column %d', $recursion_level, $pos, $global_pos, $global_line, $global_column);
      $next_pos = $r->read($io->buffer, $pos);
      @events = @{$r->events()};
    } catch {
      #
      # It is okay to retry only if there are required event names and none of them has fired.
      #
      $self->_logger->debugf('[%3d] %s', $recursion_level, "$_");
      $self->_read($io, $length, $recursion_level);
    } finally {
      if (! @events) {
        $redo_first_read = 1;
      } else {
        $pos = $next_pos;
      }
    };
  } while ($redo_first_read);

  $self->_logger->debugf('[%3d] Reading returned internal position %d', $recursion_level, $pos);
  my $got_end_event_name;
  while ($pos < $length) {
    $got_end_event_name = 0;
    foreach (@{$r->events()}) {
      my $event_name = $_->[0];
      my ($line, $column) = $self->_get_line_column($r, $internal_events_ref->{$event_name}->{lexeme}, $internal_events_ref->{$event_name}->{symbol_name});
      $self->_logger->debugf('[%3d] Got event \'%s\' at internal position %d global position %d line %d column %d', $recursion_level, $event_name, $pos, $pos + $global_pos, $line + $global_line, $column + $global_column);
      my $code_ref = $switches_ref->{$event_name}->{code_ref};
      my $args_ref = $switches_ref->{$event_name}->{args_ref};
      if ($code_ref) {
        $pos = $self->$code_ref(@{$args_ref});
      }
      if ($event_name eq $end_event_name) {
        $got_end_event_name = 1;
        last;
      }
    }
    if (! $got_end_event_name) {
      $io->read;
      my $new_length;
      if (($new_length = $io->length) <= $length) {
        $self->_exception('[%3d] EOF when parsing %s', $recursion_level, $r, $start_symbol);
      }
      $length = $new_length;
      $self->_logger->debugf('[%3d] Resuming at internal buffer position %d', $recursion_level, $pos);
      $pos = $r->resume($pos);
    }
  }
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
    # Very initial block size and read
    #
    $io->block_size($block_size)->read;
    #
    # Go
    #
    my %internal_events = (
                           #
                           # A valid XML must have at least one element
                           #
                           '^ELEMENT_START' => { required => 1, lexeme => 1, type => 'before',    symbol_name => 'ELEMENT_START' },
                           #
                           # A valid XML may have a declaration block
                           #
                           '^XMLDECL_START' => { required => 0, lexeme => 1, type => 'before',    symbol_name => 'XMLDECL_START' },
                           #
                           # Encoding declaration is optional
                           #
                           'EncodingDecl$'  => { required => 0, lexeme => 0, type => 'completed', symbol_name => 'EncodingDecl' },
                           );
    my %switches = (
                   );
    $self->_generic_parse(
                          $io,               # io
                          0,                 # pos
                          0,                 # global_pos
                          0,                 # global_line
                          0,                 # global_column
                          {},                # grammars_ref
                          \%hash,            # $hash_ref
                          $parse_opts_ref,   # parse_opts_ref
                          'document',        # start_symbol
                          '',                # end_event_name
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
