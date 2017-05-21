# Pure-Perl MurmurHash3_32 implementation.
# This is used by some intification operators and based on the Wikipedia
# implementation. It's limited to 32 bits because otherwise ni will fail on 32-bit
# machines.

use constant murmur_c1 => 0xcc9e2d51;
use constant murmur_c2 => 0x1b873593;
use constant murmur_n  => 0xe6546b64;

sub murmurhash3($;$) {
  use integer;
  local $_;
  my $h = $_[1] || 0;

  for (unpack 'L*', $_[0]) {
    $_ *= murmur_c1;
    $h ^= ($_ << 15 | $_ >> 17 & 0x7fff) * murmur_c2 & 0xffffffff;
    $h  = ($h << 13 | $h >> 19 & 0x1fff) * 5 + murmur_n;
  }

  my ($r) = unpack 'V', substr($_[0], ~3 & length $_[0]) . "\0\0\0\0";
  $r *= murmur_c1;
  $h ^= ($r << 15 | $r >> 17 & 0x7fff) * murmur_c2 & 0xffffffff ^ length $_[0];
  $h &= 0xffffffff;
  $h  = ($h ^ $h >> 16) * 0x85ebca6b & 0xffffffff;
  $h  = ($h ^ $h >> 13) * 0xc2b2ae35 & 0xffffffff;
  return $h ^ $h >> 16;
}
