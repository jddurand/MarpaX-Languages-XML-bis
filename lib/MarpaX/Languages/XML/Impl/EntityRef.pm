package MarpaX::Languages::XML::Impl::EntityRef;
use MarpaX::Languages::XML::Role::EntityRef;
use Moo;
use MooX::late;
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
                             exists => 'exists',
                             get => 'get',
                             set => 'set',
                            }
                );

with 'MarpaX::Languages::XML::Role::EntityRef';

1;
