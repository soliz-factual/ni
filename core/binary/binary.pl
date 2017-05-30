# Binary import operator.
# An operator that reads data in terms of bytes rather than lines. This is done
# in a Perl context with functions that manage a queue of data in `$_`.

use constant binary_perlgen => gen q{
  %prefix
  close STDIN;
  open STDIN, '<&=3';
  while (available) {
    %body
  }
};

defperlprefix 'core/binary/bytewriter.pm';

our @binary_perl_prefix_keys = qw| core/binary/bytestream.pm |;

sub binary_perl_prefix() {join "\n", perl_prefix,
                                     @ni::self{@binary_perl_prefix_keys}}

sub defbinaryperlprefix($) {push @binary_perl_prefix_keys, $_[0]}

sub binary_perl_mapper($) {binary_perlgen->(prefix => binary_perl_prefix,
                                            body   => perl_expand_begin $_[0])}

defoperator binary_perl => q{stdin_to_perl binary_perl_mapper $_[0]};

defoperator binary_fixed => q{
  my ($pack_template) = @_;
  my @packed = unpack $pack_template, "\0" x 65536;
  my $length = length pack $pack_template, @packed;
  my $offset = 0;
  die "ni: binary_fixed template consumes no data" unless $length;
  my $buf = $length;
  $buf <<= 1 until $buf >= 65536;
  while (1) {
    sysread STDIN, $_, $buf - length, length or return until length >= $length;
    my @vs = unpack "($pack_template)*", $_;
    for (my $n = 0; $n + @packed < @vs; $n += @packed) {
      print join("\t", @vs[$n..$n+$#packed]), "\n";
    }
    $_ = length() % $length ? substr($_, $length * @vs / @packed) : '';
  }
};

defshort '/b',
  defdsp 'binaryalt', 'dispatch table for the /b binary operator',
    f => pmap(q{binary_fixed_op $_}, generic_code),
    p => pmap q{binary_perl_op $_}, plcode \&binary_perl_mapper;
