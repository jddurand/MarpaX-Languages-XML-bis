package MarpaX::Languages::XML::Type::G1Description;
use Type::Library
  -base,
  -declare => qw/G1Description/;
use Type::Utils -all;
use Types::Standard -types;
use Types::Common::Numeric qw/PositiveOrZeroInt/;

declare G1Description,
  as Dict[
          fixed_length  => Bool,
          type          => Str,
          min_chars     => PositiveOrZeroInt,
          symbol_name   => Str,
          lexeme_name   => Str,
         ];

1;
