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

sub _get_literal {
  my ($self, $r, $non_terminal) = @_;

  my ($start, $span_length) = $r->last_completed_span($non_terminal);
  return $r->literal($start, $span_length);
}

sub _get_lexeme_line_column {
  my ($self, $r) = @_;

  my ($start, $length) = $r->pause_span();
  return $r->line_column($start);
}

sub parse {
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
    # - 'exhausted  : parsing exhausted but lexemes remain
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
