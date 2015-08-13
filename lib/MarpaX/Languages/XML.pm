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
  my ($self, $hash_ref) = @_;

  $hash_ref //= {};

  if (ref($hash_ref) ne 'HASH') {
    MarpaX::Languages::XML::Exception->throw('First parameter must be a ref to HASH');
  }

  return MarpaX::Languages::XML::Impl::Parser->new->parse($hash_ref);

}

1;
