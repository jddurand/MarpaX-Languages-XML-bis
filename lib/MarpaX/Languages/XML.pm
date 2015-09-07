package MarpaX::Languages::XML;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Impl::Parser;
use MarpaX::Languages::XML::Exception;
use Moo;
use MooX::late;

# ABSTRACT: XML parsing with Marpa

# VERSION

# AUTHORITY

sub parse {
  my $class = shift;

  return MarpaX::Languages::XML::Impl::Parser->new(@_)->parse();
}

1;
