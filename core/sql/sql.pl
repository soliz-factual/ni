# SQL parsing context.
# Translates ni CLI grammar to a SELECT query. This is a little interesting
# because SQL has a weird structure to it; to help with this I've also got a
# 'sqlgen' abstraction that figures out when we need to drop into a subquery.

sub sqlgen($) {bless {from => $_[0]}, 'ni::sqlgen'}

sub ni::sqlgen::render {
  local $_;
  my ($self) = @_;
  return $$self{from} if 1 == keys %$self;

  my $select = ni::dor $$self{select}, '*';
  my @others;

  for (qw/from where order_by group_by limit union intersect except
          inner_join left_join right_join full_join natural_join/) {
    next unless exists $$self{$_};
    (my $k = $_) =~ y/a-z_/A-Z /;
    push @others, "$k $$self{$_}";
  }

  ni::gen('SELECT %distinct %stuff %others')
       ->(stuff    => $select,
          distinct => $$self{uniq} ? 'DISTINCT' : '',
          others   => join ' ', @others);
}

sub ni::sqlgen::modify_where {join ' AND ', @_}

sub ni::sqlgen::modify {
  my ($self, %kvs) = @_;
  while (my ($k, $v) = each %kvs) {
    if (exists $$self{$k}) {
      if (exists ${'ni::sqlgen::'}{"modify_$k"}) {
        $v = &{"ni::sqlgen::modify_$k"}($$self{$k}, $v);
      } else {
        $self = ni::sqlgen "($self->render)";
      }
    }
    $$self{$k} = $v;
  }
  $self;
}

sub ni::sqlgen::map        {$_[0]->modify(select => $_[1])}
sub ni::sqlgen::filter     {$_[0]->modify(where =>  $_[1])}
sub ni::sqlgen::take       {$_[0]->modify(limit =>  $_[1])}
sub ni::sqlgen::sample     {$_[0]->modify(where =>  "random() < $_[1]")}

sub ni::sqlgen::ijoin      {$_[0]->modify(join => 1, inner_join   => $_[1])}
sub ni::sqlgen::ljoin      {$_[0]->modify(join => 1, left_join    => $_[1])}
sub ni::sqlgen::rjoin      {$_[0]->modify(join => 1, right_join   => $_[1])}
sub ni::sqlgen::njoin      {$_[0]->modify(join => 1, natural_join => $_[1])}

sub ni::sqlgen::order_by   {$_[0]->modify(order_by => $_[1])}

sub ni::sqlgen::uniq       {${$_[0]}{uniq} = 1; $_[0]}

sub ni::sqlgen::union      {$_[0]->modify(setop => 1, union     => $_[1])}
sub ni::sqlgen::intersect  {$_[0]->modify(setop => 1, intersect => $_[1])}
sub ni::sqlgen::difference {$_[0]->modify(setop => 1, except    => $_[1])}

# SQL code parse element.
# Counts brackets outside quoted strings.

BEGIN {defparseralias sqlcode => generic_code}

# Code compilation.
# Parser elements can generate one of two things: [method, @args] or
# {%modifications}. Compiling code is just starting with a SQL context and
# left-reducing method calls.

sub sql_compile {
  local $_;
  my ($g, @ms) = @_;
  for (@ms) {
    if (ref($_) eq 'ARRAY') {
      my ($m, @args) = @$_;
      $g = $g->$m(@args);
    } else {
      $g = $g->modify(%$_);
    }
  }
  $g->render;
}

# SQL operator mapping.
# For the most part we model SQL operations the same way that we address Spark
# RDDs, though the mnemonics are a mix of ni and SQL abbreviations.

BEGIN {defcontext 'sql', q{SQL generator context}}
BEGIN {defparseralias sql_table => pmap q{sqlgen $_}, prc '^[^][]*'}
BEGIN {defparseralias sql_query => pmap q{sql_compile $$_[0], @{$$_[1]}},
                                   pseq sql_table, popt parser 'sql/qfn'}

defshort 'sql/m', pmap q{['map', $_]}, sqlcode;
defshort 'sql/u', pk ['uniq'];

defshort 'sql/r',
  defalt 'sqlrowalt', 'alternatives for sql/r row operator',
    pmap(q{['take',   $_]}, integer),
    pmap(q{['filter', $_]}, sqlcode);

defshort 'sql/j',
  defalt 'sqljoinalt', 'alternatives for sql/j join operator',
    pmap(q{['ljoin', $_]}, pn 1, pstr 'L', sql_query),
    pmap(q{['rjoin', $_]}, pn 1, pstr 'R', sql_query),
    pmap(q{['njoin', $_]}, pn 1, pstr 'N', sql_query),
    pmap(q{['ijoin', $_]}, sql_query);

defshort 'sql/g', pmap q{['order_by', $_]},        sqlcode;
defshort 'sql/o', pmap q{['order_by', "$_ ASC"]},  sqlcode;
defshort 'sql/O', pmap q{['order_by', "$_ DESC"]}, sqlcode;

defshort 'sql/+', pmap q{['union',      $_]}, sql_query;
defshort 'sql/*', pmap q{['intersect',  $_]}, sql_query;
defshort 'sql/-', pmap q{['difference', $_]}, sql_query;

# Global operator.
# SQL stuff is accessed using Q, which delegates to a sub-parser that handles
# configuration/connections. The dev/compile delegate is provided so you can see
# the SQL code being generated.

defoperator sql_preview => q{sio; print "$_[0]\n"};

defshort '/Q',
  defdsp 'sqlprofile', 'dispatch for SQL profiles',
    'dev/compile' => pmap q{sql_preview_op($_[0])}, sql_query;
