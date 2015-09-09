package MarpaX::Languages::XML::Impl::PEReference;
use MarpaX::Languages::XML::Role::PEReference;
use Moo;
use MooX::late;
use MooX::Role::Logger;
use MooX::HandlesVia;
use Types::Standard -all;

# ABSTRACT: Character Reference implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is an implementation of MarpaX::Languages::XML::Role::PEReference.

=cut

has _ref => (
                 is => 'rw',
                 isa => HashRef[Str],
                 default => sub { {} },
                 handles_via => 'Hash',
                 handles => {
                             _exists_ref => 'exists',
                             _get_ref => 'get',
                             _set_ref => 'set',
                            }
                );

sub exists {
  my ($self, $key) = @_;

  my $rc = $self->_exists_ref($key);
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('PEReference %s exists ? %s', $key, $rc ? 'yes' : 'no');
  }
  return $rc;
}

sub set {
  my ($self, $key, $value) = @_;

  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('PEReference %s <- %s', $key, $value);
  }
  return $self->_set_ref($key, $value);
}

sub get {
  my ($self, $key) = @_;

  my $rc = $self->_get_ref($key);
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('PEReference %s -> %s', $key, $rc);
  }
  return $rc;
}


with 'MooX::Role::Logger';
with 'MarpaX::Languages::XML::Role::PEReference';

1;