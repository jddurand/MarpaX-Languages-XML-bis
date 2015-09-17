package MarpaX::Languages::XML::Exception;
use XML::SAX::Exception;
use Moo;

# ABSTRACT: XML::SAX::Exception extension with Marpa progress report and expected terminals

# VERSION

# AUTHORITY

extends 'XML::SAX::Exception';

around stringify => sub {
  my ($orig, $self) = (shift, shift);

  my $string = $self->$orig(@_);
  if ($self->{Progress}) {
    $string .= "\n"
      . "Grammar progress:\n"
      . "-----------------\n"
      . $self->{Progress};
  }
  #
  # Data::HexDumper is a great module, except there is no option
  # to ignore 0x00, which is impossible in XML.
  #
  my $nbzeroes = ($self->{Data} =~ s/( 00)(?= (?::|00))/   /g);
  if ($nbzeroes) {
    $self->{Data} =~ s/\.{$nbzeroes}$//;
  }
  if ($self->{Data}) {
    if ($self->{DataBefore}) {
      my $nbzeroes = ($self->{DataBefore} =~ s/( 00)(?= (?::|00))/   /g);
      if ($nbzeroes) {
        $self->{DataBefore} =~ s/\.{$nbzeroes}$//;
      }
      $string .= "\n"
        . "Characters around the error:\n"
        . "----------------------------\n";
      $string .= $self->{DataBefore};
      $string .= '  <' . $self->{Message} . ">\n";
    } else {
      $string .= "\n"
        . "Characters just after the error:\n"
        . "--------------------------------\n";
    }
    $string .= $self->{Data};
  }
  if ($self->{TerminalsExpected}) {
    $string .= "\n"
      . "Terminals expected:\n"
      . "-------------------\n"
      . join(', ', @{$self->{TerminalsExpected}}) . "\n";
  }
  return $string;
};

package MarpaX::Languages::XML::Exception::NotRecognized;
use Moo;
extends 'MarpaX::Languages::XML::Exception';

package MarpaX::Languages::XML::Exception::NotSupported;
use Moo;
extends 'MarpaX::Languages::XML::Exception';

package MarpaX::Languages::XML::Exception::Parse;
use Moo;
extends 'MarpaX::Languages::XML::Exception';

1;
