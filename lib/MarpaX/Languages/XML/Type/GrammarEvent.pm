package MarpaX::Languages::XML::Type::GrammarEvent;
use Type::Library
  -base,
  -declare => qw/GrammarEvent/;
use Type::Utils -all;
use Types::Standard -all;
use Types::Common::Numeric -all;
use MarpaX::Languages::XML::Type::EventType -all;

declare GrammarEvent,
  as Dict[
          fixed_length  => Optional[Bool],
          min_chars     => Optional[PositiveOrZeroInt],
          symbol_name   => Str,
          type          => EventType,
          lexeme        => Optional[Str],
         ];

1;
