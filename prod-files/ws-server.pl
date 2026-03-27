#!/usr/bin/perl

# Pure-Perl WebSocket server for real-time event delivery.
# Subscribes to Redis PubSub channel and fans out events to
# browser clients connected via WebSocket, routed by user_id.
#
# Runs inside the `core` container alongside shm-server.pl.
# No external CPAN deps — uses only modules from Dockerfile-base:
#   IO::Socket::INET, IO::Select, Digest::SHA, MIME::Base64, JSON

use v5.14;
use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;
use Digest::SHA qw(sha1);
use MIME::Base64 qw(encode_base64);
use JSON qw(decode_json encode_json);
use POSIX ();

POSIX::setgid(33); # www-data
POSIX::setuid(33);

$| = 1;

my $WS_PORT    = $ENV{WS_PORT}            || 9083;
my $REDIS_HOST = $ENV{REDIS_HOST}          || 'redis';
my $REDIS_PORT = $ENV{REDIS_PORT}          || 6379;
my $CHANNEL    = $ENV{WS_REDIS_CHANNEL}    || 'shm:events';
my $WS_MAGIC   = '258EAFA5-E914-47DA-95CA-5AB5DC799C07';

# --- state ---
my $select = IO::Select->new();
my %clients;       # fileno => { sock, user_id, buf, handshake_done }
my %user_socks;    # user_id => { fileno => 1 }
my $listen_sock;
my $redis_sock;
my $redis_buf = '';

sub log_msg { say STDERR "[ws-server] @_" }

# ===== main =====
$listen_sock = IO::Socket::INET->new(
    LocalAddr => '0.0.0.0',
    LocalPort => $WS_PORT,
    Proto     => 'tcp',
    Listen    => 128,
    ReuseAddr => 1,
) or die "Cannot listen on :$WS_PORT: $!\n";
$listen_sock->blocking(0);
$select->add($listen_sock);

log_msg("listening on :$WS_PORT");

redis_connect();

# event loop
my $last_ping = time;
while (1) {
    my @ready = $select->can_read(10);

    for my $fh (@ready) {
        if ($fh == $listen_sock) {
            accept_client();
        } elsif (defined $redis_sock && $fh == $redis_sock) {
            read_redis();
        } else {
            read_client($fh);
        }
    }

    # periodic ping to keep connections alive + detect dead sockets
    if (time - $last_ping > 30) {
        $last_ping = time;
        send_ping_all();
        redis_ensure();
    }
}

# ===== Redis =====

sub redis_connect {
    eval {
        $redis_sock = IO::Socket::INET->new(
            PeerAddr => $REDIS_HOST,
            PeerPort => $REDIS_PORT,
            Proto    => 'tcp',
            Timeout  => 3,
        ) or die "connect failed: $!";
        $redis_sock->blocking(0);
        $redis_buf = '';

        # SUBSCRIBE shm:events
        my $cmd = redis_cmd('SUBSCRIBE', $CHANNEL);
        $redis_sock->syswrite($cmd);
        $select->add($redis_sock);
        log_msg("Redis subscribed to $CHANNEL");
    };
    if ($@) {
        log_msg("Redis connect error: $@");
        undef $redis_sock;
    }
}

sub redis_ensure {
    return if defined $redis_sock;
    log_msg("Reconnecting to Redis...");
    redis_connect();
}

sub redis_cmd {
    my @args = @_;
    my $out = "*" . scalar(@args) . "\r\n";
    for my $a (@args) {
        $out .= '$' . length($a) . "\r\n" . $a . "\r\n";
    }
    return $out;
}

sub read_redis {
    my $data;
    my $n = $redis_sock->sysread($data, 65536);
    unless ($n) {
        log_msg("Redis disconnected");
        $select->remove($redis_sock);
        $redis_sock->close;
        undef $redis_sock;
        return;
    }
    $redis_buf .= $data;

    # Parse RESP messages: *3\r\n$7\r\nmessage\r\n$N\r\nchannel\r\n$M\r\npayload\r\n
    while ($redis_buf =~ s/^\*3\r\n\$7\r\nmessage\r\n\$\d+\r\n[^\r]*\r\n\$(\d+)\r\n//) {
        my $len = $1;
        if (length($redis_buf) < $len + 2) {
            # incomplete — put prefix back (won't happen often)
            last;
        }
        my $payload = substr($redis_buf, 0, $len);
        $redis_buf = substr($redis_buf, $len + 2); # skip \r\n

        dispatch_event($payload);
    }

    # Discard non-message RESP replies (subscribe confirmation etc)
    $redis_buf =~ s/^\*3\r\n\$9\r\nsubscribe\r\n[^\r]*\r\n:\d+\r\n//;
}

sub dispatch_event {
    my $json = shift;
    my $event;
    eval { $event = decode_json($json) };
    return unless $event && $event->{user_id};

    my $uid = $event->{user_id};
    my $socks = $user_socks{$uid} or return;

    my $frame = ws_encode_text($json);
    for my $fn (keys %$socks) {
        my $c = $clients{$fn} or next;
        eval { $c->{sock}->syswrite($frame) };
        if ($@) { remove_client($fn) }
    }
}

# ===== WebSocket clients =====

sub accept_client {
    my $csock = $listen_sock->accept or return;
    $csock->blocking(0);
    my $fn = fileno($csock);
    $clients{$fn} = {
        sock           => $csock,
        user_id        => 0,
        buf            => '',
        handshake_done => 0,
    };
    $select->add($csock);
}

sub read_client {
    my $fh = shift;
    my $fn = fileno($fh);
    my $c  = $clients{$fn};
    unless ($c) { $select->remove($fh); return }

    my $data;
    my $n = $fh->sysread($data, 65536);
    unless ($n) { remove_client($fn); return }

    $c->{buf} .= $data;

    if (!$c->{handshake_done}) {
        do_handshake($fn);
    } else {
        process_ws_frames($fn);
    }
}

sub do_handshake {
    my $fn = shift;
    my $c  = $clients{$fn};

    # Wait for full HTTP request
    return unless $c->{buf} =~ /\r\n\r\n/;

    my ($header) = $c->{buf} =~ /^(.*?\r\n\r\n)/s;
    $c->{buf} = substr($c->{buf}, length($header));

    # Parse key & user_id
    my ($key)     = $header =~ /Sec-WebSocket-Key:\s*(\S+)/i;
    my ($query)   = $header =~ /GET\s+[^?\s]*\?(\S*)\s/;
    my ($user_id) = ($query // '') =~ /(?:^|&)user_id=(\d+)/;

    unless ($key && $user_id && $user_id > 0) {
        $c->{sock}->syswrite("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n");
        remove_client($fn);
        return;
    }

    # Accept handshake
    my $accept = encode_base64(sha1($key . $WS_MAGIC), '');
    my $resp = "HTTP/1.1 101 Switching Protocols\r\n"
             . "Upgrade: websocket\r\n"
             . "Connection: Upgrade\r\n"
             . "Sec-WebSocket-Accept: $accept\r\n"
             . "\r\n";
    $c->{sock}->syswrite($resp);

    $c->{user_id}        = $user_id;
    $c->{handshake_done} = 1;
    $user_socks{$user_id}{$fn} = 1;
}

sub process_ws_frames {
    my $fn = shift;
    my $c  = $clients{$fn};

    while (length $c->{buf} >= 2) {
        my @hdr = unpack('C2', $c->{buf});
        my $opcode  = $hdr[0] & 0x0F;
        my $masked  = ($hdr[1] & 0x80) ? 1 : 0;
        my $payload_len = $hdr[1] & 0x7F;
        my $offset = 2;

        if ($payload_len == 126) {
            last if length($c->{buf}) < 4;
            $payload_len = unpack('n', substr($c->{buf}, 2, 2));
            $offset = 4;
        } elsif ($payload_len == 127) {
            last if length($c->{buf}) < 10;
            $payload_len = unpack('Q>', substr($c->{buf}, 2, 8));
            $offset = 10;
        }

        my $mask_len = $masked ? 4 : 0;
        my $total = $offset + $mask_len + $payload_len;
        last if length($c->{buf}) < $total;

        my $mask_key = $masked ? substr($c->{buf}, $offset, 4) : '';
        my $payload  = substr($c->{buf}, $offset + $mask_len, $payload_len);
        $c->{buf} = substr($c->{buf}, $total);

        if ($masked && length($mask_key) == 4) {
            my @m = unpack('C4', $mask_key);
            my @d = unpack('C*', $payload);
            $d[$_] ^= $m[$_ % 4] for 0..$#d;
            $payload = pack('C*', @d);
        }

        if ($opcode == 0x8) {
            # Close
            $c->{sock}->syswrite(ws_close_frame());
            remove_client($fn);
            return;
        } elsif ($opcode == 0x9) {
            # Ping → Pong
            $c->{sock}->syswrite(ws_pong_frame($payload));
        } elsif ($opcode == 0xA) {
            # Pong — ignore
        }
        # Text/binary frames from client — ignore (read-only channel)
    }
}

sub remove_client {
    my $fn = shift;
    my $c  = delete $clients{$fn} or return;
    $select->remove($c->{sock});
    eval { $c->{sock}->close };
    if (my $uid = $c->{user_id}) {
        delete $user_socks{$uid}{$fn};
        delete $user_socks{$uid} unless %{$user_socks{$uid} // {}};
    }
}

# ===== WebSocket frame encoding =====

sub ws_encode_text {
    my $data = shift;
    my $len  = length $data;
    my $hdr;
    if ($len < 126) {
        $hdr = pack('CC', 0x81, $len);
    } elsif ($len < 65536) {
        $hdr = pack('CCn', 0x81, 126, $len);
    } else {
        $hdr = pack('CCQ>', 0x81, 127, $len);
    }
    return $hdr . $data;
}

sub ws_close_frame { pack('CC', 0x88, 0) }

sub ws_ping_frame  { pack('CC', 0x89, 0) }

sub ws_pong_frame  {
    my $data = shift // '';
    my $len = length $data;
    return pack('CC', 0x8A, $len) . $data;
}

sub send_ping_all {
    my $ping = ws_ping_frame();
    for my $fn (keys %clients) {
        my $c = $clients{$fn} or next;
        next unless $c->{handshake_done};
        eval { $c->{sock}->syswrite($ping) };
        if ($@) { remove_client($fn) }
    }
}
