package MarpaX::Languages::XML::Impl::CharRef;
use MarpaX::Languages::XML::Role::CharRef;
use Moo;
use MooX::late;
use MooX::Role::Logger;
use MooX::HandlesVia;
use Types::Standard -all;

# ABSTRACT: Character Reference implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is an implementation of MarpaX::Languages::XML::Role::CharRef.

=cut

has _charref => (
                 is => 'rw',
                 isa => HashRef[Str],
                 default => sub { {} },
                 handles_via => 'Hash',
                 handles => {
                             _exists_charref => 'exists',
                             _get_charref => 'get',
                             _set_charref => 'set',
                            }
                );

sub exists {
  my ($self, $key) = @_;

  my $rc = $self->_exists_charref($key);
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('CharRef %s exists ? %s', $key, $rc ? 'yes' : 'no');
  }
  return $rc;
}

sub set {
  my ($self, $key, $value) = @_;

  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('CharRef %s <- %s', $key, $value);
  }
  return $self->_set_charref($key, $value);
}

sub get {
  my ($self, $key) = @_;

  my $rc = $self->_get_charref($key);
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('CharRef %s -> %s', $key, $rc);
  }
  return $rc;
}


with 'MooX::Role::Logger';
with 'MarpaX::Languages::XML::Role::CharRef';

1;
