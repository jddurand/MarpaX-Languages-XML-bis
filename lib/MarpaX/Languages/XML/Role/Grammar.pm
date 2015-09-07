package MarpaX::Languages::XML::Role::Grammar;
use Moo::Role;

# ABSTRACT: Grammar role for MarpaX::Languages::XML

# VERSION

# AUTHORITY

requires 'scanless';
requires 'lexeme_regexp';
requires 'lexeme_exclusion';
requires 'get_grammar_event';
requires 'normalize_attvalue';

1;
