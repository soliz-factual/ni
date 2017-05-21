# Syntax mapping.
# We can inspect the parser dispatch tables within various contexts to get a
# character-level map of prefixes and to indicate which characters are available
# for additional operators.

use constant qwerty_prefixes => 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%=$+_,.:';
use constant qwerty_effort =>   '02200011000021011000011212244222332222432332222334344444455544565565223';

defoperator meta_short_availability => q{
  sio;
  print "--------" . qwerty_prefixes . "\n";
  for my $c (sort keys %ni::contexts) {
    my $s = $ni::short_refs{$c};
    my %multi;
    ++$multi{substr $_, 0, 1} for grep 1 < length, keys %$s;

    print substr(meta_context_name $c, 0, 7) . "\t"
        . join('', map $multi{$_} ? '.' : $$s{$_} ? '|' : ' ',
                       split //, qwerty_prefixes)
        . "\n";
  }
};

defshort '///ni/map/short', pmap q{meta_short_availability_op}, pnone;
