package MarpaX::Languages::XML::Role::Grammar;
use Moo::Role;
use MooX::late;

# ABSTRACT: Grammar role for MarpaX::Languages::XML

# VERSION

# AUTHORITY

requires 'xml_scanless';
requires 'xmlns_scanless';
requires 'elements_grammar_event';
requires 'elements_lexeme_match';
requires 'elements_lexeme_exclusion';
requires 'elements_lexeme_match_by_symbol_ids';
requires 'spec';

requires 'eol_impl';
requires 'eol_decl_impl';
requires 'attvalue_impl';
requires 'nsattname_impl';

requires 'namespace_validate';

1;
