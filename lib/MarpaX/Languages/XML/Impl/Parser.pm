package MarpaX::Languages::XML::Impl::Parser;
use Data::Hexdumper qw/hexdump/;
use Marpa::R2;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Impl::Encoding;
use MarpaX::Languages::XML::Impl::Grammar;
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
                                    },
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

sub _trigger__pos {
  my ($self, $pos) = @_;

  $self->_set__remaining($self->_length - $pos);
  if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
    $self->_logger->debugf('[%d:%d] Data: %s', $self->LineNumber, $self->ColumnNumber,
                           hexdump(data              => substr(${$self->io->buffer}, $self->_pos, 15),
                                   suppress_warnings => 1,
                                  ));
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
                   default     => 1024 * 1024 * 1024
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
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace && $r) {
    $hash{Progress} = $r->show_progress();
    $hash{TerminalsExpected} = $r->terminals_expected();
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
  my $buffer = ${$self->io->buffer};

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
  my ($self, undef, $grammar, $end_event_name, $callbacks_ref) = @_;

  #
  # Create a recognizer
  #
  my $r = Marpa::R2::Scanless::R->new({ grammar => $grammar->scanless });

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

    #
    # Mapping event <=> lexeme cached for performance
    #
    my %lexeme = ();
    my %prediction = ();
    my %min_chars = ();
    my %lexeme_regexp = ();
    my %lexeme_exclusion = ();
    my %fixed_length = ();
  manage_events:
    #
    # Predicted events always come first -;
    #
    my $have_lexeme_prediction = 0;
    my $data;
    my %length = ();
    my $max_length = 0;
    my @predicted_lexemes = ();
    foreach (@event_names) {
      my $lexeme = $lexeme{$_}     //= $grammar->get_grammar_event($_)->{lexeme};
      $prediction{$_} //= $grammar->get_grammar_event($_)->{type} eq 'predicted';

      if ($lexeme && $prediction{$_}) {
        #
        # INTERNAL PREDICTION EVENTS
        # --------------------------
        $have_lexeme_prediction = 1;
        push(@predicted_lexemes, $lexeme);
        #
        # Check if the decision about this lexeme can be done
        #
        $min_chars{$_} //= $grammar->get_grammar_event($_)->{min_chars} // 0;
        if ($min_chars{$_} > $self->_remaining) {
          my $old_remaining = $self->_remaining;
          if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
            $self->_logger->tracef('[%d:%d] Lexeme %s requires %d chars > %d remaining for decidability', $self->LineNumber, $self->ColumnNumber, $lexeme, $min_chars{$_}, $self->_remaining);
          }
          $self->_reduceAndRead($_[1], 0, $r);
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
        pos($_[1]) = $self->_pos;
        #
        # It is assumed that if the caller setted a lexeme name, he also setted a lexeme regexp
        #
        $lexeme_regexp{$lexeme} //= $grammar->get_lexeme_regexp($lexeme);
        if ($_[1] =~ $lexeme_regexp{$lexeme}) {
          my $matched_data = substr($_[1], $-[0], $+[0] - $-[0]);
          $lexeme_exclusion{$lexeme} //= $grammar->get_lexeme_exclusion($lexeme) || '';
          if ($lexeme_exclusion{$lexeme} && ($matched_data =~ $lexeme_exclusion{$lexeme})) {
            if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
              $self->_logger->tracef('[%d:%d] Lexeme %s match excluded', $self->LineNumber, $self->ColumnNumber, $lexeme);
            }
          } else {
            $fixed_length{$_} //= $grammar->get_grammar_event($_)->{fixed_length} || 0;
            if (($+[0] >= $self->_length) && ! $fixed_length{$_}) {
              if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
                $self->_logger->tracef('[%d:%d] Lexeme %s is of unpredicted size and currently reaches end-of-buffer', $self->LineNumber, $self->ColumnNumber, $lexeme);
              }
              my $old_remaining = $self->_remaining;
              $self->_reduceAndRead($_[1], 0, $r);
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
            $length{$lexeme} = $+[0] - $-[0];
            if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
              $self->_logger->tracef('[%d:%d] %s: match of length %d', $self->LineNumber, $self->ColumnNumber, $lexeme, $length{$lexeme});
            }
            if ((! $max_length) || ($length{$lexeme} > $max_length)) {
              $data = $matched_data;
              $max_length = $length{$lexeme};
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
        my $code = $callbacks_ref->{$_};
        #
        # A G1 callback has no argument
        #
        my $rc_switch = defined($code) ? $self->$code() : 1;
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
        $self->_set__next_pos($self->_pos + $max_length);
        $self->_set__next_global_pos($self->_global_pos + $max_length);
        my $linebreaks;
        if ($linebreaks = () = $data =~ /\R/g) {
          $self->_set__next_global_line($self->LineNumber + $linebreaks);
          $self->_set__next_global_column(1 + (length($data) - $+[0]));
        } else {
          $self->_set__next_global_line($self->LineNumber);
          $self->_set__next_global_column($self->ColumnNumber + $max_length);
        }
        my @alternatives = grep { $length{$_} == $max_length } keys %length;
        if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
          $self->_logger->debugf('[%d:%d->%d:%d] Match: %s, length %d', $self->LineNumber, $self->ColumnNumber, $self->_next_global_line, $self->_next_global_column, \@alternatives, $max_length);
        }
        my @lexeme_complete_events = ();
        foreach (@alternatives) {
          #
          # Callback on lexeme prediction
          #
          my $lexeme_prediction_event = "^$_";
          my $code = $callbacks_ref->{$lexeme_prediction_event};
          #
          # A L0 callback has a lot of arguments
          #
          my $rc_switch = defined($code) ? $self->$code($data) : 1;
          if (! $rc_switch) {
            if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
              $self->_logger->debugf('[%d:%d] Event callback %s says to stop', $self->LineNumber, $self->ColumnNumber, $lexeme_prediction_event);
            }
            return;
          }
          #
          # A negative value means that the input have changed and alternatives should be rescanned
          #
          if ($rc_switch < 0) {
            if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
              $self->_logger->debugf('[%d:%d] Event callback %s says input have changed: rescanning', $self->LineNumber, $self->ColumnNumber, "^$_");
            }
            goto manage_events;
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
          $self->_logger->tracef('[%d:%d->%d:%d] Lexeme complete of length %d', $self->LineNumber, $self->ColumnNumber, $self->_next_global_line, $self->_next_global_column, $max_length);
        }
        #
        # Position 0 and length 1: the Marpa input buffer is virtual
        #
        $r->lexeme_complete(0, 1);
        $self->_set_LineNumber($self->_next_global_line);
        $self->_set_ColumnNumber($self->_next_global_column);
        $self->_set__global_pos($self->_next_global_pos);
        $self->_set__pos($self->_next_pos);
        #
        # Fake the lexeme completion events
        #
        foreach (@lexeme_complete_events) {
          my $code = $callbacks_ref->{$_};
          #
          # A L0 completion callback has less arguments than a predicted one
          #
          my $rc_switch = defined($code) ? $self->$code($data) : 1;
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
  my ($self,  undef, $eof_is_fatal, $r) = @_;
  #
  # Crunch previous data
  #
  if ($self->_pos > 0) {
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

  $self->_set__length($self->_read($eof_is_fatal, $r));
  $self->_set__pos(0);
  return;
}

sub _read {
  my ($self, $eof_is_fatal, $r) = @_;

  $eof_is_fatal //= 1;

  $self->io->read;
  my $new_length;
  if (($new_length = $self->io->length) <= 0) {
    if ($eof_is_fatal) {
      $self->_exception('EOF', $r);
    } else {
      if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
        $self->_logger->tracef('[%d:%d] EOF', $self->LineNumber, $self->ColumnNumber);
      }
    }
  }
  return $new_length;
}

sub start_document {
  my ($self, $user_code, @args) = @_;

  if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
    $self->_logger->debugf('[%d:%d] SAX event start_document', $self->LineNumber, $self->ColumnNumber);
  }
  #
  # No argument for start_document
  #
  $self->$user_code(@args);
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
  my %grammar_event = ( 'prolog$' => { type => 'completed', symbol_name => 'prolog' } );
  my %callbacks = (
                   '^_ENCNAME' => sub {
                     my ($self, $data) = @_;
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
                       return 0;
                     }
                     return 1;
                   },
                   '^_VERSIONNUM' => sub {
                     my ($self, $data) = @_;
                     if ($MarpaX::Languages::XML::Impl::Parser::is_debug) {
                       $self->_logger->debugf('[%d:%d] XML says version number %s', $self->LineNumber, $self->ColumnNumber, $data);
                     }
                     return 1;
                   },
                   '^_ELEMENT_START' => sub {
                     my ($self, $data) = @_;
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
    if ($self->exists_sax_handler($_)) {
      my $user_code = $self->get_sax_handler($_);
      $grammar_event{$_} = { type => 'nulled', symbol_name => $_ };
      $callbacks{$_} = sub { return shift->$_($user_code) };
    }
  }
  #
  # Generate grammar
  #
  my $grammar = MarpaX::Languages::XML::Impl::Grammar->new( start => 'document', grammar_event => \%grammar_event );
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
                        \%callbacks        # callbacks
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
  my $buffer;
  $self->io->buffer($buffer);

  # ------------
  # Parse prolog
  # ------------
  $self->_parse_prolog($buffer);

  # --------------------
  # Parse (root) element
  # --------------------
  $self->_parse_element($buffer);

}

with 'MooX::Role::Logger';
with 'MarpaX::Languages::XML::Role::Parser';

1;
