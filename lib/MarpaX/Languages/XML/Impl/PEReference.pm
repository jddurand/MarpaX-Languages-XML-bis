package MarpaX::Languages::XML::Impl::PEReference;
use MarpaX::Languages::XML::Role::PEReference;
use Moo;
use MooX::late;
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
                             exists => 'exists',
                             get => 'get',
                             set => 'set',
                            }
                );

with 'MarpaX::Languages::XML::Role::PEReference';

1;
