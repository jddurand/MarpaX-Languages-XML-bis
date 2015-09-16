package MarpaX::Languages::XML::Type::GrammarEvent;
use Type::Library
  -base,
  -declare => qw/GrammarEvent/;
use Type::Utils -all;
use Types::Standard -all;
use Types::Common::Numeric -all;
use MarpaX::Languages::XML::Type::EventType -all;

# VERSION

# AUTHORITY

declare GrammarEvent,
  as Dict[
          symbol_name      => Str,
          type             => EventType,
          lexeme           => Optional[Str],
         ];

1;
