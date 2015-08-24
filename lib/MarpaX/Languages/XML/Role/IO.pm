package MarpaX::Languages::XML::Role::IO;
use Moo::Role;

# ABSTRACT: I/O role for MarpaX::Languages::XML

# VERSION

# AUTHORITY

requires 'block_size';
requires 'read';
requires 'pos';
requires 'clear';
requires 'length';
requires 'encoding';
requires 'buffer';

1;
