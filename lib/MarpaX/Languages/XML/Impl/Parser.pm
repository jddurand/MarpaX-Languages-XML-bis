package MarpaX::Languages::XML::Impl::Parser;
use Config;
use Encode::Guess;
use Fcntl qw/:seek/;
use Marpa::R2;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Impl::Logger;
use MarpaX::Languages::XML::Impl::Grammar;
use Moo;
use MooX::late;
use IO::All;
use IO::All::LWP;
use Scalar::Util qw/blessed reftype/;
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

sub _bytes_to_BOM {
  my ($self, $bytes) = @_;

  $self->_logger->debugf('Guessing encoding with the BOM');

  my $bom = '';
  my $bom_size = 0;

  #
  # 5 bytes
  #
  if ($bytes =~ m/^\x{2B}\x{2F}\x{76}\x{38}\x{2D}/) { # If no following character is encoded, 38 is used for the fourth byte and the following byte is 2D
    $bom = 'UTF-7';
    $bom_size = 5;
  }
  #
  # 4 bytes
  #
  elsif ($bytes =~ m/^(?:\x{2B}\x{2F}\x{76}\x{38}|\x{2B}\x{2F}\x{76}\x{39}|\x{2B}\x{2F}\x{76}\x{2B}|\x{2B}\x{2F}\x{76}\x{2F})/s) { # 3 bytes + all possible values of the 4th byte
    $bom = 'UTF-7';
    $bom_size = 4;
  }
  elsif ($bytes =~ m/^(?:\x{00}\x{00}\x{FF}\x{FE}|\x{FE}\x{FF}\x{00}\x{00})/s) { # UCS-4, unusual octet order (2143 or 3412)
    $bom = 'UCS-4';
    $bom_size = 4;
  }
  elsif ($bytes =~ m/^\x{00}\x{00}\x{FE}\x{FF}/s) { # UCS-4, big-endian machine (1234 order)
    $bom = 'UTF-32BE';
    $bom_size = 4;
  }
  elsif ($bytes =~ m/^\x{FF}\x{FE}\x{00}\x{00}/s) { # UCS-4, little-endian machine (4321 order)
    $bom = 'UTF-32LE';
    $bom_size = 4;
  }
  elsif ($bytes =~ m/^\x{DD}\x{73}\x{66}\x{73}/s) {
    $bom = 'UTF-EBCDIC';
    $bom_size = 4;
  }
  elsif ($bytes =~ m/^\x{84}\x{31}\x{95}\x{33}/s) {
    $bom = 'GB-18030';
    $bom_size = 4;
  }
  #
  # 3 bytes
  #
  elsif ($bytes =~ m/^\x{EF}\x{BB}\x{BF}/s) { # UTF-8
    $bom = 'UTF-8';
    $bom_size = 3;
  }
  elsif ($bytes =~ m/^\x{F7}\x{64}\x{4C}/s) {
    $bom = 'UTF-1';
    $bom_size = 3;
  }
  elsif ($bytes =~ m/^\x{0E}\x{FE}\x{FF}/s) { # Signature recommended in UTR #6
    $bom = 'SCSU';
    $bom_size = 3;
  }
  elsif ($bytes =~ m/^\x{FB}\x{EE}\x{28}/s) {
    $bom = 'BOCU-1';
    $bom_size = 3;
  }
  #
  # 2 bytes
  #
  elsif ($bytes =~ m/^\x{FE}\x{FF}/s) { # UTF-16, big-endian
    $bom = 'UTF-16BE';
    $bom_size = 2;
  }
  elsif ($bytes =~ m/^\x{FF}\x{FE}/s) { # UTF-16, little-endian
    $bom = 'UTF-16LE';
    $bom_size = 2;
  }

  if ($bom_size > 0) {
    $self->_logger->debugf('BOM says %s using %d bytes', $bom, $bom_size);
  }

  return ($bom, $bom_size);
}

sub _guess_encoding {
  my ($self, $bytes) = @_;

  $self->_logger->debugf('Guessing encoding with the data');

  #
  # Do ourself common guesses
  #
  my $name = '';
  if ($bytes =~ /^\x{00}\x{00}\x{00}\x{3C}/) { # '<' in UTF-32BE
    $name = 'UTF-32BE';
  }
  elsif ($bytes =~ /^\x{3C}\x{00}\x{00}\x{00}/) { # '<' in UTF-32LE
    $name = 'UTF-32LE';
  }
  elsif ($bytes =~ /^\x{00}\x{3C}\x{00}\x{3F}/) { # '<?' in UTF-16BE
    $name = 'UTF-16BE';
  }
  elsif ($bytes =~ /^\x{3C}\x{00}\x{3F}\x{00}/) { # '<?' in UTF-16LE
    $name = 'UTF-16LE';
  }
  elsif ($bytes =~ /^\x{3C}\x{3F}\x{78}\x{6D}/) { # '<?xml' in US-ASCII
    $name = 'ASCII';
  }

  if (! $name) {
    my $is_ebcdic = $Config{'ebcdic'} || '';
    if ($is_ebcdic eq 'define') {
      $self->_logger->debugf('Encode::Guess not supported on EBCDIC platform');
      return;
    }

    my @suspect_list = ();
    if ($bytes =~ /\e/) {
      push(@suspect_list, qw/7bit-jis iso-2022-kr/);
    }
    elsif ($bytes =~ /[\x80-\xFF]{4}/) {
      push(@suspect_list, qw/euc-cn big5-eten euc-jp cp932 euc-kr cp949/);
    } else {
      push(@suspect_list, qw/utf-8/);
    }

    local $Encode::Guess::NoUTFAutoGuess = 0;
    try {
      my $enc = guess_encoding($bytes, @suspect_list);
      if (! defined($enc) || ! ref($enc)) {
        die $enc || 'unknown encoding';
      }
      $name = uc($enc->name || '');
    } catch {
      $self->_logger->debugf('%s', $_);
    };
  }

  if ($name eq 'ASCII') {
    #
    # Ok, ascii is UTF-8 compatible. Let's say UTF-8.
    #
    $self->_logger->debugf('data says %s, revisited as UTF-8', $name);
    $name = 'UTF-8';
  } else {
    $self->_logger->debugf('data says %s', $name);
  }

  return $name;
}

sub _set_position {
  my ($self, $source, $io, $position) = @_;

  my $pos_ok = 0;
  try {
    my $tell = $io->tell;
    if ($tell != $position) {
      $self->_logger->debugf('Moving io position from %d to %d', $tell, $position);
      $io->seek($position, SEEK_SET);
      if ($io->tell != $position) {
        die sprintf('Failure setting position from %d to %d failure', $tell, $position);
      } else {
        $pos_ok = 1;
      }
    } else {
      $pos_ok = 1;
    }
  } catch {
    $self->_logger->debugf("$_");
  };
  if (! $pos_ok) {
    #
    # Ah... not seekable perhaps
    # The only alternative is to reopen the stream
    #
    $self->_logger->debugf('Seek failure');
    my $orig_block_size = $io->block_size;
    $io = $self->_io($source);
    $self->_binary($io);
    $self->_block_size($io, $position);
    my $length = $self->_read($io);
    if ($length != $position) {
      #
      # Really I do not know what else to do
      #
      $self->_exception("Re-opening failed to position source at byte $position");
    } else {
      #
      # Restore original $io block size
      $io->block_size($orig_block_size);
    }
  }

  return $io;
}

sub _open {
  my ($self, $source) = @_;
  #
  # Read the first five bytes if any. Supported encodings at those
  # mentionned at https://en.wikipedia.org/wiki/Byte_order_mark
  #
  my $io = $self->_io($source);
  $self->_binary($io);
  $self->_block_size($io, 1024);
  my $length = $self->_read($io);
  my $buffer = ${$io->buffer};

  my $bom_encoding = '';
  my $guess_encoding = '';

  my ($found_encoding, $byte_start) = $self->_bytes_to_BOM($buffer);
  if (length($found_encoding) <= 0) {
    $found_encoding = $self->_guess_encoding($buffer);
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

  $self->_encoding($io, $found_encoding);

  #
  # Make sure we are positionned at the beginning of the buffer. This is inefficient
  # for everything that is not seekable.
  #
  $io = $self->_set_position($source, $io, $byte_start);

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

sub _clear {
  my ($self, $io) = @_;

  $self->_logger->debugf('Clearing io internal buffer');
  $io->clear;
}

sub _read {
  my ($self, $io) = @_;

  my $length = $io->read;
  $self->_logger->debugf('Got %d characters', $length);

  if ($length <= 0) {
    $self->_exception('EOF');
  }

  return $length;
}

sub _block_size {
  my ($self, $io, $block_size) = @_;

  $self->_logger->debugf('Setting io internal buffer to %d', $block_size);
  return $io->block_size($block_size);
}

sub _binary {
  my ($self, $io) = @_;

  $self->_logger->debugf('Setting io access to binary');
  return $io->binary;
}

sub _encoding {
  my ($self, $io, $encoding) = @_;

  $self->_logger->debugf('Setting encoding to %s', $encoding);
  return $io->encoding($encoding);
}

sub _io {
  my ($self, $source) = @_;

  $self->_logger->debugf('Opening %s', $source);
  return io($source);
}

sub parse {
  my ($self, %hash) = @_;

  my $r;
  my $value;

  my $source = $hash{source} || '';
  if (reftype($source)) {
    $self->_exception('source must be a SCALAR');
  }

  my $block_size = $hash{block_size} || 11;
  if (reftype($block_size)) {
    $self->_exception('block_size must be a SCALAR');
  }

  #
  # We force our internal start_element callback, just to catch the end of the prolog
  #
  my $document = MarpaX::Languages::XML::Impl::Grammar->new->grammar(%hash, start => 'document');
  my $element  = MarpaX::Languages::XML::Impl::Grammar->new->grammar(%hash, start => 'element');

  my $parse_opts = $hash{parse_opts} || {};
  if ((reftype($parse_opts) || '') ne 'HASH') {
    $self->_exception('parse_opts must be a ref to HASH');
  }

  try {
    #
    # Guess the encoding
    #
    my ($io, $bom_encoding, $guess_encoding, $orig_encoding, $byte_start) = $self->_open($source);
    #
    # $xml_encoding will hold the encoding as per the XML itself
    #
    my $xml_encoding = '';
    my $root_element_pos = -1;
    my $nb_first_read = 0;
    my $pos;
    my @events;
    #
    # Very initial block size
    #
    $self->_block_size($io, $block_size);
    #
    # First the prolog.
    #
  redo_first_read:
    my $length = $self->_read($io);
    my $buffer = '';
    do {
      $buffer .= ${$io->buffer};
      $self->_logger->debugf('Appended %d characters to initial buffer that has now a length of %d characters', $length, length($buffer));
      $self->_logger->debugf('Instanciating a recognizer');
      $r = Marpa::R2::Scanless::R->new({%{$parse_opts},
                                        grammar => $document,
                                        trace_file_handle => $MARPA_TRACE_FILE_HANDLE,
                                       });
      @events = ();
      try {
        $pos = $r->read(\$buffer);
        @events = map { $_->[0] } @{$r->events()};
      };
      #
      # We expect either start_element or EncodingDecl$.
      # Why start_element ? Because an XML document must have at least one. This is a
      # a way to eat everything up to the end of the prolog.
      #
      if (! @events) {
        $self->_logger->debugf('No event');
        $block_size *= 2;
        $self->_block_size($io, $block_size);
        $length = $self->_read($io);
      } else {
        foreach (@events) {
          $self->_logger->debugf('Got parse event \'%s\'', $_);
          if ($_ eq 'EncodingDecl$') {
            #
            # Remember encoding as given in the XML
            #
            my ($start, $span_length) = $r->last_completed_span('EncName');
            $xml_encoding = uc($r->literal($start, $span_length));
            $self->_logger->debugf('Got encoding name \'%s\'', $xml_encoding);
          }
          elsif ($_ eq 'tagStart$') {
            $root_element_pos = $pos - 1;
          }
        }
      }
    } while ((! $xml_encoding) || ($root_element_pos >= 0));
    #
    # Check eventual encoding v.s. endianness. Algorithm vaguely taken from
    # https://blogs.oracle.com/tucu/entry/detecting_xml_charset_encoding_again
    #
    my $final_encoding = $self->_final_encoding($bom_encoding, $guess_encoding, $xml_encoding, $orig_encoding);
    if ($final_encoding ne $orig_encoding) {
      $self->_logger->debugf('Original encoding was \'%s\', final encoding is \'%s\': redo initial read', $orig_encoding, $final_encoding);
      #
      # We have to retry. EncodingDecl$ event, if any, will match.
      #
      $self->_encoding($io, $final_encoding);
      $io = $self->_set_position($source, $io, $byte_start);
      $orig_encoding = $final_encoding;
      goto redo_first_read;
    } else {
      $self->_logger->debugf('Original encoding was \'%s\', final encoding is \'%s\': continuing', $orig_encoding, $final_encoding);
    }
    #
    # At this point the the root element may not have been reached. In such a case, force it.
    # This will croak if prolog is buggy or if there is no root element, or if initial buffer
    # is too small.
    #
    if ($root_element_pos < 0) {
      $self->_logger->debugf('Resuming prolog parsing up to eventual root element in the buffer');
      @events = ();
      try {
        $pos = $r->resume($pos);
        @events = map { $_->[0] } @{$r->events()};
      };
      foreach (@events) {
        $self->_logger->debugf('Got parse event \'%s\'', $_);
        if ($_ eq 'tagStart$') {
          $root_element_pos = $pos - 1;
        }
      }
      if ($root_element_pos < 0) {
        #
        # Bad luck
        #
        $self->_logger->debugf('No tag start');
        $block_size *= 2;
        $self->_block_size($io, $block_size);
        $io = $self->_set_position($source, $io, $byte_start);
        goto redo_first_read;
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
    $self->_logger->debugf('Looping on element grammar starting at position %d', $root_element_pos);
    $r = Marpa::R2::Scanless::R->new({%{$parse_opts},
                                      grammar => $element,
                                      exhaustion => 'event',
                                      trace_file_handle => $MARPA_TRACE_FILE_HANDLE,
                                     });
    $pos = $r->read(\$buffer, $root_element_pos);
    while ($pos < length($buffer)) {
      my $resume_ok = 0;
      try {
        $self->_logger->debugf('Resuming recognizer at position %d', $pos);
        $pos = $r->resume($pos);
        my @events = map { $_->[0] } @{$r->events()};
        foreach (@events) {
          $self->_logger->debugf('Got parse event \'%s\'', $_);
        }
      } catch {
        $self->_logger->debugf('%s', "$_");
      };
    }

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
    $self->_exception("$_", $r);
    return;                          # Will never be executed
  };

  return $value;
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
        MarpaX::Languages::XML::Exception->throw("BOM encoding '$bom_encoding' disagree with XML encoding '$xml_encoding");
      }
    } else {
      if ($bom_encoding =~ /^(.*)[LB]E$/) {
        my $without_le_or_be = ($+[1] > $-[1]) ? substr($bom_encoding, $-[1], $+[1] - $-[1]) : '';
        if (($xml_encoding ne '') && ($xml_encoding ne $without_le_or_be) && ($xml_encoding ne $bom_encoding)) {
          MarpaX::Languages::XML::Exception->throw("BOM encoding '$bom_encoding' disagree with XML encoding '$xml_encoding");
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
