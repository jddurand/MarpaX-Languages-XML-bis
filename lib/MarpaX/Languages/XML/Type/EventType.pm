package MarpaX::Languages::XML::Type::EventType;
use Type::Library
  -base,
  -declare => qw/EventType/;
use Type::Utils -all;
use Types::Standard -types;

# VERSION

# AUTHORITY

declare EventType,
  as Enum[qw/predicted nulled completed/];

1;
