package MarpaX::Languages::XML::Type::GrammarDescription;
use Type::Library
  -base,
  -declare => qw/GrammarDescription/;
use Type::Utils -all;
use Types::Standard -types;
use Types::Common::Numeric qw/PositiveOrZeroInt/;

declare GrammarDescription,
  as Dict[
          lexeme        => Bool,
          fixed_length  => Bool,
          type          => Str,
          min_chars     => PositiveOrZeroInt,
          symbol_name   => Str,
          lexeme_name   => Str,
         ];

1;
