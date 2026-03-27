package Local::DataNotify;

# Hooks into Core::Sql::Data write methods (_set, _add, _delete)
# to publish real-time events via Redis on commit.
#
# Uses SHM's add_post_commit_callback for transactional safety:
# events are published only after successful DB commit.
#
# Call Local::DataNotify::install() after Core::Sql::Data is loaded.

use v5.14;
use strict;
use warnings;

my $installed = 0;

sub install {
    return if $installed;
    return unless defined &Core::Sql::Data::_set;

    $installed = 1;

    require Local::WebSocketNotify;

    my %skip_tables = map { $_ => 1 } qw(
        sessions spool_history configs
    );

    for my $method (qw(_set _add _delete)) {
        my $orig = \&{"Core::Sql::Data::$method"};

        no strict 'refs';
        no warnings 'redefine';

        *{"Core::Sql::Data::$method"} = sub {
            my $self = shift;
            my %args = @_;

            # Call original
            my $result = $orig->($self, %args);

            # Register post-commit callback for real-time notification
            eval {
                my $table = $args{table} || eval { $self->table } || return;
                return if $skip_tables{$table};

                my $user_id = $self->{user_id} || 0;
                return unless $user_id;

                my $action = $method eq '_add'    ? 'create'
                           : $method eq '_delete' ? 'delete'
                           : 'update';

                # Deduplicate: use table+user_id as key
                my $key = "ws:$table:$user_id";
                my $pending = Core::System::ServiceManager::get_service('config')->local;
                return if $pending->{$key}++;

                $self->add_post_commit_callback(sub {
                    Local::WebSocketNotify::publish(
                        action  => $action,
                        table   => $table,
                        user_id => $user_id,
                    );
                });
            };

            return $result;
        };
    }

    warn "[WS] DataNotify installed: _set, _add, _delete hooked\n";
}

1;
