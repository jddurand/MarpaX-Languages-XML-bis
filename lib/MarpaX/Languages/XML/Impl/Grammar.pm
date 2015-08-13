package MarpaX::Languages::XML::Impl::Grammar;
use Data::Section -setup;
use Marpa::R2;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Impl::Logger;
use Moo;
use MooX::late;
use MooX::ClassAttribute;
use MooX::Types::MooseLike::Base qw/:all/;

# ABSTRACT: MarpaX::Languages::XML::Role::Grammar implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is an implementation of MarpaX::Languages::XML::Role::Grammar. It provides Marpa::R2::Scanless::G's class attributes for XML versions 1.0 and 1.1.

=cut
our $XML10_REF_DATA = __PACKAGE__->section_data('xml10');
our $XML11_REF_DATA = __PACKAGE__->section_data('xml10');
our @START = qw/document/;

class_has '_xml10' => (
                      is      => 'ro',
                      isa     => HashRef[InstanceOf['Marpa::R2::Scanless::G']],
                      lazy    => 1,
                      builder => '__build_xml10'
                     );

class_has '_xml11' => (
                      is      => 'ro',
                      isa     => HashRef[InstanceOf['Marpa::R2::Scanless::G']],
                      lazy    => 1,
                      builder => '__build_xml11'
                     );

sub __build_xml10 {
  return __build_xmlxx($XML10_REF_DATA, 'MarpaX::Languages::XML::XML10::AST', @START);
}

sub __build_xml11 {
  return __build_xmlxx($XML10_REF_DATA, 'MarpaX::Languages::XML::XML11::AST', @START);
}

sub __build_xmlxx {
  my ($source_ref, $bless, @start) = @_;
  my %rc = ();
  foreach (@start) {
    my $new_source = ${$source_ref};
    $new_source =~ s/\$START/$_/sxmg;
    $rc{$_} = Marpa::R2::Scanless::G->new({source => \$new_source, bless_package => $bless});
  }
  return \%rc;
}

sub get {
  my ($self, $version, $start) = @_;

  $version //= '1.0';
  $start //= 'document';
  my $rc;

  if ($version eq '1.0') {
    $rc = $self->_xml10->{$start};
  }
  elsif ($version eq '1.1') {
    $rc = $self->_xml11->{$start};
  }

  if (! $rc) {
    MarpaX::Languages::XML::Exception->throw("Invalid grammar version ($version) or grammar start ($start)");
  }
  $self->_logger->debugf('Got grammar for %s, version %s', $start, $version);

  return $rc;
}

=head1 SEE ALSO

L<Marpa::R2>, L<XML1.0|http://www.w3.org/TR/xml/>, L<XML1.1|http://www.w3.org/TR/xml11/>

=cut

extends 'MarpaX::Languages::XML::Impl::Logger';
with 'MarpaX::Languages::XML::Role::Grammar';

1;

__DATA__
__[ xml10 ]__
inaccessible is ok by default
:default ::= action => [values] bless => ::lhs
lexeme default = action => [start,length,value,name] forgiving => 1

# start                         ::= document | extParsedEnt | extSubset
start                         ::= $START
MiscAny                       ::= Misc*
document                      ::= prolog element MiscAny
Name                          ::= NAME
Names                         ::= Name+ separator => SPACE proper => 1
Nmtoken                       ::= NMTOKENMANY
Nmtokens                      ::= Nmtoken+ separator => SPACE proper => 1

EntityValue                   ::= '"' EntityValueInteriorDquote '"'
                                | ['] EntityValueInteriorSquote [']
EntityValueInteriorDquoteUnit ::= ENTITYVALUEINTERIORDQUOTEUNIT
PEReferenceMany               ::= PEReference+
EntityValueInteriorDquoteUnit ::= PEReferenceMany
ReferenceMany                 ::= Reference+
EntityValueInteriorDquoteUnit ::= ReferenceMany
EntityValueInteriorDquote     ::= EntityValueInteriorDquoteUnit*
EntityValueInteriorSquoteUnit ::= ENTITYVALUEINTERIORSQUOTEUNIT
EntityValueInteriorSquoteUnit ::= ReferenceMany
EntityValueInteriorSquoteUnit ::= PEReferenceMany
EntityValueInteriorSquote     ::= EntityValueInteriorSquoteUnit*

AttValue                      ::=  '"' AttValueInteriorDquote '"'
                                |  ['] AttValueInteriorSquote [']
AttValueInteriorDquoteUnit    ::= ATTVALUEINTERIORDQUOTEUNIT
AttValueInteriorDquoteUnit    ::= ReferenceMany
AttValueInteriorDquote        ::= AttValueInteriorDquoteUnit*
AttValueInteriorSquoteUnit    ::= ATTVALUEINTERIORSQUOTEUNIT
AttValueInteriorSquoteUnit    ::= ReferenceMany
AttValueInteriorSquote        ::= AttValueInteriorSquoteUnit*

SystemLiteral                 ::= '"' NOT_DQUOTEANY '"'
                                | ['] NOT_SQUOTEANY [']
PubidCharDquoteAny            ::= PubidCharDquote*
PubidCharSquoteAny            ::= PubidCharSquote*
PubidLiteral                  ::= '"' PubidCharDquoteAny '"'
                                | ['] PubidCharSquoteAny [']

PubidCharDquote               ::= [a-zA-Z0-9\-'()+,./:=?;!*#@$_%\x{20}\x{D}\x{A}]
PubidCharSquote               ::= [a-zA-Z0-9\-()+,./:=?;!*#@$_%\x{20}\x{D}\x{A}]

CharData                      ::= CHARDATAMANY

CommentCharAny                ::= COMMENTCHARANY
Comment                       ::= '<!--' CommentCharAny '-->'

PI                            ::= '<?' PITarget S PICHARDATAMANY '?>'
                                | '<?' PITarget                  '?>'
                                | '<?' PITarget S                '?>'
                                | '<?' PITarget                  '?>'

PITarget                      ::= PITARGET
CDSect                        ::= CDStart CData CDEnd
CDStart                       ::= '<![CDATA['
CData                         ::= CDATAANY
CDEnd                         ::= ']]>'
XMLDeclMaybe                  ::= XMLDecl
XMLDeclMaybe                  ::=
prolog                        ::= XMLDeclMaybe MiscAny
prolog                        ::= XMLDeclMaybe MiscAny doctypedecl MiscAny
EncodingDeclMaybe             ::= EncodingDecl
EncodingDeclMaybe             ::=
SDDeclMaybe                   ::= SDDecl
SDDeclMaybe                   ::=
SMaybe                        ::= S
SMaybe                        ::=
event 'XMLDecl$' = completed <XMLDecl>
XMLDecl                       ::= '<?xml' VersionInfo EncodingDeclMaybe SDDeclMaybe SMaybe '?>'
VersionInfo                   ::= S 'version' Eq ['] VersionNum [']
VersionInfo                   ::= S 'version' Eq '"' VersionNum '"'
Eq                            ::= SMaybe '=' SMaybe
VersionNum                    ::= '1.0'
Misc                          ::= Comment | PI | S
doctypedecl                   ::= '<!DOCTYPE' S Name              SMaybe '[' intSubset ']' SMaybe '>' # [VC: Root Element Type] [WFC: External Subset]
                                | '<!DOCTYPE' S Name              SMaybe                           '>' # [VC: Root Element Type] [WFC: External Subset]
                                | '<!DOCTYPE' S Name S ExternalID SMaybe '[' intSubset ']' SMaybe '>' # [VC: Root Element Type] [WFC: External Subset]
                                | '<!DOCTYPE' S Name S ExternalID SMaybe                           '>' # [VC: Root Element Type] [WFC: External Subset]
DeclSep                       ::= PEReference   # [WFC: PE Between Declarations]
                                | S
intSubsetUnit                 ::= markupdecl | DeclSep
intSubset                     ::= intSubsetUnit*
markupdecl                    ::= elementdecl  # [VC: Proper Declaration/PE Nesting] [WFC: PEs in Internal Subset]
                                | AttlistDecl  # [VC: Proper Declaration/PE Nesting] [WFC: PEs in Internal Subset]
                                | EntityDecl   # [VC: Proper Declaration/PE Nesting] [WFC: PEs in Internal Subset]
                                | NotationDecl # [VC: Proper Declaration/PE Nesting] [WFC: PEs in Internal Subset]
                                | PI           # [VC: Proper Declaration/PE Nesting] [WFC: PEs in Internal Subset]
                                | Comment      # [VC: Proper Declaration/PE Nesting] [WFC: PEs in Internal Subset]
TextDeclMaybe                 ::= TextDecl
TextDeclMaybe                 ::=
extSubset                     ::= TextDeclMaybe extSubsetDecl
extSubsetDeclUnit             ::= markupdecl | conditionalSect | DeclSep
extSubsetDecl                 ::= extSubsetDeclUnit*
SDDecl                        ::= S 'standalone' Eq ['] 'yes' [']  # [VC: Standalone Document Declaration]
                                | S 'standalone' Eq [']  'no' [']  # [VC: Standalone Document Declaration]
                                | S 'standalone' Eq '"' 'yes' '"'  # [VC: Standalone Document Declaration]
                                | S 'standalone' Eq '"'  'no' '"'  # [VC: Standalone Document Declaration]
element                       ::= EmptyElemTag
                                | STag content ETag  # [WFC: Element Type Match] [VC: Element Valid]
STagUnit                      ::= S Attribute
STagUnitAny                   ::= STagUnit*
event 'tagStart$' = completed <tagStart>
tagStart                      ::= TAG_START
STag                          ::= tagStart Name STagUnitAny SMaybe '>' # [WFC: Unique Att Spec]
Attribute                     ::= Name Eq AttValue  # [VC: Attribute Value Type] [WFC: No External Entity References] [WFC: No < in Attribute Values]
ETag                          ::= '</' Name SMaybe '>'
CharDataMaybe                 ::= CharData
CharDataMaybe                 ::=
contentUnit                   ::= element CharDataMaybe | Reference CharDataMaybe | CDSect CharDataMaybe | PI CharDataMaybe | Comment CharDataMaybe
contentUnitAny                ::= contentUnit*
content                       ::= CharDataMaybe contentUnitAny
EmptyElemTagUnit              ::= S Attribute
EmptyElemTagUnitAny           ::= EmptyElemTagUnit*
EmptyElemTag                  ::= tagStart Name EmptyElemTagUnitAny SMaybe '/>' # [WFC: Unique Att Spec]
elementdecl                   ::= '<!ELEMENT' S Name S contentspec SMaybe '>' # [VC: Unique Element Type Declaration]
contentspec                   ::= 'EMPTY' | 'ANY' | Mixed | children
ChoiceOrSeq                   ::= choice | seq
children                      ::= ChoiceOrSeq
                                | ChoiceOrSeq [?*+]
NameOrChoiceOrSeq             ::= Name | choice | seq
cp                            ::= NameOrChoiceOrSeq
                                | NameOrChoiceOrSeq [?*+]
choiceUnit                    ::= SMaybe '|' SMaybe cp
choiceUnitMany                ::= choiceUnit+
choice                        ::= '(' SMaybe cp choiceUnitMany SMaybe ')' # [VC: Proper Group/PE Nesting]
seqUnit                       ::= SMaybe ',' SMaybe cp
seqUnitAny                    ::= seqUnit*
seq                           ::= '(' SMaybe cp seqUnitAny SMaybe ')' # [VC: Proper Group/PE Nesting]
MixedUnit                     ::= SMaybe '|' SMaybe Name
MixedUnitAny                  ::= MixedUnit*
Mixed                         ::= '(' SMaybe '#PCDATA' MixedUnitAny SMaybe ')*' # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | '(' SMaybe '#PCDATA'               SMaybe ')'            # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
AttlistDecl                   ::= '<!ATTLIST' S Name AttDefAny SMaybe '>'
AttDefAny                     ::= AttDef*
AttDef                        ::= S Name S AttType S DefaultDecl
AttType                       ::= StringType | TokenizedType | EnumeratedType
StringType                    ::= 'CDATA'
TokenizedType                 ::= 'ID'                 # [VC: ID] [VC: One ID per Element Type] [VC: ID Attribute Default]
                                | 'IDREF'              # [VC: IDREF]
                                | 'IDREFS'             # [VC: IDREF]
                                | 'ENTITY'             # [VC: Entity Name]
                                | 'ENTITIES'           # [VC: Entity Name]
                                | 'NMTOKEN'            # [VC: Name Token]
                                | 'NMTOKENS'           # [VC: Name Token]
EnumeratedType                ::= NotationType | Enumeration
NotationTypeUnit              ::= SMaybe '|' SMaybe Name
NotationTypeUnitAny           ::= NotationTypeUnit*
NotationType                  ::= 'NOTATION' S '(' SMaybe Name NotationTypeUnitAny SMaybe ')' # [VC: Notation Attributes] [VC: One Notation Per Element Type] [VC: No Notation on Empty Element] [VC: No Duplicate Tokens]
EnumerationUnit               ::= SMaybe '|' SMaybe Nmtoken
EnumerationUnitAny            ::= EnumerationUnit*
Enumeration                   ::= '(' SMaybe Nmtoken EnumerationUnitAny SMaybe ')' # [VC: Enumeration] [VC: No Duplicate Tokens]
DefaultDecl                   ::= '#REQUIRED' | '#IMPLIED'
                                |            AttValue                              # [VC: Required Attribute] [VC: Attribute Default Value Syntactically Correct] [WFC: No < in Attribute Values] [VC: Fixed Attribute Default] [WFC: No External Entity References]
                                | '#FIXED' S AttValue                              # [VC: Required Attribute] [VC: Attribute Default Value Syntactically Correct] [WFC: No < in Attribute Values] [VC: Fixed Attribute Default] [WFC: No External Entity References]
conditionalSect               ::= includeSect | ignoreSect
includeSect                   ::= '<![' SMaybe 'INCLUDE' SMaybe '[' extSubsetDecl          ']]>' # [VC: Proper Conditional Section/PE Nesting]
ignoreSect                    ::= '<![' SMaybe  'IGNORE' SMaybe '[' ignoreSectContentsAny ']]>'
                                | '<![' SMaybe  'IGNORE' SMaybe '['                        ']]>' # [VC: Proper Conditional Section/PE Nesting]
ignoreSectContentsAny         ::= ignoreSectContents*
ignoreSectContentsUnit        ::= '<![' ignoreSectContents ']]>' Ignore
ignoreSectContentsUnit        ::= '<!['                    ']]>' Ignore
ignoreSectContentsUnitAny     ::= ignoreSectContentsUnit*
ignoreSectContents            ::= Ignore ignoreSectContentsUnitAny
Ignore                        ::= IGNOREMANY
CharRef                       ::= '&#' DIGITMANY ';'
                                | '&#x' ALPHAMANY ';' # [WFC: Legal Character]
Reference                     ::= EntityRef | CharRef
EntityRef                     ::= '&' Name ';' # [WFC: Entity Declared] [VC: Entity Declared] [WFC: Parsed Entity] [WFC: No Recursion]
PEReference                   ::= '%' Name ';' # [VC: Entity Declared] [WFC: No Recursion] [WFC: In DTD]
EntityDecl                    ::= GEDecl | PEDecl
GEDecl                        ::= '<!ENTITY' S Name S EntityDef SMaybe '>'
PEDecl                        ::= '<!ENTITY' S '%' S Name S PEDef SMaybe '>'
EntityDef                     ::= EntityValue
                                | ExternalID
                                | ExternalID NDataDecl
PEDef                         ::= EntityValue
                                | ExternalID
ExternalID                    ::= 'SYSTEM' S SystemLiteral
                                | 'PUBLIC' S PubidLiteral S SystemLiteral
NDataDecl                     ::= S 'NDATA' S Name  # [VC: Notation Declared]
VersionInfoMaybe             ::= VersionInfo
VersionInfoMaybe             ::=
TextDecl                      ::= '<?xml' VersionInfoMaybe EncodingDecl SMaybe '?>'
extParsedEnt                  ::= TextDeclMaybe content
EncodingDecl                  ::= S 'encoding' Eq '"' EncName '"'
EncodingDecl                  ::= S 'encoding' Eq ['] EncName [']
event 'EncName$' = completed <EncName>
EncName                       ::= ENCNAME
NotationDecl                  ::= '<!NOTATION' S Name S ExternalID SMaybe '>' # [VC: Unique Notation Name]
NotationDecl                  ::= '<!NOTATION' S Name S   PublicID SMaybe '>' # [VC: Unique Notation Name]
PublicID                      ::= 'PUBLIC' S PubidLiteral

_SPACE                          ~ [\x{20}]
_NOT_SQUOTEANY                  ~ [^']*
_NOT_DQUOTEANY                  ~ [^"]*

SPACE                           ~ _SPACE
NOT_SQUOTEANY                   ~ _NOT_SQUOTEANY
NOT_DQUOTEANY                   ~ _NOT_DQUOTEANY

_CHARDATAUNIT                   ~      [^<&\]]
                                |  ']'
                                |  ']' [^<&\]]
                                | ']]'
                                | ']]' [^<&>]
_CHARDATAMANY                   ~ _CHARDATAUNIT+
CHARDATAMANY                    ~ _CHARDATAMANY

# A PI char is a Char minus '?>'. We revisit char range from:
# [\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]
# to its equivalent exclusion:
# [^\x{0}-\x{8}\x{B}-\x{C}\x{E}-\x{1F}\x{D800}-\x{DFFF}\x{FFFE}\x{FFFF}]

_PICHARDATAUNIT                 ~      [^\x{0}-\x{8}\x{B}-\x{C}\x{E}-\x{1F}\x{D800}-\x{DFFF}\x{FFFE}\x{FFFF}?]
                                |  '?'
                                |  '?' [^\x{0}-\x{8}\x{B}-\x{C}\x{E}-\x{1F}\x{D800}-\x{DFFF}\x{FFFE}\x{FFFF}>]
_PICHARDATAMANY                 ~ _PICHARDATAUNIT+
PICHARDATAMANY                  ~ _PICHARDATAMANY

# _CHAR                           ~ [\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]
# _CHARANY                        ~ _CHAR*
# CHARANY                         ~ _CHARANY

_NAMESTARTCHAR                  ~ [:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}]
_NAMEENDCHARANY                 ~ [:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*
_NAME                           ~ _NAMESTARTCHAR _NAMEENDCHARANY
NAME                            ~ _NAME

_NMTOKENMANY                    ~ [:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]+
NMTOKENMANY                     ~ _NMTOKENMANY

# A PITarget is a Name without [xX][mM][lL]
_PITARGET_NAMESTARTCHAR_WITHOUT_X ~ [^\x{0}-\x{39}\x{3B}-x\{40}\x{5B}-\x{5E}\x{60}\x{7B}-\x{DF}\x{D7}\x{F7}\x{300}-\x{36F}\x{37E}\x{2000}-\x{200B}\x{200E}-\x{206F}\x{2190}-\x{2BFF}\x{2FF0}-\x{3000}\x{D800}-\x{F8FF}\x{FDD0}-\x{FDDF}\x{FFFE}-\x{FFFF}\x{F0000}-\x{10FFFF}xX]
_PITARGET_NAMEENDCHAR_WITHOUT_X   ~ [^\x{0}-\x{2C}\x{2F}\x{3B}-x\{40}\x{5B}-\x{5E}\x{60}\x{7B}-\x{B6}\x{B8}-\x{DF}\x{D7}\x{F7}\x{37E}\x{2000}-\x{200B}\x{200E}-\x{203E}\x{2041}-\x{206F}\x{2190}-\x{2BFF}\x{2FF0}-\x{3000}\x{D800}-\x{F8FF}\x{FDD0}-\x{FDDF}\x{FFFE}-\x{FFFF}\x{F0000}-\x{10FFFF}xX]
_PITARGET_NAMEENDCHAR_WITHOUT_M   ~ [^\x{0}-\x{2C}\x{2F}\x{3B}-x\{40}\x{5B}-\x{5E}\x{60}\x{7B}-\x{B6}\x{B8}-\x{DF}\x{D7}\x{F7}\x{37E}\x{2000}-\x{200B}\x{200E}-\x{203E}\x{2041}-\x{206F}\x{2190}-\x{2BFF}\x{2FF0}-\x{3000}\x{D800}-\x{F8FF}\x{FDD0}-\x{FDDF}\x{FFFE}-\x{FFFF}\x{F0000}-\x{10FFFF}mM]
_PITARGET_NAMEENDCHAR_WITHOUT_L   ~ [^\x{0}-\x{2C}\x{2F}\x{3B}-x\{40}\x{5B}-\x{5E}\x{60}\x{7B}-\x{B6}\x{B8}-\x{DF}\x{D7}\x{F7}\x{37E}\x{2000}-\x{200B}\x{200E}-\x{203E}\x{2041}-\x{206F}\x{2190}-\x{2BFF}\x{2FF0}-\x{3000}\x{D800}-\x{F8FF}\x{FDD0}-\x{FDDF}\x{FFFE}-\x{FFFF}\x{F0000}-\x{10FFFF}lL]
_PITARGET_NAMESTARTCHAR           ~ _PITARGET_NAMESTARTCHAR_WITHOUT_X
                                  |                              [xX]
                                  |                              [xX] _PITARGET_NAMEENDCHAR_WITHOUT_M
                                  |                              [xX] [mM]
                                  |                              [xX] [mM] _PITARGET_NAMEENDCHAR_WITHOUT_L
_PITARGET_NAMEENDCHAR             ~ _PITARGET_NAMEENDCHAR_WITHOUT_X
                                  |                            [xX]
                                  |                            [xX] _PITARGET_NAMEENDCHAR_WITHOUT_M
                                  |                            [xX] [mM]
                                  |                            [xX] [mM] _PITARGET_NAMEENDCHAR_WITHOUT_L
_PITARGET_NAMEENDCHARANY         ~ _PITARGET_NAMEENDCHAR*
_PITARGET                         ~ _PITARGET_NAMESTARTCHAR _PITARGET_NAMEENDCHARANY
PITARGET                          ~ _PITARGET

# A CData is a sequence of Char minus ']]>'
_CHAR_WITHOUT_RBRACKET              ~ [^\x{0}-\x{8}\x{B}-\x{C}\x{E}-\x{1F}\x{D800}-\x{DFFF}\x{FFFE}\x{FFFF}\]]
_CHAR_WITHOUT_GT                    ~ [^\x{0}-\x{8}\x{B}-\x{C}\x{E}-\x{1F}\x{D800}-\x{DFFF}\x{FFFE}\x{FFFF}>]
_CHAR_WITHOUT_RBRACKET_RBRACKET_GT  ~ _CHAR_WITHOUT_RBRACKET
                                    |                    ']'
                                    |                    ']' _CHAR_WITHOUT_RBRACKET
                                    |                   ']]'
                                    |                   ']]' _CHAR_WITHOUT_GT
_CDATAANY                          ~ _CHAR_WITHOUT_RBRACKET_RBRACKET_GT*
CDATAANY                           ~ _CDATAANY

# A Ignore is a positive sequence of Char minus '<![' or ']]>'
_CHAR_WITHOUT_LT                    ~ [^\x{0}-\x{8}\x{B}-\x{C}\x{E}-\x{1F}\x{D800}-\x{DFFF}\x{FFFE}\x{FFFF}<]
_CHAR_WITHOUT_LBRACKET              ~ [^\x{0}-\x{8}\x{B}-\x{C}\x{E}-\x{1F}\x{D800}-\x{DFFF}\x{FFFE}\x{FFFF}\[]
_CHAR_WITHOUT_EMARK                 ~ [^\x{0}-\x{8}\x{B}-\x{C}\x{E}-\x{1F}\x{D800}-\x{DFFF}\x{FFFE}\x{FFFF}!]
_CHAR_WITHOUT_LT_EMARK_LBRACKET     ~ _CHAR_WITHOUT_LT
                                    |               '<' _CHAR_WITHOUT_EMARK
                                    |               '<'
                                    |              '<!'
                                    |              '<!' _CHAR_WITHOUT_LBRACKET
_IGNORE                             ~ _CHAR_WITHOUT_LT_EMARK_LBRACKET
                                    | _CHAR_WITHOUT_RBRACKET_RBRACKET_GT
_IGNOREMANY                        ~ _IGNORE+
IGNOREMANY                         ~ _IGNOREMANY

# A comment is a sequence of Char minus '--'
_CHAR_WITHOUT_MINUS                 ~ [^\x{0}-\x{8}\x{B}-\x{C}\x{E}-\x{1F}\x{D800}-\x{DFFF}\x{FFFE}\x{FFFF}\-]
_COMMENTCHAR     ~ _CHAR_WITHOUT_MINUS
                 |                 '-' _CHAR_WITHOUT_MINUS
_COMMENTCHARANY                     ~ _COMMENTCHAR*
COMMENTCHARANY                     ~ _COMMENTCHARANY

_DIGIT                              ~ [0-9]
_DIGITMANY                         ~ _DIGIT+
DIGITMANY                          ~ _DIGITMANY

_ALPHA                              ~ [0-9a-fA-F]
_ALPHAMANY                         ~ _ALPHA+
ALPHAMANY                          ~ _ALPHAMANY

_ENCNAME_STAR                       ~ [A-Za-z]
_ENCNAME_END                        ~ [A-Za-z0-9._\-]*
_ENCNAME                            ~ _ENCNAME_STAR _ENCNAME_END
ENCNAME                             ~ _ENCNAME

ENTITYVALUEINTERIORDQUOTEUNIT       ~ [^%&"]+
ENTITYVALUEINTERIORSQUOTEUNIT       ~ [^%&']+

ATTVALUEINTERIORDQUOTEUNIT          ~ [^<&"]+
ATTVALUEINTERIORSQUOTEUNIT          ~ [^<&']+

S                                   ~ [\x{20}\x{9}\x{D}\x{A}]+
TAG_START                           ~ '<'
