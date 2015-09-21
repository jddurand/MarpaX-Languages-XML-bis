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

    # my $g1_subgrammar = $_[0]->[Marpa::R2::Internal::Scanless::G::THICK_G1_GRAMMAR];
    # my $g1_tracer  = $g1_subgrammar->tracer();
    # return $g1_tracer->symbol_by_name_hash;

    return $_[0]->[Marpa::R2::Internal::Scanless::G::THICK_G1_GRAMMAR]->tracer()->symbol_by_name_hash;
  }
}

package Marpa::R2::Scanless::R;
{
  no warnings 'redefine';

  sub lexeme_alternative_by_symbol_id {
    my $result = $_[0]->[Marpa::R2::Internal::Scanless::R::C]->g1_alternative( $_[1], @_[2..$#_] );
    return 1 if ($result == $Marpa::R2::Error::NONE);

    # The last two are perhaps unnecessary or arguable,
    # but they preserve compatibility with Marpa::XS
    return
        if $result == $Marpa::R2::Error::UNEXPECTED_TOKEN_ID
            || $result == $Marpa::R2::Error::NO_TOKEN_EXPECTED_HERE
            || $result == $Marpa::R2::Error::INACCESSIBLE_TOKEN;

    Marpa::R2::exception( qq{Problem reading symbol id "$symbol_id": },
        ( scalar $_[0]->[Marpa::R2::Internal::Scanless::R::GRAMMAR]->[Marpa::R2::Internal::Scanless::G::THICK_G1_GRAMMAR]->error() ) );
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

#
# Events is used so many times
#
package Marpa::R2::Scanless::R;
{
  no warnings 'redefine';

  sub Marpa::R2::Scanless::R::events {
    return $_[0]->[Marpa::R2::Internal::Scanless::R::EVENTS];
  }

  sub Marpa::R2::Scanless::R::lexeme_complete {
    # my ( $slr, $start, $length ) = @_;
    $_[0]->[Marpa::R2::Internal::Scanless::R::EVENTS] = [];
    $_[0]->[Marpa::R2::Internal::Scanless::R::C]->g1_lexeme_complete( $_[1], $_[2] );
    Marpa::R2::Internal::Scanless::convert_libmarpa_events($_[0]);
    #
    # Never happens for me: I rely entirely on predicted lexemes
    #
    # die q{} . $thin_slr->g1()->error() if $return_value == 0;
    #
    # Return value is not important in my case
    #
    return;
  }

}

#
# For a fast recognizer creation, c.f. https://github.com/jeffreykegler/Marpa--R2/pull/256
#
package Marpa::R2::Scanless::R;
{
  no warnings 'redefine';

  sub Marpa::R2::Scanless::R::registrations {
    return $_[0]->[Marpa::R2::Internal::Scanless::R::THICK_G1_RECCE]->registrations(@_[1..$#_]);
  }

  sub Marpa::R2::Recognizer::registrations {
    if ($#_ > 0) {
      #if (! defined($_[1]) ||
      #    ref($_[1]) ne 'HASH' ||
      #    grep {! exists($_[1]->{$_})} qw/
      #                                     NULL_VALUES
      #                                     REGISTRATIONS
      #                                     CLOSURE_BY_SYMBOL_ID
      #                                     CLOSURE_BY_RULE_ID
      #                                     RESOLVE_PACKAGE
      #                                     RESOLVE_PACKAGE_SOURCE
      #                                     PER_PARSE_CONSTRUCTOR
      #                                   /) {
      #  Marpa::R2::exception(
      #                       "Attempt to reuse registrations failed:\n",
      #                       "  Registration data is not a hash containing all necessary keys:\n",
      #                       "  Got : " . ((ref($_[1]) eq 'HASH') ? join(', ', sort keys %{$_[1]}) : '') . "\n",
      #                       "  Want: CLOSURE_BY_RULE_ID, CLOSURE_BY_SYMBOL_ID, NULL_VALUES, PER_PARSE_CONSTRUCTOR, REGISTRATIONS, RESOLVE_PACKAGE, RESOLVE_PACKAGE_SOURCE\n"
      #                      );
      #}
      $_[0]->[Marpa::R2::Internal::Recognizer::NULL_VALUES]            = $_[1]->{NULL_VALUES};
      $_[0]->[Marpa::R2::Internal::Recognizer::REGISTRATIONS]          = $_[1]->{REGISTRATIONS};
      $_[0]->[Marpa::R2::Internal::Recognizer::CLOSURE_BY_SYMBOL_ID]   = $_[1]->{CLOSURE_BY_SYMBOL_ID};
      $_[0]->[Marpa::R2::Internal::Recognizer::CLOSURE_BY_RULE_ID]     = $_[1]->{CLOSURE_BY_RULE_ID};
      $_[0]->[Marpa::R2::Internal::Recognizer::RESOLVE_PACKAGE]        = $_[1]->{RESOLVE_PACKAGE};
      $_[0]->[Marpa::R2::Internal::Recognizer::RESOLVE_PACKAGE_SOURCE] = $_[1]->{RESOLVE_PACKAGE_SOURCE};
      $_[0]->[Marpa::R2::Internal::Recognizer::PER_PARSE_CONSTRUCTOR]  = $_[1]->{PER_PARSE_CONSTRUCTOR};
    }
    return {
            NULL_VALUES            => $_[0]->[Marpa::R2::Internal::Recognizer::NULL_VALUES],
            REGISTRATIONS          => $_[0]->[Marpa::R2::Internal::Recognizer::REGISTRATIONS],
            CLOSURE_BY_SYMBOL_ID   => $_[0]->[Marpa::R2::Internal::Recognizer::CLOSURE_BY_SYMBOL_ID],
            CLOSURE_BY_RULE_ID     => $_[0]->[Marpa::R2::Internal::Recognizer::CLOSURE_BY_RULE_ID],
            RESOLVE_PACKAGE        => $_[0]->[Marpa::R2::Internal::Recognizer::RESOLVE_PACKAGE],
            RESOLVE_PACKAGE_SOURCE => $_[0]->[Marpa::R2::Internal::Recognizer::RESOLVE_PACKAGE_SOURCE],
            PER_PARSE_CONSTRUCTOR  => $_[0]->[Marpa::R2::Internal::Recognizer::PER_PARSE_CONSTRUCTOR]
           };
  }
}

1;
