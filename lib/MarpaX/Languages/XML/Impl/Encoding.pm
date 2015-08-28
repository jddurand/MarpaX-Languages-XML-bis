package MarpaX::Languages::XML::Impl::Encoding;
use Config;
use Encode::Guess;
use MarpaX::Languages::XML::Impl::Logger;
use Moo;
use MooX::late;
use Try::Tiny;

# ABSTRACT: MarpaX::Languages::XML::Role::Encoding implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is an implementation of MarpaX::Languages::XML::Role::Encoding. It is used to return encoding from BOM or a guess, using bytes in input.

=cut

sub bom {
  my ($self, $bytes) = @_;

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

  if (length($bom) > 0) {
    $self->_logger->debugf('Encoding guess from BOM: \'%s\' using %d bytes', $bom, $bom_size);
  } else {
    $self->_logger->debugf('No encoding guess from BOM');
  }

  return ($bom, $bom_size);
}

sub guess {
  my ($self, $bytes) = @_;

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
    $self->_logger->debugf('Revisiting %s encoding guess to UTF-8', $name);
    $name = 'UTF-8';
  }

  if (length($name) > 0) {
    $self->_logger->debugf('Encoding guess from bytes: \'%s\'', $name);
  } else {
    $self->_logger->debugf('No encoding guess from bytes');
  }

  return $name;
}

sub final {
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

  $self->_logger->debugf('Final encoding is \'%s\'', $final_encoding);

  return $final_encoding;
}

extends 'MarpaX::Languages::XML::Impl::Logger';

1;
