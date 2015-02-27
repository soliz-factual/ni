#!/usr/bin/env perl
$ni::selfcode = '';
$ni::selfcode .= ($_ = <DATA>) until /^__END__$/;
eval $ni::selfcode;
die $@ if $@;
__DATA__
{
use v5.14;
no strict 'refs';
package ni;
sub ni;
sub ::ni;
sub self {
  join "\n", "#!/usr/bin/env perl",
             q{$ni::selfcode = '';},
             q{$ni::selfcode .= ($_ = <DATA>) until /^__END__$/;},
             q{eval $ni::selfcode;},
             q{die $@ if $@;},
             "__DATA__",
             $ni::selfcode;
}
use POSIX qw/:sys_wait_h/;
$SIG{CHLD} = sub {
  local ($!, $?);
  waitpid -1, WNOHANG;
};
BEGIN {
sub ni::gen::new;
sub gen       { local $_; ni::gen->new(@_) }
sub gen_empty { gen('empty', {}, '') }
sub gen_seq {
  my ($name, @statements) = @_;
  my $code_template = join "\n", map "%\@x$_;", 0 .. $#statements;
  my %subst;
  $subst{"x$_"} = $statements[$_] for 0 .. $#statements;
  gen $name, {%subst}, $code_template;
}
{
package ni::gen;
use overload qw# %  subst  * map  @{} inserted_code_keys  "" compile
                 eq compile_equals #;
our $gensym_id = 0;
sub gensym { '$_' . ($_[0] // '') . '_' . $gensym_id++ . '__gensym' }
sub parse_signature {
  return $_[0] if ref $_[0];
  my ($first, @stuff) = split /\s*;\s*/, $_[0];
  my ($desc, $type)   = split /\s*:\s*/, $first;
  my $result = {description => $desc,
                type        => $type};
  /^(\S+)\s*=\s*(.*)$/ and $$result{$1} = $2 for @stuff;
  $result;
}
sub parse_code;
sub new {
  my ($class, $sig, $refs, $code) = @_;
  my ($fragments, $gensym_indexes, $insertions) = parse_code $code;
  my %subst;
  for (keys %$refs) {
    if (exists $$insertions{$_}) {
      $subst{$_} = $$refs{$_};
      delete $$refs{$_};
    }
  }
  bless({ sig               => parse_signature($sig),
          fragments         => $fragments,
          gensym_names      => {map {$_, undef} keys %$gensym_indexes},
          gensym_indexes    => $gensym_indexes,
          insertion_indexes => $insertions,
          refs              => $refs // {} },
        $class) % {%subst};
}
sub copy {
  my ($self) = @_;
  my %new = %$self;
  $new{sig}          = {%{$new{sig}}};
  $new{fragments}    = [@{$new{fragments}}];
  $new{gensym_names} = {%{$new{gensym_names}}};
  bless(\%new, ref $self)->replace_gensyms(
    {map {$_, gensym $_} keys %{$new{gensym_names}}});
}
sub replace_gensyms {
  my ($self, $replacements) = @_;
  for (keys %$replacements) {
    if (exists $$self{gensym_names}{$_}) {
      my $is = $$self{gensym_indexes}{$_};
      my $g  = $$self{gensym_names}{$_} = $$replacements{$_};
      $$self{fragments}[$_] = $g for @$is;
    }
  }
  $self;
}
sub genify {
  return $_[0] if ref $_[0] && $_[0]->isa('ni::gen');
  return ni::gen('genified', {}, $_[0]);
}
sub compile_equals {
  my ($self, $x) = @_;
  $x = $x->compile if ref $x;
  $self->compile eq $x;
}
sub share_gensyms_with {
  my ($self, $g) = @_;
  $self->replace_gensyms($$g{gensym_names});
}
sub inherit_gensyms_from {
  $_[1]->share_gensyms_with($_[0]);
  $_[0];
}
sub build_ref_hash {
  my ($self, $refs) = @_;
  $refs //= {};
  $$refs{$$self{gensym_names}{$_}} = $$self{refs}{$_} for keys %{$$self{refs}};
  $$self{fragments}[$$self{insertion_indexes}{$_}[0]]->build_ref_hash($refs)
    for @$self;
  $refs;
}
sub inserted_code_keys {
  my ($self) = @_;
  [sort keys %{$$self{insertion_indexes}}];
}
sub subst_in_place {
  my ($self, $vars) = @_;
  for my $k (keys %$vars) {
    my $is = $$self{insertion_indexes}{$k};
    my $f = genify $$vars{$k};
    $$self{fragments}[$_] = $f for @$is;
  }
  $self;
}
sub subst {
  my ($self, $vars) = @_;
  $self->copy->subst_in_place($vars);
}
sub map {
  my ($self, $f) = @_;
  $f = ni::compile $f;
  my $y = &$f($self);
  return $y unless $y eq $self;
  my $new = bless {}, ref $self;
  $$new{$_} = $$self{$_} for keys %$self;
  $$new{fragments} = [@{$$new{fragments}}];
  $new % {map {$_, $$new{fragments}[$$new{insertion_indexes}{$_}] * $f} @$new};
}
sub compile {
  my ($self) = @_;
  join '', @{$$self{fragments}};
}
sub lexical_definitions {
  my ($self, $refs) = @_;
  $refs //= $self->build_ref_hash;
  ni::gen "lexicals", {},
    join "\n", map sprintf("my %s = \$_[0]->{'%s'};", $_, $_), keys %$refs;
}
sub compile_to_sub {
  my ($self) = @_;
  my $code     = $self->compile;
  my $refs     = $self->build_ref_hash;
  my $bindings = $self->lexical_definitions($refs);
  my $f        = eval($code = "package main; sub {\n$bindings\n$code\n}");
  die "$@ compiling\n$code" if $@;
  ($f, $refs);
}
sub run {
  my ($self) = @_;
  my ($f, $refs) = $self->compile_to_sub;
  my @result = &$f($refs);
  delete $$refs{$_} for keys %$refs;    # we create circular refs sometimes
  @result;
}
our %parsed_code_cache;
sub parse_code {
  my ($code) = @_;
  my $cached;
  unless (defined($cached = $parsed_code_cache{$code})) {
    my @pieces = grep length, split /(\%:\w+|\%\@\w+)/, $code;
    my @fragments;
    my %gensym_indexes;
    my %insertion_indexes;
    for (0 .. $#pieces) {
      if ($pieces[$_] =~ /^\%:(\w+)$/) {
        push @{$gensym_indexes{$1} //= []}, $_;
        push @fragments, undef;
      } elsif ($pieces[$_] =~ /^\%\@(\w+)$/) {
        push @{$insertion_indexes{$1} //= []}, $_;
        push @fragments, [$1];
      } else {
        push @fragments, $pieces[$_];
      }
    }
    $cached = $parsed_code_cache{$code} = [[@fragments],
                                           {%gensym_indexes},
                                           {%insertion_indexes}];
  }
  @$cached;
}
}
}
our %conversions = (
  'F:L' => q{ $_ = join("\t", @_) . "\n"; %@body },
  'F:O' => q{ $_ = join("\t", @_); %@body },
  'L:O' => q{ chomp; %@body },
  'L:F' => q{ chomp; @_ = split /\t/; %@body },
  'O:F' => q{ @_ = split /\t/; %@body },
  'O:L' => q{ $_ .= "\n"; %@body });
$conversions{$_} = gen "conversion:$_", {}, $conversions{$_}
  for keys %conversions;
sub with_type {
  my ($type, $gen) = @_;
  return $gen if $$gen{sig}{type} eq $type;
  my $k = "$$gen{sig}{type}:$type";
  $conversions{$k} % {body => $gen};
}
sub typed_save_recover {
  my ($type) = @_;
  if ($type eq 'F') {
    my $xs = [];
    (gen('s:F', {xs => $xs}, q{ @{%:xs} = @_ }),
     gen('r:F', {xs => $xs}, q{ @_ = @{%:xs} }));
  } elsif ($type =~ /^I/) {
    my $xs = [];
    my $x  = '';
    (gen("s:$type", {xs => $xs, x => \$x}, q{ @{%:xs} = @_; ${%:x} = $_ }),
     gen("r:$type", {xs => $xs, x => \$x}, q{ @_ = @{%:xs}; $_ = ${%:x} }));
  } else {
    my $x = '';
    (gen("s:$type", {x => \$x}, q{ ${%:x} = $_ }),
     gen("r:$type", {x => \$x}, q{ $_ = ${%:x} }));
  }
}
our %compiled_functions;
sub expand_function_shorthands {
  my ($code) = @_;
  $code =~ s/%(\d+)/\$_[$1]/g;
  1 while $code =~ s/([a-zA-Z0-9_\)\}\]\?\$])
                     \.
                     ([\$_a-zA-Z](?:-[0-9\w\?\$]|[0-9_\w?\$])*)
                    /$1\->{'$2'}/x;
  $code;
}
sub compile {
  return $_[0] if ref $_[0] eq 'CODE';
  return $compiled_functions{$_[0]}
     //= eval "package main; sub {\n" . expand_function_shorthands($_[0])
                                      . "\n}";
}
our %io_constructors;
sub is_io { ref $_[0] && $_[0]->isa('ni::io') }
sub defio {
  my ($name, $constructor, $methods) = @_;
  *{"ni::io::${name}::new"} = $io_constructors{$name} = sub {
    my ($class, @args) = @_;
    bless $constructor->(@args), $class;
  };
  *{"::ni_$name"} = *{"ni::ni_$name"} =
    sub { ${"ni::io::${name}::"}{new}("ni::io::$name", @_) };
  *{"ni::io::$name::$_"} = $methods->{$_} for keys %$methods;
  push @{"ni::io::${name}::ISA"}, 'ni::io';
}
sub defioproxy {
  my ($name, $f) = @_;
  *{"::ni_$name"} = *{"ni::ni_$name"} = $f;
}
sub mapone_binding;
sub flatmap_binding;
sub reduce_binding;
sub grep_binding;
sub pipe_binding;
{
package ni::io;
use overload qw# + plus_op  * mapone_op  / reduce_op  % grep_op  | pipe_op
                 eq compare_refs
                 "" explain
                 >>= bind_op
                 > into  >= into_bg
                 < from  <= from_bg #;
use Scalar::Util qw/refaddr/;
BEGIN { *gen = \&ni::gen }
use POSIX qw/dup2/;
sub source_gen { ... }          # gen to source from this thing
sub sink_gen   { ... }          # gen to sink into this thing
sub explain    { ... }
sub transform {
  my ($self, $f) = @_;
  $f->($self);
}
sub reader_fh { (::ni_pipe() <= $_[0])->reader_fh }
sub writer_fh { (::ni_pipe() >= $_[0])->writer_fh }
sub has_reader_fh { 0 }
sub has_writer_fh { 0 }
sub process_local { 0 }
sub supports_reads  { 1 }
sub supports_writes { 0 }
sub flatten { ($_[0]) }
sub close   { $_[0] }
sub plus_op   { $_[0]->plus($_[1]) }
sub bind_op   { $_[0]->bind($_[1]) }
sub mapone_op { $_[0]->mapone($_[1]) }
sub reduce_op { $_[0]->reduce($_[1], {}) }
sub grep_op   { $_[0]->grep($_[1]) }
sub pipe_op   { $_[0]->pipe($_[1]) }
sub plus    { ::ni_sum(@_) }
sub bind    { ::ni_bind(@_) }
sub mapone  { $_[0] >>= ni::mapone_binding  @_[1..$#_] }
sub flatmap { $_[0] >>= ni::flatmap_binding @_[1..$#_] }
sub reduce  { $_[0] >>= ni::reduce_binding  @_[1..$#_] }
sub grep    { $_[0] >>= ni::grep_binding    @_[1..$#_] }
sub pipe    { ::ni_process($_[1], $_[0], undef) }
sub compare_refs { refaddr($_[0]) eq refaddr($_[1]) }
sub from {
  my ($self, $source) = @_;
  ::ni($source)->source_gen($self)->run;
  $self;
}
sub from_bg {
  my ($self, $source) = @_;
  $self < $source, exit unless fork;
  $self;
}
sub into {
  my ($self, $dest) = @_;
  $self->source_gen(::ni $dest)->run;
  $self;
}
sub into_bg {
  my ($self, $dest) = @_;
  $self > $dest, exit unless fork;
  $self;
}
}
BEGIN {
  our @data_names;
  our %data_matchers;
  our %data_transformers;
  sub defdata {
    my ($name, $matcher, $transfomer) = @_;
    die "data type $name is already defined" if exists $data_matchers{$name};
    unshift @data_names, $name;
    $data_matchers{$name}     = $matcher;
    $data_transformers{$name} = $transfomer;
  }
  sub ni_io_for {
    my ($f, @args) = @_;
    for my $n (@data_names) {
      return $data_transformers{$n}->($f, @args)
        if $data_matchers{$n}->($f, @args);
    }
    die "$f does not match any known ni::io constructor";
  }
  sub ::ni {
    my ($f, @args) = @_;
    return undef unless defined $f;
    return $f if ref $f && $f->isa('ni::io');
    return ni_io_for($f, @args);
  }
  *{"ni::ni"} = *{"::ni"};
}
our %read_filters;
our %write_filters;
defdata 'file',
  sub { -e $_[0] || $_[0] =~ s/^file:// },
  sub {
    my ($f)       = @_;
    my $extension = ($f =~ /\.(\w+)$/)[0];
    my $file      = ni_file("[file $f]", "< $f", "> $f");
    exists $read_filters{$extension}
      ? ni_filter($file, $read_filters{$extension}, $write_filters{$extension})
      : $file;
  };
sub deffilter {
  my ($extension, $read, $write) = @_;
  $read_filters{$extension}  = $read;
  $write_filters{$extension} = $write;
  my $prefix_detector = qr/^$extension:/;
  defdata $extension,
    sub { $_[0] =~ s/$prefix_detector// },
    sub { ni_filter(ni($_[0]), $read, $write) };
}
deffilter 'gz',  'gzip -d',  'gzip';
deffilter 'lzo', 'lzop -d',  'lzop';
deffilter 'xz',  'xz -d',    'xz';
deffilter 'bz2', 'bzip2 -d', 'bzip2';
defdata 'ssh',
  sub { $_[0] =~ /^\w*@[^:\/]+:/ },
  sub { $_[0] =~ /^([^:@]+)@([^:]+):(.*)$/;
        my ($user, $host, $file) = ($1, $2, $3);
        };
defdata 'globfile', sub { ref $_[0] eq 'GLOB' },
                    sub { ni_file("[fh = " . fileno($_[0]) . "]",
                                  $_[0], $_[0]) };
BEGIN {
use List::Util qw/min max/;
use POSIX qw/dup2/;
sub to_fh {
  return undef unless defined $_[0];
  return $_[0]->() if ref $_[0] eq 'CODE';
  return $_[0]     if ref $_[0] eq 'GLOB';
  open my $fh, $_[0] or die "failed to open $_[0]: $!";
  $fh;
}
defio 'sink_as',
sub { +{description => $_[0], f => $_[1]} },
{
  explain         => sub { "[sink as: " . ${$_[0]}{description} . "]" },
  supports_reads  => sub { 0 },
  supports_writes => sub { 1 },
  sink_gen        => sub { ${$_[0]}{f}->(@_[1..$#_]) },
};
defio 'source_as',
sub { +{description => $_[0], f => $_[1]} },
{
  explain    => sub { "[source as: " . ${$_[0]}{description} . "]" },
  source_gen => sub { ${$_[0]}{f}->(@_[1..$#_]) },
};
sub sink_as(&)   { ni_sink_as("[anonymous sink]", @_) }
sub source_as(&) { ni_source_as("[anonymous source]", @_) }
defio 'file',
sub {
  die "ni_file() requires three constructor arguments (got @_)" unless @_ == 3;
  +{description => $_[0], reader => $_[1], writer => $_[2]}
},
{
  explain => sub { ${$_[0]}{description} },
  reader_fh => sub {
    my ($self) = @_;
    die "io not configured for reading" unless $self->supports_reads;
    $$self{reader} = to_fh $$self{reader};
  },
  writer_fh => sub {
    my ($self) = @_;
    die "io not configured for writing" unless $self->supports_writes;
    $$self{writer} = to_fh $$self{writer};
  },
  supports_reads  => sub { defined ${$_[0]}{reader} },
  supports_writes => sub { defined ${$_[0]}{writer} },
  has_reader_fh   => sub { ${$_[0]}->supports_reads },
  has_writer_fh   => sub { ${$_[0]}->supports_writes },
  source_gen => sub {
    my ($self, $destination) = @_;
    gen 'file_source:V', {fh   => $self->reader_fh,
                          body => $destination->sink_gen('L')},
      q{ while (<%:fh>) {
           %@body
         } };
  },
  sink_gen => sub {
    my ($self, $type) = @_;
    with_type $type,
      gen 'file_sink:L', {fh => $self->writer_fh},
        q{ print %:fh $_; };
  },
  close => sub { close $_[0]->writer_fh; $_[0] },
};
defio 'memory',
sub { [@_] },
{
  explain => sub {
    "[memory io of " . scalar(@{$_[0]}) . " element(s): "
                     . "[" . join(', ', @{$_[0]}[0 .. min(3, $#{$_[0]})],
                                        @{$_[0]} > 4 ? ("...") : ()) . "]]";
  },
  supports_writes => sub { 1 },
  process_local   => sub { 1 },
  source_gen => sub {
    my ($self, $destination) = @_;
    gen 'memory_source', {xs   => $self,
                          body => $destination->sink_gen('O')},
      q{ for (@{%:xs}) {
           %@body
         } };
  },
  sink_gen => sub {
    my ($self, $type) = @_;
    gen "memory_sink:$type", {xs => $self},
      $type eq 'F' ? q{ push @{%:xs}, [@_]; }
                   : q{ push @{%:xs}, $_; };
  },
};
defio 'ring',
sub { die "ring must contain at least one element" unless $_[0] > 0;
      my $n = 0;
      +{xs       => [map undef, 1..$_[0]],
        overflow => $_[1],
        n        => \$n} },
{
  explain => sub {
    my ($self) = @_;
    "[ring io of " . min(${$$self{n}}, scalar @{$$self{xs}})
                   . " element(s)"
                   . ($$self{overflow} ? ", > $$self{overflow}]"
                                       : "]");
  },
  supports_writes => sub { 1 },
  process_local   => sub { 1 },
  source_gen => sub {
    my ($self, $destination) = @_;
    my $i     = ${$$self{n}};
    my $size  = @{$$self{xs}};
    my $start = max 0, $i - $size;
    gen 'ring_source:VV', {xs    => $$self{xs},
                           n     => $size,
                           end   => $i % $size,
                           i     => $start % $size,
                           body  => $destination->sink_gen('O')},
      q{ %:i = %@i;
         while (%:i < %@n) {
           $_ = ${%:xs}[%:i++];
           %@body
         }
         %:i = 0;
         while (%:i < %@end) {
           $_ = ${%:xs}[%:i++];
           %@body
         } };
  },
  sink_gen => sub {
    my ($self, $type) = @_;
    if (defined $$self{overflow}) {
      gen "ring_sink:${type}V", {xs   => $$self{xs},
                                 size => scalar(@{$$self{xs}}),
                                 body => $$self{overflow}->sink_gen('O'),
                                 n    => $$self{n},
                                 e    => $type eq 'F' ? '[@_]' : '$_',
                                 v    => 0,
                                 i    => 0},
        q{ %:v = $_;
           %:i = ${%:n} % %@size;
           if (${%:n}++ >= %@size) {
             $_ = ${%:xs}[%:i];
             %@body
           }
           ${%:xs}[%:i] = %:v; };
    } else {
      gen "ring_sink:${type}V", {xs   => $$self{xs},
                                 size => scalar(@{$$self{xs}}),
                                 n    => $$self{n},
                                 e    => $type eq 'F' ? '[@_]' : '$_'},
        q{ ${%:xs}[${%:n}++ % %@size] = %@e; };
    }
  },
};
defio 'iterate', sub { +{f => $_[0], x => $_[1]} },
{
};
defio 'null', sub { +{} },
{
  explain         => sub { '[null io]' },
  supports_writes => sub { 1 },
  source_gen      => sub { gen 'empty', {}, '' },
  sink_gen        => sub { gen "null_sink:$_[1]V", {}, '' },
};
defio 'sum',
sub { [map $_->flatten, @_] },
{
  explain => sub {
    "[sum: " . join(' + ', @{$_[0]}) . "]";
  },
  transform  => sub {
    my ($self, $f) = @_;
    my $x = $f->($self);
    $x eq $self ? ni_sum(map $_->transform($f), @$self)
                : $x;
  },
  flatten    => sub { @{$_[0]} },
  source_gen => sub {
    my ($self, $destination) = @_;
    return gen 'empty', {}, '' unless @$self;
    gen_seq 'sum_source:VV', map $_->source_gen($destination), @$self;
  },
};
defio 'cat',
sub { \$_[0] },
{
  explain => sub {
    "[cat ${$_[0]}]";
  },
  source_gen => sub {
    my ($self, $destination) = @_;
    $$self->source_gen(sink_as {
      my ($type) = @_;
      with_input_type $type,
        gen 'cat_source:OV',
            {dest => $destination},
            q{ $_ > %:dest; }});
  },
};
defio 'bind',
sub {
  die "code transform must be [description, f]" unless ref $_[1] eq 'ARRAY';
  +{ base => $_[0], code_transform => $_[1] }
},
{
  explain => sub {
    my ($self) = @_;
    "$$self{base} >>= $$self{code_transform}[0]";
  },
  supports_reads  => sub { ${$_[0]}{base}->supports_reads },
  supports_writes => sub { ${$_[0]}{base}->supports_writes },
  transform => sub {
    my ($self, $f) = @_;
    my $x = $f->($self);
    $x eq $self ? ni_bind($$self{base}->transform($f), $$self{code_transform})
                : $x;
  },
  sink_gen => sub {
    my ($self, $type) = @_;
    $$self{code_transform}[1]->($$self{base}, $type);
  },
  source_gen => sub {
    my ($self, $destination) = @_;
    $$self{base}->source_gen(sink_as {
      my ($type) = @_;
      $$self{code_transform}[1]->($destination, $type);
    });
  },
  close => sub { ${$_[0]}{base}->close; $_[0] },
};
defioproxy 'pipe', sub {
  pipe my $out, my $in or die "pipe failed: $!";
  ni_file("[pipe in = " . fileno($in) . ", out = " . fileno($out). "]",
          $out, $in);
};
defioproxy 'process', sub {
  my ($command, $stdin_fh, $stdout_fh) = @_;
  my $stdin  = undef;
  my $stdout = undef;
  unless (defined $stdin_fh) {
    $stdin    = ni_pipe();
    $stdin_fh = $stdin->reader_fh;
  }
  unless (defined $stdout_fh) {
    $stdout    = ni_pipe();
    $stdout_fh = $stdout->writer_fh;
  }
  my $pid = undef;
  my $create_process = sub {
    return if defined $pid;
    unless ($pid = fork) {
      close STDIN;  close $stdin->writer_fh  if defined $stdin;
      close STDOUT; close $stdout->reader_fh if defined $stdout;
      dup2 fileno $stdin_fh,  0 or die "dup2 failed: $!";
      dup2 fileno $stdout_fh, 1 or die "dup2 failed: $!";
      exec $command or exit;
    }
  };
  ni_file(
    "[process $command, stdin = $stdin, stdout = $stdout]",
    sub { $create_process->(); defined $stdout ? $stdout->reader_fh : undef },
    sub { $create_process->(); defined $stdin  ? $stdin->writer_fh  : undef });
};
defioproxy 'filter', sub {
  my ($base, $read_filter, $write_filter) = @_;
  ni_file(
    "[filter $base, read = $read_filter, write = $write_filter]",
    $base->supports_reads && defined $read_filter
      ? sub {ni_process($read_filter, $base->reader_fh, undef)->reader_fh}
      : undef,
    $base->supports_writes && defined $write_filter
      ? sub {ni_process($write_filter, undef, $base->writer_fh)->writer_fh}
      : undef);
};
}
sub flatmap_binding {
  my @args = @_;
  ["flatmap @args", sub {
    my ($into, $type) = @_;
    my $i = invocation $type, @args;
    gen "flatmap:$type", {invocation => $i,
                          body       => $into->sink_gen('O')},
      q{ for (%@invocation) {
           %@body
         } };
  }];
}
sub mapone_binding {
  my @args = @_;
  ["mapone @args", sub {
    my ($into, $type) = @_;
    my $i = invocation $type, @args;
    gen "mapone:$type", {invocation => $i,
                         body       => $into->sink_gen('F')},
      q{ if (@_ = %@invocation) {
           %@body
         } };
  }];
}
sub grep_binding {
  my @args = @_;
  ["grep @_", sub {
    my ($into, $type) = @_;
    my $i = invocation $type, @_;
    gen "grep:$type", {invocation => $i,
                       body       => $into->sink_gen($type)},
      q{ if (%@invocation) {
           %@body
         } };
  }];
}
sub reduce_binding {
  my ($f, $init, @args) = @_;
  ["reduce $f $init @args", sub {
    my ($into, $type) = @_;
    my $i = invocation $type, $f;
    with_type $type,
      gen 'reduce:F', {f    => $f,
                       init => $init,
                       body => $into->sink_gen('O')},
        q{ (%:init, @_) = %:f->(%:init, @_);
           for (@_) {
             %@body
           } };
  }];
}
sub tee_binding {
  my ($tee) = @_;
  ["tee $tee", sub {
    my ($into, $type) = @_;
    my ($save, $recover) = typed_save_recover $type;
    gen_seq "tee:$type", $save,    $tee->sink_gen($type),
                         $recover, $into->sink_gen($type);
  }];
}
sub take_binding {
  my ($n) = @_;
  die "must take a positive number of elements" unless $n > 0;
  ["take $n", sub {
    my ($into, $type) = @_;
    gen "take:${type}", {body      => $into->sink_gen($type),
                         remaining => $n},
      q{ %@body;
         return if --%:remaining <= 0; };
  }];
}
sub drop_binding {
  my ($n) = @_;
  ["drop $n", sub {
    my ($into, $type) = @_;
    gen "take:${type}", {body      => $into->sink_gen($type),
                         remaining => $n},
      q{ if (--%:remaining < 0) {
           %@body
         }};
  }];
}
sub ni::io::peek {
  my ($self, $n) = @_;
  my $buffer = ni_memory();
  ($buffer < $self->bind(take_binding($n)), $self);
}
our %op_shorthand_lookups;      # keyed by short
our %op_shorthands;             # keyed by long
our %op_formats;                # ditto
our %op_usage;                  # ditto
our %op_fns;                    # ditto
sub long_op_method  { "--$_[0]" =~ s/-/_/gr }
sub short_op_method { "_$_[0]" }
sub defop {
  my ($long, $short, $format, $usage, $fn) = @_;
  if (defined $short) {
    $op_shorthands{$long}         = $short;
    $op_shorthand_lookups{$short} = "--$long";
  }
  $op_formats{$long} = $format;
  $op_usage{$long}   = $usage;
  $op_fns{$long}     = $fn;
  my $long_method_name = long_op_method $long;
  my $short_method_name =
    defined $short ? short_op_method $short : undef;
  die "operator $long already exists (possibly as a method rather than an op)"
    if exists $ni::io::{$long_method_name}
    or defined $short_method_name && exists $ni::io::{$short_method_name};
  *{"ni::io::$short_method_name"} = $fn if defined $short_method_name;
  *{"ni::io::$long_method_name"}  = $fn;
}
our %format_matchers = (
  a => qr/^[a-zA-Z]+$/,
  d => qr/^[-+\.0-9]+$/,
  s => qr/^.*$/,
  v => qr/^[^-].*$/,
);
sub apply_format {
  my ($format, @args) = @_;
  my @format = split //, $format;
  my @parsed;
  for (@format) {
    die "too few arguments for $format" if !@args && !/[A-Z]/;
    my $a = shift @args;
    if ($a =~ /$format_matchers{lc $_}/) {
      push @parsed, $a;
    } else {
      die "failed to match format $format" unless /[A-Z]/;
      push @parsed, undef;
    }
  }
  [@parsed], @args;
}
sub file_opt { ['plus', ni $_[0]] }
sub parse_commands {
  my @parsed;
  for (my $o; defined($o = shift @_);) {
    return @parsed, map file_opt($_), @_ if $o eq '--';
    if ($o =~ /^--/) {
      my $c = $o =~ s/^--//r;
      die "unknown long command: $o" unless exists $op_fns{$c};
      my ($args, @rest) = apply_format $op_formats{$c}, @_;
      push @parsed, [$c, @$args];
      @_ = @rest;
    } elsif ($o =~ s/^-//) {
      my ($op, @stuff) = grep length,
                         split /([:+^=%\/]?[a-zA-Z]|[-+\.0-9]+)/, $o;
      die "undefined short op: $op" unless exists $op_shorthand_lookups{$op};
      unshift @_, map $op_shorthand_lookups{$_} // $_, $op, @stuff;
    } else {
      push @parsed, file_opt $o;
    }
  }
  @parsed;
}
use B::Deparse;
use File::Temp qw/tmpnam/;
defop 'self', undef, '',
  'adds the source code of ni',
  sub { $_[0] + ni_memory(self) };
defop 'explain-stream', undef, '',
  'explains the current stream',
  sub { ni_memory($_[0]->explain) };
defop 'explain-compilation', undef, '',
  'shows the compiled output for the current stream',
  sub {
    my $gen = $_[0]->source_gen(sink_as {
      with_type $_[0], gen 'print:L', {}, "print \$_;"});
    my $deparser = B::Deparse->new;
    my ($f, $refs) = $gen->compile_to_sub;
    delete $$refs{$_} for keys %$refs;
    ni_memory($deparser->coderef2text($f));
  };
defop 'defined-methods', undef, '',
  'lists defined long and short methods on IO objects',
  sub { ni_memory(map "$_\n", grep /^_/, sort keys %{ni::io::}) };
defop 'plus', undef, '',
  'adds two streams together (implied for files)',
  sub { $_[0] + $_[1] };
defop 'tee', undef, 's',
  'tees current output into the specified io',
  sub { $_[0] >>= tee_binding(ni $_[1]) };
defop 'take', undef, 'd',
  'takes the first or last N records from the specified io',
  sub { $_[1] > 0 ? $_[0] >>= take_binding($_[1])
                  : ni_ring(-$_[1]) < $_[0] };
defop 'drop', undef, 'd',
  'drops the first or last N records from the specified io',
  sub {
    my ($self, $n) = @_;
    $n >= 0
      ? $self->bind(drop_binding($n))
      : ni_source_as("$self >>= drop " . -$n . "]", sub {
          my ($destination) = @_;
          $self->source_gen(ni_ring(-$n, $destination));
        });
  };
defop 'zip', 'z', 's',
  'zips lines together with those from the specified IO',
  sub { $_[0] >>= zip_binding(ni $_[1]) };
defop 'map', 'm', 's',
  'transforms each record using the specified function',
  sub { $_[0] * $_[1] };
defop 'keep', 'k', 's',
  'keeps records for which the function returns true',
  sub { $_[0] % $_[1] };
defop 'transform', 'M', 's',
  'transforms the stream as an object using the specified function',
  sub { compile($_[1])->($_[0]) };
defop 'deref', 'r', '',
  'interprets each record as a data source and emits it',
  sub { ni_cat($_[0] * \&ni) };
defop 'ref', 'R', 'V',
  'collects data into a file and emits the filename',
  sub { my ($self, $f) = @_;
        $self > ni($f //= "file:" . tmpnam);
        ni_memory($f) };
defop 'branch', 'b', 's',
  'splits input by its first field, forwarding to subprocesses',
  sub {
    my ($in, $subprocesses) = @_;
    my @subs = unpack_branch_map $subprocesses;
    my $fifo = ni::io::fifo->new->from(map ${$_}[1], @subs);
    unless (fork) {
      my $line;
      while (defined($line = <$in>)) {
        my ($k, $v) = split /\t/, $line, 2;
        for my $s (@subs) {
          if ($s->[0]->($k)) {
            $s->[1]->enqueue($line);
            last;
          }
        }
      }
      exit;
    }
    $fifo;
  };
sub sort_options {
  my @fieldspec = split //, $_[0] // '';
}
defop 'order', 'o', 'AD',
  'order {n|N|g|G|l|L|u|U|m} [fields]',
  sub {
    my ($in, $flags, $fields) = @_;
    $in | 'sort';
  };
use POSIX qw/dup2/;
sub preprocess_cli {
  my @preprocessed;
  for (my $o; defined($o = shift @_);) {
    if ($o =~ s/\[$//) {
      my @xs;
      my $depth = 1;
      for (@_) {
        last unless $depth -= /^\]$/;
        $depth += /\[$/;
        push @xs, $_;
      }
      push @preprocessed, bless [@xs], $o;
    } elsif ($o =~ s/\{$//) {
      my @xs;
      my $depth = 1;
      for (@_) {
        last unless $depth -= /^\}$/;
        $depth += /\{$/;
        push @xs, $_;
      }
      push @preprocessed, bless {@xs}, $o;
    } else {
      push @preprocessed, $o;
    }
  }
  @preprocessed;
}
sub stream_for {
  my ($stream, @options) = @_;
  $stream //= -t STDIN ? ni_sum() : ni_file('[stdin]', \*STDIN, undef);
  for (parse_commands @options) {
    my ($command, @args) = @$_;
    eval {$stream = $ni::io::{long_op_method $command}($stream, @args)};
    die "failed to apply stream command $command [@args] "
      . "(method: " . long_op_method($command) . "): $@" if $@;
  }
  $stream;
}
sub stream_to_process {
  my ($stream, @process_alternatives) = @_;
  my $fh = $stream->reader_fh;
  if (fileno $fh) {
    close STDIN;
    dup2 fileno $fh, 0 or die "dup2 failed: $!";
  }
  exec $_ for @process_alternatives;
}
sub main {
  $|++;
  my $data = stream_for undef, preprocess_cli @_;
  if (-t STDOUT && !exists $ENV{NI_NO_PAGER}) {
    stream_to_process $data, $ENV{NI_PAGER} // $ENV{PAGER} // 'less',
                             'more';
    print STDERR "ni: couldn't exec any pagers, writing to the terminal\n";
    print STDERR "ni: (sorry about this; if you set \$PAGER it should work)\n";
    print STDERR "\n";
    print while <>;
  } else {
    $data > \*STDOUT;
  }
}
END { main @ARGV }
}
__END__