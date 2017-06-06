# Bloom filter library.
# A simple pure-Perl implementation of Bloom filters.

# Swiped from https://hur.st/bloomfilter
sub bloom_args($$) {
  my ($n, $p) = @_;
  my $m = int 1 + $n * -log($p) / log(2 ** log 2);
  my $k = int 0.5 + log(2) * $m / $n;
  ($m, $k);
}

sub bloom_new($$) {
  my ($m, $k) = @_;
  ($m, $k) = bloom_args($m, $k) if $k < 1;
  pack("NN", $m, $k) . "\0" x ($m + 7 >> 3);
}

# Destructively adds an element to the filter and returns the filter.
sub bloom_add($$) {
  my ($m, $k) = unpack "NN", $_[0];
  vec($_[0], $_ + 64, 1) = 1 for map murmurhash3($_[1], $_) % $m, 1..$k;
  $_[0];
}

sub bloom_contains($$) {
  my ($m, $k) = unpack "NN", $_[0];
  vec($_[0], $_ + 64, 1) || return 0 for map murmurhash3($_[1], $_) % $m, 1..$k;
  1;
}
