package MarpaX::Languages::XML::Type::XmlSupport;
use Type::Library
  -base,
  -declare => qw/XmlSupport/;
use Type::Utils -all;
use Types::Standard -types;

# VERSION

# AUTHORITY

declare XmlSupport,
  as Enum[qw/xml xmlns xml_or_xmlns/];

1;
