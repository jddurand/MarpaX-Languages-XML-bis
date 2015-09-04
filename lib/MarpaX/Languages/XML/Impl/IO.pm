package MarpaX::Languages::XML::Impl::IO;
use Fcntl qw/:seek/;
use IO::All;
use IO::All::LWP;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Role::IO;
use Moo;
use MooX::late;
use Types::Standard qw/InstanceOf Str Int/;
use Try::Tiny;

# ABSTRACT: MarpaX::Languages::XML::Role::IO implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is an implementation of MarpaX::Languages::XML::Role::IO. It provides a layer on top of IO::All.

=cut

has _io => (
            is => 'rw',
            isa => InstanceOf['IO::All']
           );

has _source => (
                is => 'rw',
                isa => Str
               );

has _block_size_value => (
                          is => 'rw',
                          isa => Int,
                          default => 1024
                         );

sub open {
  my $self = shift;
  my $source = shift;

  $self->_source($source);

  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('[IO] Opening %s %s', $self->_source, \@_);
  }
  $self->_io(io($self->_source));
  $self->_io->open(@_);

  return $self;
}

sub close {
  my $self = shift;

  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('[IO] Closing %s', $self->_source);
  }
  $self->_io->close();

  return $self;
}

sub block_size {
  my $self = shift;

  $self->_io->block_size($self->block_size_value(@_));

  return $self;
}

sub block_size_value {
  my $self = shift;

  my $rc = $self->_block_size_value(@_);
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('[IO] %s block-size %s %s', @_ ? 'Setting' : 'Getting', @_ ? '->' : '<-', $rc);
  }

  return $rc;
}

sub binary {
  my $self = shift;

  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('[IO] Setting binary');
  }
  $self->_io->binary();

  return $self;
}

sub length {
  my $self = shift;

  my $rc = $self->_io->length(@_);
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('[IO] Getting length -> %s', $rc);
  }
  return $rc;
}

sub buffer {
  my $self = shift;

  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('[IO] %s buffer', @_ ? 'Setting' : 'Getting');
  }
  return $self->_io->buffer(@_);
}


{
  no warnings 'redefine';
  sub read {
    my $self = shift;

    if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
      $self->_logger->tracef('[IO] Reading %d units', $self->_block_size_value);
    }
    $self->_io->read;

    return $self;
  }
}

sub clear {
  my $self = shift;

  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('[IO] Clearing buffer');
  }
  $self->_io->clear;

  return $self;
}

sub tell {
  my $self = shift;

  my $rc = $self->_io->tell;
  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('[IO] Tell -> %s', $rc);
  }
  return $rc;
}

sub seek {
  my $self = shift;

  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('[IO] Seek %s', \@_);
  }
  $self->_io->seek(@_);

  return $self;
}

sub encoding {
  my $self = shift;
  my $encoding = shift;

  if ($MarpaX::Languages::XML::Impl::Parser::is_trace) {
    $self->_logger->tracef('[IO] Setting encoding %s', $encoding);
  }
  $self->_io->encoding($encoding);

  return $self;
}

sub pos {
  my $self = shift;
  my $pos = shift;

  my $pos_ok = 0;
  try {
    my $tell = $self->tell;
    if ($tell != $pos) {
      $self->seek($pos, SEEK_SET);
      if ($self->tell != $pos) {
        MarpaX::Languages::XML::Exception->throw(sprintf('Failure setting position from %d to %d failure', $tell, $pos));
      } else {
        $pos_ok = 1;
      }
    } else {
      $pos_ok = 1;
    }
  };
  if (! $pos_ok) {
    #
    # Ah... not seekable perhaps
    # The only alternative is to reopen the stream
    #
    my $orig_block_size = $self->block_size_value;
    $self->close;
    $self->open($self->_source);
    $self->binary;
    $self->block_size($pos);
    $self->read;
    if ($self->length != $pos) {
      #
      # Really I do not know what else to do
      #
      MarpaX::Languages::XML::Exception->throw("Re-opening failed to position " . $self->_source . " at byte $pos");
    } else {
      #
      # Restore original io block size
      $self->block_size($self->block_size_value($orig_block_size));
    }
  }

  return $self;
}

with 'MooX::Role::Logger';
with 'MarpaX::Languages::XML::Role::IO';

1;
