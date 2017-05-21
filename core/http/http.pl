# HTTP server.
# A very simple HTTP server that can be used to serve a stream's contents. This is used
# by other libraries to serve things like JSPlot.

use Socket;
use Errno qw/EINTR/;

sub http_reply($$$%) {
  my ($fh, $code, $body, %headers) = @_;
  $fh->print(join "\n", "HTTP/1.1 $code NI",
                        map("$_: $headers{$_}", sort keys %headers),
                        "Content-Length: " . length($body),
                        '',
                        $body);
}

sub uri_decode(@) {(my $u = $_[0]) =~ s/%([0-9A-Fa-f]{2})/chr hex $1/eg; $u}

sub safeaccept($$) {
  my $r;
  1 until $r = accept $_[0], $_[1] or !$!{EINTR};
  $r;
}

sub http($$) {
  my (undef, $f) = @_;
  my ($server, $client);
  $f = fn $f;

  socket $server, PF_INET, SOCK_STREAM, getprotobyname 'tcp'
    or die "ni http: socket() failed: $!";
  setsockopt $server, SOL_SOCKET, SO_REUSEADDR, pack 'l', 1
    or die "ni http: setsockopt() failed: $!";

  ++$_[0] > 65535 && die "ni http: bind() failed: $!"
    until bind $server, sockaddr_in $_[0], INADDR_LOOPBACK;

  listen $server, SOMAXCONN or die "ni http: listen() failed: $!";

  &$f;
  for (; $_ = '', safeaccept $client, $server; close $client) {
    next if cfork;
    my $n = 1;
    close $server;
    $n = saferead $client, $_, 8192, length until /\r?\n\r?\n/ || !$n;
    &$f(uri_decode(/^GET (.*) HTTP\//), $_, $client);
    exit;
  }
}

# Websocket operators.
# This is used to stream a data source to the browser. See `core/jsplot` for details.

defoperator http_websocket_encode => q{
  load 'core/http/ws.pm';
  safewrite \*STDOUT, ws_encode($_) while <STDIN>;
};

defoperator http_websocket_encode_batch => q{
  load 'core/http/ws.pm';
  safewrite \*STDOUT, ws_encode($_) while saferead \*STDIN, $_, $_[0] || 8192;
};

defshort '/--http/wse',       pmap q{http_websocket_encode_op}, pnone;
defshort '/--http/wse-batch', pmap q{http_websocket_encode_batch_op $_}, popt integer;
