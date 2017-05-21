# Process + filehandle combination.
# We can't use Perl's process-aware FHs because they block-wait for the process
# on close. There are some situations where we care about the exit code and
# others where we don't, and this class supports both cases.

package ni::procfh;

use POSIX qw/:sys_wait_h/;

# Global child collector.
# Collect children regardless of whether anyone is listening for them. If we have
# an interested party, notify them.

our %child_owners;

sub await_children {
  local ($!, $?, $_);
  while (0 < ($_ = waitpid -1, WNOHANG)) {
    $child_owners{$_}->child_exited($?) if defined $child_owners{$_};
  }
  $SIG{CHLD} = \&await_children;
};
$SIG{CHLD} = \&await_children;

# Signal forwarding.
# Propagate termination signals to children and run finalizers. This makes it so
# that non-writing pipelines like `ni n100000000gzn` still die out without
# waiting for the SIGPIPE.

sub kill_children($) {kill $_[0], keys %child_owners}

# Proc-filehandle class.
# Overloading *{} makes it possible for this to act like a real filehandle in
# every sense: fileno() works, syswrite() works, etc. The constructor takes care
# of numeric fds by promoting them into Perl fh references.

use overload qw/*{} fh "" str/;
sub new($$$) {
  my ($class, $fd, $pid) = @_;
  my $result = bless {pid => $pid, status => undef}, $class;
  $child_owners{$pid} = $result;
  my $fh = ref($fd) ? $fd : undef;
  open $fh, "<&=$fd" or die "ni: procfh($fd, $pid) failed: $!"
    unless defined $fh;
  $$result{fh} = $fh;
  $result;
}

sub DESTROY {
  my ($self) = @_;
  close $$self{fh};
  delete $child_owners{$$self{pid}} unless defined $$self{status};
}

sub fh($)     {my ($self) = @_; $$self{fh}}
sub pid($)    {my ($self) = @_; $$self{pid}}
sub status($) {my ($self) = @_; $$self{status}}

sub kill($$) {
  my ($self, $sig) = @_;
  kill $sig, $$self{pid} unless defined $$self{status};
}

sub str($)
{ my ($self) = @_;
  sprintf "<fd %d, pid %d, status %s>",
          fileno $$self{fh}, $$self{pid}, $$self{status} || 'none' }

# Child await.
# We have to stop the SIGCHLD handler while we wait for the child in question.
# Otherwise we run the risk of waitpid() blocking forever or catching the wrong
# process. This ends up being fine because this process can't create more
# children while waitpid() is waiting, so we might have some resource delays but
# we won't have a leak.

# We also don't have to worry about multithreading: only one await() call can
# happen per process.

sub await($) {
  local ($?, $SIG{CHLD});
  my ($self) = @_;
  return $$self{status} if defined $$self{status};
  $SIG{CHLD} = 'DEFAULT';
  return $$self{status} if defined $$self{status};
  if (kill 'ZERO', $$self{pid}) {
    my $pid = waitpid $$self{pid}, 0;
    $self->child_exited($pid <= 0 ? "-1 [waitpid: $!]" : $?);
  } else {
    $self->child_exited("-1 [child already collected]");
  }
  $$self{status};
}

sub child_exited($$) {
  my ($self, $status) = @_;
  $$self{status} = $status;
  delete $child_owners{$$self{pid}};
}
