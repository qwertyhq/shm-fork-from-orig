package Local::WebSocketNotify;

use v5.14;
use strict;
use warnings;
use JSON::XS qw(encode_json);

my $redis_host = $ENV{REDIS_HOST} || 'redis';
my $redis_port = $ENV{REDIS_PORT} || 6379;
my $channel    = $ENV{WS_REDIS_CHANNEL} || 'shm:events';

# Buffer of pending events (flushed on commit)
my @pending_events;

sub queue_event {
    my %args = @_;
    return unless $args{user_id} && $args{table};
    push @pending_events, {
        action    => $args{action}  || 'update',
        table     => $args{table},
        user_id   => $args{user_id},
        timestamp => time(),
        %{ $args{extra} || {} },
    };
}

sub flush_events {
    return unless @pending_events;

    # Deduplicate: one event per user_id+table combo
    my %seen;
    my @unique;
    for my $ev (@pending_events) {
        my $key = "$ev->{user_id}:$ev->{table}";
        next if $seen{$key}++;
        push @unique, $ev;
    }
    @pending_events = ();

    for my $ev (@unique) {
        _publish($ev);
    }
}

sub clear_events {
    @pending_events = ();
}

sub publish {
    my %args = @_;
    return unless $args{user_id} && $args{table};

    my $payload = {
        action    => $args{action}  || 'update',
        table     => $args{table},
        user_id   => $args{user_id},
        timestamp => time(),
        %{ $args{extra} || {} },
    };

    _publish($payload);
}

sub _publish {
    my $payload = shift;

    eval {
        require IO::Socket::INET;
        my $sock = IO::Socket::INET->new(
            PeerAddr => $redis_host,
            PeerPort => $redis_port,
            Proto    => 'tcp',
            Timeout  => 1,
        );
        return unless $sock;

        my $json = encode_json($payload);
        my $cmd = _redis_cmd('PUBLISH', $channel, $json);
        $sock->print($cmd);
        my $resp = <$sock>;
        $sock->close;
    };
    if ($@) {
        warn "[WS] Redis publish failed: $@";
    }
}

sub _redis_cmd {
    my @args = @_;
    my $cmd = "*" . scalar(@args) . "\r\n";
    for my $arg (@args) {
        $cmd .= '$' . length($arg) . "\r\n" . $arg . "\r\n";
    }
    return $cmd;
}

1;
