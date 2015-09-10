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
  if ($self->{TerminalsExpected}) {
    $string .= "\nTerminals expected:\n" . join(', ', @{$self->{TerminalsExpected}}) . "\n";
  }
  if ($self->{Data}) {
    $string .= "\nData:\n" . $self->{Data} . "\n";
  }
  return $string;
};

# Other exception classes:

@MarpaX::Languages::XML::Exception::NotRecognized::ISA = ('MarpaX::Languages::XML::Exception');
@MarpaX::Languages::XML::Exception::NotSupported::ISA = ('MarpaX::Languages::XML::Exception');
@MarpaX::Languages::XML::Exception::Parse::ISA = ('MarpaX::Languages::XML::Exception');

1;
