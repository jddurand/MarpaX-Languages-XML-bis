package MarpaX::Languages::XML::Impl::IO;
use Fcntl qw/:seek/;
use IO::All;
use IO::All::LWP;
use MarpaX::Languages::XML::Exception;
use MarpaX::Languages::XML::Impl::Logger;
use MarpaX::Languages::XML::Role::IO;
use Moo;
use MooX::late;
use Types::Standard qw/InstanceOf Str/;
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

around BUILDARGS => sub {
  my $orig  = shift;
  my $class = shift;

  if ( @_ == 1 && !ref $_[0] ) {
    return $class->$orig( source => $_[0] );
  }
  else {
    return $class->$orig(@_);
  }
};

sub BUILD {
  my $self = shift;
  my $args = shift;

  $self->_logger->tracef('IO: Opening %s', $args->{source});
  $self->_source($args->{source});
  $self->_io(io($self->_source));

  $self->_logger->tracef('IO: Setting binary mode');
  $self->_binary;
}

sub block_size {
  my $self = shift;

  if (@_) {
    $self->_logger->tracef('IO: Setting block size to %d', $_[0]);
    $self->_io->block_size($_[0]);
  }

  return $self;
}

sub _binary {
  my $self = shift;

  $self->_logger->tracef('IO: Setting binary mode');
  $self->_io->binary();

  return $self;
}

sub length {
  my $self = shift;

  my $length = $self->_io->length;
  $self->_logger->tracef('IO: Buffer length is %d', $length);

  return $length;
}

sub buffer {
  my $self = shift;

  return $self->_io->buffer(@_);
}


sub eof {
  my $self = shift;

  return $self->_io->eof;
}


{
  no warnings 'redefine';
  sub read {
    my $self = shift;

    $self->_logger->tracef('IO: Reading %d characters', $self->_io->block_size);
    $self->_io->read;

    return $self;
  }
}

sub clear {
  my $self = shift;

  $self->_logger->tracef('IO: Clearing buffer');
  $self->_io->clear;

  return $self;
}

sub encoding {
  my $self = shift;

  if (@_) {
    $self->_logger->tracef('IO: Setting encoding to %s', $_[0]);
    $self->_io->encoding($_[0]);
  }

  return $self;
}

sub pos {
  my ($self, $pos) = @_;

  $self->_logger->tracef('IO: Setting position to %d', $pos);

  my $pos_ok = 0;
  try {
    my $tell = $self->_io->tell;
    if ($tell != $pos) {
      $self->_logger->tracef('IO: Moving io position from %d to %d', $tell, $pos);
      $self->_io->seek($pos, SEEK_SET);
      if ($self->_io->tell != $pos) {
        die sprintf('Failure setting position from %d to %d failure', $tell, $pos);
      } else {
        $pos_ok = 1;
      }
    } else {
      $pos_ok = 1;
    }
  } catch {
    $self->_logger->tracef('IO: %s', "$_");
  };
  if (! $pos_ok) {
    #
    # Ah... not seekable perhaps
    # The only alternative is to reopen the stream
    #
    $self->_logger->tracef('IO: Seek failure');

    my $orig_block_size = $self->block_size;

    $self->_logger->tracef('IO: Re-opening %s', $self->_source);
    my $io = io($self->_source);
    $self->_io($io);
    $self->_binary;
    $self->block_size($pos)->read;
    if ($self->length != $pos) {
      #
      # Really I do not know what else to do
      #
      MarpaX::Languages::XML::Exception->throw("Re-opening failed to position " . $self->_source . " at byte $pos");
    } else {
      #
      # Restore original io block size
      $self->block_size($orig_block_size);
    }
  }

  return $self;
}

with 'MarpaX::Languages::XML::Role::IO';
extends 'MarpaX::Languages::XML::Impl::Logger';

1;
