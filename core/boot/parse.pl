# Parser combinators.
# List-structured combinators. These work like normal parser combinators, but are
# indirected through data structures to make them much easier to inspect. This
# allows ni to build an operator mapping table.

our %parsers;
BEGIN {defdocumentable 'parser', \%parsers, q{
  my ($p, $doc) = @_;
  if (ref $p) {
    my ($name, @args) = @$p;
    return $ni::doc{parser}{$name}->($p) if ref $ni::doc{parser}{$name};
    parser_doc($name);
  } else {
    doc_sections
      "PARSER $p"  => $doc,
      "DEFINITION" => parser_ebnf($ni::parsers{$p});
  }
}}

our %parser_ebnf;
sub defparserebnf($$) {$parser_ebnf{$_[0]} = fn $_[1]}
sub parser_ebnf($) {
  my ($p) = @_;
  return "<$p>" unless ref $p;
  return "<core parser {\n" . indent($p, 2) . "\n}>" unless 'ARRAY' eq ref $p;
  my ($name, @args) = @$p;
  return "<" . join(' ', $name, map dev_inspect($_), @args) . ">" unless exists $parser_ebnf{$name};
  $parser_ebnf{$name}->($p);
}

sub parser($);
sub parser($) {
  return $_[0] if ref $_[0];
  die "ni: parser $_[0] is not defined" unless exists $parsers{$_[0]};
  parser $parsers{$_[0]};
}

sub defparser($$$) {
  my ($name, $proto, $f) = @_;
  (my $code_name = $name) =~ s/\W+/_/g;
  die "ni: defparser cannot redefine $name" if exists $parsers{$name};
  $parsers{$name} = fn $f;
  eval "sub $code_name($proto) {['$name', \@_]}";
}

sub defparseralias($$) {
  my ($name, $alias) = @_;
  (my $code_name = $name) =~ s/\W+/_/g;
  die "ni: defparseralias cannot redefine $name" if exists $parsers{$name};
  $parsers{$name} = $alias;
  eval "sub $code_name() {['$name']}" unless exists ${ni::}{$code_name};
}

# Parse function.
# ($result, @remaining) = parse($parser, @inputs). $parser can take one of three
# forms:

# | ['parser-name', @args]: $parsers{'parser-name'} is a function
#   ['parser-name']: $parsers{'parser-name'} could be a function or an array
#   'parser-name': $parsers{'parser-name'} is an array

our $recursion_level = 0;
sub parse;
sub parse {
  local $_;
  local $recursion_level = $recursion_level + 1;
  my ($p, @args) = @{parser $_[0]};
  die "ni: runaway parse of $p [@args] on @_[1..$#_] ($recursion_level levels)"
    if $recursion_level > 1024;
  my $f = $parsers{$p};
  'ARRAY' eq ref $f ? parse $f, @_[1..$#_] : &$f([$p, @args], @_[1..$#_]);
}

# Base parsers.
# Stuff for dealing with some base cases.

BEGIN {
  defparser 'pend',   '',  q{@_ > 1                        ? () : (0)};
  defparser 'pempty', '',  q{defined $_[1] && length $_[1] ? () : (0, @_[2..$#_])};
  defparser 'pk',     '$', q{(${$_[0]}[1], @_[1..$#_])};
  defparser 'pnone',  '',  q{(undef,       @_[1..$#_])};
}

defparserebnf pend   => q{'<argv_end>'};
defparserebnf pempty => q{'<empty>'};
defparserebnf pk     => q{"<'', evaluate as " . dev_inspect($_[0][1]) . ">"};
defparserebnf pnone  => q{"''"};

# Basic combinators.
# Sequence, alternation, etc. 'alt' implies a sequence of alternatives; 'dsp' is
# a dispatch on specified prefixes. The 'r' suffix means that the parser
# combinator takes a reference to a collection; this allows you to modify the
# collection later on to add more alternatives.

BEGIN {
  defparser 'paltr', '\@',
    q{my ($self, @xs, @ps, @r) = @_;
      @r = parse $_, @xs and return @r for @ps = @{parser $$self[1]}; ()};

  defparser 'pdspr', '\%',
    q{my ($self, $x, @xs, $k, @ys, %ls, $c) = @_;
      my (undef, $ps) = @$self;
      return () unless defined $x;
      ++$ls{length $_} for keys %$ps;
      for my $l (sort {$b <=> $a} keys %ls) {
        return (@ys = parse $$ps{$c}, substr($x, $l), @xs) ? @ys : ()
        if exists $$ps{$c = substr $x, 0, $l} and $l <= length $x;
      }
      ()};
}

sub palt(@) {my @ps = @_; paltr @ps}
sub pdsp(%) {my %ps = @_; pdspr %ps}

defparserebnf paltr => fn q{
  my ($self, $alt) = @{$_[0]};
  my @docs = map "| " . sr(indent(parser_ebnf $_, 2), qr/^  /, ''), @$alt;
  "(\n" . join("\n", @docs) . "\n)";
};

defparserebnf pdspr => fn q{
  my ($self, $dsp) = @{$_[0]};
  my @docs = map "| '$_' " . sr(indent(parser_ebnf $$dsp{$_}, 2), qr/^  /, ''),
             sort keys %$dsp;
  "(\n" . join("\n", @docs) . "\n)";
};

BEGIN {
  defparser 'pseq', '@',
    q{my ($self, @is, $x, @xs, @ys) = @_;
      my (undef, @ps) = @$self;
      (($x, @is) = parse $_, @is) ? push @xs, $x : return () for @ps;
      (\@xs, @is)};

  defparser 'prep', '$;$',
    q{my ($self, @is, @c, @r) = @_;
      my (undef, $p, $n) = (@$self, 0);
      push @r, $_ while ($_, @is) = parse $p, (@c = @is);
      @r >= $n ? (\@r, @c) : ()};

  defparser 'popt', '$',
    q{my ($self, @is) = @_;
      my @xs = parse $$self[1], @is; @xs ? @xs : (undef, @is)};

  defparser 'pmap', '$$',
    q{my ($self, @is) = @_;
      my (undef, $f, $p) = @$self;
      $f = fn $f;
      my @xs = parse $p, @is; @xs ? (&$f($_ = $xs[0]), @xs[1..$#xs]) : ()};

  defparser 'pcond', '$$',
    q{my ($self, @is) = @_;
      my (undef, $f, $p) = @$self;
      $f = fn $f;
      my @xs = parse $p, @is; @xs && &$f($_ = $xs[0]) ? @xs : ()};
}

defparserebnf pseq => fn q{
  my ($self, @ps) = @{$_[0]};
  "(\n" . join("\n", map indent(parser_ebnf $_, 2), @ps) . "\n)";
};

defparserebnf prep => fn q{
  my ($self, $p, $n) = (@{$_[0]}, 0);
  my $rep_symbol = $n == 0 ? '*' : $n == 1 ? '+' : "{$n+ times}";
  parser_ebnf($p) . "$rep_symbol";
};

defparserebnf popt => fn q{
  my ($self, $p) = @{$_[0]};
  parser_ebnf($p) . '?';
};

defparserebnf pmap => fn q{
  my ($self, $f, $p) = @{$_[0]};
  parser_ebnf($p) . " -> {$f}";
};

defparserebnf pcond => fn q{
  my ($self, $f, $p) = @{$_[0]};
  parser_ebnf($p) . " such that {$f}";
};

sub pn($@)
{ my ($n, @ps) = @_;
  'ARRAY' eq ref $n ? pmap fn "[\@\$_[" . join(',', @$n) . "]]", pseq @ps
                    : pmap fn "\$\$_[$n]", pseq @ps }

sub pc($) {pn 0, $_[0], popt pempty}

# Regex parsing.
# Consumes the match, returning either the matched text or the first match group
# you specify. Always matches from the beginning of a string.

BEGIN {
  defparser 'prx', '$',
    q{my ($self, $x, @xs) = @_;
      defined $x && $x =~ s/^($$self[1])// ? (dor($2, $1), $x, @xs) : ()};

  defparser 'pstr', '$',
    q{my ($self, $x, @xs) = @_;
      defined $x && index($x, $$self[1]) == 0
        ? ($$self[1], substr($x, length $$self[1]), @xs)
        : ()};

  defparser 'pnx', '$',
    q{my ($self, $x, @xs) = @_;
      !defined $x || $x =~ /^(?:$$self[1])/ ? () : ($x, @xs)};
}

sub prc($)  {pn 0, prx  $_[0], popt pempty}
sub pstc($) {pn 0, pstr $_[0], popt pempty}

defparserebnf pstr => fn q{
  my ($self, $s) = @{$_[0]};
  $s =~ /'/ ? json_encode($s) : "'$s'";
};

defparserebnf prx => fn q{
  my ($self, $r) = @{$_[0]};
  "/$r/";
};

defparserebnf pnx => fn q{
  my ($self, $r) = @{$_[0]};
  "!/$r/";
};
