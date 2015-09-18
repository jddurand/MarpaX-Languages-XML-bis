package MarpaX::Languages::XML::Impl::Grammar;
use Carp qw/croak/;
use Data::Section -setup;
use Marpa::R2;
use MarpaX::Languages::XML::Exception;
# use MarpaX::Languages::XML::XS;
use MarpaX::Languages::XML::Impl::EntityRef;
use MarpaX::Languages::XML::Impl::PEReference;
use MarpaX::Languages::XML::Type::GrammarEvent -all;
use MarpaX::Languages::XML::Type::XmlVersion -all;
use MarpaX::Languages::XML::Type::XmlSupport -all;
use Moo;
use MooX::late;
use MooX::Role::Logger;
use MooX::HandlesVia;
use Scalar::Util qw/blessed reftype/;
use Types::Standard -all;

# ABSTRACT: MarpaX::Languages::XML::Role::Grammar implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is an implementation of MarpaX::Languages::XML::Role::Grammar. It provides Marpa::R2::Scanless::G's class attributes for XML versions 1.0 and 1.1.

=cut

has spec => (
             is     => 'ro',
             isa    => Str,
             writer => 'set_spec'
            );

#
# Character and entity references
#
has _entityref => (
                 is => 'rw',
                 isa => ConsumerOf['MarpaX::Languages::XML::Role::EntityRef'],
                 default => sub { return MarpaX::Languages::XML::Impl::EntityRef->new() }
                );
has _pereference => (
                 is => 'rw',
                 isa => ConsumerOf['MarpaX::Languages::XML::Role::PEReference'],
                 default => sub { return MarpaX::Languages::XML::Impl::PEReference->new() }
                );

has _attvalue_impl => (
                       is     => 'ro',
                       isa    => HashRef[CodeRef],
                       default => sub {
                         {
                           '1.0' => \&_attvalue_impl_xml10,
                           '1.1' => \&_attvalue_impl_xml11
                           }
                       },
                       handles_via => 'Hash',
                       handles => {
                                   _get__attvalue_impl  => 'get'
                                  }
                      );

has _eol => (
             is     => 'ro',
             isa    => HashRef[CodeRef],
             default => sub {
               {
                 '1.0' => \&_eol_xml10,
                 '1.1' => \&_eol_xml11
                 }
             },
             handles_via => 'Hash',
             handles => {
                         _get__eol  => 'get'
                        }
            );

has _eol_decl => (
                  is     => 'ro',
                  isa    => HashRef[CodeRef],
                  default => sub {
                    {
                      '1.0' => \&_eol_decl_xml10,
                      '1.1' => \&_eol_decl_xml11
                    }
                  },
                  handles_via => 'Hash',
                  handles => {
                              _get__eol_decl  => 'get'
                             }
            );

has scanless => (
                 is     => 'ro',
                 isa    => InstanceOf['Marpa::R2::Scanless::G'],
                 lazy  => 1,
                 builder => '_build_scanless'
                );

has xml_scanless => (
                     is     => 'ro',
                     isa    => InstanceOf['Marpa::R2::Scanless::G'],
                     lazy  => 1,
                     builder => '_build_xml_scanless'
                );

has xmlns_scanless => (
                       is     => 'ro',
                       isa    => InstanceOf['Marpa::R2::Scanless::G'],
                       lazy  => 1,
                       builder => '_build_xmlns_scanless'
                );

has lexeme_match => (
                      is  => 'ro',
                      isa => HashRef[RegexpRef],
                      lazy  => 1,
                      builder => '_build_lexeme_match',
                      handles_via => 'Hash',
                      handles => {
                                  elements_lexeme_match  => 'elements',
                                  keys_lexeme_match      => 'keys',
                                  set_lexeme_match       => 'set',
                                  get_lexeme_match       => 'get',
                                  exists_lexeme_match    => 'exists'
                                 }
                      );

has lexeme_match_by_symbol_ids => (
                      is  => 'ro',
                      isa => ArrayRef[RegexpRef|Undef],
                      lazy  => 1,
                      builder => '_build_lexeme_match_by_symbol_ids',
                      handles_via => 'Array',
                      handles => {
                                  elements_lexeme_match_by_symbol_ids  => 'elements',
                                  set_lexeme_match_by_symbol_ids       => 'set',
                                  get_lexeme_match_by_symbol_ids       => 'get'
                                 }
                      );

has lexeme_exclusion => (
                         is  => 'ro',
                         isa => HashRef[RegexpRef],
                         lazy  => 1,
                         builder => '_build_lexeme_exclusion',
                         handles_via => 'Hash',
                         handles => {
                                     elements_lexeme_exclusion => 'elements',
                                     keys_lexeme_exclusion     => 'keys',
                                     set_lexeme_exclusion      => 'set',
                                     get_lexeme_exclusion      => 'get',
                                     exists_lexeme_exclusion   => 'exists'
                                    }
                         );
has grammar_event => (
                      is  => 'ro',
                      isa => HashRef[GrammarEvent],
                      default => sub { {} },
                      handles_via => 'Hash',
                      handles => {
                                  elements_grammar_event => 'elements',
                                  keys_grammar_event     => 'keys',
                                  set_grammar_event      => 'set',
                                  get_grammar_event      => 'get',
                                  exists_grammar_event   => 'exists'
                                 }
                      );

has xml_version => (
                    is  => 'ro',
                    isa => XmlVersion,
                    default => '1.0'
                   );

has xml_support => (
                    is  => 'ro',
                    isa => XmlSupport,
                    default => 'xmlns'
                   );

has start => (
              is  => 'ro',
              isa => Str,
              default => 'document'
             );

our %XMLBNF = (
               '1.0' => __PACKAGE__->section_data('xml10'),
               '1.1' => __PACKAGE__->section_data('xml10')
              );

#
# xmlns parts are special in the __DATA__ section: they contain code that should be eval'ed
#
our %XMLNSBNF = (
               '1.0' => __PACKAGE__->section_data('xmlns10'),
               '1.1' => __PACKAGE__->section_data('xmlns10')
              );
our %XMLNSBNF_ADD = (
               '1.0' => __PACKAGE__->section_data('xmlns10:add'),
               '1.1' => __PACKAGE__->section_data('xmlns10:add')
              );
our %XMLNSBNF_REPLACE_OR_ADD = (
               '1.0' => __PACKAGE__->section_data('xmlns10:replace_or_add'),
               '1.1' => __PACKAGE__->section_data('xmlns10:replace_or_add')
              );
# Regexps:
# -------
# The *+ is important: it means match zero or more times and give nothing back
# The ++ is important: it means match one  or more times and give nothing back
#
our %LEXEME_MATCH_COMMON =
  (
   #
   # These are the lexemes of unknown size
   #
   _NAME                          => qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+}p,
   _NMTOKENMANY                   => qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]++}p,
   _ENTITYVALUEINTERIORDQUOTEUNIT => qr{\G[^%&"]++}p,
   _ENTITYVALUEINTERIORSQUOTEUNIT => qr{\G[^%&']++}p,
   _ATTVALUEINTERIORDQUOTEUNIT    => qr{\G[^<&"]++}p,
   _ATTVALUEINTERIORSQUOTEUNIT    => qr{\G[^<&']++}p,
   _NOT_DQUOTEMANY                => qr{\G[^"]++}p,
   _NOT_SQUOTEMANY                => qr{\G[^']++}p,
   _CHARDATAMANY                  => qr{\G(?:[^<&\]]|(?:\](?!\]>)))++}p, # [^<&]+ without ']]>'
   _COMMENTCHARMANY               => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{2C}\x{2E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\-(?!\-)))++}p,  # Char* without '--'
   _PITARGET                      => qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+}p,  # NAME but /xml/i - c.f. exclusion hash
   _CDATAMANY                     => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{5C}\x{5E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\](?!\]>)))++}p,  # Char* minus ']]>'
   _PICHARDATAMANY                => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{3E}\x{40}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\?(?!>)))++}p,  # Char* minus '?>'
   _IGNOREMANY                    => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{3B}\x{3D}-\x{5C}\x{5E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:<(?!!\[))|(?:\](?!\]>)))++}p,  # Char minus* ('<![' or ']]>')
   _DIGITMANY                     => qr{\G[0-9]++}p,
   _ALPHAMANY                     => qr{\G[0-9a-fA-F]++}p,
   _ENCNAME                       => qr{\G[A-Za-z][A-Za-z0-9._\-]*+}p,
   _S                             => qr{\G[\x{20}\x{9}\x{D}\x{A}]++}p,
   #
   # An NCNAME is a NAME minus the ':'
   #
   _NCNAME                        => qr{\G[A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+}p,
   #
   # These are the lexemes of predicted size
   #
   _PUBIDCHARDQUOTEMANY           => qr{\G[a-zA-Z0-9\-'()+,./:=?;!*#@\$_%\x{20}\x{D}\x{A}]++}p,
   _PUBIDCHARSQUOTEMANY           => qr{\G[a-zA-Z0-9\-()+,./:=?;!*#@\$_%\x{20}\x{D}\x{A}]++}p,
   _SPACE                         => qr{\G\x{20}}p,
   _DQUOTE                        => qr{\G"}p,
   _SQUOTE                        => qr{\G'}p,
   _COMMENT_START                 => qr{\G<!\-\-}p,
   _COMMENT_END                   => qr{\G\-\->}p,
   _PI_START                      => qr{\G<\?}p,
   _PI_END                        => qr{\G\?>}p,
   _CDATA_START                   => qr{\G<!\[CDATA\[}p,
   _CDATA_END                     => qr{\G\]\]>}p,
   _XMLDECL_START                 => qr{\G<\?xml}p,
   _XMLDECL_END                   => qr{\G\?>}p,
   _VERSION                       => qr{\Gversion}p,
   _EQUAL                         => qr{\G=}p,
   _VERSIONNUM                    => qr{\G1\.[01]}p,            # We want to catch all possible versions so that we can retry the parser
   _DOCTYPE_START                 => qr{\G<!DOCTYPE}p,
   _DOCTYPE_END                   => qr{\G>}p,
   _LBRACKET                      => qr{\G\[}p,
   _RBRACKET                      => qr{\G\]}p,
   _STANDALONE                    => qr{\Gstandalone}p,
   _YES                           => qr{\Gyes}p,
   _NO                            => qr{\Gno}p,
   _ELEMENT_START                 => qr{\G<}p,
   _ELEMENT_END                   => qr{\G>}p,
   _ETAG_START                    => qr{\G</}p,
   _ETAG_END                      => qr{\G>}p,
   _EMPTYELEM_END                 => qr{\G/>}p,
   _ELEMENTDECL_START             => qr{\G<!ELEMENT}p,
   _ELEMENTDECL_END               => qr{\G>}p,
   _EMPTY                         => qr{\GEMPTY}p,
   _ANY                           => qr{\GANY}p,
   _QUESTIONMARK                  => qr{\G\?}p,
   _STAR                          => qr{\G\*}p,
   _PLUS                          => qr{\G\+}p,
   _OR                            => qr{\G\|}p,
   _CHOICE_START                  => qr{\G\(}p,
   _CHOICE_END                    => qr{\G\)}p,
   _SEQ_START                     => qr{\G\(}p,
   _SEQ_END                       => qr{\G\)}p,
   _MIXED_START                   => qr{\G\(}p,
   _MIXED_END1                    => qr{\G\)\*}p,
   _MIXED_END2                    => qr{\G\)}p,
   _COMMA                         => qr{\G,}p,
   _PCDATA                        => qr{\G#PCDATA}p,
   _ATTLIST_START                 => qr{\G<!ATTLIST}p,
   _ATTLIST_END                   => qr{\G>}p,
   _CDATA                         => qr{\GCDATA}p,
   _ID                            => qr{\GID}p,
   _IDREF                         => qr{\GIDREF}p,
   _IDREFS                        => qr{\GIDREFS}p,
   _ENTITY                        => qr{\GENTITY}p,
   _ENTITIES                      => qr{\GENTITIES}p,
   _NMTOKEN                       => qr{\GNMTOKEN}p,
   _NMTOKENS                      => qr{\GNMTOKENS}p,
   _NOTATION                      => qr{\GNOTATION}p,
   _NOTATION_START                => qr{\G\(}p,
   _NOTATION_END                  => qr{\G\)}p,
   _ENUMERATION_START             => qr{\G\(}p,
   _ENUMERATION_END               => qr{\G\)}p,
   _REQUIRED                      => qr{\G#REQUIRED}p,
   _IMPLIED                       => qr{\G#IMPLIED}p,
   _FIXED                         => qr{\G#FIXED}p,
   _INCLUDE                       => qr{\GINCLUDE}p,
   _IGNORE                        => qr{\GIGNORE}p,
   _INCLUDESECT_START             => qr{\G<!\[}p,
   _INCLUDESECT_END               => qr{\G\]\]>}p,
   _IGNORESECT_START              => qr{\G<!\[}p,
   _IGNORESECT_END                => qr{\G\]\]>}p,
   _IGNORESECTCONTENTSUNIT_START  => qr{\G<!\[}p,
   _IGNORESECTCONTENTSUNIT_END    => qr{\G\]\]>}p,
   _CHARREF_START1                => qr{\G&#}p,
   _CHARREF_END1                  => qr{\G;}p,
   _CHARREF_START2                => qr{\G&#x}p,
   _CHARREF_END2                  => qr{\G;}p,
   _ENTITYREF_START               => qr{\G&}p,
   _ENTITYREF_END                 => qr{\G;}p,
   _PEREFERENCE_START             => qr{\G%}p,
   _PEREFERENCE_END               => qr{\G;}p,
   _ENTITY_START                  => qr{\G<!ENTITY}p,
   _ENTITY_END                    => qr{\G>}p,
   _PERCENT                       => qr{\G%}p,
   _SYSTEM                        => qr{\GSYSTEM}p,
   _PUBLIC                        => qr{\GPUBLIC}p,
   _NDATA                         => qr{\GNDATA}p,
   _TEXTDECL_START                => qr{\G<\?xml}p,
   _TEXTDECL_END                  => qr{\G\?>}p,
   _ENCODING                      => qr{\Gencoding}p,
   _NOTATIONDECL_START            => qr{\G<!NOTATION}p,
   _NOTATIONDECL_END              => qr{\G>}p,
   _COLON                         => qr{\G:}p,
   _XMLNSCOLON                    => qr{\Gxmlns:}p,
   _XMLNS                         => qr{\Gxmlns}p,
  );

our %LEXEME_MATCH=
  (
   '1.0' => \%LEXEME_MATCH_COMMON,
   '1.1' => \%LEXEME_MATCH_COMMON,
  );

our %LEXEME_EXCLUSION_COMMON =
  (
   _PITARGET => qr{^xml$}i,
  );


our %LEXEME_EXCLUSION =
  (
   '1.0' => \%LEXEME_EXCLUSION_COMMON,
   '1.1' => \%LEXEME_EXCLUSION_COMMON,
  );

sub _build_lexeme_match {
  my ($self) = @_;

  return $LEXEME_MATCH{$self->xml_version};
}

sub _build_lexeme_exclusion {
  my ($self) = @_;

  return $LEXEME_EXCLUSION{$self->xml_version};
}

sub _build_xmlns_scanless {
  my ($self) = @_;

  #
  # Manipulate DATA section: revisit the start
  #
  my $data = ${$XMLBNF{$self->xml_version}};
  my $start = $self->start;
  $data =~ s/\$START/$start/sxmg;
  #
  # Apply xmlns specific transformations. This should never croak.
  #
  my $add            = ${$XMLNSBNF_ADD{$self->xml_version}};
  my $replace_or_add = ${$XMLNSBNF_REPLACE_OR_ADD{$self->xml_version}};
  #
  # Every rule in the $replace_or_add is removed from $data
  #
  my @rules_to_remove = ();
  while ($replace_or_add =~ m/^\w+/mgp) {
    push(@rules_to_remove, ${^MATCH});
  }
  foreach (@rules_to_remove) {
    $data =~ s/^$_\s*::=.*$//mg;
  }
  #
  # Add everything
  #
  $data .= $add;
  $data .= $replace_or_add;

  return $self->_scanless($data, 'xmlns');
}

sub _scanless {
  my ($self, $data, $spec) = @_;
  #
  # Set spec
  #
  $self->set_spec($spec);
  #
  # Add events
  #
  foreach ($self->keys_grammar_event) {
    #
    # Only G1-style events are supported
    #
    my $grammar_event = $self->get_grammar_event($_);
    my $symbol_name = $grammar_event->{symbol_name};
    my $type        = $grammar_event->{type};
    my $lexeme      = $grammar_event->{lexeme};

    if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
      $self->_logger->tracef('%s/%s/%s: Adding event %s on symbol %s type %s', $spec, $self->xml_version, $self->start, $_, $symbol_name, $type);
    }
    $data .= "event '$_' = $type <$symbol_name>\n";
  }
  #
  # Generate the grammar
  #
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('%s/%s/%s: Instanciating grammar', $spec, $self->xml_version, $self->start);
  }

  return Marpa::R2::Scanless::G->new({source => \$data});
}

sub _build_lexeme_match_by_symbol_ids {
  my ($self) = @_;

  my $symbol_by_name_hash = $self->scanless->symbol_by_name_hash;
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('%s/%s/%s: Symbol By Name: %s', $self->spec, $self->xml_version, $self->start, $symbol_by_name_hash);
  }
  #
  # Build the regexp list as an array using symbol ids as indice
  #
  my @array = ();
  foreach (keys %{$symbol_by_name_hash}) {
    if ($self->exists_lexeme_match($_)) {
      $array[$symbol_by_name_hash->{$_}] = $self->get_lexeme_match($_);
    }
  }
  return \@array;
}

sub _build_xml_scanless {
  my ($self) = @_;

  #
  # Manipulate DATA section: revisit the start
  #
  my $data = ${$XMLBNF{$self->xml_version}};
  my $start = $self->start;
  $data =~ s/\$START/$start/sxmg;

  return $self->_scanless($data, 'xml');
}

sub _build_scanless {
  my $self = shift;

  my $xml_support = $self->xml_support;
  my $method = $xml_support . '_scanless';

  return $self->$method(@_);
}

#
# End-of-line handling in a declaration
# --------------------------------------
sub _eol_decl_xml10 {
  #
  # XML 1.0 has no decl dependency
  #
  my $self = shift;
  return $self->_eol_xml10(@_);
}

sub _eol_decl_xml11 {
  my ($self, undef, $eof, $error_message_ref) = @_; # Buffer is in $_[1]

  if ($_[1] =~ /[\x{85}\x{2028}]/) {
    ${$error_message_ref} = "Invalid character \\x{" . sprintf('%X', ord(substr($_[1], $+[0], $+[0] - $-[0]))) . "}";
    return -1;
  }

  #
  # The rest is shared between decl and non decl modes
  #
  return $self->_eol_xml11($_[1], $eof, $error_message_ref);
}

#
# Note: it is expected that the caller never call eol on an empty buffer.
# Then it is guaranteed that eol never returns a value <= 0.
#
sub eol_decl {
  my $self = shift;
  my $coderef = $self->_get__eol_decl($self->xml_version);
  return $self->$coderef(@_);
}

#
# End-of-line handling outside of a declaration
# ---------------------------------------------
sub _eol_xml10 {
  my ($self, undef, $eof, $error_message_ref) = @_;
  # Buffer is in $_[1]

  #
  # If last character is a \x{D} this is undecidable unless eof flag
  #
  if (substr($_[1], -1, 1) eq "\x{D}") {
    if (! $eof) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
        $self->_logger->tracef('%s/%s: Last character in buffer is \\x{D} and requires another read', $self->xml_version, $self->start);
      }
      return 0;
    }
  }
  $_[1] =~ s/\x{D}\x{A}/\x{A}/g;
  $_[1] =~ s/\x{D}/\x{A}/g;

  return length($_[1]);
}

sub _eol_xml11 {
  my ($self, undef, $eof, $error_message_ref) = @_; # Buffer is in $_[1]

  #
  # If last character is a \x{D} this is undecidable unless eof flag
  #
  if (substr($_[1], -1, 1) eq "\x{D}") {
    if (! $eof) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
        $self->_logger->tracef('%s/%s: Last character in buffer is \\x{D} and requires another read', $self->xml_version, $self->start);
      }
      return 0;
    }
  }
  $_[1] =~ s/\x{D}\x{A}/\x{A}/g;
  $_[1] =~ s/\x{D}\x{85}/\x{A}/g;
  $_[1] =~ s/\x{85}/\x{A}/g;
  $_[1] =~ s/\x{2028}/\x{A}/g;
  $_[1] =~ s/\x{D}/\x{A}/g;

  return length($_[1]);
}

#
# Note: it is expected that the caller never call eol on an empty buffer.
# Then it is guaranteed that eol never returns a value <= 0.
#
sub eol {
  #
  # Here is how I would do params validation
  # CORE::state $check = compile(ConsumerOf['MarpaX::Languages::XML::Role::Grammar'],
  #                                       Str,
  #                                       Bool,
  #                                       Str,
  #                                       ScalarRef);
  # $check->(@_);
  my $self = shift;
  my $coderef = $self->_get__eol($self->xml_version);
  return $self->$coderef(@_);
}

#
# Normalization: XML1.0 and XML1.1 share the same algorithm
# ---------------------------------------------------------
# This routine is used Parse.pm's _generic_parse() callbacks
# so it is optimized as much as possible
#
sub _attvalue_impl_common {
  # my ($self, $cdata, @elements) = @_;
  #
  # @_ is an array describing attvalue:
  # if not a ref, this is char
  # if a ref, this is an entuty reference
  #
  # 1. All line breaks must have been normalized on input to #xA as described in 2.11 End-of-Line Handling, so the rest of this algorithm operates on text normalized in this way.
  #
  # 2. Begin with a normalized value consisting of the empty string.
  #
  my $attvalue = '';
  #
  # 3. For each character, entity reference, or character reference in the unnormalized attribute value, beginning with the first and continuing to the last, do the following:
  #
  foreach (@_[2..$#_]) {
    #
    # For a character reference, append the referenced character to the normalized value.
    # In our case this is done by the parser when pushing.
    #
    if (ref($_)) { # ref() is faster
      #
      # For an entity reference, recursively apply step 3 of this algorithm to the replacement text of the entity.
      # EntityRef case.
      #
      my $c = $_[0]->attvalue($_[1], $_[0]->{_entityref}->{$_});
      #
      # It is illegal to have '<' as a replacement character except if it comes from &lt;
      # which is considered as a string in the XML spec
      # C.f. section 2.4 Character Data and Markup
      #
        croak "Entity $_ resolves to '<' but Well-formedness constraint says: No < in Attribute Values";
      if (($c eq '<') && ($_ ne 'lt')) {
      }
      $attvalue .= $_[0]->attvalue($_[1], $_[0]->{_entityref}->{$_});
    } elsif (($_ eq "\x{20}") || ($_ eq "\x{D}") || ($_ eq "\x{A}") || ($_ eq "\x{9}")) {
      #
      # For a white space character (#x20, #xD, #xA, #x9), append a space character (#x20) to the normalized value.
      #
      $attvalue .= "\x{20}";
    } else {
      #
      # For another character, append the character to the normalized value.
      #
      $attvalue .= $_;
    }
  }
  #
  # If the attribute type is not CDATA, then the XML processor must further process the normalized attribute value by discarding any leading and trailing space (#x20) characters, and by replacing sequences of space (#x20) characters by a single space (#x20) character.
  #
  if (! $_[1]) {
    $attvalue =~ s/\A\x{20}+//;
    $attvalue =~ s/\x{20}+\z//;
    $attvalue =~ s/\x{20}+/\x{20}/g;
  }

  return $attvalue;
}

sub _attvalue_impl_xml10 {
  goto &_attvalue_impl_common;
}
sub _attvalue_impl_xml11 {
  goto &_attvalue_impl_common;
}
sub attvalue_impl {
  my ($self) = @_;

  return $self->_get__attvalue_impl($self->xml_version);
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
document                      ::= (internal_event_for_immediate_pause) (start_document) prolog element MiscAny
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
PubidCharDquoteMany           ::= PUBIDCHARDQUOTEMANY
PubidCharSquoteMany           ::= PUBIDCHARSQUOTEMANY
PubidLiteral                  ::= DQUOTE PubidCharDquoteMany DQUOTE
                                | DQUOTE                     DQUOTE
                                | SQUOTE PubidCharSquoteMany SQUOTE
                                | SQUOTE                     SQUOTE

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
prolog                        ::= XMLDecl MiscAny
prolog                        ::=         MiscAny
prolog                        ::= XMLDecl MiscAny doctypedecl MiscAny
prolog                        ::=         MiscAny doctypedecl MiscAny
XMLDecl                       ::= XMLDECL_START VersionInfo EncodingDecl SDDecl S XMLDECL_END
XMLDecl                       ::= XMLDECL_START VersionInfo EncodingDecl SDDecl   XMLDECL_END
XMLDecl                       ::= XMLDECL_START VersionInfo EncodingDecl        S XMLDECL_END
XMLDecl                       ::= XMLDECL_START VersionInfo EncodingDecl          XMLDECL_END
XMLDecl                       ::= XMLDECL_START VersionInfo              SDDecl S XMLDECL_END
XMLDecl                       ::= XMLDECL_START VersionInfo              SDDecl   XMLDECL_END
XMLDecl                       ::= XMLDECL_START VersionInfo                     S XMLDECL_END
XMLDecl                       ::= XMLDECL_START VersionInfo                       XMLDECL_END
VersionInfo                   ::= S VERSION Eq SQUOTE VersionNum SQUOTE
VersionInfo                   ::= S VERSION Eq DQUOTE VersionNum DQUOTE
Eq                            ::= S EQUAL S
Eq                            ::= S EQUAL
Eq                            ::=   EQUAL S
Eq                            ::=   EQUAL
VersionNum                    ::= VERSIONNUM
Misc                          ::= Comment | PI | S
doctypedecl                   ::= DOCTYPE_START S Name              S LBRACKET intSubset RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name              S LBRACKET intSubset RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name                LBRACKET intSubset RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name                LBRACKET intSubset RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name              S                               DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name                                              DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name S ExternalID S LBRACKET intSubset RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name S ExternalID S LBRACKET intSubset RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name S ExternalID   LBRACKET intSubset RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name S ExternalID   LBRACKET intSubset RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name S ExternalID S                               DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl                   ::= DOCTYPE_START S Name S ExternalID                                 DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
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
extSubset                     ::= TextDecl extSubsetDecl
extSubset                     ::=          extSubsetDecl
extSubsetDeclUnit             ::= markupdecl | conditionalSect | DeclSep
extSubsetDecl                 ::= extSubsetDeclUnit*
SDDecl                        ::= S STANDALONE Eq SQUOTE YES SQUOTE # [VC: Standalone Document Declaration]
                                | S STANDALONE Eq SQUOTE  NO SQUOTE  # [VC: Standalone Document Declaration]
                                | S STANDALONE Eq DQUOTE YES DQUOTE  # [VC: Standalone Document Declaration]
                                | S STANDALONE Eq DQUOTE  NO DQUOTE  # [VC: Standalone Document Declaration]
element                       ::= (internal_event_for_immediate_pause) EmptyElemTag (start_element) (end_element)
                                | (internal_event_for_immediate_pause) STag (start_element) content ETag (end_element) # [WFC: Element Type Match] [VC: Element Valid]
STagUnit                      ::= S Attribute
STagUnitAny                   ::= STagUnit*
STagName                      ::= Name
STag                          ::= ELEMENT_START STagName STagUnitAny S ELEMENT_END # [WFC: Unique Att Spec]
STag                          ::= ELEMENT_START STagName STagUnitAny   ELEMENT_END # [WFC: Unique Att Spec]
AttributeName                 ::= Name
Attribute                     ::= AttributeName Eq AttValue  # [VC: Attribute Value Type] [WFC: No External Entity References] [WFC: No < in Attribute Values]
ETag                          ::= ETAG_START Name S ETAG_END
ETag                          ::= ETAG_START Name   ETAG_END
contentUnit                   ::= element CharData
                                | element
                                | Reference CharData
                                | Reference
                                | CDSect CharData
                                | CDSect
                                | PI CharData
                                | PI
                                | Comment CharData
                                | Comment
contentUnitAny                ::= contentUnit*
content                       ::= CharData contentUnitAny
content                       ::=          contentUnitAny
EmptyElemTagUnit              ::= S Attribute
EmptyElemTagUnitAny           ::= EmptyElemTagUnit*
EmptyElemTag                  ::= ELEMENT_START Name EmptyElemTagUnitAny S EMPTYELEM_END   # [WFC: Unique Att Spec]
EmptyElemTag                  ::= ELEMENT_START Name EmptyElemTagUnitAny   EMPTYELEM_END   # [WFC: Unique Att Spec]
elementdecl                   ::= ELEMENTDECL_START S Name S contentspec S ELEMENTDECL_END # [VC: Unique Element Type Declaration]
elementdecl                   ::= ELEMENTDECL_START S Name S contentspec   ELEMENTDECL_END # [VC: Unique Element Type Declaration]
contentspec                   ::= EMPTY | ANY | Mixed | children
ChoiceOrSeq                   ::= choice | seq
children                      ::= ChoiceOrSeq
                                | ChoiceOrSeq QUESTIONMARK
                                | ChoiceOrSeq STAR
                                | ChoiceOrSeq PLUS
#
# Writen like this for the merged of XML+NS
#
NameOrChoiceOrSeq             ::= Name
NameOrChoiceOrSeq             ::= choice
NameOrChoiceOrSeq             ::= seq
cp                            ::= NameOrChoiceOrSeq
                                | NameOrChoiceOrSeq QUESTIONMARK
                                | NameOrChoiceOrSeq STAR
                                | NameOrChoiceOrSeq PLUS
choiceUnit                    ::= S OR S cp
choiceUnit                    ::= S OR   cp
choiceUnit                    ::=   OR S cp
choiceUnit                    ::=   OR   cp
choiceUnitMany                ::= choiceUnit+
choice                        ::= CHOICE_START S cp choiceUnitMany S CHOICE_END # [VC: Proper Group/PE Nesting]
choice                        ::= CHOICE_START S cp choiceUnitMany   CHOICE_END # [VC: Proper Group/PE Nesting]
choice                        ::= CHOICE_START   cp choiceUnitMany S CHOICE_END # [VC: Proper Group/PE Nesting]
choice                        ::= CHOICE_START   cp choiceUnitMany   CHOICE_END # [VC: Proper Group/PE Nesting]
seqUnit                       ::= S COMMA S cp
seqUnit                       ::= S COMMA   cp
seqUnit                       ::=   COMMA S cp
seqUnit                       ::=   COMMA   cp
seqUnitAny                    ::= seqUnit*
seq                           ::= SEQ_START S cp seqUnitAny S SEQ_END # [VC: Proper Group/PE Nesting]
seq                           ::= SEQ_START S cp seqUnitAny   SEQ_END # [VC: Proper Group/PE Nesting]
seq                           ::= SEQ_START   cp seqUnitAny S SEQ_END # [VC: Proper Group/PE Nesting]
seq                           ::= SEQ_START   cp seqUnitAny   SEQ_END # [VC: Proper Group/PE Nesting]
MixedUnit                     ::= S OR S Name
MixedUnit                     ::= S OR   Name
MixedUnit                     ::=   OR S Name
MixedUnit                     ::=   OR   Name
MixedUnitAny                  ::= MixedUnit*
Mixed                         ::= MIXED_START S PCDATA MixedUnitAny S MIXED_END1 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START S PCDATA MixedUnitAny   MIXED_END1 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START   PCDATA MixedUnitAny S MIXED_END1 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START   PCDATA MixedUnitAny   MIXED_END1 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START S PCDATA              S MIXED_END2 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START S PCDATA                MIXED_END2 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START   PCDATA              S MIXED_END2 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
                                | MIXED_START   PCDATA                MIXED_END2 # [VC: Proper Group/PE Nesting] [VC: No Duplicate Types]
AttlistDecl                   ::= ATTLIST_START S Name AttDefAny S ATTLIST_END
AttlistDecl                   ::= ATTLIST_START S Name AttDefAny   ATTLIST_END
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
NotationTypeUnit              ::= S OR S Name
NotationTypeUnit              ::= S OR   Name
NotationTypeUnit              ::=   OR S Name
NotationTypeUnit              ::=   OR   Name
NotationTypeUnitAny           ::= NotationTypeUnit*
NotationType                  ::= NOTATION S NOTATION_START S Name NotationTypeUnitAny S NOTATION_END # [VC: Notation Attributes] [VC: One Notation Per Element Type] [VC: No Notation on Empty Element] [VC: No Duplicate Tokens]
NotationType                  ::= NOTATION S NOTATION_START S Name NotationTypeUnitAny   NOTATION_END # [VC: Notation Attributes] [VC: One Notation Per Element Type] [VC: No Notation on Empty Element] [VC: No Duplicate Tokens]
NotationType                  ::= NOTATION S NOTATION_START   Name NotationTypeUnitAny S NOTATION_END # [VC: Notation Attributes] [VC: One Notation Per Element Type] [VC: No Notation on Empty Element] [VC: No Duplicate Tokens]
NotationType                  ::= NOTATION S NOTATION_START   Name NotationTypeUnitAny   NOTATION_END # [VC: Notation Attributes] [VC: One Notation Per Element Type] [VC: No Notation on Empty Element] [VC: No Duplicate Tokens]
EnumerationUnit               ::= S OR S Nmtoken
EnumerationUnit               ::= S OR   Nmtoken
EnumerationUnit               ::=   OR S Nmtoken
EnumerationUnit               ::=   OR   Nmtoken
EnumerationUnitAny            ::= EnumerationUnit*
Enumeration                   ::= ENUMERATION_START S Nmtoken EnumerationUnitAny S ENUMERATION_END # [VC: Enumeration] [VC: No Duplicate Tokens]
Enumeration                   ::= ENUMERATION_START S Nmtoken EnumerationUnitAny   ENUMERATION_END # [VC: Enumeration] [VC: No Duplicate Tokens]
Enumeration                   ::= ENUMERATION_START   Nmtoken EnumerationUnitAny S ENUMERATION_END # [VC: Enumeration] [VC: No Duplicate Tokens]
Enumeration                   ::= ENUMERATION_START   Nmtoken EnumerationUnitAny   ENUMERATION_END # [VC: Enumeration] [VC: No Duplicate Tokens]
DefaultDecl                   ::= REQUIRED | IMPLIED
                                |            AttValue                              # [VC: Required Attribute] [VC: Attribute Default Value Syntactically Correct] [WFC: No < in Attribute Values] [VC: Fixed Attribute Default] [WFC: No External Entity References]
                                | FIXED S AttValue                              # [VC: Required Attribute] [VC: Attribute Default Value Syntactically Correct] [WFC: No < in Attribute Values] [VC: Fixed Attribute Default] [WFC: No External Entity References]
conditionalSect               ::= includeSect | ignoreSect
includeSect                   ::= INCLUDESECT_START S INCLUDE S LBRACKET extSubsetDecl          INCLUDESECT_END # [VC: Proper Conditional Section/PE Nesting]
includeSect                   ::= INCLUDESECT_START S INCLUDE   LBRACKET extSubsetDecl          INCLUDESECT_END # [VC: Proper Conditional Section/PE Nesting]
includeSect                   ::= INCLUDESECT_START   INCLUDE S LBRACKET extSubsetDecl          INCLUDESECT_END # [VC: Proper Conditional Section/PE Nesting]
includeSect                   ::= INCLUDESECT_START   INCLUDE   LBRACKET extSubsetDecl          INCLUDESECT_END # [VC: Proper Conditional Section/PE Nesting]
ignoreSect                    ::= IGNORESECT_START S  IGNORE  S LBRACKET ignoreSectContentsAny  IGNORESECT_END
                                | IGNORESECT_START S  IGNORE    LBRACKET ignoreSectContentsAny  IGNORESECT_END
                                | IGNORESECT_START    IGNORE  S LBRACKET ignoreSectContentsAny  IGNORESECT_END
                                | IGNORESECT_START    IGNORE    LBRACKET ignoreSectContentsAny  IGNORESECT_END
                                | IGNORESECT_START S  IGNORE  S LBRACKET                        IGNORESECT_END # [VC: Proper Conditional Section/PE Nesting]
                                | IGNORESECT_START S  IGNORE    LBRACKET                        IGNORESECT_END # [VC: Proper Conditional Section/PE Nesting]
                                | IGNORESECT_START    IGNORE  S LBRACKET                        IGNORESECT_END # [VC: Proper Conditional Section/PE Nesting]
                                | IGNORESECT_START    IGNORE    LBRACKET                        IGNORESECT_END # [VC: Proper Conditional Section/PE Nesting]
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
GEDecl                        ::= ENTITY_START S           Name S EntityDef S ENTITY_END
GEDecl                        ::= ENTITY_START S           Name S EntityDef   ENTITY_END
PEDecl                        ::= ENTITY_START S PERCENT S Name S PEDef     S ENTITY_END
PEDecl                        ::= ENTITY_START S PERCENT S Name S PEDef       ENTITY_END
EntityDef                     ::= EntityValue
                                | ExternalID
                                | ExternalID NDataDecl
PEDef                         ::= EntityValue
                                | ExternalID
ExternalID                    ::= SYSTEM S                SystemLiteral
                                | PUBLIC S PubidLiteral S SystemLiteral
NDataDecl                     ::= S NDATA S Name  # [VC: Notation Declared]
TextDecl                      ::= TEXTDECL_START VersionInfo EncodingDecl S TEXTDECL_END
TextDecl                      ::= TEXTDECL_START VersionInfo EncodingDecl   TEXTDECL_END
TextDecl                      ::= TEXTDECL_START             EncodingDecl S TEXTDECL_END
TextDecl                      ::= TEXTDECL_START             EncodingDecl   TEXTDECL_END
extParsedEnt                  ::= TextDecl content
extParsedEnt                  ::=          content
EncodingDecl                  ::= S ENCODING Eq DQUOTE EncName DQUOTE
EncodingDecl                  ::= S ENCODING Eq SQUOTE EncName SQUOTE
EncName                       ::= ENCNAME
NotationDecl                  ::= NOTATIONDECL_START S Name S ExternalID S NOTATIONDECL_END # [VC: Unique Notation Name]
NotationDecl                  ::= NOTATIONDECL_START S Name S ExternalID   NOTATIONDECL_END # [VC: Unique Notation Name]
NotationDecl                  ::= NOTATIONDECL_START S Name S   PublicID S NOTATIONDECL_END # [VC: Unique Notation Name]
NotationDecl                  ::= NOTATIONDECL_START S Name S   PublicID   NOTATIONDECL_END # [VC: Unique Notation Name]
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
_NCNAME ~ __ANYTHING
_PUBIDCHARDQUOTEMANY ~ __ANYTHING
_PUBIDCHARSQUOTEMANY ~ __ANYTHING
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
_MIXED_START ~ __ANYTHING
_MIXED_END1 ~ __ANYTHING
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
# :lexeme ~ <_XMLNSCOLON> priority => 1         # C.f. in Parser.pm
_XMLNSCOLON ~ __ANYTHING
# :lexeme ~ <_XMLNS> priority => 1              # C.f. in Parser.pm
_XMLNS ~ __ANYTHING
_COLON ~ __ANYTHING

NAME ::= _NAME
NMTOKENMANY ::= _NMTOKENMANY
ENTITYVALUEINTERIORDQUOTEUNIT ::= _ENTITYVALUEINTERIORDQUOTEUNIT
ENTITYVALUEINTERIORSQUOTEUNIT ::= _ENTITYVALUEINTERIORSQUOTEUNIT
ATTVALUEINTERIORDQUOTEUNIT ::= _ATTVALUEINTERIORDQUOTEUNIT
ATTVALUEINTERIORSQUOTEUNIT ::= _ATTVALUEINTERIORSQUOTEUNIT
NOT_DQUOTEMANY ::= _NOT_DQUOTEMANY
NOT_SQUOTEMANY ::= _NOT_SQUOTEMANY
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
NCNAME ::= _NCNAME
PUBIDCHARDQUOTEMANY ::= _PUBIDCHARDQUOTEMANY
PUBIDCHARSQUOTEMANY ::= _PUBIDCHARSQUOTEMANY
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
MIXED_START ::= _MIXED_START
MIXED_END1 ::= _MIXED_END1
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
XMLNSCOLON ::= _XMLNSCOLON
XMLNS ::= _XMLNS
COLON ::= _COLON

#
# Internal nullable rule to force the recognizer to stop immeidately,
# before reading any lexeme
#
event '!internal_event_for_immediate_pause' = nulled <internal_event_for_immediate_pause>
internal_event_for_immediate_pause ::= ;
#
# SAX nullable rules
#
start_document ::= ;
start_element  ::= ;
end_element    ::= ;
comment        ::= ;
#
# Events are added on-the-fly
#
__[ xmlns10:add ]__
NSAttName	   ::= PrefixedAttName (prefixed_attname)
                     | DefaultAttName (default_attname)
PrefixedAttName    ::= XMLNSCOLON NCName # [NSC: Reserved Prefixes and Namespace Names]
DefaultAttName     ::= XMLNS
NCName             ::= NCNAME            # Name - (Char* ':' Char*) /* An XML Name, minus the ":" */
QName              ::= PrefixedName (prefixed_name)
                     | UnprefixedName (unprefixed_name)
PrefixedName       ::= Prefix COLON LocalPart
UnprefixedName     ::= LocalPart
Prefix             ::= NCName
LocalPart          ::= NCName

__[ xmlns10:replace_or_add ]__
STag               ::= ELEMENT_START QName STagUnitAny S ELEMENT_END           # [NSC: Prefix Declared]
STag               ::= ELEMENT_START QName STagUnitAny   ELEMENT_END           # [NSC: Prefix Declared]
ETag               ::= ETAG_START QName S ETAG_END                             # [NSC: Prefix Declared]
ETag               ::= ETAG_START QName   ETAG_END                             # [NSC: Prefix Declared]
EmptyElemTag       ::= ELEMENT_START QName EmptyElemTagUnitAny S EMPTYELEM_END # [NSC: Prefix Declared]
EmptyElemTag       ::= ELEMENT_START QName EmptyElemTagUnitAny   EMPTYELEM_END # [NSC: Prefix Declared]
Attribute          ::= NSAttName (xmlns_attribute) Eq AttValue
Attribute          ::= QName (normal_attribute) Eq AttValue                                            # [NSC: Prefix Declared][NSC: No Prefix Undeclaring][NSC: Attributes Unique]
doctypedeclUnit    ::= markupdecl | PEReference | S
doctypedeclUnitAny ::= doctypedeclUnit*
doctypedecl        ::= DOCTYPE_START S QName              S LBRACKET doctypedeclUnitAny RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName              S LBRACKET doctypedeclUnitAny RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName                LBRACKET doctypedeclUnitAny RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName                LBRACKET doctypedeclUnitAny RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName              S                                        DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName                                                       DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID S LBRACKET doctypedeclUnitAny RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID S LBRACKET doctypedeclUnitAny RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID   LBRACKET doctypedeclUnitAny RBRACKET S DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID   LBRACKET doctypedeclUnitAny RBRACKET   DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID S                                        DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
doctypedecl        ::= DOCTYPE_START S QName S ExternalID                                          DOCTYPE_END # [VC: Root Element Type] [WFC: External Subset]
elementdecl        ::= ELEMENTDECL_START S QName S contentspec S ELEMENTDECL_END
elementdecl        ::= ELEMENTDECL_START S QName S contentspec   ELEMENTDECL_END
NameOrChoiceOrSeq  ::= QName
NameOrChoiceOrSeq  ::= choice
NameOrChoiceOrSeq  ::= seq
MixedUnit          ::= S OR S QName
MixedUnit          ::= S OR   QName
MixedUnit          ::=   OR S QName
MixedUnit          ::=   OR   QName
AttlistDecl        ::= ATTLIST_START S QName AttDefAny S ATTLIST_END
AttlistDecl        ::= ATTLIST_START S QName AttDefAny   ATTLIST_END
AttDef             ::= S QName     S AttType S DefaultDecl
AttDef             ::= S NSAttName S AttType S DefaultDecl

xmlns_attribute    ::= ;
normal_attribute   ::= ;
prefixed_attname   ::= ;
default_attname    ::= ;
prefixed_name      ::= ;
unprefixed_name    ::= ;
