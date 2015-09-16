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
@EXPORT = qw/
  is_XML10_ANY                           is_XML11_ANY
  is_XML10_ATTLIST_END                   is_XML11_ATTLIST_END
  is_XML10_ATTLIST_START                 is_XML11_ATTLIST_START
  is_XML10_CDATA                         is_XML11_CDATA
  is_XML10_CHARREF_END1                  is_XML11_CHARREF_END1
  is_XML10_CHARREF_END2                  is_XML11_CHARREF_END2
  is_XML10_CHARREF_START1                is_XML11_CHARREF_START1
  is_XML10_CHARREF_START2                is_XML11_CHARREF_START2
  is_XML10_CHOICE_END                    is_XML11_CHOICE_END
  is_XML10_CHOICE_START                  is_XML11_CHOICE_START
  is_XML10_COLON                         is_XML11_COLON
  is_XML10_COMMA                         is_XML11_COMMA
  is_XML10_DOCTYPE_END                   is_XML11_DOCTYPE_END
  is_XML10_DOCTYPE_START                 is_XML11_DOCTYPE_START
  is_XML10_ELEMENTDECL_END               is_XML11_ELEMENTDECL_END
  is_XML10_ELEMENTDECL_START             is_XML11_ELEMENTDECL_START
  is_XML10_ELEMENT_END                   is_XML11_ELEMENT_END
  is_XML10_ELEMENT_START                 is_XML11_ELEMENT_START
  is_XML10_EMPTY                         is_XML11_EMPTY
  is_XML10_EMPTYELEM_END                 is_XML11_EMPTYELEM_END
  is_XML10_ENCODING                      is_XML11_ENCODING
  is_XML10_ENTITIES                      is_XML11_ENTITIES
  is_XML10_ENTITY                        is_XML11_ENTITY
  is_XML10_ENTITYREF_END                 is_XML11_ENTITYREF_END
  is_XML10_ENTITYREF_START               is_XML11_ENTITYREF_START
  is_XML10_ENTITY_END                    is_XML11_ENTITY_END
  is_XML10_ENTITY_START                  is_XML11_ENTITY_START
  is_XML10_ENUMERATION_END               is_XML11_ENUMERATION_END
  is_XML10_ENUMERATION_START             is_XML11_ENUMERATION_START
  is_XML10_ETAG_END                      is_XML11_ETAG_END
  is_XML10_ETAG_START                    is_XML11_ETAG_START
  is_XML10_FIXED                         is_XML11_FIXED
  is_XML10_ID                            is_XML11_ID
  is_XML10_IDREF                         is_XML11_IDREF
  is_XML10_IDREFS                        is_XML11_IDREFS
  is_XML10_IGNORE                        is_XML11_IGNORE
  is_XML10_IGNORESECTCONTENTSUNIT_END    is_XML11_IGNORESECTCONTENTSUNIT_END
  is_XML10_IGNORESECTCONTENTSUNIT_START  is_XML11_IGNORESECTCONTENTSUNIT_START
  is_XML10_IGNORESECT_END                is_XML11_IGNORESECT_END
  is_XML10_IGNORESECT_START              is_XML11_IGNORESECT_START
  is_XML10_IMPLIED                       is_XML11_IMPLIED
  is_XML10_INCLUDE                       is_XML11_INCLUDE
  is_XML10_INCLUDESECT_END               is_XML11_INCLUDESECT_END
  is_XML10_INCLUDESECT_START             is_XML11_INCLUDESECT_START
  is_XML10_LBRACKET                      is_XML11_LBRACKET
  is_XML10_MIXED_END1                    is_XML11_MIXED_END1
  is_XML10_MIXED_END2                    is_XML11_MIXED_END2
  is_XML10_MIXED_START                   is_XML11_MIXED_START
  is_XML10_NDATA                         is_XML11_NDATA
  is_XML10_NMTOKEN                       is_XML11_NMTOKEN
  is_XML10_NMTOKENS                      is_XML11_NMTOKENS
  is_XML10_NO                            is_XML11_NO
  is_XML10_NOTATION                      is_XML11_NOTATION
  is_XML10_NOTATIONDECL_END              is_XML11_NOTATIONDECL_END
  is_XML10_NOTATIONDECL_START            is_XML11_NOTATIONDECL_START
  is_XML10_NOTATION_END                  is_XML11_NOTATION_END
  is_XML10_NOTATION_START                is_XML11_NOTATION_START
  is_XML10_OR                            is_XML11_OR
  is_XML10_PCDATA                        is_XML11_PCDATA
  is_XML10_PERCENT                       is_XML11_PERCENT
  is_XML10_PEREFERENCE_END               is_XML11_PEREFERENCE_END
  is_XML10_PEREFERENCE_START             is_XML11_PEREFERENCE_START
  is_XML10_PLUS                          is_XML11_PLUS
  is_XML10_PUBLIC                        is_XML11_PUBLIC
  is_XML10_QUESTIONMARK                  is_XML11_QUESTIONMARK
  is_XML10_RBRACKET                      is_XML11_RBRACKET
  is_XML10_REQUIRED                      is_XML11_REQUIRED
  is_XML10_SEQ_END                       is_XML11_SEQ_END
  is_XML10_SEQ_START                     is_XML11_SEQ_START
  is_XML10_STANDALONE                    is_XML11_STANDALONE
  is_XML10_STAR                          is_XML11_STAR
  is_XML10_SYSTEM                        is_XML11_SYSTEM
  is_XML10_TEXTDECL_END                  is_XML11_TEXTDECL_END
  is_XML10_TEXTDECL_START                is_XML11_TEXTDECL_START
  is_XML10_YES                           is_XML11_YES
  is_XML10_ALPHAMANY                     is_XML11_ALPHAMANY
  is_XML10_ATTVALUEINTERIORDQUOTEUNIT    is_XML11_ATTVALUEINTERIORDQUOTEUNIT
  is_XML10_ATTVALUEINTERIORSQUOTEUNIT    is_XML11_ATTVALUEINTERIORSQUOTEUNIT
  is_XML10_CDATAMANY                     is_XML11_CDATAMANY
  is_XML10_CDATA_END                     is_XML11_CDATA_END
  is_XML10_CDATA_START                   is_XML11_CDATA_START
  is_XML10_CHARDATAMANY                  is_XML11_CHARDATAMANY
  is_XML10_COMMENTCHARMANY               is_XML11_COMMENTCHARMANY
  is_XML10_COMMENT_END                   is_XML11_COMMENT_END
  is_XML10_COMMENT_START                 is_XML11_COMMENT_START
  is_XML10_DIGITMANY                     is_XML11_DIGITMANY
  is_XML10_DQUOTE                        is_XML11_DQUOTE
  is_XML10_ENCNAME                       is_XML11_ENCNAME
  is_XML10_ENTITYVALUEINTERIORDQUOTEUNIT is_XML11_ENTITYVALUEINTERIORDQUOTEUNIT
  is_XML10_ENTITYVALUEINTERIORSQUOTEUNIT is_XML11_ENTITYVALUEINTERIORSQUOTEUNIT
  is_XML10_EQUAL                         is_XML11_EQUAL
  is_XML10_IGNOREMANY                    is_XML11_IGNOREMANY
  is_XML10_NAME                          is_XML11_NAME
  is_XML10_NCNAME                        is_XML11_NCNAME
  is_XML10_NMTOKENMANY                   is_XML11_NMTOKENMANY
  is_XML10_NOT_DQUOTEMANY                is_XML11_NOT_DQUOTEMANY
  is_XML10_NOT_SQUOTEMANY                is_XML11_NOT_SQUOTEMANY
  is_XML10_PICHARDATAMANY                is_XML11_PICHARDATAMANY
  is_XML10_PITARGET                      is_XML11_PITARGET
  is_XML10_PI_END                        is_XML11_PI_END
  is_XML10_PI_START                      is_XML11_PI_START
  is_XML10_PUBIDCHARDQUOTEMANY           is_XML11_PUBIDCHARDQUOTEMANY
  is_XML10_PUBIDCHARSQUOTEMANY           is_XML11_PUBIDCHARSQUOTEMANY
  is_XML10_S                             is_XML11_S
  is_XML10_SPACE                         is_XML11_SPACE
  is_XML10_SQUOTE                        is_XML11_SQUOTE
  is_XML10_VERSION                       is_XML11_VERSION
  is_XML10_VERSIONNUM                    is_XML11_VERSIONNUM
  is_XML10_XMLDECL_END                   is_XML11_XMLDECL_END
  is_XML10_XMLDECL_START                 is_XML11_XMLDECL_START
/;

1;

__DATA__
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

$length = is_XML10_PI_START($string = "<?--", 0);
print "==> is_XML10_PI_START(\"$string\"): $length\n\n";
$length = is_XML10_PI_START($string = "0<?--", 0);
print "==> is_XML10_PI_START(\"$string\"): $length\n\n";

$length = is_XML10_PI_END($string = "?>-->", 0);
print "==> is_XML10_PI_END(\"$string\"): $length\n\n";
$length = is_XML10_PI_END($string = "0?>-->", 0);
print "==> is_XML10_PI_END(\"$string\"): $length\n\n";

$length = is_XML10_CDATA_START($string = "![CDATA[", 0);
print "==> is_XML10_CDATA_START(\"$string\"): $length\n\n";
$length = is_XML10_CDATA_START($string = "0![CDATA[", 0);
print "==> is_XML10_CDATA_START(\"$string\"): $length\n\n";

$length = is_XML10_CDATA_END($string = "]]>", 0);
print "==> is_XML10_CDATA_END(\"$string\"): $length\n\n";
$length = is_XML10_CDATA_END($string = "0]]>", 0);
print "==> is_XML10_CDATA_END(\"$string\"): $length\n\n";

$length = is_XML10_XMLDECL_START($string = "<?xml", 0);
print "==> is_XML10_XMLDECL_START(\"$string\"): $length\n\n";
$length = is_XML10_XMLDECL_START($string = "0<?xml", 0);
print "==> is_XML10_XMLDECL_START(\"$string\"): $length\n\n";

$length = is_XML10_XMLDECL_END($string = "?>", 0);
print "==> is_XML10_XMLDECL_END(\"$string\"): $length\n\n";
$length = is_XML10_XMLDECL_END($string = "0?>", 0);
print "==> is_XML10_XMLDECL_END(\"$string\"): $length\n\n";

$length = is_XML10_VERSION($string = "version", 0);
print "==> is_XML10_VERSION(\"$string\"): $length\n\n";
$length = is_XML10_VERSION($string = "0version", 0);
print "==> is_XML10_VERSION(\"$string\"): $length\n\n";

$length = is_XML10_EQUAL($string = "=", 0);
print "==> is_XML10_EQUAL(\"$string\"): $length\n\n";
$length = is_XML10_EQUAL($string = "0=", 0);
print "==> is_XML10_EQUAL(\"$string\"): $length\n\n";

$length = is_XML10_VERSIONNUM($string = "1.0", 0);
print "==> is_XML10_VERSIONNUM(\"$string\"): $length\n\n";
$length = is_XML10_VERSIONNUM($string = "1.1", 0);
print "==> is_XML10_VERSIONNUM(\"$string\"): $length\n\n";

$length = is_XML10_VERSIONNUM($string = "1.1", 0);
print "==> is_XML10_VERSIONNUM(\"$string\"): $length\n\n";
$length = is_XML10_VERSIONNUM($string = "1.0", 0);
print "==> is_XML10_VERSIONNUM(\"$string\"): $length\n\n";

$length = is_XML10_PREFIX($string = "xmlns:env:", 0);
print "==> is_XML10_PREFIX(\"$string\"): $length\n\n";
$length = is_XML10_PREFIX($string = "xmlns:env", 0);
print "==> is_XML10_PREFIX(\"$string\"): $length\n\n";
$length = is_XML10_PREFIX($string = "xmlns::env", 0);
print "==> is_XML10_PREFIX(\"$string\"): $length\n\n";
$length = is_XML10_PREFIX($string = "xmlns", 0);
print "==> is_XML10_PREFIX(\"$string\"): $length\n\n";
$length = is_XML10_PREFIX($string = "test:namespace=", 0);
print "==> is_XML10_PREFIX(\"$string\"): $length\n\n";

$length = is_XML10_XMLNSCOLON($string = "xmlns:env:", 0);
print "==> is_XML10_XMLNSCOLON(\"$string\"): $length\n\n";
$length = is_XML10_XMLNSCOLON($string = "xmlns:env=", 0);
print "==> is_XML10_XMLNSCOLON(\"$string\"): $length\n\n";
$length = is_XML10_XMLNSCOLON($string = "xmlns:env", 0);
print "==> is_XML10_XMLNSCOLON(\"$string\"): $length\n\n";
$length = is_XML10_XMLNSCOLON($string = "xmlns:", 0);
print "==> is_XML10_XMLNSCOLON(\"$string\"): $length\n\n";

$length = is_XML10_XMLNS($string = "xmlns:env:", 0);
print "==> is_XML10_XMLNS(\"$string\"): $length\n\n";
$length = is_XML10_XMLNS($string = "xmlns:env=", 0);
print "==> is_XML10_XMLNS(\"$string\"): $length\n\n";
$length = is_XML10_XMLNS($string = "xmlns:env", 0);
print "==> is_XML10_XMLNS(\"$string\"): $length\n\n";
$length = is_XML10_XMLNS($string = "xmlns=env", 0);
print "==> is_XML10_XMLNS(\"$string\"): $length\n\n";
$length = is_XML10_XMLNS($string = "xmlns=", 0);
print "==> is_XML10_XMLNS(\"$string\"): $length\n\n";
$length = is_XML10_XMLNS($string = "xmlns", 0);
print "==> is_XML10_XMLNS(\"$string\"): $length\n\n";
