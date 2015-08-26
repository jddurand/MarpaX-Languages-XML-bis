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
  my ($self, $source) = @_;
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

  my $encoding = MarpaX::Languages::XML::Impl::Encoding->new();

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

  try {
    #
    # Guess the encoding
    #
    my ($io, $bom_encoding, $guess_encoding, $orig_encoding, $byte_start) = $self->_open($source);
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
      @events = ();
      #
      # We accept a failure if buffer is too small
      #
      try {
        $pos = $r->read(\$buffer);
        @events = map { $_->[0] } @{$r->events()};
      };
      #
      # We expect either tagSart$ or EncodingDecl$.
      # Why tagSart$ ? Because an XML document must have at least one element.
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
            my ($start, $span_length) = $r->last_completed_span('EncName');
            $xml_encoding = uc($r->literal($start, $span_length));
            $self->_logger->debugf('XML says encoding \'%s\'', $xml_encoding);
          }
          elsif ($_ eq '^STAG_START') {
            $root_element_pos = $pos;
            my ($start, $length) = $r->pause_span();
            ($root_line, $root_column) = $r->line_column($start);
          }
        }
      }
    } while ((! $xml_encoding) && ($root_element_pos < 0));
    #
    # Check eventual encoding v.s. endianness. Algorithm vaguely taken from
    # https://blogs.oracle.com/tucu/entry/detecting_xml_charset_encoding_again
    #
    my $final_encoding = $self->_final_encoding($bom_encoding, $guess_encoding, $xml_encoding, $orig_encoding);
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
      $self->_logger->debugf('Resuming prolog parsing up to root element');
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
    $self->_element_loop($io, $block_size, $parse_opts, \%hash, \$buffer, $root_element_pos, $root_line, $root_column);

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
  my ($self, $io, $block_size, $parse_opts, $hash_ref, $buffer_ref, $pos, $line, $column, $element) = @_;

  $self->_logger->debugf('Parsing element at line %d column %d position %d', $line, $column, $pos);

  $element //= MarpaX::Languages::XML::Impl::Grammar->new->compile(%{$hash_ref},
                                                                   start => 'element',
                                                                   internal_events =>
                                                                   {
                                                                    G1 =>
                                                                    {
                                                                     Attribute => { type => 'completed', name => 'Attribute$' }
                                                                    },
                                                                    L0 =>
                                                                    {
                                                                     STAG_START => { type => 'before', name => '^STAG_START' },
                                                                     STAG_END   => { type => 'after', name => 'STAG_END$' }
                                                                    }
                                                                   }
                                                                  );

  my $r;
  my @events;
  do {
    $self->_logger->debugf('Instanciating an element recognizer');
    $r = Marpa::R2::Scanless::R->new({%{$parse_opts},
                                      grammar => $element,
                                      exhaustion => 'event',
                                      trace_file_handle => $MARPA_TRACE_FILE_HANDLE,
                                     });
    #
    # Very first event is always predictable we guarantee that $pos's character
    # is always the lexeme STAG_START.
    #
    $self->_logger->debugf('Disabling %s event', '^STAG_START');
    $r->activate('^STAG_START', 0);
    $self->_logger->debugf('Doing first read');
    my $next_pos = $r->read($buffer_ref, $pos);
    $self->_logger->debugf('Enabling %s event', '^STAG_START');
    $r->activate('^STAG_START', 1);
    #
    # After the first read, we expect to be paused by either:
    # - ^STAG_START : a new element
    # - STAG_END$   : end of current element
    # - Attribute$  : end of an attribute in current element
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
    } else {
      $pos = $next_pos;
    }
  } while (! @events);

  foreach (@events) {
    $self->_logger->debugf('Got parse event \'%s\' at position %d', $_, $pos);
  }

  exit;
  while (! $io->eof) {
    my $resume_ok = 0;
    try {
      $self->_logger->debugf('Resuming recognizer at position %d', $pos);
      $pos = $r->resume($pos);
      my @events = map { $_->[0] } @{$r->events()};
      foreach (@events) {
        $self->_logger->debugf('Got parse event \'%s\' at position %d', $_, $pos);
      }
    } catch {
      $self->_logger->debugf('%s', "$_");
    };
  }
}

sub _final_encoding {
  my ($self, $bom_encoding, $guess_encoding, $xml_encoding, $orig_encodingp) = @_;

  $self->_logger->debugf('BOM encoding says \'%s\', guess encoding says \'%s\', XML encoding says \'%s\'', $bom_encoding, $guess_encoding, $xml_encoding);

  my $final_encoding;
  if (! $bom_encoding) {
    if (! $guess_encoding || ! $xml_encoding) {
      $final_encoding = 'UTF-8';
    } else {
      #
      # General handling of 'LE' and 'BE' extensions
      #
      if (($guess_encoding eq "${xml_encoding}BE") || ($guess_encoding eq "${xml_encoding}LE")) {
        $final_encoding = $guess_encoding;
      } else {
        $final_encoding = $xml_encoding;
      }
    }
  } else {
    if ($bom_encoding eq 'UTF-8') {
      #
      # Why trusting a guess when it is only a guess.
      #
      # if (($guess_encoding ne '') && ($guess_encoding ne 'UTF-8')) {
      #   $self->_logger->errorf('BOM encoding \'%s\' disagree with guessed encoding \'%s\'', $bom_encoding, $xml_encoding);
      # }
      if (($xml_encoding ne '') && ($xml_encoding ne 'UTF-8')) {
        $self->_exception("BOM encoding '$bom_encoding' disagree with XML encoding '$xml_encoding");
      }
    } else {
      if ($bom_encoding =~ /^(.*)[LB]E$/) {
        my $without_le_or_be = ($+[1] > $-[1]) ? substr($bom_encoding, $-[1], $+[1] - $-[1]) : '';
        if (($xml_encoding ne '') && ($xml_encoding ne $without_le_or_be) && ($xml_encoding ne $bom_encoding)) {
          $self->_exception("BOM encoding '$bom_encoding' disagree with XML encoding '$xml_encoding");
        }
      }
    }
    #
    # In any case, BOM win. So we always inherit the correct $byte_start.
    #
    $final_encoding = $bom_encoding;
  }

  return $final_encoding;
}


extends 'MarpaX::Languages::XML::Impl::Logger';
with 'MarpaX::Languages::XML::Role::Parser';

1;
