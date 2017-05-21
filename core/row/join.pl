# Streaming joins.
# The UNIX `join` command does this, but rearranges fields in the process. ni
# implements its own operators as a workaround.

defoperator join => q{
  my ($left_cols, $right_cols, $f) = @_;
  my $fh = sni @$f;
  my ($leof, $reof) = (0, 0);
  my ($llimit, @lcols) = @$left_cols;
  my ($rlimit, @rcols) = @$right_cols;
  while (!$leof && !$reof) {
    chomp(my $lkey = join "\t", (split /\t/, my $lrow = <STDIN>, $llimit + 1)[@lcols]);
    chomp(my $rkey = join "\t", (split /\t/, my $rrow = <$fh>,   $rlimit + 1)[@rcols]);
    $reof ||= !defined $rrow;
    $leof ||= !defined $lrow;

    until ($lkey eq $rkey or $leof or $reof) {
      chomp($rkey = join "\t", (split /\t/, $rrow = <$fh>, $llimit + 1)[@lcols]),
        $reof ||= !defined $rrow until $reof or $rkey ge $lkey;
      chomp($lkey = join "\t", (split /\t/, $lrow = <STDIN>, $rlimit + 1)[@rcols]),
        $leof ||= !defined $lrow until $leof or $lkey ge $rkey;
    }

    if ($lkey eq $rkey and !$leof && !$reof) {
      chomp $lrow;
      print "$lrow\t$rrow";
    }
  }
};

defshort '/j', pmap q{join_op $$_[0] || [1, 0], $$_[0] || [1, 0], $$_[1]},
               pseq popt colspec, _qfn;
