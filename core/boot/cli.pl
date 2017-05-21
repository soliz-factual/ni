# CLI grammar.
# ni's command line grammar uses some patterns on top of the parser combinator
# primitives defined in parse.pl.sdoc. Probably the most important one to know
# about is the long/short option dispatch, which looks like this:

# | option = alt @longs, dsp %shorts

our %contexts;
our %shorts;
our %longs;
our %long_refs;
our %short_refs;
our %dsps;
our %alts;

BEGIN {
  defdocumentable context => \%contexts, q{
    my ($c, $doc) = @_;
    doc_sections
      "CONTEXT $c" => $doc,
      "LONG OPERATORS (ni --doc/long X)"   => join("\n", sort grep /^$c\//, keys %ni::longs),
      "SHORT OPERATORS (ni --doc/short X)" => join("\n", sort grep /^$c\//, keys %ni::shorts);
  };

  defdocumentable short => \%shorts, q{
    my ($s, $doc) = @_;
    doc_sections
      "SHORT OPERATOR $s" => $doc,
      "SYNTAX" => parser_ebnf $ni::shorts{$s};
  };

  defdocumentable long => \%longs, q{
    my ($l, $doc) = @_;
    doc_sections
      "LONG OPERATOR $l" => $doc,
      "SYNTAX" => parser_ebnf $ni::longs{$l};
  };

  defdocumentable dsp => \%dsps, q{
    my ($d, $doc) = @_;
    doc_sections
      "EXTENSIBLE DISPATCH TABLE $d" => $doc,
      "OPTIONS" => parser_ebnf parser "dsp/$d";
  };

  defdocumentable alt => \%alts, q{
    my ($a, $doc) = @_;
    doc_sections
      "EXTENSIBLE LIST $a" => $doc,
      "OPTIONS" => parser_ebnf parser "alt/$a";
  };
}

sub defcontext($$) {
  my ($c, $doc) = @_;
  $short_refs{$c} = {};
  $long_refs{$c}  = ["$c/short"];
  $contexts{$c}   = paltr @{$long_refs{$c}};

  doccontext $c, $doc;

  defparseralias "$c/short",  pdspr %{$short_refs{$c}};
  defparseralias "$c/op",     $contexts{$c};
  defparseralias "$c/suffix", prep "$c/op";
  defparseralias "$c/series", prep pn 1, popt pempty, "$c/op", popt pempty;
  defparseralias "$c/lambda", pn 1, pstc '[', "$c/series", pstr ']';
  defparseralias "$c/qfn",    palt "$c/lambda", "$c/suffix";

  docparser "$c/short" => qq{Dispatch table for short options in context '$c'};
  docparser "$c/op" => qq{A single operator in the context '$c'};
  docparser "$c/suffix" => qq{A string of operators unbroken by whitespace};
  docparser "$c/series" => qq{A string of operators, possibly including whitespace};
  docparser "$c/lambda" => qq{A bracketed lambda function in context '$c'};
  docparser "$c/qfn" => qq{Operators that are interpreted as a lambda, whether bracketed or written as a suffix};
}

sub defshort($$) {
  my ($context, $dsp) = split /\//, $_[0], 2;
  warn "ni: defshort is redefining '$_[0]' (use rmshort to avoid this warning)"
    if exists $short_refs{$context}{$dsp};
  $shorts{$_[0]} = $short_refs{$context}{$dsp} = $_[1];
}

sub deflong($$) {
  my ($context, $name) = split /\//, $_[0], 2;
  unshift @{$long_refs{$context}}, $longs{$_[0]} = $_[1];
}

sub rmshort($) {
  my ($context, $dsp) = split /\//, $_[0], 2;
  delete $shorts{$_[0]};
  delete $short_refs{$context}{$dsp};
}

sub cli_parse(@) {parse parser '/series', @_}
sub cli(@) {
  my ($r, @rest) = cli_parse @_;
  die "ni: failed to parse starting here:\n  @rest" if @rest;
  $r;
}

# Extensible parse elements.
# These patterns come up a lot, and it's worth being able to autogenerate their
# documentation.

sub defalt($$@) {
  no strict 'refs';
  my ($name, $doc, @entries) = @_;
  my $vname = __PACKAGE__ . "::$name";
  docalt $name, $doc;
  @{$vname} = @entries;
  $alts{$name} = \@{$vname};
  *{__PACKAGE__ . "::def$name"} = sub ($) {unshift @{$vname}, $_[0]};
  my $r = paltr @{$vname};
  defparseralias "alt/$name" => $r;
  $r;
}

sub defdsp($$%) {
  no strict 'refs';
  my ($name, $doc, %entries) = @_;
  my $vname = __PACKAGE__ . "::$name";
  docdsp $name, $doc;
  %{$vname} = %entries;
  $dsps{$name} = \%{$vname};
  *{__PACKAGE__ . "::def$name"} = sub ($$) {${$vname}{$_[0]} = $_[1]};
  my $r = pdspr %{$vname};
  defparseralias "dsp/$name" => $r;
  $r;
}
