package MarpaX::Languages::XML;
require DynaLoader;
@ISA = qw/DynaLoader/;
#
# All out bootstraps are in the XML object library
#
bootstrap MarpaX::Languages::XML;

package MarpaX::Languages::XML::XS;
require Exporter;
@EXPORT = qw/is_XML_S is_XML10_NAME/;

my $length = is_XML10_S(" \x{D}\x{2020}", 0);
print "==> is_XML10_S: $length\n";
$length = is_XML10_NAME("A12345\x{2020}env ", 0);
print "==> is_XML10_NAME: $length\n";

1;
