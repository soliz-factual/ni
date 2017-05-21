# Python stuff.
# A context for processing stuff in Python, as well as various functions to
# handle the peculiarities of Python code.

# Indentation fixing.
# This is useful in any context where code is artificially indented, e.g. when
# you've got a multiline quotation and the first line appears outdented because
# the quote opener has taken up space:

# | my $python_code = q{import numpy as np
#                       print np};
#   # -----------------| <- this indentation is misleading

# In this case, we want to have the second line indented at zero, not at the
# apparent indentation. The pydent function does this transformation for you, and
# correctly handles Python block constructs:

# | my $python_code = pydent q{if True:
#                                print "well that's good"};

sub pydent($) {
  my @lines   = split /\n/, $_[0];
  my @indents = map length(sr $_, qr/\S.*$/, ''), @lines;
  my $indent  = @lines > 1 ? $indents[1] - $indents[0] : 0;

  $indent = min $indent - 1, @indents[2..$#indents]
    if $lines[0] =~ /:\s*(#.*)?$/ && @lines >= 2;

  my $spaces = ' ' x $indent;
  $lines[$_] =~ s/^$spaces// for 1..$#lines;
  join "\n", @lines;
}

sub pyquote($) {"'" . sgr(sgr($_[0], qr/\\/, '\\\\'), qr/'/, '\\\'') . "'"}

# Python code parse element.
# Counts brackets, excluding those inside quoted strings. This is more efficient
# and less accurate than Ruby/Perl, but the upside is that errors are not
# particularly common.

defparseralias pycode => pmap q{pydent $_}, generic_code;
