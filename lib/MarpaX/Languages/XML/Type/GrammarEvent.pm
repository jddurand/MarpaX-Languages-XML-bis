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
          fixed_length  => Bool,
          min_chars     => PositiveOrZeroInt,
          symbol_name   => Str,
          type          => EventType,
          is_prediction => Optional[Bool],            # Overwriten a scanless creation time
          lexeme        => Optional[Str],
         ];

1;
