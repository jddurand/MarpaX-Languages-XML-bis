package MarpaX::Languages::XML::Exception;
use XML::SAX::Exception;
use Moo;

# ABSTRACT: XML::SAX::Exception extension with Marpa progress report

# VERSION

# AUTHORITY

extends 'XML::SAX::Exception';

around stringify => sub {
  my ($orig, $self) = (shift, shift);

  my $string = $self->$orig(@_);
  if ($self->{Progress}) {
    $string .= "\nProgress:\n" . $self->{Progress} . "\n";
  }
  return $string;
};

1;
