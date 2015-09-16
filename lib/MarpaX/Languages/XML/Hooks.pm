package MarpaX::Languages::XML::Hooks;
#
# Hooks to make Marpa::R2 faster by using symbol IDs directly
#
package Marpa::R2::Thin::Trace;
{
  no warnings 'redefine';

  sub symbol_by_name_hash {
    # my ($self) = @_;
    return $_[0]->{symbol_by_name};
  }
}

package Marpa::R2::Scanless::G;
{
  no warnings 'redefine';

  sub symbol_by_name_hash {
    # my ( $slg ) = @_;

    my $g1_subgrammar = $_[0]->[Marpa::R2::Internal::Scanless::G::THICK_G1_GRAMMAR];
    my $g1_tracer  = $g1_subgrammar->tracer();
    return $g1_tracer->symbol_by_name_hash;
  }
}

package Marpa::R2::Scanless::R;
{
  no warnings 'redefine';

  sub lexeme_alternative_by_symbol_id {
    my ( $slr, $symbol_id, @value ) = @_;
    my $thin_slr = $slr->[Marpa::R2::Internal::Scanless::R::C];
    #
    # I know what I am doing
    #
    #Marpa::R2::exception(
    #    "slr->alternative(): symbol id is undefined\n",
    #    "    The symbol id cannot be undefined\n"
    #) if not defined $symbol_id;

    my $slg        = $slr->[Marpa::R2::Internal::Scanless::R::GRAMMAR];
    my $g1_grammar = $slg->[Marpa::R2::Internal::Scanless::G::THICK_G1_GRAMMAR];

    my $result = $thin_slr->g1_alternative( $symbol_id, @value );
    return 1 if $result == $Marpa::R2::Error::NONE;

    # The last two are perhaps unnecessary or arguable,
    # but they preserve compatibility with Marpa::XS
    return
        if $result == $Marpa::R2::Error::UNEXPECTED_TOKEN_ID
            || $result == $Marpa::R2::Error::NO_TOKEN_EXPECTED_HERE
            || $result == $Marpa::R2::Error::INACCESSIBLE_TOKEN;

    Marpa::R2::exception( qq{Problem reading symbol id "$symbol_id": },
        ( scalar $g1_grammar->error() ) );
  }

  sub terminals_expected_to_symbol_ids {
    # my ($self) = @_;
    return $_[0]->[Marpa::R2::Internal::Scanless::R::THICK_G1_RECCE]->terminals_expected_to_symbol_ids();
  }
}

package Marpa::R2::Recognizer;
{
  no warnings 'redefine';

  sub terminals_expected_to_symbol_ids {
    # my ($recce) = @_;
    return $_[0]->[Marpa::R2::Internal::Recognizer::C]->terminals_expected();
  }
}

1;
