# Code generator.
# A general-purpose interface to do code-generation stuff. This is used when
# you've got a task that's mostly boilerplate of some kind, but you've got
# variable regions. For example, if you wanted to generalize JVM-hosted
# command-line filters:

# | my $java_linefilter = gen q{
#     import java.io.*;
#     public class %classname {
#       public static void main(String[] args) {
#         BufferedReader stdin = <the ridiculous crap required to do this>;
#         String %line;
#         while ((%line = stdin.readLine()) != null) {
#           %body;
#         }
#       }
#     }
#   };
#   my $code = &$java_linefilter(classname => 'Foo',
#                                line      => 'line',
#                                body      => 'System.out.println(line);');

our $gensym_index = 0;
sub gensym {join '_', '_gensym', ++$gensym_index, @_}

sub gen($) {
  my @pieces = split /(%\w+)/, $_[0];
  sub {
    my %vars = @_;
    my @r = @pieces;
    $r[$_] = $vars{substr $pieces[$_], 1} for grep $_ & 1, 0..$#pieces;
    join '', map defined $_ ? $_ : '', @r;
  };
}
