package MarpaX::Languages::XML::Impl::Logger;
use MarpaX::Languages::XML::Exception;
use Moo;
use MooX::late;

# ABSTRACT: MarpaX::Languages::XML::Role::Logger implementation

# VERSION

# AUTHORITY

=head1 DESCRIPTION

This module is a MooX::Role::Logger implementation of MarpaX::Languages::XML::Role::Logger. Marpa::R2's trace_file_handle should be tied to this package, and logging happens only at the TRACE level.

=cut

sub BEGIN {
    #
    ## Some Log implementation specificities
    #
    my $log4perl = eval 'use Log::Log4perl; 1;' || 0; ## no critic
    if ($log4perl) {
        #
        ## Here we put known hooks for logger implementations
        #
        Log::Log4perl->wrapper_register(__PACKAGE__);
    }
}

sub TIEHANDLE {
  my($class) = @_;
  return bless {}, $class;
}

sub PRINT {
  my $self = shift;
  if ($self->_logger->is_trace) {
    $self->_logger->trace(@_);
  }
  return 1;
}

sub PRINTF {
  my $self = shift;
  if ($self->_logger->is_trace) {
    $self->_logger->tracef(@_);
  }
}

sub UNTIE {
  my ($obj, $count) = @_;
  if ($count) {
    MarpaX::Languages::XML::Exception('untie attempted while $count inner references still exist');
  }
}

=head1 SEE ALSO

L<MooX::Role::Logger>, L<Marpa::R2>, L<http://osdir.com/ml/lang.perl.modules.log4perl.devel/2007-03/msg00030.html>

=cut

with 'MarpaX::Languages::XML::Role::Logger';

1;
