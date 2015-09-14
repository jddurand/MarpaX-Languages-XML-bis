package MarpaX::Languages::XML::Type::Callback;
use Type::Library
  -base,
  -declare => qw/Callback/;
use Type::Utils -all;
use Types::Standard -all;
use Types::Common::Numeric -all;

# VERSION

# AUTHORITY

declare Callback,
  as Dict[
          name => Str,
          code => CodeRef
         ];

1;
