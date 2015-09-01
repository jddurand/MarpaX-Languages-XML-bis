package MarpaX::Languages::XML::Role::IO;
use Moo::Role;

# ABSTRACT: I/O role for MarpaX::Languages::XML

# VERSION

# AUTHORITY

requires 'open';
requires 'block_size';
requires 'block_size_value';
requires 'binary';
requires 'read';
requires 'pos';
requires 'tell';
requires 'seek';
requires 'clear';
requires 'length';
requires 'encoding';
requires 'buffer';
requires 'close';

1;
