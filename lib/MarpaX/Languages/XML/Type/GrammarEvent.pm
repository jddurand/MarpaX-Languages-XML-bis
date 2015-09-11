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
          predicted_length => Optional[Int],               # Setted to 0 if undef at scanless creation time
          symbol_name      => Str,
          type             => EventType,
          is_prediction    => Optional[Bool],              # Overwriten at scanless creation time
          lexeme           => Optional[Str],
          priority         => Optional[Int],               # Setted to 0 if undef at scanless creation time
         ];

1;
