package MarpaX::Languages::XML::Impl::Grammar;
use Data::Section -setup;
use Marpa::R2;
use MarpaX::Languages::XML::Impl::Logger;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Impl::Logger;
use Moo;
use MooX::late;
use MooX::HandlesVia;
use Scalar::Util qw/blessed reftype/;

# ABSTRACT: MarpaX::Languages::XML::Role::Grammar implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is an implementation of MarpaX::Languages::XML::Role::Grammar. It provides Marpa::R2::Scanless::G's class attributes for XML versions 1.0 and 1.1.

=cut
our %XMLVERSION = (
                   '1.0' => __PACKAGE__->section_data('xml10'),
                   '1.1' => __PACKAGE__->section_data('xml10')
                  );
#
# C.f. comments in the grammar explaining why end_document and end_element are absent
#
our @SAX_EVENTS = qw/start_document

                     start_element
                     end_element

                     characters
                     ignorable_whitespace
                     start_prefix_mapping
                     end_prefix_mapping
                     processing_instruction
                     skipped_entity

                     notation_decl
                     unparsed_entity_decl

                     start_dtd
                     end_dtd
                     start_entity
                     end_entity
                     start_cdata
                     end_cdata
                     comment

                     element_decl
                     attribute_decl
                     internal_entity_decl
                     external_entity_decl
                    /;

has _grammars => (
                  is => 'ro',
                  writer =>'_set_grammars',
                  isa => 'HashRef[Marpa::R2::Scanless::G]',
                  default => sub { {} },
                  handles_via => 'Hash',
                  handles => {
                              '_get_grammar' => 'get',
                              '_set_grammar' => 'set'
                             }
                 );

sub compile {
  my ($self, %hash) = @_;

  my $xmlversion = $hash{xmlversion} || '1.0';
  if (reftype($xmlversion)) {
    MarpaX::Languages::XML::Exception->throw('xmlversion must be a SCALAR');
  }
  my $start = $hash{start} || 'document';
  if (reftype($start)) {
    MarpaX::Languages::XML::Exception->throw('start must be a SCALAR');
  }
  #
  # We simulate a singleton within the instance
  #
  my $grammar = "$xmlversion/$start";
  return $self->_get_grammar($grammar) || $self->_set_grammar($grammar => $self->_grammar(%hash, xmlversion => $xmlversion, start => $start));
}

sub _grammar {
  my ($self, %hash) = @_;

  my $xmlversion      = $hash{xmlversion}      || '1.0';
  my $start           = $hash{start}           || 'document';
  my $sax_handlers    = $hash{sax_handlers}    || {};
  my $internal_events = $hash{internal_events} || {};

  #
  # Sanity checks
  #
  if (! exists($XMLVERSION{$xmlversion})) {
    MarpaX::Languages::XML::Exception->throw("Invalid grammar version: $xmlversion");
  }
  if (! reftype($sax_handlers) || reftype($sax_handlers) ne 'HASH') {
    MarpaX::Languages::XML::Exception->throw("Invalid sax handlers: $sax_handlers");
  }
  if (! reftype($internal_events) || reftype($internal_events) ne 'HASH') {
    MarpaX::Languages::XML::Exception->throw("Invalid internal events: $internal_events");
  }
  #
  # Manipulate DATA section
  #
  my $data = ${$XMLVERSION{$xmlversion}};
  #
  # Revisit the start
  #
  $data =~ s/\$START/$start/sxmg;
  #
  # Remove all non-needed SAX events for performance.
  #
  foreach (@SAX_EVENTS) {
    if (exists($sax_handlers->{$_})) {
      if (! reftype($sax_handlers->{$_}) || reftype($sax_handlers->{$_}) ne 'CODE') {
        $self->_logger->warnf('%s/%s: SAX Handler for %s is not a \'CODE\' reference', $xmlversion, $start, $_);
      } else {
        $self->_logger->debugf('%s/%s: Adding SAX Handler for %s', $xmlversion, $start, $_);
        $data .= "event '$_' = nulled <$_>\n";
      }
    }
  }
  foreach (keys %{$internal_events}) {
    my $event_name  = $_;
    my $lexeme      = $internal_events->{$_}->{lexeme};
    my $symbol_name = $internal_events->{$_}->{symbol_name};
    my $type        = $internal_events->{$_}->{type};
    $self->_logger->debugf('%s/%s: Adding %s %s event', $xmlversion, $start, $lexeme ? 'L0' : 'G1', $event_name);
    if ($lexeme) {
      $data .= ":lexeme ~ <$symbol_name> pause => $type event => '$event_name'\n";
    }
    else {
      $data .= "event '$event_name' = $type <$symbol_name>\n";
    }
  }
  #
  # Generate the grammar
  #
  $self->_logger->debugf('%s/%s: Instanciating grammar', $xmlversion, $start);
  return Marpa::R2::Scanless::G->new({source => \$data});
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
:default ::= action => [values]
lexeme default = action => [start,length,value,name] forgiving => 1

# start                         ::= document | extParsedEnt | extSubset
start                         ::= $START
MiscAny                       ::= Misc*
# Note: end_document is when either we abandoned parsing or reached the end of input of the 'document' grammar
document                      ::= (start_document) prolog element MiscAny
Name                          ::= NAME
Names                         ::= Name+ separator => SPACE proper => 1
Nmtoken                       ::= NMTOKENMANY
Nmtokens                      ::= Nmtoken+ separator => SPACE proper => 1

EntityValue                   ::= DQUOTE EntityValueInteriorDquote DQUOTE
                                | SQUOTE EntityValueInteriorSquote SQUOTE
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

AttValue                      ::=  DQUOTE AttValueInteriorDquote DQUOTE
                                |  SQUOTE AttValueInteriorSquote SQUOTE
AttValueInteriorDquoteUnit    ::= ATTVALUEINTERIORDQUOTEUNIT
AttValueInteriorDquoteUnit    ::= ReferenceMany
AttValueInteriorDquote        ::= AttValueInteriorDquoteUnit*
AttValueInteriorSquoteUnit    ::= ATTVALUEINTERIORSQUOTEUNIT
AttValueInteriorSquoteUnit    ::= ReferenceMany
AttValueInteriorSquote        ::= AttValueInteriorSquoteUnit*

SystemLiteral                 ::= DQUOTE NOT_DQUOTEMANY DQUOTE
                                | DQUOTE                DQUOTE
                                | SQUOTE NOT_SQUOTEMANY SQUOTE
                                | SQUOTE                SQUOTE
PubidCharDquoteAny            ::= PubidCharDquote*
PubidCharSquoteAny            ::= PubidCharSquote*
PubidLiteral                  ::= DQUOTE PubidCharDquoteAny DQUOTE
                                | SQUOTE PubidCharSquoteAny SQUOTE

PubidCharDquote               ::= PUBIDCHARDQUOTE
PubidCharSquote               ::= PUBIDCHARSQUOTE

CharData                      ::= CHARDATAMANY

CommentCharAny                ::= COMMENTCHARMANY
CommentCharAny                ::=
Comment                       ::= COMMENT_START CommentCharAny (comment) COMMENT_END

PI                            ::= PI_START PITarget S PICHARDATAMANY PI_END
                                | PI_START PITarget S                PI_END
                                | PI_START PITarget                  PI_END

PITarget                      ::= PITARGET
CDSect                        ::= CDStart CData CDEnd
CDStart                       ::= CDATA_START
CData                         ::= CDATAMANY
CData                         ::=
CDEnd                         ::= CDATA_END
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
XMLDecl                       ::= XMLDECL_START VersionInfo EncodingDeclMaybe SDDeclMaybe SMaybe XMLDECL_END
VersionInfo                   ::= S VERSION Eq SQUOTE VersionNum SQUOTE
VersionInfo                   ::= S VERSION Eq DQUOTE VersionNum DQUOTE
Eq                            ::= SMaybe EQUAL SMaybe
VersionNum                    ::= VERSIONNUM
Misc                          ::= Comment | PI | S
doctypedecl                   ::= DOCTYPE_START S Name              SMaybe LBRACKET intSubset RBRACKET SMaybe DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
                                | DOCTYPE_START S Name              SMaybe                                    DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
                                | DOCTYPE_START S Name S ExternalID SMaybe LBRACKET intSubset RBRACKET SMaybe DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
                                | DOCTYPE_START S Name S ExternalID SMaybe                                    DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
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
SDDecl                        ::= S STANDALONE Eq SQUOTE YES SQUOTE # [VC: Standalone Document Declaration]
                                | S STANDALONE Eq SQUOTE  NO SQUOTE  # [VC: Standalone Document Declaration]
                                | S STANDALONE Eq DQUOTE YES DQUOTE  # [VC: Standalone Document Declaration]
                                | S STANDALONE Eq DQUOTE  NO DQUOTE  # [VC: Standalone Document Declaration]
element                       ::= EmptyElemTag (start_element) (end_element)
                                | STag (start_element) content ETag (end_element) # [WFC: Element Type Match] [VC: Element Valid]
STagUnit                      ::= S Attribute
STagUnitAny                   ::= STagUnit*
STagName                      ::= Name
STag                          ::= ELEMENT_START STagName STagUnitAny SMaybe ELEMENT_END # [WFC: Unique Att Spec]
AttributeName                 ::= Name
Attribute                     ::= AttributeName Eq AttValue  # [VC: Attribute Value Type] [WFC: No External Entity References] [WFC: No < in Attribute Values]
ETag                          ::= ETAG_START Name SMaybe ETAG_END
CharDataMaybe                 ::= CharData
CharDataMaybe                 ::=
contentUnit                   ::= element CharDataMaybe | Reference CharDataMaybe | CDSect CharDataMaybe | PI CharDataMaybe | Comment CharDataMaybe
contentUnitAny                ::= contentUnit*
content                       ::= CharDataMaybe contentUnitAny
EmptyElemTagUnit              ::= S Attribute
EmptyElemTagUnitAny           ::= EmptyElemTagUnit*
EmptyElemTag                  ::= EMPTYELEM_START Name EmptyElemTagUnitAny SMaybe EMPTYELEM_END # [WFC: Unique Att Spec]
elementdecl                   ::= ELEMENTDECL_START S Name S contentspec SMaybe ELEMENTDECL_END # [VC: Unique Element Type Declaration]
contentspec                   ::= EMPTY | ANY | Mixed | children
ChoiceOrSeq                   ::= choice | seq
children                      ::= ChoiceOrSeq
                                | ChoiceOrSeq QUESTIONMARK_OR_STAR_OR_PLUS
NameOrChoiceOrSeq             ::= Name | choice | seq
cp                            ::= NameOrChoiceOrSeq
                                | NameOrChoiceOrSeq QUESTIONMARK_OR_STAR_OR_PLUS
choiceUnit                    ::= SMaybe OR SMaybe cp
choiceUnitMany                ::= choiceUnit+
choice                        ::= CHOICE_START SMaybe cp choiceUnitMany SMaybe CHOICE_END # [VC: Proper Group/PE Nesting]
seqUnit                       ::= SMaybe COMMA SMaybe cp
seqUnitAny                    ::= seqUnit*
seq                           ::= SEQ_START SMaybe cp seqUnitAny SMaybe SEQ_END # [VC: Proper Group/PE Nesting]
MixedUnit                     ::= SMaybe OR SMaybe Name
MixedUnitAny                  ::= MixedUnit*
Mixed                         ::= MIXED_START1 SMaybe PCDATA MixedUnitAny SMaybe MIXED_END1 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START2 SMaybe PCDATA              SMaybe MIXED_END2 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
AttlistDecl                   ::= ATTLIST_START S Name AttDefAny SMaybe ATTLIST_END
AttDefAny                     ::= AttDef*
AttDef                        ::= S Name S AttType S DefaultDecl
AttType                       ::= StringType | TokenizedType | EnumeratedType
StringType                    ::= CDATA
TokenizedType                 ::= ID                 # [VC: ID] [VC: One ID per Element Type] [VC: ID Attribute Default]
                                | IDREF              # [VC: IDREF]
                                | IDREFS             # [VC: IDREF]
                                | ENTITY             # [VC: Entity Name]
                                | ENTITIES           # [VC: Entity Name]
                                | NMTOKEN            # [VC: Name Token]
                                | NMTOKENS           # [VC: Name Token]
EnumeratedType                ::= NotationType | Enumeration
NotationTypeUnit              ::= SMaybe OR SMaybe Name
NotationTypeUnitAny           ::= NotationTypeUnit*
NotationType                  ::= NOTATION S NOTATION_START SMaybe Name NotationTypeUnitAny SMaybe NOTATION_END # [VC: Notation Attributes] [VC: One Notation Per Element Type] [VC: No Notation on Empty Element] [VC: No Duplicate Tokens]
EnumerationUnit               ::= SMaybe OR SMaybe Nmtoken
EnumerationUnitAny            ::= EnumerationUnit*
Enumeration                   ::= ENUMERATION_START SMaybe Nmtoken EnumerationUnitAny SMaybe ENUMERATION_END # [VC: Enumeration] [VC: No Duplicate Tokens]
DefaultDecl                   ::= REQUIRED | IMPLIED
                                |            AttValue                              # [VC: Required Attribute] [VC: Attribute Default Value Syntactically Correct] [WFC: No < in Attribute Values] [VC: Fixed Attribute Default] [WFC: No External Entity References]
                                | FIXED S AttValue                              # [VC: Required Attribute] [VC: Attribute Default Value Syntactically Correct] [WFC: No < in Attribute Values] [VC: Fixed Attribute Default] [WFC: No External Entity References]
conditionalSect               ::= includeSect | ignoreSect
includeSect                   ::= INCLUDESECT_START SMaybe INCLUDE SMaybe LBRACKET extSubsetDecl          INCLUDESECT_END # [VC: Proper Conditional Section/PE Nesting]
ignoreSect                    ::= IGNORESECT_START SMaybe  IGNORE SMaybe LBRACKET ignoreSectContentsAny  IGNORESECT_END
                                | IGNORESECT_START SMaybe  IGNORE SMaybe LBRACKET                        IGNORESECT_END # [VC: Proper Conditional Section/PE Nesting]
ignoreSectContentsAny         ::= ignoreSectContents*
ignoreSectContentsUnit        ::= IGNORESECTCONTENTSUNIT_START ignoreSectContents IGNORESECTCONTENTSUNIT_END Ignore
ignoreSectContentsUnit        ::= IGNORESECTCONTENTSUNIT_START                    IGNORESECTCONTENTSUNIT_END Ignore
ignoreSectContentsUnitAny     ::= ignoreSectContentsUnit*
ignoreSectContents            ::= Ignore ignoreSectContentsUnitAny
Ignore                        ::= IGNOREMANY
CharRef                       ::= CHARREF_START1 DIGITMANY CHARREF_END1
                                | CHARREF_START2 ALPHAMANY CHARREF_END2 # [WFC: Legal Character]
Reference                     ::= EntityRef | CharRef
EntityRef                     ::= ENTITYREF_START Name ENTITYREF_END # [WFC: Entity Declared] [VC: Entity Declared] [WFC: Parsed Entity] [WFC: No Recursion]
PEReference                   ::= PEREFERENCE_START Name PEREFERENCE_END # [VC: Entity Declared] [WFC: No Recursion] [WFC: In DTD]
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
EncName                       ::= ENCNAME
NotationDecl                  ::= '<!NOTATION' S Name S ExternalID SMaybe '>' # [VC: Unique Notation Name]
NotationDecl                  ::= '<!NOTATION' S Name S   PublicID SMaybe '>' # [VC: Unique Notation Name]
PublicID                      ::= 'PUBLIC' S PubidLiteral

_SPACE                          ~ [\x{20}]
_NOT_SQUOTEMANY                 ~ [^']+
_NOT_DQUOTEMANY                 ~ [^"]+

SPACE                           ~ _SPACE
NOT_SQUOTEMANY                  ~ _NOT_SQUOTEMANY
NOT_DQUOTEMANY                  ~ _NOT_DQUOTEMANY

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
_CDATAMANY                         ~ _CHAR_WITHOUT_RBRACKET_RBRACKET_GT+
CDATAMANY                          ~ _CDATAMANY

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
_COMMENTCHARMANY                    ~ _COMMENTCHAR+
COMMENTCHARMANY                     ~ _COMMENTCHARMANY

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
DQUOTE                              ~ '"'
SQUOTE                              ~ [']
PUBIDCHARDQUOTE                     ~ [a-zA-Z0-9\-'()+,./:=?;!*#@$_%\x{20}\x{D}\x{A}]
PUBIDCHARSQUOTE                     ~ [a-zA-Z0-9\-()+,./:=?;!*#@$_%\x{20}\x{D}\x{A}]
COMMENT_START                       ~ '<!--'
COMMENT_END                         ~ '-->'
PI_START                            ~ '<?'
PI_END                              ~ '?>'
CDATA_START                         ~ '<![CDATA['
CDATA_END                           ~ ']]>'
XMLDECL_START                       ~ '<?xml'
XMLDECL_END                         ~ '?>'
VERSION                             ~ 'version'
EQUAL                               ~ '='
VERSIONNUM                          ~ '1.0'
DOCTYPE_START                       ~ '<!DOCTYPE'
DOCTYPE_END                         ~ '>'
LBRACKET                            ~ '['
RBRACKET                            ~ ']'
STANDALONE                          ~ 'standalone'
YES                                 ~ 'yes'
NO                                  ~ 'no'
ELEMENT_START                       ~ '<'
ELEMENT_END                         ~ '>'
ETAG_START                          ~ '</'
ETAG_END                            ~ '>'
EMPTYELEM_START                     ~ '<'
EMPTYELEM_END                       ~ '/>'
ELEMENTDECL_START                   ~ '<!ELEMENT'
ELEMENTDECL_END                     ~ '>'
EMPTY                               ~ 'EMPTY'
ANY                                 ~ 'ANY'
QUESTIONMARK_OR_STAR_OR_PLUS        ~ [?*+]
OR                                  ~ '|'
CHOICE_START                        ~ '('
CHOICE_END                          ~ ')'
SEQ_START                           ~ '('
SEQ_END                             ~ ')'
MIXED_START1                        ~ '('
MIXED_END1                          ~ ')*'
MIXED_START2                        ~ '('
MIXED_END2                          ~ ')'
COMMA                               ~ ','
PCDATA                              ~ '#PCDATA'
ATTLIST_START                       ~ '<!ATTLIST'
ATTLIST_END                         ~ '>'
CDATA                               ~ 'CDATA'
ID                                  ~ 'ID'
IDREF                               ~ 'IDREF'
IDREFS                              ~ 'IDREFS'
ENTITY                              ~ 'ENTITY'
ENTITIES                            ~ 'ENTITIES'
NMTOKEN                             ~ 'NMTOKEN'
NMTOKENS                            ~ 'NMTOKENS'
NOTATION                            ~ 'NOTATION'
NOTATION_START                      ~ '('
NOTATION_END                        ~ ')'
ENUMERATION_START                   ~ '('
ENUMERATION_END                     ~ ')'
REQUIRED                            ~ '#REQUIRED'
IMPLIED                             ~ '#IMPLIED'
FIXED                               ~ '#FIXED'
INCLUDE                             ~ 'INCLUDE'
IGNORE                              ~ 'IGNORE'
INCLUDESECT_START                   ~ '<!['
INCLUDESECT_END                     ~ ']]>'
IGNORESECT_START                    ~ '<!['
IGNORESECT_END                      ~ ']]>'
IGNORESECTCONTENTSUNIT_START        ~ '<!['
IGNORESECTCONTENTSUNIT_END          ~ ']]>'
CHARREF_START1                      ~ '&#'
CHARREF_END1                        ~ ';'
CHARREF_START2                      ~ '&#x'
CHARREF_END2                        ~ ';'
ENTITYREF_START                     ~ '&'
ENTITYREF_END                       ~ ';'
PEREFERENCE_START                   ~ '%'
PEREFERENCE_END                     ~ ';'
#
# SAX nullable rules
#
start_document ::= ;
start_element  ::= ;
end_element    ::= ;
comment        ::= ;
#
# SAX events are added on-the-fly, c.f. method xml().
#
