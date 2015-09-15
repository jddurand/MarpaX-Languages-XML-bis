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

my $string;
my $length = is_XML10_S($string = " \x{D}\x{2020}", 0);
print "==> is_XML10_S(\"$string\"): $length\n\n";
$length = is_XML10_NAME($string = "A12345\x{2020}env ", 0);
print "==> is_XML10_NAME(\"$string\"): $length\n\n";
$length = is_XML10_CHARDATAMANY($string = "0A124]]]>345\x{2020}env ", 0);
print "==> is_XML10_CHARDATAMANY(\"$string\"): $length\n\n";
$length = is_XML10_COMMENTCHARMANY($string = "0-A--124]]]>345\x{2020}env ", 0);
print "==> is_XML10_COMMENTCHARMANY(\"$string\"): $length\n\n";

$length = is_XML10_CDATAMANY($string = "x]]>0", 0);
print "==> is_XML10_CDATAMANY(\"$string\"): $length\n\n";
$length = is_XML10_PICHARDATAMANY($string = "x?>>0", 0);
print "==> is_XML10_PICHARDATAMANY(\"$string\"): $length\n\n";
$length = is_XML10_IGNOREMANY($string = "x<![?>>0", 0);
print "==> is_XML10_IGNOREMANY(\"$string\"): $length\n\n";
$length = is_XML10_IGNOREMANY($string = "ff]]>x<![?>>0", 0);
print "==> is_XML10_IGNOREMANY(\"$string\"): $length\n\n";
$length = is_XML10_DIGITMANY($string = "ff]]>x<![?>>0", 0);
print "==> is_XML10_DIGITMANY(\"$string\"): $length\n\n";
$length = is_XML10_DIGITMANY($string = "12345678901ff]]>x<![?>>0", 0);
print "==> is_XML10_DIGITMANY(\"$string\"): $length\n\n";
$length = is_XML10_ALPHAMANY($string = "ff]]>x<![?>>0", 0);
print "==> is_XML10_ALPHAMANY(\"$string\"): $length\n\n";
$length = is_XML10_ALPHAMANY($string = "12345678901ff]]>x<![?>>0", 0);
print "==> is_XML10_ALPHAMANY(\"$string\"): $length\n\n";
$length = is_XML10_ENCNAME($string = "ISO-8859-1 12345678901ff]]>x<![?>>0", 0);
print "==> is_XML10_ENCNAME(\"$string\"): $length\n\n";

$length = is_XML10_NCNAME($string = "xmlns:env:", 0);
print "==> is_XML10_NCNAME(\"$string\"): $length\n\n";
$length = is_XML10_NCNAME($string = "xmlns:env", 0);
print "==> is_XML10_NCNAME(\"$string\"): $length\n\n";
$length = is_XML10_NCNAME($string = "xmlns::env", 0);
print "==> is_XML10_NCNAME(\"$string\"): $length\n\n";
$length = is_XML10_NCNAME($string = "xmlns", 0);
print "==> is_XML10_NCNAME(\"$string\"): $length\n\n";

$length = is_XML10_PUBIDCHARDQUOTEMANY($string = "a-zA-Z0-9-'()+,./:=?;!*#\@\$_%\x{20}\x{D}\x{A}\x{1234}", 0);
print "==> is_XML10_PUBIDCHARDQUOTEMANY(\"$string\"): $length\n\n";

$length = is_XML10_PUBIDCHARSQUOTEMANY($string = "a-zA-Z0-9-()+,./:=?;!*#\@\$_%\x{20}\x{D}\x{A}\x{1234}", 0);
print "==> is_XML10_PUBIDCHARSQUOTEMANY(\"$string\"): $length\n\n";

$length = is_XML10_SPACE($string = "\x{20}" x 20, 0);
print "==> is_XML10_SPACE(\"$string\"): $length\n\n";

$length = is_XML10_PITARGET($string = "xml2", 0);
print "==> is_XML10_PITARGET(\"$string\"): $length\n\n";
$length = is_XML10_PITARGET($string = "xml", 0);
print "==> is_XML10_PITARGET(\"$string\"): $length\n\n";
$length = is_XML10_PITARGET($string = "XmL", 0);
print "==> is_XML10_PITARGET(\"$string\"): $length\n\n";

$length = is_XML10_DQUOTE($string = "\"", 0);
print "==> is_XML10_DQUOTE(\"$string\"): $length\n\n";
$length = is_XML10_DQUOTE($string = "\"\"", 0);
print "==> is_XML10_DQUOTE(\"$string\"): $length\n\n";
$length = is_XML10_DQUOTE($string = "0\"\"", 0);
print "==> is_XML10_DQUOTE(\"$string\"): $length\n\n";

$length = is_XML10_SQUOTE($string = "'", 0);
print "==> is_XML10_SQUOTE(\"$string\"): $length\n\n";
$length = is_XML10_SQUOTE($string = "''", 0);
print "==> is_XML10_SQUOTE(\"$string\"): $length\n\n";
$length = is_XML10_SQUOTE($string = "0''", 0);
print "==> is_XML10_SQUOTE(\"$string\"): $length\n\n";

$length = is_XML10_COMMENT_START($string = "<!--", 0);
print "==> is_XML10_COMMENT_START(\"$string\"): $length\n\n";
$length = is_XML10_COMMENT_START($string = "0<!--", 0);
print "==> is_XML10_COMMENT_START(\"$string\"): $length\n\n";

$length = is_XML10_COMMENT_END($string = "-->", 0);
print "==> is_XML10_COMMENT_END(\"$string\"): $length\n\n";
$length = is_XML10_COMMENT_END($string = "0-->", 0);
print "==> is_XML10_COMMENT_END(\"$string\"): $length\n\n";

1;
