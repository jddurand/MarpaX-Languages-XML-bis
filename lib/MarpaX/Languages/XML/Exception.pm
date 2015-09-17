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
    $string .= "\nGrammar progress:\n" . $self->{Progress};
  }
  if (defined($self->{Position})) {
    $string .= "\nInternal buffer position: " . $self->{Position} . " (hex: " . sprintf('0x%04x', $self->{Position}) . ")\n";
  }
  if ($self->{Data}) {
    if ($self->{DataBefore}) {
      $string .= "\nCharacters around the error:\n";
      $string .= $self->{DataBefore};
      $string .= "<<< EXCEPTION OCCURED HERE >>>\n";
    } else {
      $string .= "\nCharacters just after the error:\n";
    }
    $string .= $self->{Data};
  }
  if ($self->{TerminalsExpected}) {
    $string .= "\nTerminals expected:\n" . join(', ', @{$self->{TerminalsExpected}}) . "\n";
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
