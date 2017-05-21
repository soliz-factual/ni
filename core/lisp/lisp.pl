# Lisp backend.
# A super simple SBCL operator. The first thing we want to do is to define the
# code template that we send to Lisp via stdin (using a heredoc). So ni ends up
# generating a pipeline element like this:

# | ... | sbcl --noinform --script 3<&0 <<'EOF' | ...
#         (prefix lisp code)
#         (line mapping code)
#         EOF

use POSIX ();

use constant lisp_mapgen => gen q{
  %prefix
  (with-ni-env nil
    %body)
};

use constant lisp_grepgen => gen q{
  %prefix
  (with-ni-env t
    %body)
};

# Now we specify which files get loaded into the prefix. File paths become keys
# in the %self hash.

sub lisp_prefix() {join "\n", @ni::self{qw| core/lisp/prefix.lisp |}}

# Finally we define the toplevel operator. 'root' is the operator context, 'L' is
# the operator name, and pmap {...} mrc '...' is the parsing expression that
# consumes the operator's arguments (in this case a single argument of just some
# Lisp code) and returns a shell command. (See src/sh.pl.sdoc for details about
# how shell commands are represented.)

BEGIN {defparseralias lispcode => prc '.*[^]]+'}

defoperator lisp_code => q{
  my ($code) = @_;
  cdup2 0, 3;
  POSIX::close 0;
  safewrite siproc {exec qw| sbcl --noinform --noprint --eval |,
                         '(load *standard-input* :verbose nil :print nil)'},
            $code;
};

defshort '/l', pmap q{lisp_code_op lisp_mapgen->(prefix => lisp_prefix,
                                                 body   => $_)},
               lispcode;

defrowalt pmap q{lisp_code_op lisp_grepgen->(prefix => lisp_prefix,
                                             body   => $_)},
          pn 1, pstr 'l', lispcode;
