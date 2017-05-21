# Development functions.
# Utilities helpful for debugging and developing ni.

sub try_to_resolve_coderef($) {
  for my $f (keys %{ni::}) {
    return "ni::$f" if \&{"ni::$f"} eq $_[0];
  }
  return '<opaque code reference>';
}

sub dev_inspect($;\%);
sub dev_inspect($;\%) {
  local $_;
  my ($x, $refs) = (@_, {});
  return "<circular $x>" if defined $x && exists $$refs{$x};

  $$refs{$x} = $x if defined $x;
  my $r = 'ARRAY' eq ref $x ? '[' . join(', ', map dev_inspect($_, %$refs), @$x) . ']'
        : 'HASH'  eq ref $x ? '{' . join(', ', map "$_ => " . dev_inspect($$x{$_}, %$refs), keys %$x) . '}'
        : 'CODE'  eq ref $x ? try_to_resolve_coderef($x)
        : defined $x        ? "" . $x
        :                     'undef';
  delete $$refs{$x} if defined $x;
  $r;
}

sub dev_inspect_nonl($) {(my $r = dev_inspect $_[0]) =~ s/\s+/ /g; $r}

sub dev_trace($) {
  no strict 'refs';
  my ($fname) = @_;
  my $f = \&{$fname};
  my $indent = '';
  *{$fname} = sub {
    printf STDERR "$indent$fname %s ...\n", dev_inspect [@_];
    $indent .= "  ";
    my @r = &$f(@_);
    $indent =~ s/  $//;
    printf STDERR "$indent$fname %s = %s\n", dev_inspect([@_]), dev_inspect [@r];
    @r;
  };
}
