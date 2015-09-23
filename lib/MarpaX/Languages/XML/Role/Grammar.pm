package MarpaX::Languages::XML::Role::Grammar;
use Moo::Role;
use MooX::late;

# ABSTRACT: Grammar role for MarpaX::Languages::XML

# VERSION

# AUTHORITY

requires 'xml_scanless';
requires 'xmlns_scanless';
requires 'elements_lexeme_exclusion_by_symbol_ids';
requires 'elements_lexeme_match_by_symbol_ids';
requires 'spec';

requires 'eol_impl';
requires 'eol_decl_impl';
requires 'start_document_impl';
requires 'attvalue_impl';
requires 'nsattname_impl';
requires 'qname_impl';
requires 'end_document_impl';

requires 'namespace_validate';

1;
