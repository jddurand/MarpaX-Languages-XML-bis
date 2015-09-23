package MarpaX::Languages::XML::Impl::Parser;
use Data::Hexdumper qw/hexdump/;
use Marpa::R2;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Impl::Encoding;
use MarpaX::Languages::XML::Impl::Grammar;
use MarpaX::Languages::XML::Type::XmlVersion -all;
use MarpaX::Languages::XML::Type::XmlSupport -all;
use Moo;
use MooX::late;
use MooX::HandlesVia;
use MooX::Role::Logger;
use Scalar::Util qw/reftype/;
use Try::Tiny;
use Types::Standard -all;
use Types::Common::Numeric -all;
use XML::NamespaceSupport;

#
# Perl OPs optimized as per:
# http://www.nntp.perl.org/group/perl.perl5.porters/2015/05/msg228068.html
#

# ABSTRACT: MarpaX::Languages::XML::Role::parser implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is an implementation of MarpaX::Languages::XML::Role::Parser.

=cut

#
# Constants
#
our $LOG_LINECOLUMN_FORMAT_MOVE = '%6d:%-4d->%6d:%-4d  :';
our $LOG_LINECOLUMN_FORMAT_HERE = '%6d:%-4d               :';

#
# Internal attributes
# -------------------

#
# EOF (let's say end of input instead)
#
has _eof => (
             is => 'rw',
             isa => Bool,
             default => undef
            );

#
# Namespace
#
has _namespace => (
                   is => 'rw',
                   isa => InstanceOf['XML::NamespaceSupport']
                  );
#
# parse() method return value
#
has _parse_rc => (
                  is => 'rw',
                  isa => Int,
                  default => 0
                 );
#
# Attributes
#
has _attributes => (
                   is => 'rw',
                   isa => HashRef[Dict[Name => Str, Value => Str, NamespaceURI => Str|Undef, Prefix => Str|Undef, LocalName => Str|Undef]],
                   default => sub { {} },
                   handles_via => 'Hash',
                   handles => {
                               _set__attribute => 'set',
                               _exists__attribute => 'exists',
                               _clear__attribute => 'clear',
                               _elements__attribute => 'elements'
                              },
                  );

#
# XmlDecl or TextDecl context because of XML1.1 restriction on #x85 and #x2028
#
has _decl_start_pos => (
                        is => 'rw',
                        isa => PositiveOrZeroInt,
                        default => 0
                       );
has _decl_end_pos => (
                      is => 'rw',
                      isa => PositiveOrZeroInt,
                      default => 0
                     );

#
# Because of the prolog retry, start_document can happen twice
#
has _start_document_done => (
                             is          => 'rw',
                             isa         => Bool,
                             default     => 0
                    );

#
# Last lexemes
#
has _last_lexeme => (
                     is          => 'rw',
                     isa         => ArrayRef[Str],
                     default     => sub { [] },
                     handles_via => 'Array',
                     handles     => {
                                     _get__last_lexeme => 'get',
                                     _set__last_lexeme => 'set',
                                    }
                    );

#
# Internal buffer length
#
has _length => (
                is          => 'rw',
                isa         => PositiveOrZeroInt,
                default     => 0,
                writer      => '_set__length',
                trigger     => \&_trigger__length
               );

sub _trigger__length {
  my ($self, $length) = @_;

  $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Pos: %d, Length=>%d, Remaining: %d -> %d",
                         $self->LineNumber,
                         $self->ColumnNumber,
                         $self->_pos,
                         $length,
                         $self->_remaining,
                         $length - $self->_pos) if ($MarpaX::Languages::XML::Impl::Parser::is_trace);
  $self->_set__remaining($length - $self->_pos);
}
#
# Encoding
#
has _encoding => (
                  is          => 'rw',
                  isa         => Str,
                  writer      => '_set__encoding'
                );
#
# Internal buffer position
#
has _pos => (
             is          => 'rw',
             isa         => PositiveOrZeroInt,
             default     => 0,
             writer      => '_set__pos',
             trigger     => \&_trigger__pos
            );

sub _trigger__pos {
  my ($self, $pos) = @_;

  $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Pos=>%d, Length: %d, Remaining: %d -> %d",
                         $self->LineNumber,
                         $self->ColumnNumber,
                         $pos, $self->_length,
                         $self->_remaining,
                         $self->_length - $pos) if ($MarpaX::Languages::XML::Impl::Parser::is_trace);
  $self->_set__remaining($self->_length - $pos);
}

#
# Reference to internal buffer. Used only for logging data and to avoid a call to $self->io->buffer that
# would log... 'Getting buffer' -;
#
has _bufferRef => (
                   is          => 'rw',
                   isa         => ScalarRef
                  );

#
# Remaining characters
#
has _remaining => (
                   is          => 'rw',
                   isa         => PositiveOrZeroInt,
                   default     => 0,
                   writer      => '_set__remaining'
                  );

#
# Internal virtual global position
#
has _global_pos => (
                    is          => 'rw',
                    isa         => PositiveOrZeroInt,
                    writer      => '_set__global_pos'
                   );

#
# Grammars (cached because of element recursivity)
#
has _grammars => (
                  is          => 'rw',
                  isa         => HashRef[InstanceOf['Marpa::R2::Scanless::G']],
                  handles_via => 'Hash',
                  default     => sub { {} },
                  handles     => {
                                  _exists__grammar => 'exists',
                                  _get__grammar    => 'get',
                                  _set__grammar    => 'set',
                                 },
                 );
#
# Predicted next position, line number, column number, global position
#
has _next_pos => (
                  is          => 'rw',
                  isa         => PositiveOrZeroInt,
                  writer      => '_set__next_pos'
                 );
has _next_global_line => (
                          is          => 'rw',
                          isa         => PositiveInt,
                          writer      => '_set__next_global_line'
                         );
has _next_global_column => (
                            is          => 'rw',
                            isa         => PositiveInt,
                            writer      => '_set__next_global_column'
                           );
has _next_global_pos => (
                         is          => 'rw',
                         isa         => PositiveOrZeroInt,
                         writer      => '_set__next_global_pos'
                        );

has _newline_regexp => (
                        is          => 'rw',
                        isa         => RegexpRef,
                        default     => sub { return qr/\R/; }
          );

#
# External attributes
# -------------------

has xml_version => (
                    is      => 'ro',
                    isa     => XmlVersion|Undef,
                    default => undef,
                    writer  => '_set_xml_version'
                   );

has xml_support => (
                    is      => 'ro',
                    isa     => XmlSupport|Undef,
                    default => undef
                   );

has io => (
           is          => 'ro',
           isa         => ConsumerOf['MarpaX::Languages::XML::Role::IO'],
           required    => 1
          );

has block_size => (
                   is          => 'ro',
                   isa         => PositiveInt,
                   default     => 1024 * 1024
          );

has sax_handler => (
                    is  => 'ro',
                    isa => HashRef[CodeRef],
                    default => sub { {} },
                    handles_via => 'Hash',
                    handles => {
                                keys_sax_handler  => 'keys',
                                get_sax_handler    => 'get',
                                exists_sax_handler => 'exists',
                               }
                    );

has unicode_newline => (
                        is          => 'ro',
                        isa         => Bool|Undef,
                        default     => 1,
                        trigger     => \&_trigger_unicode_newline
          );

sub _trigger_unicode_newline {
  my ($self, $unicode_newline) = @_;

  $self->_newline_regexp($unicode_newline ? qr/\R/ : qr/\n/);  # undef is a false value
}

#
# Logger attribute that need to be external
#
has LineNumber => (
                   is => 'ro',
                   isa => PositiveInt,
                   writer => '_set_LineNumber',
                   default => 1
                  );

has ColumnNumber => (
                   is => 'ro',
                   isa => PositiveInt,
                   writer => '_set_ColumnNumber',
                   default => 1
                  );

=head1 SEE ALSO

L<IO::All>, L<Marpa::R2>

=cut

sub _parse_exception {
  my ($self, $message, $r) = @_;

  my %hash = (
              Message      => $message || '',
              LineNumber   => $self->LineNumber,
              ColumnNumber => $self->ColumnNumber
             );
  #
  # In any case, remove EOLs in message
  #
  $hash{Message} =~ s/\s*\z//;
  if ($r) {
    $hash{Progress} = $r->show_progress();
    $hash{TerminalsExpected} = $r->terminals_expected();
  }
  if ($self->_bufferRef && ${$self->_bufferRef}) {
    # 47 = 15+16+16
    if ($self->_pos > 0) {
      my $previous_pos = ($self->_pos >= 48) ? $self->_pos - 48 : 0;
      $hash{DataBefore} = hexdump(data              => ${$self->_bufferRef},
                                  start_position    => $previous_pos,
                                  end_position      => $self->_pos - 1,
                                  suppress_warnings => 1,
                                  space_as_space    => 1
                                 );
    }
    $hash{Data} = hexdump(data              => ${$self->_bufferRef},
                          start_position    => $self->_pos,
                          end_position      => (($self->_pos + 47) <= $self->_length) ? $self->_pos + 47 : $self->_length,
                          suppress_warnings => 1,
                          space_as_space    => 1
                         );
  }

  MarpaX::Languages::XML::Exception::Parse->throw(%hash);
}

sub _find_encoding {
  my ($self, $encoding) = @_;
  #
  # Read the first bytes. 1024 is far enough.
  #
  my $old_block_size = $self->io->block_size_value();
  $self->io->block_size(1024) if ($old_block_size != 1024);
  $self->io->read;
  $self->_parse_exception('EOF when reading first bytes') if ($self->io->length <= 0);
  my $buffer = ${$self->_bufferRef};

  my $bom_encoding = '';
  my $guess_encoding = '';

  my ($found_encoding, $byte_start) = $encoding->bom($buffer);
  if (length($found_encoding) <= 0) {
    $found_encoding = $encoding->guess($buffer);
    if (length($found_encoding) <= 0) {
      $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Assuming relaxed (perl) utf8 encoding",
                             $self->LineNumber,
                             $self->ColumnNumber) if ($MarpaX::Languages::XML::Impl::Parser::is_debug);
      $found_encoding = 'UTF8';  # == utf8 == perl relaxed unicode
    } else {
      $guess_encoding = uc($found_encoding);
    }
    $byte_start = 0;
  } else {
    $bom_encoding = uc($found_encoding);
  }

  $self->io->encoding($found_encoding);

  #
  # Make sure we are positionned at the beginning of the buffer and at correct
  # source position. This is inefficient for everything that is not seekable.
  #
  $self->io->clear;
  $self->io->pos($byte_start);

  #
  # Restore original block size
  #
  $self->io->block_size($old_block_size) if ($old_block_size != 1024);

  #
  # The stream is supposed to be opened with the correct encoding, if any
  # If there was no guess from the BOM, default will be UTF-8. Nevertheless we
  # do NOT set it immediately: if it UTF-8, the beginning of the XML file will
  # start with one byte chars only, which is compatible with binary mode.
  # And if it is not UTF-8, the first chars will tell us more.
  # If the encoding is setted to something else but what the BOM eventually says
  # this will be handled by a callback from the grammar.
  #
  # An XML processor SHOULD work with case-insensitive encoding name. So we uc()
  # (note: per def an encoding name contains only Latin1 character, i.e. uc() is ok)
  #
  return ($bom_encoding, $guess_encoding, $found_encoding, $byte_start);
}
#
# This routine is the core of the package, so quite highly optimized, making it
# less readable -; For instance setters and getters are avoided.
#
sub _generic_parse {
  #
  # buffer is accessed using $_[1] to avoid dereferencing $self->io->buffer everytime
  #
  my ($self, undef, $grammar, $end_event_name, $callbacks_ref, $eol, $lexeme_callbacks_ref) = @_;
  #
  # Create a recognizer
  #
  my $r = Marpa::R2::Scanless::R->new({ grammar => $grammar->scanless });
  $r->read(\'  ');
  #
  # Variables that need initialization
  #
  my $global_pos       = $self->{_global_pos};
  my $LineNumber       = $self->{LineNumber};
  my $ColumnNumber     = $self->{ColumnNumber};
  my $pos              = $self->{_pos};
  my $length           = $self->{_length};
  my $remaining        = $self->{_remaining};
  my @lexeme_match_by_symbol_ids     = $grammar->elements_lexeme_match_by_symbol_ids;
  my @lexeme_exclusion_by_symbol_ids = $grammar->elements_lexeme_exclusion_by_symbol_ids;
  my $previous_can_stop = 0;
  my $_XMLNSCOLON_ID   = $grammar->scanless->symbol_by_name_hash->{'_XMLNSCOLON'};
  my $_XMLNS_ID        = $grammar->scanless->symbol_by_name_hash->{'_XMLNS'};
  my $eol_impl         = $grammar->eol_impl;
  #
  # Infinite loop until user says to stop or error
  #
  while (1) {
    my @event_names = map { $_->[0] } @{$r->events()};
    my @terminals_expected_to_symbol_ids = $r->terminals_expected_to_symbol_ids();
    if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
      $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE Pos: %d, Length: %d, Remaining: %d", $LineNumber, $ColumnNumber, $pos, $length, $remaining);
      if ($self->_remaining > 0) {
        $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE Data: %s", $LineNumber, $ColumnNumber,
                               hexdump(data              => substr($_[1], $pos, 15),
                                       suppress_warnings => 1,
                                       space_as_space    => 1
                                      ));
      }
      $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE %s/%s/%s: Events                : %s", $LineNumber, $ColumnNumber, $grammar->spec, $grammar->xml_version, $grammar->start, \@event_names);
      $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE %s/%s/%s: Expected terminals    : %s", $LineNumber, $ColumnNumber, $grammar->spec, $grammar->xml_version, $grammar->start, $r->terminals_expected());
      $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE %s/%s/%s: Expected terminals IDs: %s", $LineNumber, $ColumnNumber, $grammar->spec, $grammar->xml_version, $grammar->start, \@terminals_expected_to_symbol_ids);
    }
    #
    # First the events
    #
    my $can_stop = 0;
    foreach (@event_names) {
      #
      # The end event name ?
      #
      $can_stop = 1 if ($_ eq $end_event_name);
      #
      # Callback ?
      #
      my $code = $callbacks_ref->{$_};
      #
      # A callback has no other argument but the buffer, the recognizer and the grammar
      # Take care: in our model, any true value in return will mean immediate stop
      #
      return if ($code && $self->$code($_[1], $r, $grammar));
    }
    #
    # Then the expected lexemes
    # This is a do {} while () because of end-of-buffer management
    #
    my $terminals_expected_again = 0;
    do {
      my %length = ();
      my $max_length = 0;
      foreach (@terminals_expected_to_symbol_ids) {
        #
        # It is a configuration error to have $lexeme_match{$_} undef at this stage
        # Note: all our patterns are compiled with the /p modifier for perl < 5.20
        #
        # We use an optimized version to bypass the the Marpa::R2::Grammar::symbol_name call
        if ($_[1] =~ $lexeme_match_by_symbol_ids[$_]) {
          my $matched_data = ${^MATCH};
          my $length_matched_data = length($matched_data);
          #
          # Match reaches end of buffer ?
          #
          if ((($pos + $length_matched_data) >= $length) && ! $self->{_eof}) { # Match up to the end of buffer is avoided as much as possible
            $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE Lexeme %s (%s) is reaching end-of-buffer",
                                   $LineNumber,
                                   $ColumnNumber,
                                   $_,
                                   $grammar->scanless->symbol_name($_)) if ($MarpaX::Languages::XML::Impl::Parser::is_trace);
            my $old_remaining = $remaining;
            $remaining = $self->_reduceAndRead($_[1], $r, $pos, $length, \$pos, \$length, $grammar, $eol, $eol_impl);
            if ($remaining > $old_remaining) {
              #
              # Something was read
              #
              $terminals_expected_again = 1;
              last;
            } else {
              $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE Nothing more read",
                                     $LineNumber,
                                     $ColumnNumber) if ($MarpaX::Languages::XML::Impl::Parser::is_trace);
              $self->{_eof} = 1;
            }
          }
          #
          # Match excluded ?
          #
          my $lexeme_exclusion = $lexeme_exclusion_by_symbol_ids[$_];
          next if ($lexeme_exclusion && ($matched_data =~ $lexeme_exclusion));
          #
          # Lexeme ok
          #
          $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE [Match] %s: length=%d",
                                 $LineNumber,
                                 $ColumnNumber,
                                 $grammar->scanless->symbol_name($_),
                                 length($matched_data)) if ($MarpaX::Languages::XML::Impl::Parser::is_trace);
          $length{$_} = $length_matched_data;
          $max_length = $length_matched_data if ($length_matched_data > $max_length);
        }
      }
      #
      # Push terminals if any
      #
      if (@terminals_expected_to_symbol_ids) {
        if (! $max_length) {
          if ($can_stop || $previous_can_stop) {
            $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE No predicted lexeme found but grammar end flag is on",
                                   $LineNumber,
                                   $ColumnNumber) if ($MarpaX::Languages::XML::Impl::Parser::is_trace);
            return;
          } else {
            $self->_parse_exception('No predicted lexeme found', $r);
          }
        }
        my $data = undef;
        #
        # Special case of _XMLNSCOLON and _XMLNS: we /know/ in advance they have
        # higher priority
        #
        if (exists($length{$_XMLNSCOLON_ID})) {
          $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE Lexeme _XMLNSCOLON detected and has priority", $LineNumber, $ColumnNumber) if ($MarpaX::Languages::XML::Impl::Parser::is_trace);
          $data = 'xmlns:';
          $max_length = length($data);
          %length = ($_XMLNSCOLON_ID => $max_length);
        } elsif (exists($length{$_XMLNS_ID})) {
          $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE Lexeme _XMLNS detected and has priority", $LineNumber, $ColumnNumber) if ($MarpaX::Languages::XML::Impl::Parser::is_trace);
          $data = 'xmlns';
          $max_length = length($data);
          %length = ($_XMLNS_ID => $max_length);
        } else {
          #
          # Everything else has the same (default) priority of 0: keep the longests only
          #
          %length = map {
            $_ => $length{$_}
          } grep {
            ($length{$_} == $max_length) ? do { do { $data //= substr($_[1], $pos, $max_length)}, 1 } : 0
          } keys %length;
        }
        #
        # Prepare trackers change
        #
        my $next_pos        = $self->{_next_pos}        = $pos + $max_length;
        my $next_global_pos = $self->{_next_global_pos} = $global_pos + $max_length;
        my $linebreaks;
        my $next_global_column;
        my $next_global_line;
        if ($linebreaks = () = $data =~ /$MarpaX::Languages::XML::Impl::Parser::newline_regexp/g) {
          $next_global_line   = $self->{_next_global_line}   = $LineNumber + $linebreaks;
          $next_global_column = $self->{_next_global_column} = 1 + ($max_length - $+[0]);
        } else {
          $next_global_line   = $self->{_next_global_line}   = $LineNumber;
          $next_global_column = $self->{_next_global_column} = $ColumnNumber + $max_length;
        }
        $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_MOVE Pushing %d characters with %s",
                               $LineNumber,
                               $ColumnNumber,
                               $next_global_line,
                               $next_global_column,
                               $max_length,
                               [ map { $grammar->scanless->symbol_name($_) } keys %length ]) if ($MarpaX::Languages::XML::Impl::Parser::is_trace);
        foreach (keys %length) {
          $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE [Found] %s: length=%d",
                                 $LineNumber,
                                 $ColumnNumber,
                                 $grammar->scanless->symbol_name($_),
                                 $max_length) if ($MarpaX::Languages::XML::Impl::Parser::is_debug);
          #
          # Handle ourself lexeme event, if any
          # This is NOT a Marpa event, but our stuff.
          # This is why we base it on another reference
          # for speed (the lexeme ID). The semantic is quite similar to
          # Marpa's lexeme predicted event.
          #
          my $code = $lexeme_callbacks_ref->[$_];
          #
          # A lexeme event has also the data in the arguments
          # Take care: in our model, any true value in return will mean immediate stop
          #
          return if ($code && $self->$code($_[1], $r, $grammar, $data));
          #
          # Remember last data for this lexeme
          #
          $self->{_last_lexeme}->[$_] = $data;
          #
          # Do the alternative
          #
          $r->lexeme_alternative_by_symbol_id($_);
        }
        #
        # Make it complete from grammar point of view. Never fails because
        # I rely entirely on predicted lexemes.
        #
        $r->lexeme_complete(0, 1);
        #
        # Move trackers
        #
        $LineNumber   = $self->{LineNumber}   = $next_global_line;
        $ColumnNumber = $self->{ColumnNumber} = $next_global_column;
        $global_pos   = $self->{_global_pos}  = $next_global_pos;
        $pos          = $self->{_pos}         = $next_pos;
        $remaining    = $self->{_remaining}   = $length - $pos;
        #
        # Reposition internal buffer
        #
        pos($_[1]) = $pos;
      } else {
        #
        # No prediction: this is ok only if grammar end_of_grammar flag is set
        #
        if ($can_stop || $previous_can_stop) {
          $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE No prediction and grammar end flag is on", $LineNumber, $ColumnNumber) if ($MarpaX::Languages::XML::Impl::Parser::is_trace);
          return;
        } else {
          $self->_parse_exception('No prediction and grammar end flag is not set', $r);
        }
      }
    } while ($terminals_expected_again);
    #
    # Go to next events
    #
    $previous_can_stop = $can_stop;
  }
  #
  # Never reached -;
  #
  return;
}

sub _reduceAndRead {
  my ($self,  undef, $r, $pos, $length, $posp, $lengthp, $grammar, $eol, $eol_impl) = @_;
  #
  # Crunch previous data unless we are in the decl context
  #
  if (! $MarpaX::Languages::XML::Impl::Parser::in_decl) {
    #
    # Faster like this -;
    #
    if ($pos >= $length) {
      $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE Rolling-out buffer", $self->LineNumber, $self->ColumnNumber) if ($MarpaX::Languages::XML::Impl::Parser::is_trace);
      $_[1] = '';
    } else {
      $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE Rolling-out %d characters", $self->LineNumber, $self->ColumnNumber, $pos) if ($MarpaX::Languages::XML::Impl::Parser::is_trace);
      #
      # substr is efficient at front-end of a string
      #
      substr($_[1], 0, $pos, '');
    }
    ${$posp} = $pos = $self->_set__pos(0);
    #
    # Re-position internal buffer
    #
    pos($_[1]) = $pos;
  }
  #
  # Read more data
  #
  $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE Reading %d characters",
                         $self->LineNumber,
                         $self->ColumnNumber,
                         $self->block_size) if ($MarpaX::Languages::XML::Impl::Parser::is_trace);
  ${$lengthp} = $length = $self->_set__length($self->_read($_[1], $r, $grammar, $eol, $eol_impl));

  return $length - $pos;
}

sub _read {
  my ($self, undef, $r, $grammar, $eol, $eol_impl) = @_;

  my $length;
  do {
    my $io_length;
    $self->io->read;
    if (($io_length = $self->io->length) <= 0) {
      $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE EOF", $self->LineNumber, $self->ColumnNumber) if ($MarpaX::Languages::XML::Impl::Parser::is_trace);
      $self->{_eof} = 1;
      return 0;
    } else {
      if ($eol) {
        #
        # This can croak
        #
        my $ok = 1;
        my $message;
        try {
          my $eol_length = $grammar->$eol_impl($_[1], $self->{_eof});
          if ($eol_length > 0) {
            $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE End-of-line handling removed %d character%s",
                                   $self->LineNumber,
                                   $self->ColumnNumber,
                                   $io_length - $eol_length,
                                   ($io_length - $eol_length) > 0 ? 's' : '') if ($MarpaX::Languages::XML::Impl::Parser::is_trace && ($eol_length != $io_length));
            $length = $eol_length;
          }
        } catch {
          $ok = 0;
          $message = "$_";
          #
          # Never reached
          #
          return;
        };
        $self->_parse_exception($message, $r) if (! $ok);
      } else {
        $length = $io_length;
      }
    }
  } while (! $length);

  return $length;
}

sub start_document {
  # my ($self, $user_code) = @_;         # Callback from _generic_parse() : optimized as much as possible

  if (! $_[0]->{_start_document_done}) {
    my $usercode = $_[1];
    $_[0]->{_parse_rc} = $_[0]->$usercode({});   # $_[0]->$_[1] is a compile error
    $_[0]->{_start_document_done} = 1;
  }
  return;
}

sub end_document {
  # my ($self, $user_code) = @_;         # Callback from _generic_parse() : optimized as much as possible

  my $usercode = $_[1];
  $_[0]->$usercode({});

  return;
}

sub start_element {
  # my ($self, $user_code, %attributes) = @_;         # Callback from _generic_parse() : optimized as much as possible

  my $usercode = $_[1];
  $_[0]->$usercode({
                    Attributes => $_[0]->{_attributes}
                   }
                  );

  $_[0]->{_attributes} = {};

  return;
}

sub end_element {
  # my ($self, $user_code) = @_;         # Callback from _generic_parse() : optimized as much as possible

  my $usercode = $_[1];
  $_[0]->$usercode({});

  return;
}

sub _parse_prolog {
  my ($self) = @_;              # buffer is in $_[1]

  #
  # Encoding object instance
  #
  my $encoding = MarpaX::Languages::XML::Impl::Encoding->new();
  my ($bom_encoding, $guess_encoding, $orig_encoding, $byte_start)  = $self->_find_encoding($encoding);
  $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE BOM and/or guess gives encoding %s and byte offset %d",
                         $self->LineNumber,
                         $self->ColumnNumber,
                         $orig_encoding,
                         $byte_start) if ($MarpaX::Languages::XML::Impl::Parser::is_debug);
  #
  # Grammar's xml version
  #
  my $xml_version;
  #
  # Default grammar event and callbacks
  #
  my $grammar;
  my %grammar_event;
  foreach (qw/prolog/) {
    $grammar_event{"$_\$"} = { type => 'completed', symbol_name => $_ };
  }
  my $_ENCNAME_ID;
  my $_XMLDECL_START_ID;
  my $_XMLDECL_END_ID;
  my $_VERSIONNUM_ID;
  my $_ELEMENT_START_ID;
  my %callbacks = ();
  #
  # Initialized after grammar creation, though must be visible right now:
  #
  my $start_document_impl;
  my $end_document_impl;
  #
  # Other grammar events for eventual SAX handlers. At this stage only start_document
  # is supported.
  #
  foreach (qw/start_document/) {
    my $user_code = $self->get_sax_handler($_);
    if ($user_code) {
      my $internal_code = $_;
      my $event_name = "!$_";
      $grammar_event{$event_name} = { type => 'nulled', symbol_name => $_ };
      #
      # Part of _generic_parse() - so optimized as much as possible
      #
      $callbacks{$event_name} = sub {
        # my ($self, undef, $r) = @_; # $_[1] is the internal buffer
        return $_[0]->$internal_code($user_code);
      };
    }
  }
  my $nb_retry_because_of_xml_version = 0;
 retry_because_of_xml_version:
  #
  # Generate grammar
  #
  $grammar = $self->_generate_grammar(start => 'document', grammar_event => \%grammar_event);
  $xml_version = $grammar->xml_version;
  #
  # Get implementations of interest
  #
  $start_document_impl = $grammar->start_document_impl;
  $end_document_impl   = $grammar->end_document_impl;
  #
  # Get IDs and implementations of interest
  #
  $_ENCNAME_ID       = $grammar->scanless->symbol_by_name_hash->{'_ENCNAME'};
  $_XMLDECL_START_ID = $grammar->scanless->symbol_by_name_hash->{'_XMLDECL_START'};
  $_XMLDECL_END_ID   = $grammar->scanless->symbol_by_name_hash->{'_XMLDECL_END'};
  $_VERSIONNUM_ID    = $grammar->scanless->symbol_by_name_hash->{'_VERSIONNUM'};
  $_ELEMENT_START_ID = $grammar->scanless->symbol_by_name_hash->{'_ELEMENT_START'};
  my $eol_decl_impl  = $grammar->eol_decl_impl;
  #
  # and the associated namespace support
  #
  my %namespacesupport_options = ();
  if ($grammar->xml_support eq 'xmlns') {
    $namespacesupport_options{xmlns} = 1;
    #
    # Not really need but a safeguard, let's say.
    # We detect ourself if we are undeclaring in the 1.0 version
    #
    $namespacesupport_options{xmlns_11} = ($grammar->xml_version eq '1.1') ? 1 : 0;
  }
  $self->_namespace(XML::NamespaceSupport->new(\%namespacesupport_options));
  #
  # then the eventual lexeme "man-in-the-middle" callbacks.
  # Lexeme callbacks are part of the _generic_parse(), so they must be optimized as much as possible
  #
  my @lexeme_callbacks_optimized;
  $lexeme_callbacks_optimized[$_ELEMENT_START_ID] = sub {
    # my ($self, undef, $r, $g, $data) = @_;    # $_[1] is the internal buffer
    #
    # Say stop
    #
    $_[0]->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE [ cbk ] _ELEMENT_START: XML root element detected",
                           $_[0]->{LineNumber},
                           $_[0]->{ColumnNumber}) if ($MarpaX::Languages::XML::Impl::Parser::is_debug);
    return 1;
  };
  $lexeme_callbacks_optimized[$_ENCNAME_ID] = sub {
    # my ($self, undef, $r, $g, $data) = @_;    # $_[1] is the internal buffer
    #
    # Encoding is composed only of ASCII codepoints, so uc is ok
    #
    my $xml_encoding = uc($_[4]);
    $_[0]->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE [ cbk ] _ENCNAME: XML says encoding %s (uppercased to %s)",
                           $_[0]->{LineNumber},
                           $_[0]->{ColumnNumber},
                           $_[4],
                           $xml_encoding) if ($MarpaX::Languages::XML::Impl::Parser::is_debug);
    #
    # Check eventual encoding v.s. endianness. Algorithm vaguely taken from
    # https://blogs.oracle.com/tucu/entry/detecting_xml_charset_encoding_again
    #
    my $final_encoding = $encoding->final($bom_encoding, $guess_encoding, $xml_encoding);
    if ($final_encoding ne $_[0]->{_encoding}) {
      $_[0]->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE \[_ENCNAME\] XML encoding %s disagree with current encoding %s",
                             $_[0]->{LineNumber},
                             $_[0]->{ColumnNumber},
                             $xml_encoding,
                             $_[0]->{_encoding}) if ($MarpaX::Languages::XML::Impl::Parser::is_debug);
      $orig_encoding = $final_encoding;
      #
      # No need to go further. We will have to retry anyway.
      #
      return 1;
    }
    return;
  };
  $lexeme_callbacks_optimized[$_XMLDECL_START_ID] = sub {
    # my ($self, undef, $r, $g, $data) = @_;    # $_[1] is the internal buffer

    $_[0]->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE [ cbk ] _XMLDECL_START: XML Declaration is starting",
                           $_[0]->{LineNumber},
                           $_[0]->{ColumnNumber}) if ($MarpaX::Languages::XML::Impl::Parser::is_debug);
    #
    # Remember we are in a Xml or Text declaration
    #
    $MarpaX::Languages::XML::Impl::Parser::in_decl = 1;
    $_[0]->{_decl_start_pos} = $_[0]->{_pos};
    return;
  };
  $lexeme_callbacks_optimized[$_XMLDECL_END_ID] = sub {
    # my ($self, undef, $r, $g, $data) = @_;    # $_[1] is the internal buffer

    $_[0]->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE [ cbk ] _XMLDECL_END: XML Declaration is ending",
                           $_[0]->{LineNumber},
                           $_[0]->{ColumnNumber}) if ($MarpaX::Languages::XML::Impl::Parser::is_debug);
    #
    # Remember we are not in a Xml or Text declaration
    #
    $MarpaX::Languages::XML::Impl::Parser::in_decl = 0;
    $_[0]->{_decl_end_pos} = $_[0]->{_pos} + length($_[3]);
    #
    # And apply end-of-line handling to this portion using a specific decl eol method
    #
    my $decl = substr($_[1], $_[0]->{_decl_start_pos}, $_[0]->{_decl_end_pos} - $_[0]->{_decl_start_pos});
    my $orig_length = length($decl);
    #
    # This can croak
    #
    my $ok = 1;
    my $message;
    try {
      my $eol_length = $_[3]->$eol_decl_impl($decl, $_[0]->{_eof});
      #
      # Replace in $_[1]
      #
      substr($_[1], $_[0]->{_decl_start_pos}, $_[0]->{_decl_end_pos} - $_[0]->{_decl_start_pos}, $decl) if (($eol_length > 0) && ($eol_length != $orig_length));
    } catch {
      #
      # $_[0] is not available in catch {}
      #
      $ok = 0;
      #
      # I suppose $_ will corectly stringify
      #
      $message = $_;
      return;
    };
    $_[0]->_parse_exception($message, $_[2]) if (! $ok);
    return;
  };
  $lexeme_callbacks_optimized[$_VERSIONNUM_ID] = sub {
    # my ($self, undef, $r, $g, $data) = @_;    # $_[1] is the internal buffer

    $_[0]->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE [ cbk ] _VERSIONNUM: XML says version number %s",
                           $_[0]->{LineNumber},
                           $_[0]->{ColumnNumber},
                           $_[4]) if ($MarpaX::Languages::XML::Impl::Parser::is_debug);
    #
    # A true value mean immediate stop
    #
    return ($_[3]->xml_version ne $_[4]);
  };
  #
  # Go
  #
  my $nb_retry_because_of_encoding = 0;
 retry_because_of_encoding:
  #
  # Initial block size and read
  #
  $self->io->block_size($self->block_size);
  $self->io->read;
  #
  # Parser variables initializations
  #
  $self->_set__encoding($orig_encoding);
  $self->_set__global_pos($byte_start);
  my $length = $self->_set__length($self->io->length);
  $self->_set__pos(0);
  $self->_set_LineNumber(1);
  $self->_set_ColumnNumber(1);
  $self->_generic_parse(
                        $_[1],             # buffer
                        $grammar,          # grammar
                        'prolog$',         # end_event_name
                        \%callbacks,       # callbacks
                        1,                 # eol
                        \@lexeme_callbacks_optimized
                       );
  if ($xml_version && $grammar->xml_version ne $xml_version) {
    $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Redoing parse using xml version %s instead of %s",
                           $self->LineNumber,
                           $self->ColumnNumber,
                           $xml_version,
                           $grammar->xml_version) if ($MarpaX::Languages::XML::Impl::Parser::is_debug);
    #
    # I/O reset
    #
    $self->io->clear;
    $self->io->pos($byte_start);
    #
    # XML version
    #
    $self->_set_xml_version($xml_version);
    if (++$nb_retry_because_of_xml_version == 1) {
      goto retry_because_of_xml_version;
    } else {
      $self->_parse_exception('Two many retries because of xml version difference beween previous grammar and XML');
    }
  }
  if ($self->_encoding ne $orig_encoding) {
    $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Redoing parse using encoding %s instead of %s",
                           $self->LineNumber,
                           $self->ColumnNumber,
                           $orig_encoding,
                           $self->_encoding) if ($MarpaX::Languages::XML::Impl::Parser::is_debug);
    #
    # I/O reset
    #
    $self->io->encoding($orig_encoding);
    $self->io->clear;
    $self->io->pos($byte_start);
    if (++$nb_retry_because_of_encoding == 1) {
      goto retry_because_of_encoding;
    } else {
      $self->_parse_exception('Two many retries because of encoding difference beween BOM, guess and XML');
    }
  }
}

sub _safe_string {
  my ($self, $string) = @_;
  #
  # Replace any character that would not be a known ASCII printable one with its hexadecimal value a-la-XML
  #
  # http://stackoverflow.com/questions/9730054/how-can-i-dump-a-string-in-perl-to-see-if-there-are-any-character-differences
  #
  $string =~ s/([^\x20-\x7E])/sprintf("&#x%x;", ord($1))/ge;
  return $string;
}

sub _generate_grammar {
  my ($self, %grammar_option) = @_;

  $grammar_option{xml_version} = $self->xml_version if (! Undef->check($self->xml_version));
  $grammar_option{xml_support} = $self->xml_support if (! Undef->check($self->xml_support));

  return MarpaX::Languages::XML::Impl::Grammar->new(%grammar_option);
}

sub _parse_element {
  my ($self) = @_;              # buffer is in $_[1]

  #
  # Default grammar event and callbacks
  #
  my $grammar;
  my %grammar_event;
  foreach (qw/element AttributeName AttValue/) {
    $grammar_event{"$_\$"} = { type => 'completed', symbol_name => $_ };
  }
  #
  # Depending on the grammar support (xml or xmlns), the attribute is either:
  #
  # For XML1.0:
  # Attribute          ::= AttributeName Eq AttValue  # [VC: Attribute Value Type] [WFC: No External Entity References] [WFC: No < in Attribute Values]
  # AttributeName      ::= Name
  #
  # For XMLNS1.0:
  # Attribute          ::= NSAttName Eq AttValue
  # Attribute          ::= QName Eq AttValue
  # NSAttName	       ::= PrefixedAttName (prefixed_attname)
  #                      | DefaultAttName (default_attname)
  # PrefixedAttName    ::= XMLNSCOLON NCName
  # DefaultAttName     ::= XMLNS
  # QName              ::= PrefixedName (prefixed_name)
  #                      | UnprefixedName (unprefixed_name)
  # PrefixedName       ::= Prefix COLON LocalPart
  # UnprefixedName     ::= LocalPart
  # Prefix             ::= NCName
  # LocalPart          ::= NCName
  #
  if ((! $self->xml_support) || ($self->xml_support eq 'xmlns')) {
    foreach (qw/prefixed_attname default_attname
                prefixed_name unprefixed_name/) {
      $grammar_event{"!$_"} = { type => 'nulled', symbol_name => $_ };
    }
    foreach (qw/Prefix LocalPart/) {
      $grammar_event{"$_\$"} = { type => 'completed', symbol_name => $_ };
    }
  }

  my $attname = '';
  my @attvalue = ();
  my @attributes = ();
  my $prefix = '';
  my $localpart = '';
  my $qname = '';
  my $namespace_prefix = '';
  my $is_nsattname = 0;
  my $is_qname = 0;
  my $attribute_context = 0;
  my $cdata_context = 0;
  #
  # Initialized after grammar creation, though must be visible right now:
  #
  my $attvalue_impl;
  my $nsattname_impl;
  my $qname_impl;

  my $_NAME_ID;
  my $_ATTVALUEINTERIORDQUOTEUNIT_ID;
  my $_ATTVALUEINTERIORSQUOTEUNIT_ID;
  my $_DIGITMANY_ID;
  my $_ALPHAMANY_ID;
  my $_NCNAME_ID;
  my $_ENTITYREF_END_ID;
  my %callbacks = (
                   #
                   # They are part of _generic_parse() - so are optimized as much as possible
                   #
                   'Prefix$' => sub {
                     # my ($self, undef, $r, $g) = @_;    # $_[1] is the internal buffer
                     $prefix = $_[0]->{_last_lexeme}->[$_NCNAME_ID];
                     return;
                   },
                   'LocalPart$' => sub {
                     # my ($self, undef, $r, $g) = @_;    # $_[1] is the internal buffer
                     $localpart = $_[0]->{_last_lexeme}->[$_NCNAME_ID];
                     return;
                   },
                   '!prefixed_name' => sub {
                     # my ($self, undef, $r, $g) = @_;    # $_[1] is the internal buffer
                     $attribute_context = 1;
                     #
                     # Per both $prefix and $localpart are set
                     #
                     $is_qname = 1;
                     return;
                   },
                   '!unprefixed_name' => sub {
                     # my ($self, undef, $r, $g) = @_;    # $_[1] is the internal buffer
                     $attribute_context = 1;
                     #
                     # Per def $prefix is set and there is no $localpart
                     #
                     $localpart = '';
                     $is_qname = 1;
                     return;
                   },
                   '!prefixed_attname' => sub {
                     # my ($self, undef, $r, $g) = @_;    # $_[1] is the internal buffer
                     $attribute_context = 1;
                     $namespace_prefix = $_[0]->{_last_lexeme}->[$_NCNAME_ID];
                     $is_nsattname = 1;
                     return;
                   },
                   '!default_attname' => sub {
                     # my ($self, undef, $r, $g) = @_;    # $_[1] is the internal buffer
                     $attribute_context = 1;
                     $namespace_prefix = '';
                     $is_nsattname = 1;
                     return;
                   },
                   'AttributeName$' => sub {
                     # my ($self, undef, $r, $g) = @_;    # $_[1] is the internal buffer
                     $attribute_context = 1;
                     $attname = $_[0]->{_last_lexeme}->[$_NAME_ID];
                     return;
                   },
                   'AttValue$' => sub {
                     # my ($self, undef, $r, $g) = @_;    # $_[1] is the internal buffer
                     #
                     # This can croak
                     #
                     my $attvalue;
                     my $ok = 1;
                     my $message;
                     try {
                       $attvalue = $grammar->$attvalue_impl($cdata_context, @attvalue);
                       @attvalue = ();
                       if ($is_nsattname) {
                         $grammar->$nsattname_impl($namespace_prefix, $attvalue);
                       }
                     } catch {
                       #
                       # $_[0] is not available in catch {}
                       #
                       $ok = 0;
                       #
                       # I suppose $_ will corectly stringify
                       #
                       $message = $_;
                       return;
                     };
                     $_[0]->_parse_exception($message, $_[2]) if (! $ok);

                     if ($is_nsattname) {
                       #
                       # All prefixes beginning with the three-letter sequence x, m, l, in any case combination, are reserved. This means that:
                       # * users SHOULD NOT use them except as defined by later specifications
                       # * processors MUST NOT treat them as fatal errors
                       #
                       if ($namespace_prefix =~ /^xml./i) {
                         #
                         # I would have like to put in Grammar.pm, but this is not really a WFC constraint. Just a recommandation.
                         #
                         $_[0]->_logger->warnf("$LOG_LINECOLUMN_FORMAT_HERE [ cbk ] AttValue\$: Any prefix starting with 'xml', in any case combination, are reserved: %s",
                                               $_[0]->{LineNumber},
                                               $_[0]->{ColumnNumber},
                                               $_[0]->_safe_string($namespace_prefix)) if ($MarpaX::Languages::XML::Impl::Parser::is_warn);
                       }
                       if (length($namespace_prefix)) {
                         $_[0]->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE [ cbk ] AttValue\$: Declaring %snamespace%s%s to %s",
                                                $_[0]->{LineNumber},
                                                $_[0]->{ColumnNumber},
                                                length($namespace_prefix) ? '': 'default ',
                                                length($namespace_prefix) ? ' ': ' ',
                                                $_[0]->_safe_string($namespace_prefix),
                                                $_[0]->_safe_string($attvalue)) if ($MarpaX::Languages::XML::Impl::Parser::is_debug);
                       } else {
                         $_[0]->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE [ cbk ] AttValue\$: Declaring default namespace to %s",
                                                $_[0]->{LineNumber},
                                                $_[0]->{ColumnNumber},
                                                $_[0]->_safe_string($attvalue)) if ($MarpaX::Languages::XML::Impl::Parser::is_debug);
                       }
                       $self->{_namespace}->declare_prefix($namespace_prefix, $attvalue);
                     } else {
                       #
                       # namespace scoping backtrack to the start of the element, so we have to delay
                       # validation of QName and AttName
                       #
                       push(@attributes, { prefix => $prefix, localpart => $localpart, attname => $attname, attvalue => $attvalue });
                     }
                     #
                     # Reset booleans
                     #
                     $attribute_context = 0;
                     $is_qname = 0;
                     $is_nsattname = 0;
                     return;
                   }
                  );
  #
  # Other grammar events for eventual SAX handlers
  #
  foreach (qw/start_element end_element/) {
    my $user_code = $self->get_sax_handler($_);
    if ($user_code) {
      my $internal_code = $_;
      my $event_name = "!$_";
      $grammar_event{$event_name} = { type => 'nulled', symbol_name => $_ };
      if ($_ eq 'start_element') {
        #
        # Add @attributes in the parameters
        #
        $callbacks{$event_name} = sub {
          # my ($self, undef, $r) = @_; # $_[1] is the internal buffer
          return $_[0]->$internal_code($user_code, @attributes);
        };
      } else {
        $callbacks{$event_name} = sub {
          # my ($self, undef, $r) = @_; # $_[1] is the internal buffer
          return $_[0]->$internal_code($user_code, @attributes);
        };
      }
    }
  }
  #
  # Generate grammar
  #
  $grammar = $self->_generate_grammar(start => 'element', grammar_event => \%grammar_event);
  #
  # Get implementations of interest
  #
  $attvalue_impl  = $grammar->attvalue_impl;
  $nsattname_impl = $grammar->nsattname_impl;
  $qname_impl     = $grammar->qname_impl;
  #
  # Get IDs of interest
  #
  $_NAME_ID                       = $grammar->scanless->symbol_by_name_hash->{'_NAME'};
  $_ATTVALUEINTERIORDQUOTEUNIT_ID = $grammar->scanless->symbol_by_name_hash->{'_ATTVALUEINTERIORDQUOTEUNIT'};
  $_ATTVALUEINTERIORSQUOTEUNIT_ID = $grammar->scanless->symbol_by_name_hash->{'_ATTVALUEINTERIORSQUOTEUNIT'};
  $_DIGITMANY_ID                  = $grammar->scanless->symbol_by_name_hash->{'_DIGITMANY'};
  $_ALPHAMANY_ID                  = $grammar->scanless->symbol_by_name_hash->{'_ALPHAMANY'};
  $_NCNAME_ID                     = $grammar->scanless->symbol_by_name_hash->{'_NCNAME'} if ($grammar->xml_support eq 'xmlns');
  $_ENTITYREF_END_ID              = $grammar->scanless->symbol_by_name_hash->{'_ENTITYREF_END'};
  #
  # Lexeme "man-in-the-middle" callbacks
  # Lexeme callbacks are part of the _generic_parse(), so they must be optimized as much as possible.
  my @lexeme_callbacks_optimized;
  $lexeme_callbacks_optimized[$_ATTVALUEINTERIORDQUOTEUNIT_ID] = sub {
    # my ($self, undef, $r, $g, $data) = @_;    # $_[1] is the internal buffer

    push(@attvalue, $_[4]);
    return;
  };
  $lexeme_callbacks_optimized[$_ATTVALUEINTERIORSQUOTEUNIT_ID] = sub {
    # my ($self, undef, $r, $g, $data) = @_;    # $_[1] is the internal buffer

    push(@attvalue, $_[4]);
    return;
  };
  $lexeme_callbacks_optimized[$_ENTITYREF_END_ID] = sub {
    # my ($self, undef, $r, $g, $data) = @_;    # $_[1] is the internal buffer

    my $name = $_[0]->{_last_lexeme}->[$_NAME_ID];
    my $entityref = $_[3]->entityref->get($name);
    if ($attribute_context) {
      if (! defined($entityref)) {
        $_[0]->_parse_exception('Entity reference $name is not defined', $_[2]);
      } else {
        push(@attvalue, $entityref);
      }
    }
    return;
  };
  $lexeme_callbacks_optimized[$_DIGITMANY_ID] = sub {
    # my ($self, undef, $r, $g, $data) = @_;    # $_[1] is the internal buffer

    #
    # A char reference is nothing else but the chr() of it.
    # Perl will warn by itself if this is not a good character.
    #
    push(@attvalue, chr($_[4])) if ($attribute_context);
    return;
  };
  $lexeme_callbacks_optimized[$_ALPHAMANY_ID] = sub {
    # my ($self, undef, $r, $g, $data) = @_;    # $_[1] is the internal buffer

    #
    # A char reference is nothing else but the chr() of it (given in hex format)
    # Perl will warn by itself if this is not a good character.
    #
    push(@attvalue, chr(hex($_[4]))) if ($attribute_context);
    return;
  };
  #
  # Go
  #
  $self->_generic_parse(
                        $_[1],             # buffer
                        $grammar,          # grammar
                        'element$',        # end_event_name
                        \%callbacks,       # callbacks
                        1,                 # eol
                        \@lexeme_callbacks_optimized
                       );
}

sub parse {
  my ($self) = @_;

  #
  # Localized variables not needed to be fetched more than once
  #
  local $MarpaX::Languages::XML::Impl::Parser::is_trace = $self->_logger->is_trace;
  local $MarpaX::Languages::XML::Impl::Parser::is_debug = $self->_logger->is_debug;
  local $MarpaX::Languages::XML::Impl::Parser::is_warn  = $self->_logger->is_warn;
  local $MarpaX::Languages::XML::Impl::Parser::in_decl  = 0;
  local $MarpaX::Languages::XML::Impl::Parser::newline_regexp  = $self->_newline_regexp;
  #
  # We want to handle buffer direcly with no COW: buffer is a variable send in all parameters
  # and accessed using $_[]
  #
  my $buffer = '';
  $self->_bufferRef(\$buffer);
  $self->io->buffer($self->_bufferRef);

  # ------------
  # Parse prolog
  # ------------
  $self->_parse_prolog($buffer);

  # --------------------
  # Parse (root) element
  # --------------------
  $self->_parse_element($buffer);


  # ----------------------------------------------------
  # Return value eventually overwriten by end_document()
  # ----------------------------------------------------
  return $self->_parse_rc;
}

with 'MooX::Role::Logger';
with 'MarpaX::Languages::XML::Role::Parser';

1;
