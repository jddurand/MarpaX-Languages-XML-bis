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
  if ($bytes =~ m/^\x{2B}\x{2F}\x{76}\x{38}\x{2D}/) {
    $bom = 'UTF-7';
    $bom_size = 5;
  }
  #
  # 4 bytes
  #
  elsif ($bytes =~ m/^(?:\x{2B}\x{2F}\x{76}\x{38}|\x{2B}\x{2F}\x{76}\x{39}|\x{2B}\x{2F}\x{76}\x{2B}|\x{2B}\x{2F}\x{76}\x{2F})/s) {
    $bom = 'UTF-7';
    $bom_size = 4;
  }
  elsif ($bytes =~ m/^\x{00}\x{00}\x{FE}\x{FF}/s) {
    $bom = 'UTF-32BE';
    $bom_size = 4;
  }
  elsif ($bytes =~ m/^\x{FF}\x{FE}\x{00}\x{00}/s) {
    $bom = 'UTF-32LE';
    $bom_size = 4;
  }
  elsif ($bytes =~ m/^\x{FF}\x{FE}\x{00}\x{00}/s) {
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
  elsif ($bytes =~ m/^\x{EF}\x{BB}\x{BF}/s) {
    $bom = 'UTF-8';
    $bom_size = 3;
  }
  elsif ($bytes =~ m/^\x{F7}\x{64}\x{4C}/s) {
    $bom = 'UTF-1';
    $bom_size = 3;
  }
  elsif ($bytes =~ m/^\x{0E}\x{FE}\x{FF}/s) {
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
  elsif ($bytes =~ m/^\x{FE}\x{FF}/s) {
    $bom = 'UTF-16BE';
    $bom_size = 2;
  }
  elsif ($bytes =~ m/^\x{FF}\x{FE}/s) {
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
    push(@suspect_list, qw/latin1/);
  }

  my $name = '';
  try {
    my $enc = guess_encoding($bytes, @suspect_list);
    if (! defined($enc) || ! ref($enc)) {
      die $enc || 'unknown encoding';
    }
    $name = $enc->name || '';
  } catch {
    $self->_logger->debugf('%s', $_);
  };

  if (length($name) > 0) {
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
    $self->_logger->warnf('%s', $_);
    return;
  };
  if (! $pos_ok) {
    #
    # Ah... not seekable perhaps
    # The only alternative is to reopen the stream
    #
    $self->_logger->debugf('Closing %s', $source);
    $io = undef;
    $self->_logger->debugf('Opening %s again', $source);
    $io = io($source);
    $self->_logger->debugf('Setting io access to binary');
    $io->binary;
    $self->_logger->debugf('Setting io internal buffer to %d (wanted position)', $position);
    $io->block_size($position);
    $self->_logger->debugf('Reading %d bytes', $io->block_size);
    $io->read;
    if ($io->tell != $position) {
      #
      # Really I do not know what else to do
      #
      $self->_logger->errorf('Re-opening failed to position source at byte %d', $position);
      $self->_logger->debugf('Closing %s', $source);
      $io = undef;
    } else {
      $self->_logger->debugf('Setting io internal buffer to %d', $1024);
      $io->block_size(1024);
      $self->_logger->debugf('Clearing io internal buffer');
      $io->clear;
    }
  }

  return $io;
}

sub _open {
  my ($self, $source, $encoding) = @_;
  #
  # Read the first five bytes if any. Supported encodings at those
  # mentionned at https://en.wikipedia.org/wiki/Byte_order_mark
  #
  $self->_logger->debugf('Opening %s', $source);
  my $io = io($source);
  $self->_logger->debugf('Setting io access to binary');
  $io = $io->binary;
  $self->_logger->debugf('Setting io internal buffer to %d', 1024);
  $io->block_size(1024);
  $self->_logger->debugf('Reading %d bytes', $io->block_size);
  my $length = $io->read;
  if ($length <= 0) {
    $self->_logger->errorf('No bytes read');
    return;
  }
  my $buffer = ${$io->buffer};

  my $ok_encoding;
  my $ok_byte_start;
  my ($found_encoding, $byte_start) = $self->_bytes_to_BOM($buffer);
  if (length($found_encoding) <= 0) {
    $found_encoding = $self->_guess_encoding($buffer);
    if (length($found_encoding) <= 0) {
      $self->_logger->debugf('Assuming relaxed (perl) utf8 encoding');
      $found_encoding = 'utf8';
    } else {
      ($ok_encoding, $ok_byte_start) = ($found_encoding, 0);
    }
    $byte_start = 0;
  } else {
    ($ok_encoding, $ok_byte_start) = ($found_encoding, $byte_start);
  }

  #
  # Per def encoding is always writen in Latin1 characters, so lc() is ok
  if ($encoding && (lc($encoding) ne lc($found_encoding))) {
    $self->_logger->debugf('Giving priority to user input that says encoding is %s while we found %s', $encoding, $found_encoding);
  } else {
    $encoding = $found_encoding;
  }
  $self->_logger->debugf('Setting encoding to %s', $encoding);
  $io->encoding($encoding);

  #
  # Make sure we are positionned at the beginning of the buffer. This is inefficient
  # for everything that is not seekable.
  #
  $io = $self->_set_position($source, $io, $byte_start);
  if (! defined($io)) {
    return;
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
  return ($io, $encoding);
}

sub parse {
  my ($self, $hash_ref) = @_;

  my $r;
  my $value;

  $hash_ref //= {};
  if ((reftype($hash_ref) || '') ne 'HASH') {
    MarpaX::Languages::XML::Exception->throw('First parameter must be a ref to HASH');
  }

  my $source = $hash_ref->{source};
  if ((reftype($source) || '') ne '') {
    MarpaX::Languages::XML::Exception->throw('Hash\'s source must be a SCALAR');
  }

  my $encoding = $hash_ref->{encoding} || '';
  if ((reftype($encoding) || '') ne '') {
    MarpaX::Languages::XML::Exception->throw('Hash\'s encoding must be a SCALAR');
  }

  my $block_size = $hash_ref->{block_size} || 1048576;
  if ((reftype($block_size) || '') ne '') {
    MarpaX::Languages::XML::Exception->throw('Hash\'s block_size must be a SCALAR');
  }

  my $grammar    = $hash_ref->{grammar} || MarpaX::Languages::XML::Impl::Grammar->xml10;
  if ((blessed($grammar) || '') ne 'Marpa::R2::Scanless::G') {
    MarpaX::Languages::XML::Exception->throw('Hash\'s grammar must be an Marpa::R2::Scanless::G instance');
  }

  my $parse_opts = $hash_ref->{parse_opts} || {};
  if ((reftype($parse_opts) || '') ne 'HASH') {
    MarpaX::Languages::XML::Exception->throw('Hash\'s parse_opts must be a ref to HASH');
  }

  try {
    #
    # Guess the encoding
    #
    my ($io, $encoding) = $self->_open($source, $encoding);
    if (defined($io)) {
      $self->_logger->debugf('Setting io internal buffer to %d', $block_size);
      $io->block_size($block_size);
      $self->_logger->debugf('Clearing io internal buffer');
      $io->clear;
      #
      # We do not want to slurp the entire input.
      # Instead we rely on the fact that all XML grammars are a "loop" on element.
      # An element is nullable, and is preceeded by an eventual prolog also nullable,
      # folllowed by an eventual MiscAny, also nullable.
      # This mean that we can loop on element completion event.
      # The parse will be over if Marpa says it is exhausted.
      # The parse will stop if we reach eof or parse is exhausted.
      #
    retry_initial_read:
      $self->_logger->debugf('Trying to read %d characters', $block_size);
      my $length = $io->read;
      $self->_logger->debugf('Got %d characters', $length);
      if ($length > 0) {
        #
        # First call to recognizer must always be read()
        #
        my $buffer = '';
        my $pos;
        my $first_read_ok = 0;
        my @events;
        do {
          $buffer .= ${$io->buffer};
          $self->_logger->debugf('Appended %d characters to initial buffer', $length);
          try {
            $self->_logger->debugf('Instanciating a recognizer');
            $r = Marpa::R2::Scanless::R->new({%{$parse_opts},
                                              grammar => $grammar,
                                              trace_file_handle => $MARPA_TRACE_FILE_HANDLE,
                                             });
            $pos = $r->read(\$buffer);
          };
          @events = map { $_->[0] } @{$r->events()};
          if (! @events) {
            #
            # Try to read more in the initial buffer. We want to catch 'EncName$' eventually.
            #
            $self->_logger->debugf('Increasing internal buffer from %d to %d', $block_size, $block_size * 2);
            $block_size *= 2;
            $io->block_size($block_size);
            $self->_logger->debugf('Clearing io internal buffer');
            $io->clear;
            $self->_logger->debugf('Trying to read %d characters', $block_size);
            $length = $io->read;
            if ($length <= 0) {
              $self->_logger->debugf('EOF');
              last;
            }
          }
        } while (! @events);
        foreach (@events) {
          $self->_logger->debugf('Got parse event \'%s\'', $_);
        }
      } else {
        $self->_logger->debugf('EOF');
      }

      my $ambiguous = $r->ambiguous();
      if ($ambiguous) {
        MarpaX::Languages::XML::Exception->throw("Parse of the input is ambiguous: $ambiguous");
      }
      my $value_ref = $r->value || MarpaX::Languages::XML::Exception->throw('No parse');
      $value = ${$value_ref} || MarpaX::Languages::XML::Exception->throw('No parse value');
    }
  } catch {
    #
    # We do "$_" to force an eventual stringification
    #
    $self->_exception("$_", $r);
    return;                          # Will never be executed
  };

  return $value;
}

extends 'MarpaX::Languages::XML::Impl::Logger';
with 'MarpaX::Languages::XML::Role::Parser';

1;
