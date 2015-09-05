package MarpaX::Languages::XML::Impl::Grammar;
use Data::Section -setup;
use Marpa::R2;
use MarpaX::Languages::XML::Exception;
use Moo;
use MooX::late;
use MooX::Role::Logger;
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
        if ($MarpaX::Languages::XML::Impl::Parser::is_warn) {
          $self->_logger->warnf('[%s/%s] SAX Handler for %s is not a \'CODE\' reference', $xmlversion, $start, $_);
        }
      } else {
        if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
          $self->_logger->tracef('[%s/%s] Adding SAX Handler for %s', $xmlversion, $start, $_);
        }
        $data .= "event '$_' = nulled <$_>\n";
      }
    }
  }
  foreach (keys %{$internal_events}) {
    my $event_name  = $_;
    my $lexeme      = $internal_events->{$_}->{lexeme};
    my $symbol_name = $internal_events->{$_}->{symbol_name};
    my $type        = $internal_events->{$_}->{type};
    if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
      $self->_logger->tracef('[%s/%s] Adding %s %s %s event', $xmlversion, $start, $lexeme ? 'L0' : 'G1', $event_name, $type);
    }
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
  if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
    $self->_logger->debugf('[%s/%s] Instanciating grammar', $xmlversion, $start);
  }
  return Marpa::R2::Scanless::G->new({source => \$data});
}

=head1 SEE ALSO

L<Marpa::R2>, L<XML1.0|http://www.w3.org/TR/xml/>, L<XML1.1|http://www.w3.org/TR/xml11/>

=cut

with 'MooX::Role::Logger';
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
EmptyElemTag                  ::= ELEMENT_START Name EmptyElemTagUnitAny SMaybe EMPTYELEM_END # [WFC: Unique Att Spec]
elementdecl                   ::= ELEMENTDECL_START S Name S contentspec SMaybe ELEMENTDECL_END # [VC: Unique Element Type Declaration]
contentspec                   ::= EMPTY | ANY | Mixed | children
ChoiceOrSeq                   ::= choice | seq
children                      ::= ChoiceOrSeq
                                | ChoiceOrSeq QUESTIONMARK
                                | ChoiceOrSeq STAR
                                | ChoiceOrSeq PLUS
NameOrChoiceOrSeq             ::= Name | choice | seq
cp                            ::= NameOrChoiceOrSeq
                                | NameOrChoiceOrSeq QUESTIONMARK
                                | NameOrChoiceOrSeq STAR
                                | NameOrChoiceOrSeq PLUS
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
GEDecl                        ::= ENTITY_START S           Name S EntityDef SMaybe ENTITY_END
PEDecl                        ::= ENTITY_START S PERCENT S Name S PEDef     SMaybe ENTITY_END
EntityDef                     ::= EntityValue
                                | ExternalID
                                | ExternalID NDataDecl
PEDef                         ::= EntityValue
                                | ExternalID
ExternalID                    ::= SYSTEM S                SystemLiteral
                                | PUBLIC S PubidLiteral S SystemLiteral
NDataDecl                     ::= S NDATA S Name  # [VC: Notation Declared]
VersionInfoMaybe              ::= VersionInfo
VersionInfoMaybe              ::=
TextDecl                      ::= TEXTDECL_START VersionInfoMaybe EncodingDecl SMaybe TEXTDECL_END
extParsedEnt                  ::= TextDeclMaybe content
EncodingDecl                  ::= S ENCODING Eq DQUOTE EncName DQUOTE
EncodingDecl                  ::= S ENCODING Eq SQUOTE EncName SQUOTE
EncName                       ::= ENCNAME
NotationDecl                  ::= NOTATIONDECL_START S Name S ExternalID SMaybe NOTATIONDECL_END # [VC: Unique Notation Name]
NotationDecl                  ::= NOTATIONDECL_START S Name S   PublicID SMaybe NOTATIONDECL_END # [VC: Unique Notation Name]
PublicID                      ::= PUBLIC S PubidLiteral
#
# Generic internal token matching anything
#
__ANYTHING ~ [\s\S]
_NAME ~ __ANYTHING
_NMTOKENMANY ~ __ANYTHING
_ENTITYVALUEINTERIORDQUOTEUNIT ~ __ANYTHING
_ENTITYVALUEINTERIORSQUOTEUNIT ~ __ANYTHING
_ATTVALUEINTERIORDQUOTEUNIT ~ __ANYTHING
_ATTVALUEINTERIORSQUOTEUNIT ~ __ANYTHING
_NOT_DQUOTEMANY ~ __ANYTHING
_NOT_SQUOTEMANY ~ __ANYTHING
_PUBIDCHARDQUOTE ~ __ANYTHING
_PUBIDCHARSQUOTE ~ __ANYTHING
_CHARDATAMANY ~ __ANYTHING
_COMMENTCHARMANY ~ __ANYTHING
_PITARGET ~ __ANYTHING
_CDATAMANY ~ __ANYTHING
_PICHARDATAMANY ~ __ANYTHING
_IGNOREMANY ~ __ANYTHING
_DIGITMANY ~ __ANYTHING
_ALPHAMANY ~ __ANYTHING
_ENCNAME ~ __ANYTHING
_S ~ __ANYTHING
_SPACE ~ __ANYTHING
_DQUOTE ~ __ANYTHING
_SQUOTE ~ __ANYTHING
_COMMENT_START ~ __ANYTHING
_COMMENT_END ~ __ANYTHING
_PI_START ~ __ANYTHING
_PI_END ~ __ANYTHING
_CDATA_START ~ __ANYTHING
_CDATA_END ~ __ANYTHING
_XMLDECL_START ~ __ANYTHING
_XMLDECL_END ~ __ANYTHING
_VERSION ~ __ANYTHING
_EQUAL ~ __ANYTHING
_VERSIONNUM ~ __ANYTHING
_DOCTYPE_START ~ __ANYTHING
_DOCTYPE_END ~ __ANYTHING
_LBRACKET ~ __ANYTHING
_RBRACKET ~ __ANYTHING
_STANDALONE ~ __ANYTHING
_YES ~ __ANYTHING
_NO ~ __ANYTHING
_ELEMENT_START ~ __ANYTHING
_ELEMENT_END ~ __ANYTHING
_ETAG_START ~ __ANYTHING
_ETAG_END ~ __ANYTHING
_EMPTYELEM_END ~ __ANYTHING
_ELEMENTDECL_START ~ __ANYTHING
_ELEMENTDECL_END ~ __ANYTHING
_EMPTY ~ __ANYTHING
_ANY ~ __ANYTHING
_QUESTIONMARK ~ __ANYTHING
_STAR ~ __ANYTHING
_PLUS ~ __ANYTHING
_OR ~ __ANYTHING
_CHOICE_START ~ __ANYTHING
_CHOICE_END ~ __ANYTHING
_SEQ_START ~ __ANYTHING
_SEQ_END ~ __ANYTHING
_MIXED_START1 ~ __ANYTHING
_MIXED_END1 ~ __ANYTHING
_MIXED_START2 ~ __ANYTHING
_MIXED_END2 ~ __ANYTHING
_COMMA ~ __ANYTHING
_PCDATA ~ __ANYTHING
_ATTLIST_START ~ __ANYTHING
_ATTLIST_END ~ __ANYTHING
_CDATA ~ __ANYTHING
_ID ~ __ANYTHING
_IDREF ~ __ANYTHING
_IDREFS ~ __ANYTHING
_ENTITY ~ __ANYTHING
_ENTITIES ~ __ANYTHING
_NMTOKEN ~ __ANYTHING
_NMTOKENS ~ __ANYTHING
_NOTATION ~ __ANYTHING
_NOTATION_START ~ __ANYTHING
_NOTATION_END ~ __ANYTHING
_ENUMERATION_START ~ __ANYTHING
_ENUMERATION_END ~ __ANYTHING
_REQUIRED ~ __ANYTHING
_IMPLIED ~ __ANYTHING
_FIXED ~ __ANYTHING
_INCLUDE ~ __ANYTHING
_IGNORE ~ __ANYTHING
_INCLUDESECT_START ~ __ANYTHING
_INCLUDESECT_END ~ __ANYTHING
_IGNORESECT_START ~ __ANYTHING
_IGNORESECT_END ~ __ANYTHING
_IGNORESECTCONTENTSUNIT_START ~ __ANYTHING
_IGNORESECTCONTENTSUNIT_END ~ __ANYTHING
_CHARREF_START1 ~ __ANYTHING
_CHARREF_END1 ~ __ANYTHING
_CHARREF_START2 ~ __ANYTHING
_CHARREF_END2 ~ __ANYTHING
_ENTITYREF_START ~ __ANYTHING
_ENTITYREF_END ~ __ANYTHING
_PEREFERENCE_START ~ __ANYTHING
_PEREFERENCE_END ~ __ANYTHING
_ENTITY_START ~ __ANYTHING
_ENTITY_END ~ __ANYTHING
_PERCENT ~ __ANYTHING
_SYSTEM ~ __ANYTHING
_PUBLIC ~ __ANYTHING
_NDATA ~ __ANYTHING
_TEXTDECL_START ~ __ANYTHING
_TEXTDECL_END ~ __ANYTHING
_ENCODING ~ __ANYTHING
_NOTATIONDECL_START ~ __ANYTHING
_NOTATIONDECL_END ~ __ANYTHING

NAME ::= _NAME
NMTOKENMANY ::= _NMTOKENMANY
ENTITYVALUEINTERIORDQUOTEUNIT ::= _ENTITYVALUEINTERIORDQUOTEUNIT
ENTITYVALUEINTERIORSQUOTEUNIT ::= _ENTITYVALUEINTERIORSQUOTEUNIT
ATTVALUEINTERIORDQUOTEUNIT ::= _ATTVALUEINTERIORDQUOTEUNIT
ATTVALUEINTERIORSQUOTEUNIT ::= _ATTVALUEINTERIORSQUOTEUNIT
NOT_DQUOTEMANY ::= _NOT_DQUOTEMANY
NOT_SQUOTEMANY ::= _NOT_SQUOTEMANY
PUBIDCHARDQUOTE ::= _PUBIDCHARDQUOTE
PUBIDCHARSQUOTE ::= _PUBIDCHARSQUOTE
CHARDATAMANY ::= _CHARDATAMANY
COMMENTCHARMANY ::= _COMMENTCHARMANY
PITARGET ::= _PITARGET
CDATAMANY ::= _CDATAMANY
PICHARDATAMANY ::= _PICHARDATAMANY
IGNOREMANY ::= _IGNOREMANY
DIGITMANY ::= _DIGITMANY
ALPHAMANY ::= _ALPHAMANY
ENCNAME ::= _ENCNAME
S ::= _S
SPACE ::= _SPACE
DQUOTE ::= _DQUOTE
SQUOTE ::= _SQUOTE
COMMENT_START ::= _COMMENT_START
COMMENT_END ::= _COMMENT_END
PI_START ::= _PI_START
PI_END ::= _PI_END
CDATA_START ::= _CDATA_START
CDATA_END ::= _CDATA_END
XMLDECL_START ::= _XMLDECL_START
XMLDECL_END ::= _XMLDECL_END
VERSION ::= _VERSION
EQUAL ::= _EQUAL
VERSIONNUM ::= _VERSIONNUM
DOCTYPE_START ::= _DOCTYPE_START
DOCTYPE_END ::= _DOCTYPE_END
LBRACKET ::= _LBRACKET
RBRACKET ::= _RBRACKET
STANDALONE ::= _STANDALONE
YES ::= _YES
NO ::= _NO
ELEMENT_START ::= _ELEMENT_START
ELEMENT_END ::= _ELEMENT_END
ETAG_START ::= _ETAG_START
ETAG_END ::= _ETAG_END
EMPTYELEM_END ::= _EMPTYELEM_END
ELEMENTDECL_START ::= _ELEMENTDECL_START
ELEMENTDECL_END ::= _ELEMENTDECL_END
EMPTY ::= _EMPTY
ANY ::= _ANY
QUESTIONMARK ::= _QUESTIONMARK
STAR ::= _STAR
PLUS ::= _PLUS
OR ::= _OR
CHOICE_START ::= _CHOICE_START
CHOICE_END ::= _CHOICE_END
SEQ_START ::= _SEQ_START
SEQ_END ::= _SEQ_END
MIXED_START1 ::= _MIXED_START1
MIXED_END1 ::= _MIXED_END1
MIXED_START2 ::= _MIXED_START2
MIXED_END2 ::= _MIXED_END2
COMMA ::= _COMMA
PCDATA ::= _PCDATA
ATTLIST_START ::= _ATTLIST_START
ATTLIST_END ::= _ATTLIST_END
CDATA ::= _CDATA
ID ::= _ID
IDREF ::= _IDREF
IDREFS ::= _IDREFS
ENTITY ::= _ENTITY
ENTITIES ::= _ENTITIES
NMTOKEN ::= _NMTOKEN
NMTOKENS ::= _NMTOKENS
NOTATION ::= _NOTATION
NOTATION_START ::= _NOTATION_START
NOTATION_END ::= _NOTATION_END
ENUMERATION_START ::= _ENUMERATION_START
ENUMERATION_END ::= _ENUMERATION_END
REQUIRED ::= _REQUIRED
IMPLIED ::= _IMPLIED
FIXED ::= _FIXED
INCLUDE ::= _INCLUDE
IGNORE ::= _IGNORE
INCLUDESECT_START ::= _INCLUDESECT_START
INCLUDESECT_END ::= _INCLUDESECT_END
IGNORESECT_START ::= _IGNORESECT_START
IGNORESECT_END ::= _IGNORESECT_END
IGNORESECTCONTENTSUNIT_START ::= _IGNORESECTCONTENTSUNIT_START
IGNORESECTCONTENTSUNIT_END ::= _IGNORESECTCONTENTSUNIT_END
CHARREF_START1 ::= _CHARREF_START1
CHARREF_END1 ::= _CHARREF_END1
CHARREF_START2 ::= _CHARREF_START2
CHARREF_END2 ::= _CHARREF_END2
ENTITYREF_START ::= _ENTITYREF_START
ENTITYREF_END ::= _ENTITYREF_END
PEREFERENCE_START ::= _PEREFERENCE_START
PEREFERENCE_END ::= _PEREFERENCE_END
ENTITY_START ::= _ENTITY_START
ENTITY_END ::= _ENTITY_END
PERCENT ::= _PERCENT
SYSTEM ::= _SYSTEM
PUBLIC ::= _PUBLIC
NDATA ::= _NDATA
TEXTDECL_START ::= _TEXTDECL_START
TEXTDECL_END ::= _TEXTDECL_END
ENCODING ::= _ENCODING
NOTATIONDECL_START ::= _NOTATIONDECL_START
NOTATIONDECL_END ::= _NOTATIONDECL_END

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
