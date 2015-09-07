package MarpaX::Languages::XML::Type::GrammarEvents;
use Type::Library
  -base,
  -declare => qw/GrammarEvents/;
use Type::Utils -all;
use Types::Standard -types;
use Types::Common::Numeric qw/PositiveOrZeroInt/;

declare GrammarEvents,
  as Dict[
          lexeme        => Bool,
          fixed_length  => Bool,
          type          => Str,
          min_chars     => PositiveOrZeroInt,
          symbol_name   => Str,
          lexeme_name   => Str,
         ];

1;
