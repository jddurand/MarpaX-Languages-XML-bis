package MarpaX::Languages::XML;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Impl::Parser;
use MarpaX::Languages::XML::Exception;
use Moo;
use MooX::late;

# ABSTRACT: XML parsing with Marpa

# VERSION

# AUTHORITY

sub ast {
  my ($self, %hash) = @_;

  return MarpaX::Languages::XML::Impl::Parser->new->parse(%hash);

}

1;
