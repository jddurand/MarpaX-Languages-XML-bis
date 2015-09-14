package MarpaX::Languages::XML::Type::XmlVersion;
use Type::Library
  -base,
  -declare => qw/XmlVersion/;
use Type::Utils -all;
use Types::Standard -types;

# VERSION

# AUTHORITY

declare XmlVersion,
  as Enum[qw/1.0 1.1/];

1;
