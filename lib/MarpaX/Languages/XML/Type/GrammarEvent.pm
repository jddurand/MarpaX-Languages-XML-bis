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
          fixed_length   => Bool,
          min_chars      => PositiveOrZeroInt,
          decision_chars => Optional[PositiveOrZeroInt], # Fixed to min_chars at scanless creation if undef
          symbol_name    => Str,
          type           => EventType,
          is_prediction  => Optional[Bool],              # Overwriten at scanless creation time
          lexeme         => Optional[Str],
          priority       => Optional[Int],               # Fixed to 0 at scanless creation time if undef and lexeme
         ];

1;
