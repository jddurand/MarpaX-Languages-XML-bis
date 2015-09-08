package MarpaX::Languages::XML::Impl::Parser;
use Data::Hexdumper qw/hexdump/;
use Marpa::R2;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Impl::CharRef;
use MarpaX::Languages::XML::Impl::Encoding;
use MarpaX::Languages::XML::Impl::EntityRef;
use MarpaX::Languages::XML::Impl::Grammar;
use MarpaX::Languages::XML::Impl::PEReference;
use Moo;
use MooX::late;
use MooX::HandlesVia;
use MooX::Role::Logger;
use Scalar::Util qw/reftype/;
use Try::Tiny;
use Types::Standard -all;
use Types::Common::Numeric -all;

# ABSTRACT: MarpaX::Languages::XML::Role::parser implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is an implementation of MarpaX::Languages::XML::Role::Parser.

=cut

#
# Internal attributes
# -------------------

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
has _charref => (
                 is => 'rw',
                 isa => ConsumerOf['MarpaX::Languages::XML::Role::CharRef'],
                 default => sub { return MarpaX::Languages::XML::Impl::CharRef->new() }
                );
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
# EOF
#
has _eof => (
             is => 'rw',
             isa => Bool,
             default => 0
            );

#
# XmlDecl or TextDecl context because of XML1.1 restriction on #x85 and #x2028
#
has _inDecl => (
                is => 'rw',
                isa => Bool,
                default => 0
               );
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
                writer      => '_set__length'
               );
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
             writer      => '_set__pos',
             trigger     => \&_trigger__pos
            );
#
# Reference to internal buffer. Used only for logging data and to avoid a call to $self->io->buffer that
# would log... 'Getting buffer' -;
#
has _bufferRef => (
                   is          => 'rw',
                   isa         => ScalarRef
                  );

sub _trigger__pos {
  my ($self, $pos) = @_;

  $self->_set__remaining($self->_length - $pos);
  if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
    $self->_logger->debugf('[%d:%d] Pos: %d, Length: %d, Remaining: %d', $self->LineNumber, $self->ColumnNumber, $pos, $self->_length, $self->_remaining);
    if ($self->_remaining > 0) {
      $self->_logger->debugf('[%d:%d] Data: %s', $self->LineNumber, $self->ColumnNumber,
                             hexdump(data              => substr(${$self->_bufferRef}, $self->_pos, 15),
                                     suppress_warnings => 1,
                                    ));
    }
  }
}

#
# Remaining characters
#
has _remaining => (
                   is          => 'rw',
                   isa         => PositiveOrZeroInt,
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

sub _exception {
  my ($self, $message, $r) = @_;

  my %hash = (
              Message      => $message || '',
              LineNumber   => $self->LineNumber,
              ColumnNumber => $self->ColumnNumber
             );
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
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

  MarpaX::Languages::XML::Exception->throw(%hash);
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
    $self->_exception('EOF when reading first bytes');
  }
  my $buffer = ${$self->_bufferRef};

  my $bom_encoding = '';
  my $guess_encoding = '';

  my ($found_encoding, $byte_start) = $encoding->bom($buffer);
  if (length($found_encoding) <= 0) {
    $found_encoding = $encoding->guess($buffer);
    if (length($found_encoding) <= 0) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
        $self->_logger->debugf('Assuming relaxed (perl) utf8 encoding');
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
# It is assumed that caller ONLY USE completed or nulled events
# The predicted events are RESERVED for lexeme prediction.
#
sub _generic_parse {
  #
  # buffer is accessed using $_[1] to avoid dereferencing $self->io->buffer everytime
  #
  my ($self, undef, $grammar, $end_event_name, $callbacks_ref, $eol) = @_;

  #
  # Create a recognizer
  #
  my $r = Marpa::R2::Scanless::R->new({ grammar => $grammar->scanless });

  #
  # Mapping event <=> lexeme cached for performance
  #
  my %lexeme = ();
  my %prediction = ();
  my %min_chars = ();
  my %lexeme_regexp = ();
  my %lexeme_exclusion = ();
  my %fixed_length = ();
  my %callback = ();

  #
  # Loop on input
  #
  for (
       #
       # The buffer for Marpa is not of importance here, but two bytes at least for the length to avoid exhaustion.
       # Since we pause on everything, read() and resume() always never change position in the virtual buffer
       #
       $r->read(\'  ')
       ;
       ;
       #
       # Resume will croak if grammar is exhausted. We handle this case ourself (absence of prediction + remaining chargs)
       #
       $r->resume()
      ) {
    my $can_stop = 0;
    my @event_names = map { $_->[0] } @{$r->events()};
    if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
      $self->_logger->tracef('[%d:%d] Events: %s', $self->LineNumber, $self->ColumnNumber, \@event_names);
    }

  manage_events:
    #
    # Predicted events always come first -;
    #
    my $have_lexeme_prediction = 0;
    my $data;
    my %length = ();
    my $max_length = 0;
    my @predicted_lexemes = ();
    my $pos = $self->_pos;
    my $length = $self->_length;

    foreach (@event_names) {
      $lexeme{$_}     //= $grammar->get_grammar_event($_)->{lexeme} // '';
      $prediction{$_} //= $grammar->get_grammar_event($_)->{type} eq 'predicted';    # An event must always be set

      if ($lexeme{$_} && $prediction{$_}) {
        my $lexeme = $lexeme{$_};
        #
        # INTERNAL PREDICTION EVENTS
        # --------------------------
        $have_lexeme_prediction = 1;
        push(@predicted_lexemes, $lexeme);
        #
        # Check if the decision about this lexeme can be done
        #
        $min_chars{$_} //= $grammar->get_grammar_event($_)->{min_chars} // 0;
        my $remaining = $self->_remaining;
        if (($remaining <= 0) || ($min_chars{$_} > $remaining)) {
          my $old_remaining = $remaining;
          if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
            if ($remaining > 0) {
              $self->_logger->tracef('[%d:%d] Lexeme %s requires %d chars > %d remaining for decidability', $self->LineNumber, $self->ColumnNumber, $lexeme, $min_chars{$_}, $self->_remaining);
            }
          }
          $self->_reduceAndRead($_[1], $r, $grammar, $eol);
          if ($self->_remaining > $old_remaining) {
            #
            # Something was read
            #
            goto manage_events;
          } else {
            if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
              $self->_logger->debugf('[%d:%d] Nothing more read', $self->LineNumber, $self->ColumnNumber);
            }
          }
        }
        #
        # Check if this variable length lexeme is reaching the end of the buffer.
        #
        pos($_[1]) = $pos;
        #
        # It is assumed that if the caller setted a lexeme name, he also setted a lexeme regexp
        #
        $lexeme_regexp{$lexeme} //= $grammar->get_lexeme_regexp($lexeme);         # It is a configuration error to have this undef at this stage
        if ($_[1] =~ $lexeme_regexp{$lexeme}) {
          #
          # Note: our patterns are compiled with the /p modifier
          #
          my $matched_data = ${^MATCH};
          $lexeme_exclusion{$lexeme} //= $grammar->get_lexeme_exclusion($lexeme) // '';
          if ($lexeme_exclusion{$lexeme} && ($matched_data =~ $lexeme_exclusion{$lexeme})) {
            if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
              $self->_logger->tracef('[%d:%d] Lexeme %s match excluded', $self->LineNumber, $self->ColumnNumber, $lexeme);
            }
          } else {
            $fixed_length{$_} //= $grammar->get_grammar_event($_)->{fixed_length} // 0;
            if (($+[0] >= $length) && ! $fixed_length{$_}) {
              if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
                $self->_logger->tracef('[%d:%d] Lexeme %s is of unpredicted size and currently reaches end-of-buffer', $self->LineNumber, $self->ColumnNumber, $lexeme);
              }
              my $old_remaining = $self->_remaining;
              $self->_reduceAndRead($_[1], $r, $grammar, $eol);
              if ($self->_remaining > $old_remaining) {
                #
                # Something was read
                #
                goto manage_events;
              } else {
                if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                  $self->_logger->debugf('[%d:%d] Nothing more read', $self->LineNumber, $self->ColumnNumber);
                }
              }
            }
            my $length_lexeme = $length{$lexeme} = length($matched_data);
            if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
              $self->_logger->tracef('[%d:%d] %s: match of length %d', $self->LineNumber, $self->ColumnNumber, $lexeme, $length_lexeme);
            }
            if ((! $max_length) || ($length_lexeme > $max_length)) {
              $data = $matched_data;
              $max_length = $length_lexeme;
            }
          }
        } else {
          if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
            $self->_logger->tracef('[%d:%d] %s: no match', $self->LineNumber, $self->ColumnNumber, $lexeme);
          }
        }
      } else {
        #
        # ANY OTHER EVENT
        # ---------------
        if ($_ eq $end_event_name) {
          $can_stop = 1;
          if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
            $self->_logger->debugf('[%d:%d] Grammar end event %s', $self->LineNumber, $self->ColumnNumber, $_);
          }
        }
        #
        # Callback ?
        #
        my $code = $callback{$_} //= $callbacks_ref->{$_} // '';
        #
        # A G1 callback has no argument
        #
        my $rc_switch = $code ? $self->$code($_[1], $r) : 1;
        #
        # Any false return value mean immediate stop
        #
        if (! $rc_switch) {
          if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
            $self->_logger->debugf('[%d:%d] Event callback %s says to stop', $self->LineNumber, $self->ColumnNumber, $_);
          }
          return;
        }
      }
    }
    if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
      $self->_logger->tracef('[%d:%d] have_lexeme_prediction %d can_stop %d length %s', $self->LineNumber, $self->ColumnNumber, $have_lexeme_prediction, $can_stop, \%length);
    }
    if ($have_lexeme_prediction) {
      if (! $max_length) {
        if ($can_stop) {
          if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
            $self->_logger->tracef('[%d:%d] No predicted lexeme found but grammar end flag is on', $self->LineNumber, $self->ColumnNumber);
          }
          return;
        } else {
          $self->_exception('No predicted lexeme found', $r);
        }
      } else {
        #
        # Update position and remaining chars in internal buffer, global line and column numbers. Wou might think it is too early, but
        # this is to have the expected next positions when doing predicted lexeme callbacks.
        #
        my $next_pos = $self->_set__next_pos($pos + $max_length);
        my $next_global_pos = $self->_set__next_global_pos($self->_global_pos + $max_length);
        my $linebreaks;
        my $next_global_column;
        my $next_global_line;
        if ($linebreaks = () = $data =~ /\R/g) {
          $next_global_line = $self->_set__next_global_line($self->LineNumber + $linebreaks);
          $next_global_column = $self->_set__next_global_column(1 + (length($data) - $+[0]));
        } else {
          $next_global_line = $self->_set__next_global_line($self->LineNumber);
          $next_global_column = $self->_set__next_global_column($self->ColumnNumber + $max_length);
        }
        my @alternatives = grep { $length{$_} == $max_length } keys %length;
        if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
          $self->_logger->debugf('[%d:%d->%d:%d] Match: %s, length %d', $self->LineNumber, $self->ColumnNumber, $next_global_line, $next_global_column, \@alternatives, $max_length);
        }
        my @lexeme_complete_events = ();
        foreach (@alternatives) {
          #
          # Callback on lexeme prediction
          #
          my $lexeme_prediction_event = "^$_";
          my $code = $callback{$lexeme_prediction_event} //= $callbacks_ref->{$lexeme_prediction_event} // '';
          #
          # A L0 callback has a lot of arguments
          #
          my $rc_switch = $code ? $self->$code($_[1], $r, $data) : 1;
          if (! $rc_switch) {
            if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
              $self->_logger->debugf('[%d:%d] Event callback %s says to stop', $self->LineNumber, $self->ColumnNumber, $lexeme_prediction_event);
            }
            return;
          }
        }
        #
        # If we are here, this mean that no eventual callback says to not be there -;
        #
        foreach (@alternatives) {
          #
          # Push alternative
          #
          $r->lexeme_alternative($_);
          $self->_set__last_lexeme($_, $data);
          #
          # Our stream is virtual, i.e. Marpa will never see the lexemes.
          # So we handle ourself the callbacks on lexeme completion.
          #
          push(@lexeme_complete_events, "$_\$");
        }
        if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
          $self->_logger->tracef('[%d:%d->%d:%d] Lexeme complete of length %d', $self->LineNumber, $self->ColumnNumber, $next_global_line, $next_global_column, $max_length);
        }
        #
        # Position 0 and length 1: the Marpa input buffer is virtual
        #
        $r->lexeme_complete(0, 1);
        $self->_set_LineNumber($next_global_line);
        $self->_set_ColumnNumber($next_global_column);
        $self->_set__global_pos($next_global_pos);
        $self->_set__pos($next_pos);
        #
        # Fake the lexeme completion events
        #
        foreach (@lexeme_complete_events) {
          my $code = $callback{$_} //= $callbacks_ref->{$_} // '';
          #
          # A L0 completion callback has less arguments than a predicted one
          #
          my $rc_switch = $code ? $self->$code($_[1], $r, $data) : 1;
          if (! $rc_switch) {
            if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
              $self->_logger->debugf('[%d:%d] Event callback %s says to stop', $self->LineNumber, $self->ColumnNumber, $_);
            }
            return;
          }
        }
        #
        # lexeme complete can generate new events: handle them before eventually resuming
        #
        @event_names = map { $_->[0] } @{$r->events()};
        if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
          $self->_logger->tracef('[%d:%d] Events: %s', $self->LineNumber, $self->ColumnNumber, \@event_names);
        }
        goto manage_events;
      }
    } else {
      #
      # No prediction: this is ok only if grammar end_of_grammar flag is set
      #
      if ($can_stop) {
        if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
          $self->_logger->tracef('[%d:%d] No prediction and grammar end flag is on', $self->LineNumber, $self->ColumnNumber);
        }
        return;
      } else {
        $self->_exception('No prediction and grammar end flag is not set', $r);
      }
    }
  }

  return;
}

sub _reduceAndRead {
  my ($self,  undef, $r, $grammar, $eol) = @_;
  #
  # Crunch previous data unless we are in the decl context
  #
  if ($self->_pos > 0 && ! $self->_inDecl) {
    #
    # Faster like this -;
    #
    if ($self->_pos >= $self->_length) {
      if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
        $self->_logger->tracef('[%d:%d] Rolling-out buffer', $self->LineNumber, $self->ColumnNumber);
      }
      $_[1] = '';
    } else {
      if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
        $self->_logger->tracef('[%d:%d] Rolling-out %d characters', $self->LineNumber, $self->ColumnNumber, $self->_pos);
      }
      substr($_[1], 0, $self->_pos, '');
    }
  }
  #
  # Read more data
  #
  if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
    $self->_logger->debugf('[%d:%d] Reading %d characters', $self->LineNumber, $self->ColumnNumber, $self->block_size);
  }

  $self->_set__length($self->_read($_[1], $r, $grammar, $eol));
  $self->_set__pos($self->_inDecl ? $self->_pos : 0);
  return;
}

sub _eol {
  my ($self, undef, $r, $grammar, $orig_length, $decl) = @_;

  my $error_message;
  my $eol_length = $grammar->eol($_[1], $self->_eof, $decl, \$error_message);
  if ($eol_length < 0) {
    #
    # This is an error
    #
    $self->_exception($error_message, $r);
  }
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace && ($eol_length != $orig_length)) {
    $self->_logger->tracef('[%d:%d] End-of-line handling removed %d character%s', $self->LineNumber, $self->ColumnNumber, $orig_length - $eol_length, ($orig_length - $eol_length) > 0 ? 's' : '');
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
        $self->_logger->tracef('[%d:%d] EOF', $self->LineNumber, $self->ColumnNumber);
      }
      $self->_eof(1);
      return 0;
    } else {
      if ($eol) {
        #
        # This can return 0
        #
        my $error_message;
        my $eol_length = $grammar->eol($_[1], $self->_eof, \$error_message);
        if ($eol_length < 0) {
          #
          # This is an error
          #
          $self->_exception($error_message, $r);
        } elsif ($eol_length > 0) {
          if ($MarpaX::Languages::XML::Impl::Parser::is_trace && ($eol_length != $io_length)) {
            $self->_logger->tracef('[%d:%d] End-of-line handling removed %d character%s', $self->LineNumber, $self->ColumnNumber, $io_length - $eol_length, ($io_length - $eol_length) > 0 ? 's' : '');
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
      $self->_logger->debugf('[%d:%d] SAX event start_document', $self->LineNumber, $self->ColumnNumber);
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
    $self->_logger->debugf('[%d:%d] BOM and/or guess gives encoding %s and byte offset %d', $self->LineNumber, $self->ColumnNumber, $orig_encoding, $byte_start);
  }
  #
  # Default grammar event and callbacks
  #
  my $grammar;
  my %grammar_event = ( 'prolog$' => { type => 'completed', symbol_name => 'prolog' } );
  my %callbacks = (
                   '^_ENCNAME' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     #
                     # Encoding is composed only of ASCII codepoints, so uc is ok
                     #
                     my $xml_encoding = uc($data);
                     if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                       $self->_logger->debugf('[%d:%d] XML says encoding %s', $self->LineNumber, $self->ColumnNumber, $xml_encoding);
                     }
                     #
                     # Check eventual encoding v.s. endianness. Algorithm vaguely taken from
                     # https://blogs.oracle.com/tucu/entry/detecting_xml_charset_encoding_again
                     #
                     my $final_encoding = $encoding->final($bom_encoding, $guess_encoding, $xml_encoding);
                     if ($final_encoding ne $self->_encoding) {
                       if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                         $self->_logger->debugf('[%d:%d] XML encoding %s disagree with current encoding %s', $self->LineNumber, $self->ColumnNumber, $xml_encoding, $self->_encoding);
                       }
                       $orig_encoding = $final_encoding;
                       #
                       # No need to go further. We will have to retry anyway.
                       #
                       return 0;
                     }
                     return 1;
                   },
                   '^_XMLDECL_START' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                       $self->_logger->debugf('[%d:%d] XML Declaration is starting', $self->LineNumber, $self->ColumnNumber);
                     }
                     #
                     # Remember we in a Xml or Text declaration
                     #
                     $self->_inDecl(1);
                     $self->_decl_start_pos($self->_pos);
                     return 1;
                   },
                   'XMLDECL_END$' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                       $self->_logger->debugf('[%d:%d] XML Declaration is ending', $self->LineNumber, $self->ColumnNumber);
                     }
                     #
                     # Remember we not in a Xml or Text declaration
                     #
                     $self->_inDecl(0);
                     $self->_decl_end_pos($self->_pos);
                     #
                     # And apply end-of-line handling to this portion putting the inDecl flag to true
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
                       $self->_exception($error_message, $r);
                     }
                     if ($MarpaX::Languages::XML::Impl::Parser::is_trace && ($eol_length != $orig_length)) {
                       $self->_logger->tracef('[%d:%d] End-of-line handling in declaration removed %d character%s', $self->LineNumber, $self->ColumnNumber, $orig_length - $eol_length, ($orig_length - $eol_length) > 0 ? 's' : '');
                     }
                     if ($eol_length != $orig_length) {
                       #
                       # Replace in $_[1]
                       #
                       substr($_[1], $self->_decl_start_pos, $self->_decl_end_pos - $self->_decl_start_pos, $decl);
                     }
                     return 1;
                   },
                   '^_VERSIONNUM' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                       $self->_logger->debugf('[%d:%d] XML says version number %s', $self->LineNumber, $self->ColumnNumber, $data);
                     }
                     return 1;
                   },
                   '^_ELEMENT_START' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                       $self->_logger->debugf('[%d:%d] XML has a root element', $self->LineNumber, $self->ColumnNumber, $data);
                     }
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
  $grammar = MarpaX::Languages::XML::Impl::Grammar->new( start => 'document', grammar_event => \%grammar_event );
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
  $self->_set__length($self->io->length);
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
      $self->_logger->debugf('[%d:%d] Redoing parse using encoding %s instead of %s', $self->LineNumber, $self->ColumnNumber, $self->_encoding, $orig_encoding);
    }
    #
    # I/O reset
    #
    $self->io->encoding($self->_encoding);
    $self->io->clear;
    $self->io->pos($byte_start);
    if (++$nb_retry_because_of_encoding == 1) {
      goto retry_because_of_encoding;
    } else {
      $self->_exception('Two many retries because of encoding difference beween BOM, guess and XML');
    }
  }
}

sub _parse_element {
  my ($self) = @_;              # buffer is in $_[1]

  #
  # Default grammar event and callbacks
  #
  my $grammar;
  my $cdata_context = 0;
  my %grammar_event = (
                       'element$'       => { type => 'completed', symbol_name => 'element' },
                       'AttributeName$' => { type => 'completed', symbol_name => 'AttributeName' },
                       'AttValue$'      => { type => 'completed', symbol_name => 'AttValue' },
                      );
  my %attribute = ();
  my $attname = '';
  my @attvalue = ();
  my %callbacks = (
                   '_ATTVALUEINTERIORDQUOTEUNIT$' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     push(@attvalue, $data);
                     return 1;
                   },
                   '_ATTVALUEINTERIORSQUOTEUNIT$' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     push(@attvalue, $data);
                     return 1;
                   },
                   '_ENTITYREF_END$' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     my $name = $self->_get__last_lexeme('_NAME');
                     if ($self->_attribute_context) {
                       push(@attvalue, to_EntityRef($name));
                     }
                     return 1;
                   },
                   '_CHARREF_END1$' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     my $name = $self->_get__last_lexeme('_DIGITMANY');
                     if ($self->_attribute_context) {
                       push(@attvalue, to_CharRef($name));
                     }
                     return 1;
                   },
                   '_CHARREF_END2$' => sub {
                     my ($self, undef, $r, $data) = @_;    # $_[1] is the internal buffer
                     my $name = $self->_get__last_lexeme('_ALPHAMANY');
                     if ($self->_attribute_context) {
                       push(@attvalue, to_CharRef($name));
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
                     my $attvalue = $grammar->attvalue($cdata_context, $self->_charref, $self->_entityref, @attvalue);
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
  $grammar = MarpaX::Languages::XML::Impl::Grammar->new( start => 'element', grammar_event => \%grammar_event );
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
