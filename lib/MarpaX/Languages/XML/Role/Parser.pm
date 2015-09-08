package MarpaX::Languages::XML::Role::Parser;
use Moo::Role;

# ABSTRACT: Parser role for MarpaX::Languages::XML

# VERSION

# AUTHORITY

requires 'parse';

requires 'start_document';
requires 'end_document';

requires 'start_element';
requires 'end_element';

1;
