package MarpaX::Languages::XML::Impl::EntityRef;
use MarpaX::Languages::XML::Role::EntityRef;
use Moo;
use MooX::late;
use MooX::Role::Logger;
use MooX::HandlesVia;
use Types::Standard -all;

# ABSTRACT: Character Reference implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is an implementation of MarpaX::Languages::XML::Role::EntityRef.

=cut

has _ref => (
                 is => 'rw',
                 isa => HashRef[Str],
                 default => sub { { amp => "x\{26}", lt => "\x{3C}", gt => "\x{3E}", apos => "\x{27}", quot => "\x{22}" } },
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
    $self->_logger->tracef('EntityRef %s exists ? %s', $key, $rc ? 'yes' : 'no');
  }
  return $rc;
}

sub set {
  my ($self, $key, $value) = @_;

  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('EntityRef %s <- %s', $key, $value);
  }
  return $self->_set_ref($key, $value);
}

sub get {
  my ($self, $key) = @_;

  my $rc = $self->_get_ref($key);
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('EntityRef %s -> %s', $key, $rc);
  }
  return $rc;
}


with 'MooX::Role::Logger';
with 'MarpaX::Languages::XML::Role::EntityRef';

1;
