package Local::ws_init;

# Auto-installs DataNotify hooks when Core::Sql::Data becomes available.
# Loaded via PERL5OPT=-MLocal::ws_init

use v5.14;

# INIT runs after compilation, before main execution — Core::Sql::Data is loaded by then
INIT {
    eval {
        require Local::WebSocketNotify;
        require Local::DataNotify;
        Local::DataNotify::install();
    };
    warn "[WS] Init error: $@\n" if $@;
}

1;
