# Bootstrap concatenative compiler
# Concatenative languages have the desirable characteristic that juxtaposition
# corresponds to function composition. This makes it particularly easy to
# encode such a language as a series of Perl functions.

package nb;

{ package nb::val; use overload qw/ "" str / }

push @nb::string::ISA, 'nb::val', 'nb::one';
push @nb::number::ISA, 'nb::val', 'nb::one';
push @nb::symbol::ISA, 'nb::val', 'nb::one';
push @nb::list::ISA,   'nb::val', 'nb::many';
push @nb::array::ISA,  'nb::val', 'nb::many';
push @nb::hash::ISA,   'nb::val', 'nb::many';

sub nb::list::delimiters  { '(', ')' }
sub nb::array::delimiters { '[', ']' }
sub nb::hash::delimiters  { '{', '}' }

sub nb::string::str { "\"${$_[0]}\"" }
sub nb::one::str    { ${$_[0]} }

sub nb::many::str {
  my ($self) = @_;
  my ($open, $close) = $self->delimiters;
  $open . join(' ', @$self) . $close;
}

sub nb::symbol::value { ${${$_[0]}} }
sub nb::val::value    {     $_[0]   }

sub string { my ($x) = @_; bless \$x, 'nb::string' }
sub number { my ($x) = @_; bless \$x, 'nb::number' }
sub symbol { my ($x) = @_; bless \$x, 'nb::symbol' }
sub list   { bless [@_], 'nb::list'  }
sub array  { bless [@_], 'nb::array' }
sub hash   { bless [@_], 'nb::hash'  }

our %bracket_types = ( ')' => \&list,
                       ']' => \&array,
                       '}' => \&hash );

sub parse {
  local $_;
  my @stack = [];
  while ($_[0] =~ /\G (?: (?<comment> \#[!\s].*)
                        | (?<ws>      [:,\s]+)
                        | (?<string>  "(?:[^\\"]|\\.)*")
                        | (?<number>  [-+]?[0-9]\S*)
                        | (?<symbol>  [^"()\[\]{}\s,:]+)
                        | (?<opener>  [(\[{])
                        | (?<closer>  [)\]}]))/gx) {
    my $k = (keys %+)[0];
    next if $k eq 'comment' || $k eq 'ws';
    if ($k eq 'opener') {
      push @stack, [];
    } elsif ($k eq 'closer') {
      my $last = pop @stack;
      die "too many closing brackets" unless @stack;
      push @{$stack[-1]}, $bracket_types{$+{closer}}->(@$last);
    } else {
      push @{$stack[-1]}, &{"nb::$k"}($+{$k});
    }
  }
  die "unbalanced brackets: " . scalar(@stack) . " != 1"
    unless @stack == 1;
  @{$stack[0]};
}

# Interpreter and REPL
END {
  select((select(STDERR), $|++)[0]);
  ${'^eval'}->(array(parse join '', <>)) if @ARGV;
  if (-t STDIN) {
    my @stack;
    print STDERR "> ";
    while (<STDIN>) {
      chomp;
      my $thing = $_;
      eval { @stack = $_->(@stack) for parse $thing };
      print STDERR "failed to evaluate $thing: $@" if $@;

      ${'^prstack'}->(@stack);
      print STDERR "> ";
    }
  }
}

# Global functions
# Each of these exists in two forms, CPS-converted and regular. In the "real
# language" all we'll have are the CPS versions, but writing CPS by hand is
# miserable so I'm giving myself a way out for the bootstrap layer. Once we
# have CPS-conversion macros this won't be a big issue.

sub def {
  my ($name, $f) = @_;
  ${"^$name"} = $f;
  ${$name} = sub {
    my ($k, @xs) = @_;
    $k->($f->(@xs));
  };
}

# Stack manipulation
def 'swap', sub { @_[1, 0, 2..$#_] };
def 'dup',  sub { @_[0, 0, 1..$#_] };
def 'drop', sub { @_[1..$#_] };

# Eval, definition, and conditionals
${'^eval'} = sub {
  my ($x, @stuff) = @_;
  die "argument to eval must be an array (got $x)"
    unless ref($x) eq 'nb::array';
  @stuff = $_->(@stuff) for @$x;
  @stuff;
};

${'eval'} = sub {
  my ($k, $x, @stuff) = @_;
  die "argument to eval must be an array (got $x)"
    unless ref($x) eq 'nb::array';

  if (@$x) {
    my @ks = map {
      my $i = $_;
      my $f = $$x[$i];
      sub { $f->($ks[$i + 1], @stuff) };
    } 0..$#{$x} - 1;

    push @ks, $k;
    $ks[0]->(@stuff);
  } else {
    $k->(@stuff);
  }
};

def 'def', sub {
  my ($name, $v, @stuff) = @_;
  ${$name} = $v;
  @stuff;
};

# Used for conditionals in conjunction with 'eval'
def 'nth', sub {
  my ($n, @stuff) = @_;
  $stuff[$$n], @stuff;
};

# Scalar value stuff
def 'type', sub { ref($_[0]) =~ s/^.*:://r };

def 'ys', sub { string(${$_[0]}), @_[1..$#_] };
def 'sy', sub { symbol(${$_[0]}), @_[1..$#_] };
def 'ns', sub { string(${$_[0]}), @_[1..$#_] };
def 'sn', sub { number(${$_[0]}), @_[1..$#_] };

def 'sv', sub { array(parse ${$_[0]}), @_[1..$#_] };
def 'vs', sub { string($_[0]->str), @_[1..$#_] };

def 'print', sub {
  my ($x, @stuff) = @_;
  print $$x, "\n";
  @stuff;
};

def 'prstack', sub {
  printf STDERR "%02d: %s\n", $_, $_[$_] for 0..$#_;
  @_;
};

# Multi-value stuff
def 'count', sub {
  my ($xs, @stuff) = @_;
  number(scalar @$xs), @stuff;
};

def 'xl', sub { list(@{$_[0]}),  @_[1..$#_] };
def 'xa', sub { array(@{$_[0]}), @_[1..$#_] };
def 'xh', sub { hash(@{$_[0]}),  @_[1..$#_] };

def 'lcons', sub {
  my ($x, $xs, @stuff) = @_;
  list($x, @$xs), @stuff;
};

def 'acons', sub {
  my ($x, $xs, @stuff) = @_;
  array($x, @$xs), @stuff;
};

def 'uncons', sub {
  my ($xs, @stuff) = @_;
  my ($h, @t) = @$xs;
  $h, &{ref $xs}(@t), @stuff;
};
