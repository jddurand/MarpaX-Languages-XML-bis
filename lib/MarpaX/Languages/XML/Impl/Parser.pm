package MarpaX::Languages::XML::Impl::Parser;
use Data::Hexdumper qw/hexdump/;
use Marpa::R2;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Impl::Encoding;
use MarpaX::Languages::XML::Impl::EntityRef;
use MarpaX::Languages::XML::Impl::Grammar;
use MarpaX::Languages::XML::Impl::PEReference;
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
use URI;
use XML::NamespaceSupport;

# ABSTRACT: MarpaX::Languages::XML::Role::parser implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is an implementation of MarpaX::Languages::XML::Role::Parser.

=cut

#
# Constants
#
our $LOG_LINECOLUMN_FORMAT_MOVE = '%6d:%-4d->%6d:%-4d :';
our $LOG_LINECOLUMN_FORMAT_HERE = '%6d:%-4d             :';

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

#
# Contexts
#
has _attribute_context => (
                           is => 'rw',
                           isa => Bool,
                           default => 0
                          );
has _cdata_context => (
                           is => 'rw',
                           isa => Bool,
                           default => 0
                          );

#
# Attribute
#
has _attribute => (
                   is => 'rw',
                   isa => HashRef[Dict[Name => Str, Value => Str, NamespaceURI => Str, Prefix => Str, LocalName => Str]],
                   default => sub { {} },
                   handles_via => 'Hash',
                   handles => {
                               _set__attribute => 'set',
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
                     isa         => HashRef[Str],
                     default     => sub { {} },
                     handles_via => 'Hash',
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


  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Pos: %d, Length=>%d, Remaining: %d -> %d", $self->LineNumber, $self->ColumnNumber, $self->_pos, $length, $self->_remaining, $length - $self->_pos);
  }
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

  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Pos=>%d, Length: %d, Remaining: %d -> %d", $self->LineNumber, $self->ColumnNumber, $pos, $self->_length, $self->_remaining, $self->_length - $pos);
  }
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

#
# External attributes
# -------------------

has xml_version => (
                    is      => 'ro',
                    isa     => XmlVersion|Undef,
                    default => undef
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

has strict_ns => (
                   is          => 'ro',
                   isa         => Bool,
                   default     => 0
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
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace || $ENV{XML_DEBUG}) {
    if ($r) {
      $hash{Progress} = $r->show_progress();
      $hash{TerminalsExpected} = $r->terminals_expected();
    }
    if ($self->_bufferRef) {
      $hash{Data} = hexdump(data => substr(${$self->_bufferRef}, $self->_pos, 47),  # 47 = 15+16+16
                            suppress_warnings => 1,
                           );
    }
  }

  MarpaX::Languages::XML::Exception::Parse->throw(%hash);
}

sub _find_encoding {
  my ($self, $encoding) = @_;
  #
  # Read the first bytes. 1024 is far enough.
  #
  my $old_block_size = $self->io->block_size_value();
  if ($old_block_size != 1024) {
    $self->io->block_size(1024);
  }
  $self->io->read;
  if ($self->io->length <= 0) {
    $self->_parse_exception('EOF when reading first bytes');
  }
  my $buffer = ${$self->_bufferRef};

  my $bom_encoding = '';
  my $guess_encoding = '';

  my ($found_encoding, $byte_start) = $encoding->bom($buffer);
  if (length($found_encoding) <= 0) {
    $found_encoding = $encoding->guess($buffer);
    if (length($found_encoding) <= 0) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
        $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Assuming relaxed (perl) utf8 encoding", $self->LineNumber, $self->ColumnNumber);
      }
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
  if ($old_block_size != 1024) {
    $self->io->block_size($old_block_size);
  }

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
  my ($self, undef, $grammar, $end_event_name, $callback_ref, $eol) = @_;
  #
  # Create a recognizer
  #
  my $r = Marpa::R2::Scanless::R->new({ grammar => $grammar->scanless });
  $r->read(\'  ');
  #
  # Variables that need initialization
  #
  my %grammar_event    = $grammar->elements_grammar_event;
  my %lexeme_match     = $grammar->elements_lexeme_match;
  my %lexeme_exclusion = $grammar->elements_lexeme_exclusion;
  my $global_pos       = $self->{_global_pos};
  my $LineNumber       = $self->{LineNumber};
  my $ColumnNumber     = $self->{ColumnNumber};
  my $pos              = $self->{_pos};
  my $length           = $self->{_length};
  my $remaining        = $self->{_remaining};
  my @lexeme_match_by_symbol_ids = $grammar->elements_lexeme_match_by_symbol_ids;
  my $previous_can_stop = 0;
  #
  # Infinite loop until user says to stop or error
  #
  while (1) {
    my @event_names = map { $_->[0] } @{$r->events()};
    my @terminals_expected_to_symbol_ids = $r->terminals_expected_to_symbol_ids();
    if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
      $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Pos: %d, Length: %d, Remaining: %d", $LineNumber, $ColumnNumber, $pos, $length, $remaining);
      if ($self->_remaining > 0) {
        $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Data: %s", $LineNumber, $ColumnNumber,
                               hexdump(data              => substr($_[1], $pos, 15),
                                       suppress_warnings => 1,
                                      ));
      }
      $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE Events: %s", $LineNumber, $ColumnNumber, \@event_names);
      $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE   IDs : %s", $LineNumber, $ColumnNumber, \@terminals_expected_to_symbol_ids);
      my @terminals_expected = @{$r->terminals_expected()};
      $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE ID Map: %s", $LineNumber, $ColumnNumber, \@terminals_expected);
    }
    #
    # First the events
    #
    my $can_stop = 0;
    foreach (@event_names) {
      #
      # The end event name ?
      #
      if ($_ eq $end_event_name) {
        $can_stop = 1;
        if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
          $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Grammar end event %s", $LineNumber, $ColumnNumber, $_);
        }
      }
      #
      # Callback ?
      #
      my $code = $callback_ref->{$_};
      #
      # A callback has no other argument but the buffer and the recognizer
      #
      if ($code && ! $self->$code($_[1], $r)) {
        #
        # Any false return value mean immediate stop
        #
        if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
          $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Event callback %s says to stop", $LineNumber, $ColumnNumber, $_);
        }
        return;
      }
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
            if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
              $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE Lexeme %s is reaching end-of-buffer", $LineNumber, $ColumnNumber, $_);
            }
            my $old_remaining = $remaining;
            $remaining = $self->_reduceAndRead($_[1], $r, $pos, $length, \$pos, \$length, $grammar, $eol);
            if ($remaining > $old_remaining) {
              #
              # Something was read
              #
              $terminals_expected_again = 1;
              last;
            } else {
              $self->{_eof} = 1;
              if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Nothing more read", $LineNumber, $ColumnNumber);
              }
            }
          }
          #
          # Match excluded ?
          #
          my $lexeme_exclusion = $lexeme_exclusion{$_};
          if ($lexeme_exclusion && ($matched_data =~ $lexeme_exclusion)) {
            if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
              $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE Lexeme %s match excluded", $LineNumber, $ColumnNumber, $_);
            }
            next;
          }
          #
          # Lexeme ok
          #
          if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
            $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Match %s with length=%d", $LineNumber, $ColumnNumber, $_, length($matched_data));
            foreach (split(/\R/, hexdump(data => $matched_data, suppress_warnings => 1))) {
              $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE ... %s", $LineNumber, $ColumnNumber, $_);
            }
          }
          $length{$_} = $length_matched_data;
          if ($length_matched_data > $max_length) {
            $max_length = $length_matched_data;
          }
        }
      }
      #
      # Push terminals if any
      #
      if (@terminals_expected_to_symbol_ids) {
        if (! $max_length) {
          if ($can_stop || $previous_can_stop) {
            if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
              $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE No predicted lexeme found but grammar end flag is on", $LineNumber, $ColumnNumber);
            }
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
        if (exists($length{_XMLNSCOLON})) {
          %length = (_XMLNSCOLON => $length{_XMLNSCOLON});
          $data = 'xmlns:';
          $max_length = length($data);
        } elsif (exists($length{_XMLNS})) {
          %length = (_XMLNSCOLON => $length{_XMLNSCOLON});
          $data = 'xmlns';
          $max_length = length($data);
        } else {
          #
          # Everything else has the same (default) priority of 0: keep the longests only
          #
          %length = map {$_ => $length{$_}} grep {
            if ($length{$_} == $max_length) {
              $data //= substr($_[1], $pos, $max_length);
              1;
            } else {
              0;
            }
          } keys %length;
        }
        #
        # Push the alternatives and complete
        #
        foreach (keys %length) {
          $r->lexeme_alternative_by_symbol_id($_);
          #
          # Remember last data for this lexeme
          #
          $self->{_last_lexeme}->{$_} = $data;
        }
        #
        # Position 0 and length 1: the Marpa input buffer is virtual
        #
        $r->lexeme_complete(0, 1);
        #
        # Update all trackers
        #
        my $next_pos        = $self->{_next_pos}        = $pos + $max_length;
        my $next_global_pos = $self->{_next_global_pos} = $global_pos + $max_length;
        my $linebreaks;
        my $next_global_column;
        my $next_global_line;
        if ($linebreaks = () = $data =~ /\R/g) {
          $next_global_line   = $self->{_next_global_line}   = $LineNumber + $linebreaks;
          $next_global_column = $self->{_next_global_column} = 1 + ($max_length - $+[0]);
        } else {
          $next_global_line   = $self->{_next_global_line}   = $LineNumber;
          $next_global_column = $self->{_next_global_column} = $ColumnNumber + $max_length;
        }
        if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
          $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_MOVE Push %s", $LineNumber, $ColumnNumber, $next_global_line, $next_global_column, [ keys %length ]);
          if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
            $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_MOVE Push spans on %d characters:", $LineNumber, $ColumnNumber, $next_global_line, $next_global_column, $max_length);
            foreach (split(/\R/, hexdump(data => $data, suppress_warnings => 1))) {
              $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_MOVE ... %s", $LineNumber, $ColumnNumber, $next_global_line, $next_global_column, $_);
            }
          }
        }
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
          if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
            $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE No prediction and grammar end flag is on", $LineNumber, $ColumnNumber);
          }
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
  my ($self,  undef, $r, $pos, $length, $posp, $lengthp, $grammar, $eol) = @_;
  #
  # Crunch previous data unless we are in the decl context
  #
  if (! $MarpaX::Languages::XML::Impl::Parser::in_decl) {
    #
    # Faster like this -;
    #
    if ($pos >= $length) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
        $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE Rolling-out buffer", $self->LineNumber, $self->ColumnNumber);
      }
      $_[1] = '';
    } else {
      if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
        $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE Rolling-out %d characters", $self->LineNumber, $self->ColumnNumber, $pos);
      }
      #
      # substr is efficient at front-end of a string
      #
      substr($_[1], 0, $pos, '');
    }
    $pos = 0;
  }
  #
  # Read more data
  #
  if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
    $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Reading %d characters", $self->LineNumber, $self->ColumnNumber, $self->block_size);
  }
  $length = $self->_read($_[1], $r, $grammar, $eol);

  ${$lengthp}    = $self->_set__length($length);
  ${$posp}       = $self->_set__pos($pos);

  #
  # And re-position internal buffer
  #
  pos($_[1]) = $pos;

  return $length - $pos;
}

sub _eol {
  my ($self, undef, $r, $grammar, $orig_length, $decl) = @_;

  my $error_message;
  my $eol_length = $grammar->eol($_[1], $self->{_eof}, $decl, \$error_message);
  if ($eol_length < 0) {
    #
    # This is an error
    #
    $self->_parse_exception($error_message, $r);
  }
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace && ($eol_length != $orig_length)) {
    $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE End-of-line handling removed %d character%s", $self->LineNumber, $self->ColumnNumber, $orig_length - $eol_length, ($orig_length - $eol_length) > 0 ? 's' : '');
  }
  return $eol_length;
}

sub _read {
  my ($self, undef, $r, $grammar, $eol) = @_;

  my $length;
  do {
    my $io_length;
    $self->io->read;
    if (($io_length = $self->io->length) <= 0) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
        $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE EOF", $self->LineNumber, $self->ColumnNumber);
      }
      $self->{_eof} = 1;
      return 0;
    } else {
      if ($eol) {
        #
        # This can return 0
        #
        my $error_message;
        my $eol_length = $grammar->eol($_[1], $self->{_eof}, \$error_message);
        if ($eol_length < 0) {
          #
          # This is an error
          #
          $self->_parse_exception($error_message, $r);
        } elsif ($eol_length > 0) {
          if ($MarpaX::Languages::XML::Impl::Parser::is_trace && ($eol_length != $io_length)) {
            $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE End-of-line handling removed %d character%s", $self->LineNumber, $self->ColumnNumber, $io_length - $eol_length, ($io_length - $eol_length) > 0 ? 's' : '');
          }
          $length = $eol_length;
        }
      } else {
        $length = $io_length;
      }
    }
  } while (! $length);

  return $length;
}

sub start_document {
  my ($self, $user_code) = @_;

  if (! $self->_start_document_done) {
    if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
      $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE SAX event start_document", $self->LineNumber, $self->ColumnNumber);
    }
    if ($user_code) {
      my $rc = $self->$user_code({});
      $self->_parse_rc($rc);
    }
    $self->_start_document_done(1);
  }
  return 1;
}

sub end_document {
  my ($self, $user_code) = @_;

  if ($user_code) {
    $self->$user_code(@_);
  }

  return 1;
}

sub start_element {
  my ($self, $user_code) = @_;

  if ($user_code) {
    $self->$user_code({
                       Attributes => { $self->_elements__attribute }
                      }
                     );
  }

  $self->_clear__attribute;

  return 1;
}

sub end_element {
  my ($self, $user_code) = @_;

  if ($user_code) {
    $self->$user_code(@_);
  }

  return 1;
}

sub _parse_prolog {
  my ($self) = @_;              # buffer is in $_[1]

  #
  # Encoding object instance
  #
  my $encoding = MarpaX::Languages::XML::Impl::Encoding->new();
  my ($bom_encoding, $guess_encoding, $orig_encoding, $byte_start)  = $self->_find_encoding($encoding);
  if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
    $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE BOM and/or guess gives encoding %s and byte offset %d", $self->LineNumber, $self->ColumnNumber, $orig_encoding, $byte_start);
  }
  #
  # Default grammar event and callbacks
  #
  my $grammar;
  my %grammar_event = (
                       'prolog$'         => { type => 'completed', symbol_name => 'prolog'        },
                       'ENCNAME$'        => { type => 'completed', symbol_name => 'ENCNAME'       },
                       'XMLDECL_START$'  => { type => 'completed', symbol_name => 'XMLDECL_START' },
                       'XMLDECL_END$'    => { type => 'completed', symbol_name => 'XMLDECL_END'   },
                       'VERSIONNUM$'     => { type => 'completed', symbol_name => 'VERSIONNUM'    },
                       'ELEMENT_START$ ' => { type => 'completed', symbol_name => 'ELEMENT_START' },
                      );
  my %callbacks = (
                   #
                   # LEXEME EVENTS: THEY ALWAYS START with "_", ARE ALWAYS PREDICTED EVENTS
                   # AND NEED NOT TO BE DECLARED IN %grammar_event
                   #
                   'ENCNAME$' => sub {
                     my ($self, undef, $r) = @_;    # $_[1] is the internal buffer
                     #
                     # Encoding is composed only of ASCII codepoints, so uc is ok
                     #
                     my $xml_encoding = uc($self->_get__last_lexeme('_ENCNAME'));
                     if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                       $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE XML says encoding %s", $self->LineNumber, $self->ColumnNumber, $xml_encoding);
                     }
                     #
                     # Check eventual encoding v.s. endianness. Algorithm vaguely taken from
                     # https://blogs.oracle.com/tucu/entry/detecting_xml_charset_encoding_again
                     #
                     my $final_encoding = $encoding->final($bom_encoding, $guess_encoding, $xml_encoding);
                     if ($final_encoding ne $self->_encoding) {
                       if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                         $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE XML encoding %s disagree with current encoding %s", $self->LineNumber, $self->ColumnNumber, $xml_encoding, $self->_encoding);
                       }
                       $orig_encoding = $final_encoding;
                       #
                       # No need to go further. We will have to retry anyway.
                       #
                       return 0;
                     }
                     return 1;
                   },
                   'XMLDECL_START$' => sub {
                     my ($self, undef, $r) = @_;    # $_[1] is the internal buffer
                     if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                       $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE XML Declaration is starting", $self->LineNumber, $self->ColumnNumber);
                     }
                     #
                     # Remember we are in a Xml or Text declaration
                     #
                     $MarpaX::Languages::XML::Impl::Parser::in_decl = 1;
                     $self->_decl_start_pos($self->_pos - length($self->_get__last_lexeme('_XMLDECL_START')));
                     return 1;
                   },
                   'XMLDECL_END$' => sub {
                     my ($self, undef, $r) = @_;    # $_[1] is the internal buffer
                     if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                       $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE XML Declaration is ending", $self->LineNumber, $self->ColumnNumber);
                     }
                     #
                     # Remember we not in a Xml or Text declaration
                     #
                     $MarpaX::Languages::XML::Impl::Parser::in_decl = 0;
                     $self->_decl_end_pos($self->_pos);
                     #
                     # And apply end-of-line handling to this portion using a specific decl eol method
                     #
                     my $decl = substr($_[1], $self->_decl_start_pos, $self->_decl_end_pos - $self->_decl_start_pos);
                     my $orig_length = length($decl);
                     my $error_message;
                     my $eol_length = $grammar->eol_decl($decl, $self->_eof, \$error_message);
                     #
                     # Per def a declaration does not end with "\x{D}", so eol_decl should never return 0
                     #
                     if ($eol_length <= 0) {
                       #
                       # This is an error
                       #
                       $self->_parse_exception($error_message, $r);
                     }
                     if ($MarpaX::Languages::XML::Impl::Parser::is_trace && ($eol_length != $orig_length)) {
                       $self->_logger->tracef("$LOG_LINECOLUMN_FORMAT_HERE End-of-line handling in declaration removed %d character%s", $self->LineNumber, $self->ColumnNumber, $orig_length - $eol_length, ($orig_length - $eol_length) > 0 ? 's' : '');
                     }
                     if ($eol_length != $orig_length) {
                       #
                       # Replace in $_[1]
                       #
                       substr($_[1], $self->_decl_start_pos, $self->_decl_end_pos - $self->_decl_start_pos, $decl);
                     }
                     return 1;
                   },
                   'VERSIONNUM$' => sub {
                     my ($self, undef, $r) = @_;    # $_[1] is the internal buffer
                     if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                       $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE XML says version number %s", $self->LineNumber, $self->ColumnNumber, $self->_get__last_lexeme('_VERSIONNUM'));
                     }
                     return 1;
                   },
                   'ELEMENT_START$' => sub {
                     my ($self, undef, $r) = @_;    # $_[1] is the internal buffer
                     if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                       $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE XML has a root element", $self->LineNumber, $self->ColumnNumber);
                     }
                     #
                     # Move position back
                     #
                     $self->_set__pos($self->_pos - length($self->_get__last_lexeme('_ELEMENT_START')));
                     return 0;
                   }
                  );
  #
  # Other grammar events for eventual SAX handlers. At this stage only start_document
  # is supported.
  #
  foreach (qw/start_document/) {
    my $user_code = $self->get_sax_handler($_);
    my $internal_code = $_;
    $grammar_event{$_} = { type => 'nulled', symbol_name => $_ };
    $callbacks{$_} = sub {
      my ($self, undef, $r) = @_; # $_[1] is the internal buffer
      return $self->$internal_code($user_code);
    };
  }
  #
  # Generate grammar
  #
  $grammar = $self->_generate_grammar(start => 'document', grammar_event => \%grammar_event);
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
                        1                  # eol
                       );
  if ($self->_encoding ne $orig_encoding) {
    if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
      $self->_logger->debugf("$LOG_LINECOLUMN_FORMAT_HERE Redoing parse using encoding %s instead of %s", $self->LineNumber, $self->ColumnNumber, $orig_encoding, $self->_encoding);
    }
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

sub _generate_grammar {
  my ($self, %grammar_option) = @_;

  if (! Undef->check($self->xml_version)) {
    $grammar_option{xml_version} = $self->xml_version;
  }

  if (! Undef->check($self->xml_support)) {
    $grammar_option{xml_support} = $self->xml_support;
  }

  return MarpaX::Languages::XML::Impl::Grammar->new(%grammar_option);
}

sub _parse_element {
  my ($self) = @_;              # buffer is in $_[1]

  #
  # Default grammar event and callbacks
  #
  my $grammar;
  my %grammar_event = (
                       'element$'       => { type => 'completed', symbol_name => 'element' },
                       'AttributeName$' => { type => 'completed', symbol_name => 'AttributeName' },
                       'AttValue$'      => { type => 'completed', symbol_name => 'AttValue' },
                      );
  my %attribute = ();
  my $attname = '';
  my @attvalue = ();
  my %callbacks = (
                   #
                   # LEXEME EVENTS: THEY ALWAYS START with "_", ARE ALWAYS PREDICTED EVENTS
                   # AND NEED NOT TO BE DECLARED IN %grammar_event
                   #
                   '_ATTVALUEINTERIORDQUOTEUNIT' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     push(@attvalue, $data);
                     return 1;
                   },
                   '_ATTVALUEINTERIORSQUOTEUNIT' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     push(@attvalue, $data);
                     return 1;
                   },
                   '_ENTITYREF_END' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     my $name = $self->_get__last_lexeme('_NAME');
                     if ($self->_attribute_context) {
                       my $entityref = $self->_entityref->get($name);
                       if (! defined($entityref)) {
                         $self->_parse_exception("Entity reference $name does not exist", $r);
                       } else {
                         push(@attvalue, $entityref);
                       }
                     }
                     return 1;
                   },
                   #
                   # _DIGITMANY and _ALPHAMANY appears only in the context of a CharRef
                   #
                   '_DIGITMANY' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     if ($self->_attribute_context) {
                       #
                       # A char reference is nothing else but the chr() of it.
                       # Perl will warn by itself if this is not a good character.
                       #
                       push(@attvalue, chr(hex($data)));
                     }
                     return 1;
                   },
                   '_ALPHAMANY' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     if ($self->_attribute_context) {
                       #
                       # A char reference is nothing else but the chr() of it.
                       # Perl will warn by itself if this is not a good character.
                       #
                       push(@attvalue, chr(hex($data)));
                     }
                     return 1;
                   },
                   'AttributeName$' => sub {
                     my ($self, undef, $r) = @_;    # $_[1] is the internal buffer
                     $attname = $self->_get__last_lexeme('_NAME');
                     $self->_attribute_context(1);
                     return 1;
                   },
                   'AttValue$' => sub {
                     my ($self, undef, $r) = @_;    # $_[1] is the internal buffer
                     $self->_attribute_context(0);
                     my $attvalue = $grammar->attvalue($self->_cdata_context, $self->_entityref, @attvalue);
                     $self->_set__attribute($attname, { Name => $attname, Value => $attvalue, NamespaceURI => '', Prefix => '', LocalName => '' });
                     @attvalue = ();
                     return 1;
                   },
                  );
  #
  # Other grammar events for eventual SAX handlers.
  #
  foreach (qw/start_element end_element/) {
    my $user_code = $self->get_sax_handler($_);
    my $internal_code = $_;
    $grammar_event{$_} = { type => 'nulled', symbol_name => $_ };
    $callbacks{$_} = sub {
      my ($self, undef, $r) = @_; # $_[1] is the internal buffer
      return $self->$internal_code($user_code);
    };
  }
  #
  # Generate grammar
  #
  $grammar = $self->_generate_grammar(start => 'element', grammar_event => \%grammar_event);
  #
  # Go
  #
  $self->_generic_parse(
                        $_[1],             # buffer
                        $grammar,          # grammar
                        'element$',        # end_event_name
                        \%callbacks,       # callbacks
                        1                  # eol
                       );
}

sub parse {
  my ($self) = @_;

  #
  # Localized variables
  #
  local $MarpaX::Languages::XML::Impl::Parser::is_trace = $self->_logger->is_trace;
  local $MarpaX::Languages::XML::Impl::Parser::is_debug = $self->_logger->is_debug;
  local $MarpaX::Languages::XML::Impl::Parser::is_warn  = $self->_logger->is_warn;
  local $MarpaX::Languages::XML::Impl::Parser::in_decl  = 0;
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
