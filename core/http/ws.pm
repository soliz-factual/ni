# WebSocket encoding functions.
# We just encode text messages; no binary or other protocols are defined yet.

BEGIN {
  eval 'use Digest::SHA qw/sha1_base64/';
  load 'core/deps/sha1.pm',
    Digest::SHA::PurePerl->import(qw/sha1_base64/) if $@;

  eval 'use Encode qw/encode/';
  if ($@) {
    warn 'ni: websockets will fail for utf-8 data on this machine '
       . '(no Encode module)';
    *encode = sub {$_[1]};
  }
}

use constant ws_guid => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

sub ws_header($) {
  my ($client_key) = $_[0] =~ /Sec-WebSocket-Key:\s*(\S+)/i;
  my ($protocol)   = $_[0] =~ /Sec-WebSocket-Protocol:\s*(\S+)/i;
  my $hash = sha1_base64 $client_key . ws_guid;
  join "\n", "HTTP/1.1 101 Switching Protocols",
             "Upgrade: websocket",
             "Connection: upgrade",
             "Sec-WebSocket-Accept: $hash=",
             "Sec-WebSocket-Protocol: $protocol",
             '', '';
}

sub ws_length_encode($) {
  my ($n) = @_;
  return pack 'C',        $n if $n < 126;
  return pack 'Cn',  126, $n if $n < 65536;
  return pack 'CNN', 127, $n >> 32, $n;
}

sub ws_encode($) {
  my $e = encode 'utf8', $_[0];
  "\x81" . ws_length_encode(length $e) . $e;
}
