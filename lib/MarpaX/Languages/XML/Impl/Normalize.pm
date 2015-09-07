package MarpaX::Languages::XML::Impl::Normalize;
use MarpaX::Languages::XML::Role::Normalize;
use Moo;
use MooX::late;
use MooX::Role::Logger;
use Types::Standard qw/InstanceOf Str Int/;
use Try::Tiny;

# ABSTRACT: MarpaX::Languages::XML::Role::Normalize implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is an implementation of MarpaX::Languages::XML::Role::Normalize. It it is helper class containing only class methods.

=cut

sub normalize_inplace {
  my ($self, undef, $eof) = @_;
  # Buffer is in $_[1]

  #
  # If last character is a \x{D} this is undecidable unless eof flag
  #
  if (substr($_[1], -1, 1) eq "\x{D}") {
    if (! $eof) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
        $self->_logger->tracef('[Normalize] Last character in buffer is \\x{D} and requires another read');
      }
      return 0;
    }
  }
  #
  # Do normalization
  #
  $_[1] =~ s/\x{D}\x{A}/\x{A}/g;
  $_[1] =~ s/\x{D}/\x{A}/g;

  return length($_[1]);
}
with 'MooX::Role::Logger';
with 'MarpaX::Languages::XML::Role::Normalize';

1;
