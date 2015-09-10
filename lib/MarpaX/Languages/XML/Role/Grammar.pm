package MarpaX::Languages::XML::Role::Grammar;
use Moo::Role;

# ABSTRACT: Grammar role for MarpaX::Languages::XML

# VERSION

# AUTHORITY

requires 'xml_scanless';
requires 'xmlns_scanless';
requires 'elements_grammar_event';
requires 'elements_lexeme_regexp';
requires 'elements_lexeme_exclusion';
requires 'eol';
requires 'eol_decl';
requires 'attvalue';

1;
