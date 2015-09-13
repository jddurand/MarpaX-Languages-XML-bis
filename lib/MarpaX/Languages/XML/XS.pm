package MarpaX::Languages::XML;
require DynaLoader;
@ISA = qw/DynaLoader/;
#
# All out bootstraps are in the XML object library
#
bootstrap MarpaX::Languages::XML;

package MarpaX::Languages::XML::XS;
require Exporter;
@EXPORT = qw/is_XML_S/;

# my $length = is_XML10_S(" \x{D}\x{2020}", 0);
# print "==> $length\n";

1;
