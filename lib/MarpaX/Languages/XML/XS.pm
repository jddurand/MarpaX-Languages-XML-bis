package MarpaX::Languages::XML;
require DynaLoader;
@ISA = qw/DynaLoader/;

# VERSION

# AUTHORITY

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
$length = is_XML10_CHARDATAMANY("0A124]]]>345\x{2020}env ", 0);
print "==> is_XML10_CHARDATAMANY: $length\n";
$length = is_XML10_COMMENTCHARMANY("0-A--124]]]>345\x{2020}env ", 0);
print "==> is_XML10_COMMENTCHARMANY: $length\n";
$length = is_XML10_PITARGET("xml2", 0);
print "==> is_XML10_PITARGET: $length\n";
$length = is_XML10_CDATAMANY("x]]>0", 0);
print "==> is_XML10_CDATAMANY: $length\n";
$length = is_XML10_PICHARDATAMANY("x?>>0", 0);
print "==> is_XML10_PICHARDATAMANY: $length\n";
$length = is_XML10_IGNOREMANY("x<![?>>0", 0);
print "==> is_XML10_IGNOREMANY: $length\n";
$length = is_XML10_IGNOREMANY("ff]]>x<![?>>0", 0);
print "==> is_XML10_IGNOREMANY: $length\n";
$length = is_XML10_DIGITMANY("ff]]>x<![?>>0", 0);
print "==> is_XML10_DIGITMANY: $length\n";
$length = is_XML10_DIGITMANY("12345678901ff]]>x<![?>>0", 0);
print "==> is_XML10_DIGITMANY: $length\n";
$length = is_XML10_ALPHAMANY("ff]]>x<![?>>0", 0);
print "==> is_XML10_ALPHAMANY: $length\n";
$length = is_XML10_ALPHAMANY("12345678901ff]]>x<![?>>0", 0);
print "==> is_XML10_ALPHAMANY: $length\n";
$length = is_XML10_ENCNAME("ISO-8859-1 12345678901ff]]>x<![?>>0", 0);
print "==> is_XML10_ENCNAME: $length\n";
$length = is_XML10_NCNAME("xmlns:env:", 0);
print "==> is_XML10_NCNAME: $length\n";
$length = is_XML10_NCNAME("xmlns:env", 0);
print "==> is_XML10_NCNAME: $length\n";
$length = is_XML10_NCNAME("xmlns::env", 0);
print "==> is_XML10_NCNAME: $length\n";
$length = is_XML10_NCNAME("xmlns", 0);
print "==> is_XML10_NCNAME: $length\n";

1;
