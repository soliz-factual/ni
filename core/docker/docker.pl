# Pipeline dockerization.
# Creates a transient container to execute a part of your pipeline. The image you
# specify needs to have Perl installed, but that's about it.

# Prebuilt image case.
# This is what happens by default, and looks like `ni Cubuntu[g]`.

use constant docker_image_name => prx '[^][]+';

defoperator docker_run_image => q{
  my ($image, @f) = @_;
  my $fh = siproc {exec qw|docker run --rm -i|, $image, ni_quoted_exec_args};
  quote_ni_into $fh, @f;
};

# On-demand images.
# These are untagged images built on the fly. NB: workaround here for old/buggy
# versions of the docker client; here's what's going on.

# Normally you'd use `docker build -q` and get an image ID, but some older docker
# clients ignore the `-q` option and emit full verbose output (and, in
# unexpectedly barbaric fashion, they also emit this verbosity to standard out,
# not standard error). So we instead go through the silliness of tagging and then
# untagging the image.

defoperator docker_run_dynamic => q{
  my ($dockerfile, @f) = @_;
  my $fh = siproc {
    my $quoted_dockerfile = shell_quote 'printf', '%s', $dockerfile;
    my $quoted_args       = shell_quote ni_quoted_exec_args;
    my $image_name        = "ni-tmp-" . lc noise_str 32;
    sh qq{image_name=\`$quoted_dockerfile | docker build -q -\`
          if [ \${#image_name} -gt 80 ]; then \\
            $quoted_dockerfile | docker build -q -t $image_name - >&2
            image_name=$image_name
            docker run --rm -i \$image_name $quoted_args
            docker rmi --no-prune=true \$image_name
          else
            docker run --rm -i \$image_name $quoted_args
          fi};
  };
  quote_ni_into $fh, @f;
};

sub alpine_dockerfile {
  join "\n", 'FROM alpine',
             q{RUN echo '@edge http://nl.alpinelinux.org/alpine/edge/main' \
                   >> /etc/apk/repositories \
                && echo '@testing http://nl.alpinelinux.org/alpine/edge/testing' \
                   >> /etc/apk/repositories \
                && echo '@community http://nl.alpinelinux.org/alpine/edge/community' \
                   >> /etc/apk/repositories \
                && apk update \
                && apk add perl},
             map "RUN apk add $_", @_;
}

sub ubuntu_dockerfile {
  join "\n", 'FROM ubuntu',
             'RUN apt-get update',
             map "RUN apt-get install -y $_", @_;
}

use constant docker_package_list => pmap q{[/\+([^][+]+)/g]}, prx '[^][]+';

defshort '/C',
  defalt 'dockeralt', 'alternatives for the /C containerize operator',
    pmap(q{docker_run_dynamic_op alpine_dockerfile(@{$$_[0]}), @{$$_[1]}},
         pseq pn(1, prc 'A', pc docker_package_list), _qfn),
    pmap(q{docker_run_dynamic_op ubuntu_dockerfile(@{$$_[0]}), @{$$_[1]}},
         pseq pn(1, prc 'U', pc docker_package_list), _qfn),
    pmap(q{docker_run_image_op $$_[0], @{$$_[1]}},
         pseq pc docker_image_name, _qfn);

# Execution within existing containers.
# Same idea as running a new Docker, but creates a process within an existing
# container.

use constant docker_container_name => docker_image_name;

defoperator docker_exec => q{
  my ($container, @f) = @_;
  my $fh = siproc {exec qw|docker exec -i|, $container, ni_quoted_exec_args};
  quote_ni_into $fh, @f;
};

defshort '/E', pmap q{docker_exec_op $$_[0], @{$$_[1]}},
               pseq pc docker_container_name, _qfn;
