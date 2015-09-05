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
    $string .= "\nTerminals expected: " . join(', ', @{$self->{TerminalsExpected}});
  }
  return $string;
};

1;
