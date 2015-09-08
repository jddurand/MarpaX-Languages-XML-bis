package MarpaX::Languages::XML::Type::CharacterAndEntityReferences;
use Type::Library
  -base,
  -declare => qw/CharRef EntityRef PEReference Reference/;
use Type::Utils -all;
use Types::Standard -types;

declare CharRef, as Str;
declare EntityRef, as Str;
declare PEReference, as Str;
declare Reference, as EntityRef|CharRef;

1;
