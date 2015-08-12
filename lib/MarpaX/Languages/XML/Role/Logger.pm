package MarpaX::Languages::XML::Role::Logger;
use Moo::Role;

# ABSTRACT: MooX::Role::Logger role for MarpaX::Languages::XML

# VERSION

# AUTHORITY

sub _build__logger_category {
  return 'MarpaX::Languages::XML';
}

requires 'TIEHANDLE';
requires 'PRINT';
requires 'PRINTF';
requires 'UNTIE';

with 'MooX::Role::Logger';

1;
