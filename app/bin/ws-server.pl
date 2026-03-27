#!/usr/bin/perl

# SHM WebSocket Server
# Runs alongside FastCGI in the same container
# Subscribes to Redis shm:events, pushes to connected WebSocket clients
#
# Usage: perl /app/bin/ws-server.pl &
# Port: 9083 (configure via WS_PORT env)

use v5.14;
use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;
use Digest::SHA qw(sha1);
use MIME::Base64 qw(encode_base64);
use JSON::XS qw(encode_json decode_json);
use POSIX qw(strftime);

my $WS_PORT    = $ENV{WS_PORT} || 9083;
my $REDIS_HOST = $ENV{REDIS_HOST} || 'redis';
my $REDIS_PORT = $ENV{REDIS_PORT} || 6379;
my $CHANNEL    = $ENV{WS_REDIS_CHANNEL} || 'shm:events';

# DB connection for session validation
my $DB_HOST = $ENV{DB_HOST} || 'mysql';
my $DB_PORT = $ENV{DB_PORT} || 3306;
my $DB_NAME = $ENV{DB_NAME} || 'shm';
my $DB_USER = $ENV{DB_USER} || 'shm';
my $DB_PASS = $ENV{DB_PASS} || '';

my $WS_MAGIC = '258EAFA5-E914-47DA-95CA-5AB9FC11CF48';

# State
my %clients;       # fileno => { socket, user_id, buffer }
my $redis_sock;    # Redis subscriber connection
my $redis_buffer = '';
my $dbh;           # DBI handle for session validation

$| = 1;

sub log_msg { say strftime("[%Y-%m-%d %H:%M:%S]", localtime) . " [WS] " . shift }

# --- DBI for session validation ---
sub db_connect {
    eval { require DBI };
    if ($@) {
        log_msg("DBI not available, using SHM API for auth");
        return undef;
    }
    my $dsn = "DBI:mysql:database=$DB_NAME;host=$DB_HOST;port=$DB_PORT";
    $dbh = DBI->connect($dsn, $DB_USER, $DB_PASS, {
        RaiseError => 0, PrintError => 0, mysql_auto_reconnect => 1,
    });
    log_msg($dbh ? "DB connected" : "DB connection failed: " . DBI->errstr);
    return $dbh;
}

sub validate_session {
    my $session_id = shift;
    return undef unless $session_id && length($session_id) > 10;

    if ($dbh) {
        my $row = $dbh->selectrow_hashref(
            "SELECT user_id FROM sessions WHERE id = ? AND updated > NOW() - INTERVAL 3 DAY",
            undef, $session_id
        );
        return $row ? $row->{user_id} : undef;
    }
    return undef;
}

# --- WebSocket Protocol ---
sub ws_handshake {
    my ($client_sock, $request) = @_;

    my ($key) = $request =~ /Sec-WebSocket-Key:\s*(.+?)\r?\n/i;
    return undef unless $key;

    # Extract session_id from URL
    my ($path) = $request =~ /GET\s+(\S+)/;
    my ($session_id) = ($path || '') =~ /session_id=([^&\s]+)/;

    my $user_id = validate_session($session_id);
    return undef unless $user_id;

    my $accept = encode_base64(sha1($key . $WS_MAGIC), '');

    my $response = "HTTP/1.1 101 Switching Protocols\r\n" .
                   "Upgrade: websocket\r\n" .
                   "Connection: Upgrade\r\n" .
                   "Sec-WebSocket-Accept: $accept\r\n\r\n";

    $client_sock->print($response);
    return $user_id;
}

sub ws_encode {
    my $data = shift;
    my $len = length($data);
    my $frame = chr(0x81); # FIN + text frame

    if ($len < 126) {
        $frame .= chr($len);
    } elsif ($len < 65536) {
        $frame .= chr(126) . pack('n', $len);
    } else {
        $frame .= chr(127) . pack('Q>', $len);
    }
    return $frame . $data;
}

sub ws_decode {
    my $buffer_ref = shift;
    return undef if length($$buffer_ref) < 2;

    my @header = unpack('C2', $$buffer_ref);
    my $opcode = $header[0] & 0x0F;
    my $masked = $header[1] & 0x80;
    my $len    = $header[1] & 0x7F;
    my $offset = 2;

    if ($len == 126) {
        return undef if length($$buffer_ref) < 4;
        $len = unpack('n', substr($$buffer_ref, 2, 2));
        $offset = 4;
    } elsif ($len == 127) {
        return undef if length($$buffer_ref) < 10;
        $len = unpack('Q>', substr($$buffer_ref, 2, 8));
        $offset = 10;
    }

    my $mask_len = $masked ? 4 : 0;
    my $total = $offset + $mask_len + $len;
    return undef if length($$buffer_ref) < $total;

    my $mask = $masked ? substr($$buffer_ref, $offset, 4) : '';
    $offset += $mask_len;

    my $payload = substr($$buffer_ref, $offset, $len);
    if ($masked) {
        my @mask_bytes = unpack('C4', $mask);
        my @payload_bytes = unpack('C*', $payload);
        $payload = pack('C*', map { $payload_bytes[$_] ^ $mask_bytes[$_ % 4] } 0..$#payload_bytes);
    }

    $$buffer_ref = substr($$buffer_ref, $total);

    return { opcode => $opcode, payload => $payload };
}

sub ws_send {
    my ($fileno, $type, $data) = @_;
    my $client = $clients{$fileno} or return;
    my $json = encode_json({ type => $type, data => $data, timestamp => time() });
    eval { $client->{socket}->print(ws_encode($json)) };
}

sub ws_send_to_user {
    my ($user_id, $type, $data) = @_;
    for my $fn (keys %clients) {
        ws_send($fn, $type, $data) if $clients{$fn}{user_id} eq $user_id;
    }
}

sub ws_close {
    my ($select, $fileno) = @_;
    my $client = delete $clients{$fileno} or return;
    $select->remove($client->{socket});
    $client->{socket}->close;
    log_msg("Disconnected: user $client->{user_id} (total: " . scalar(keys %clients) . ")");
}

# --- Redis Subscriber ---
sub redis_connect {
    $redis_sock = IO::Socket::INET->new(
        PeerAddr => $REDIS_HOST, PeerPort => $REDIS_PORT,
        Proto => 'tcp', Timeout => 3,
    );
    unless ($redis_sock) {
        log_msg("Redis connect failed: $!");
        return undef;
    }
    $redis_sock->print("SUBSCRIBE $CHANNEL\r\n");
    log_msg("Redis subscriber connected");
    return $redis_sock;
}

sub redis_read {
    my $data;
    my $bytes = $redis_sock->sysread($data, 65536);
    unless ($bytes) {
        log_msg("Redis disconnected");
        $redis_sock->close;
        $redis_sock = undef;
        return;
    }

    $redis_buffer .= $data;
    my @lines = split(/\r\n/, $redis_buffer);
    $redis_buffer = (substr($redis_buffer, -2) eq "\r\n") ? '' : pop @lines;

    for my $i (0..$#lines) {
        if ($lines[$i] eq 'message' && $i + 2 <= $#lines) {
            my $payload = $lines[$i + 2];
            if ($payload && $payload =~ /^\{/) {
                eval {
                    my $event = decode_json($payload);
                    handle_redis_event($event);
                };
            }
        }
    }
}

sub handle_redis_event {
    my $event = shift;
    my $user_id = $event->{user_id} or return;
    my $table   = $event->{table} || '';

    my $type = 'system_notification';
    $type = 'balance_update'  if $table =~ /^(users|pays|withdraws)$/;
    $type = 'service_update'  if $table eq 'user_services';
    $type = 'service_status'  if $table eq 'user_services' && $event->{action} =~ /ACTIVATE|BLOCK/i;

    ws_send_to_user($user_id, $type, {
        action => $event->{action},
        table  => $table,
    });
}

# --- Main ---
log_msg("Starting WebSocket server on port $WS_PORT");

db_connect();

my $server = IO::Socket::INET->new(
    LocalPort => $WS_PORT, Proto => 'tcp', Listen => 128,
    Reuse => 1, Blocking => 0,
) or die "Cannot start WS server on port $WS_PORT: $!";

my $select = IO::Select->new($server);

redis_connect();
$select->add($redis_sock) if $redis_sock;

my $last_ping = time();
my $redis_retry = 0;

log_msg("WebSocket server ready on :$WS_PORT");

while (1) {
    # Reconnect Redis if needed
    if (!$redis_sock && time() - $redis_retry > 5) {
        $redis_retry = time();
        if (redis_connect()) {
            $select->add($redis_sock);
        }
    }

    my @ready = $select->can_read(1);

    for my $sock (@ready) {
        my $fn = fileno($sock);

        # New WebSocket connection
        if ($sock == $server) {
            my $client_sock = $server->accept or next;
            $client_sock->blocking(0);

            # Read HTTP upgrade request
            my $request = '';
            while (my $line = <$client_sock>) {
                $request .= $line;
                last if $request =~ /\r\n\r\n/;
            }

            my $user_id = ws_handshake($client_sock, $request);
            unless ($user_id) {
                $client_sock->print("HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n");
                $client_sock->close;
                next;
            }

            # Count existing connections for this user
            my $user_count = grep { $clients{$_}{user_id} eq $user_id } keys %clients;
            if ($user_count >= 5) {
                $client_sock->print(ws_encode(encode_json({
                    type => 'error', data => { message => 'Too many connections' }, timestamp => time()
                })));
                $client_sock->close;
                next;
            }

            my $cfn = fileno($client_sock);
            $clients{$cfn} = { socket => $client_sock, user_id => $user_id, buffer => '' };
            $select->add($client_sock);

            ws_send($cfn, 'connected', { userId => $user_id, time => time() });
            log_msg("Connected: user $user_id (total: " . scalar(keys %clients) . ")");
        }
        # Redis data
        elsif ($redis_sock && $sock == $redis_sock) {
            redis_read();
        }
        # Client data
        elsif (my $client = $clients{$fn}) {
            my $data;
            my $bytes = $sock->sysread($data, 65536);

            unless ($bytes) {
                ws_close($select, $fn);
                next;
            }

            $client->{buffer} .= $data;

            while (my $frame = ws_decode(\$client->{buffer})) {
                if ($frame->{opcode} == 0x08) {
                    # Close frame
                    ws_close($select, $fn);
                    last;
                }
                elsif ($frame->{opcode} == 0x09) {
                    # Ping → Pong
                    eval { $sock->print(chr(0x8A) . chr(length($frame->{payload})) . $frame->{payload}) };
                }
                elsif ($frame->{opcode} == 0x0A) {
                    # Pong — ignore
                }
                elsif ($frame->{opcode} == 0x01) {
                    # Text frame — ignore (we don't expect client messages)
                }
            }
        }
    }

    # Ping every 30s
    if (time() - $last_ping > 30) {
        $last_ping = time();
        for my $fn (keys %clients) {
            eval { $clients{$fn}{socket}->print(chr(0x89) . chr(0)) } # Ping frame
                or ws_close($select, $fn);
        }
    }
}
