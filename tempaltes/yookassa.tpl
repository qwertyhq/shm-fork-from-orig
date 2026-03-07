{{ PERL }}
use v5.14;
use Core::Base;
use LWP::UserAgent ();
use POSIX ();
use Core::Utils qw(passgen encode_json decode_json get_random_value);
use JSON ();
use SHM qw(:all);

# -------------------------
# helpers
# -------------------------
sub respond_json {
    my ($http_status, $data) = @_;
    $http_status ||= 200;
    $data ||= {};
    print_header( status => $http_status, type => 'application/json; charset=utf-8' );
    print encode_json($data);
    return;
}

sub ok_text {
    my ($text) = @_;
    $text ||= 'ok';
    print_header( status => 200, type => 'text/plain; charset=utf-8' );
    print $text;
    return;
}

sub retry_text {
    my ($text) = @_;
    $text ||= 'retry';
    print_header( status => 503, type => 'text/plain; charset=utf-8' );
    print $text;
    return;
}

sub normalize_comment_payment {
    my ($h) = @_;
    $h ||= {};
    # migrate old: comment.object -> comment.payment
    if ( !$h->{payment} && $h->{object} && ref $h->{object} eq 'HASH' ) {
        $h->{payment} = $h->{object};
        delete $h->{object};
    }
    return $h;
}

sub params_object_to_payment {
    my ($h) = @_;
    $h ||= {};
    # keep only payment (not object)
    if ( $h->{object} && ref $h->{object} eq 'HASH' ) {
        $h->{payment} = $h->{object} unless ($h->{payment} && ref $h->{payment} eq 'HASH');
        delete $h->{object};
    }
    return $h;
}

# Пометка оригинального платежа как refund:
# - МЕНЯЕМ event -> refund.succeeded
# - ДОБАВЛЯЕМ refund объект
# - НЕ ТРОГАЕМ payment
sub mark_original_pay_as_refund {
    my ($pay_obj, $refund) = @_;
    return 0 unless ($pay_obj && $refund && ref $refund eq 'HASH');

    my $refund_id = $refund->{id} // '';

    my $orig_comment = $pay_obj->get_json('comment') || {};
    $orig_comment = normalize_comment_payment($orig_comment);

    # идемпотентность: если уже записан этот refund.id — ничего не делаем
    if ($orig_comment->{refund} && ref $orig_comment->{refund} eq 'HASH') {
        my $stored_refund_id = $orig_comment->{refund}->{id} // '';
        if ($stored_refund_id && $refund_id && $stored_refund_id eq $refund_id) {
            return 1;
        }
    }

    $orig_comment->{event}  = 'refund.succeeded';
    $orig_comment->{refund} = $refund;

    # полезные метки для UI/поиска
    $orig_comment->{refunded} = 1;
    $orig_comment->{last_refund_id} = $refund_id if $refund_id;

    delete $orig_comment->{object}; # на всякий

    $pay_obj->set_json('comment', $orig_comment);
    $pay_obj->commit;

    return 1;
}

# -------------------------
# params
# IMPORTANT: do NOT read STDIN manually (avoid hangs/500/499 in CGI)
# We rely on parse_args() and/or Template::Perl vars.
# -------------------------
my %params = parse_args();

# fallback from Template::Perl vars (templates/webapp)
if ( !%params ) {
    my $req = $Template::Perl::vars{request};
    if ( ref $req eq 'HASH' && $req->{params} ) {
        %params = %{ $req->{params} };
    } elsif ( ref $req eq 'CODE' ) {
        my $r = $req->();
        %params = %{ $r->{params} || {} } if ref $r eq 'HASH';
    }
}

# bind template vars (if any)
$params{action}      ||= $Template::Perl::vars{action}      if defined $Template::Perl::vars{action};
$params{user_id}     ||= $Template::Perl::vars{user_id}     if defined $Template::Perl::vars{user_id};
$params{amount}      ||= $Template::Perl::vars{amount}      if defined $Template::Perl::vars{amount};
$params{email}       ||= $Template::Perl::vars{email}       if defined $Template::Perl::vars{email};
$params{description} ||= $Template::Perl::vars{description} if defined $Template::Perl::vars{description};
$params{method}      ||= $Template::Perl::vars{method}      if defined $Template::Perl::vars{method};

my $is_post = (($ENV{REQUEST_METHOD}||'') eq 'POST') ? 1 : 0;

my $method = lc( $params{method} // 'sbp' );
$method = $method eq 'card' ? 'card' : 'sbp';

# === SINGLE SOURCE CONFIG: config.pay_systems.yookassa ===
my $config = get_service('config', _id => 'pay_systems');
my $ps     = $config->get_data->{yookassa} || {};

my $api_key        = $ps->{api_key};
my $account_id     = $ps->{account_id};
my $return_url_cfg = $ps->{return_url};
my $desc_cfg       = $ps->{description};
my $email_cfg      = $ps->{customer_email};
my $save_payments  = $ps->{save_payments};

# ==========================
# CREATE PAYMENT (GET action=create|payment)
# ==========================
if ( ($params{action} || '') eq 'create' || ($params{action} || '') eq 'payment' ) {

    my $user;
    if ( $params{user_id} ) {
        $user = SHM->new( user_id => $params{user_id} );
        if ( $params{message_id} ) {
            get_service('Transport::Telegram')->deleteMessage( message_id => $params{message_id} );
        }
    } else {
        $user = SHM->new();
    }

    respond_json(400, { status => 400, msg => 'Error: api_key required. Please set it in config.pay_systems.yookassa' })
        unless $api_key;
    respond_json(400, { status => 400, msg => 'Error: account_id required. Please set it in config.pay_systems.yookassa' })
        unless $account_id;
    return unless ( $api_key && $account_id );

    $params{amount} ||= 100;
    my $amount     = 0 + ($params{amount} // 0);
    my $amount_str = sprintf('%.2f', $amount);

    my $description = get_random_value(
        $params{description} || $desc_cfg || ($method eq 'card' ? 'Оплата картой' : 'Оплата СБП')
    );
    respond_json(400, { status => 400, msg => 'Error: description required' }) unless $description;
    return unless $description;

    my $return_url = $return_url_cfg
        || "https://bill.myvpn24.ru/shm/v1/public/pay_stat?format=html&uid=" . $user->id;

    my $customer_email = $params{email} || $email_cfg;

    my $receipt;
    if ( $customer_email ) {
        $receipt = {
            customer => { email => $customer_email },
            items => [{
                description     => $description,
                quantity        => 1,
                amount          => { value => $amount_str, currency => "RUB" },
                vat_code        => "1",
                payment_mode    => "full_payment",
                payment_subject => "service",
            }],
        };
    }

    my %payment = (
        metadata    => { user_id => $user->id },               # IMPORTANT: user_id lives on payment metadata
        amount      => { value => $amount_str, currency => "RUB" },
        capture     => JSON::true,
        description => sprintf("%s [%d]", $description, $user->id ),
        ( $receipt ? ( receipt => $receipt ) : () ),
    );

    if ( $method eq 'card' ) {
        $payment{confirmation} = { type => "redirect", return_url => $return_url };
        $payment{payment_method_types} = ["bank_card"];
        $payment{save_payment_method}  = JSON::true if $save_payments;
    } else { # sbp
        my $payment_method_id;
        if ( ($params{action} || '') eq 'payment' ) {
            $payment_method_id = $user->get_settings->{pay_systems}->{yookassa}->{payment_id};
        }

        if ( $payment_method_id ) {
            $payment{payment_method_id} = $payment_method_id;
            $payment{confirmation} = { type => "redirect", return_url => $return_url };
        } else {
            $payment{payment_method_data} = { type => "sbp" };
            $payment{confirmation}        = { type => "qr" };
            $payment{save_payment_method} = JSON::false;
        }
    }

    my $content = encode_json(\%payment);

    my $http_req = HTTP::Request->new( POST => "https://api.yookassa.ru/v3/payments" );
    $http_req->header('Content-Type'     => 'application/json');
    $http_req->header('Idempotence-Key'  => passgen(30));
    $http_req->authorization_basic( $account_id, $api_key );
    $http_req->content( $content );

    my $browser  = LWP::UserAgent->new( timeout => 30 );
    my $response = $browser->request( $http_req );

    if ( $response->is_success ) {
        my $d = decode_json( $response->decoded_content );

        if ( $method eq 'card' ) {
            if ( my $order_id = $d->{id} ) {
                my $target = "https://yoomoney.ru/checkout/payments/v2/contract/bankcard?orderId=$order_id";
                print_header( status => 302, location => $target );
                print '';
                return;
            }
        } else {
            if ( my $order_id = $d->{id} ) {
                my $sbp_url = "https://yoomoney.ru/checkout/payments/v2/contract/sbp?orderId=$order_id";
                my $sbp_qr  = "";

                if ( $d->{confirmation} && ($d->{confirmation}->{type}||'') eq 'qr' ) {
                    $sbp_qr = $d->{confirmation}->{confirmation_data} || "";
                }

                respond_json(200, {
                    status  => 200,
                    orderId => $order_id,
                    sbp_url => $sbp_url,
                    sbp_qr  => $sbp_qr,
                });
                return;
            }
        }

        if ( ($d->{status} // '') eq 'succeeded' ) {
            respond_json(200, { status => 200, msg => "Payment successful" });
            return;
        }

        my %i18n = (
            insufficient_funds => 'недостаточно средств',
            permission_revoked => 'автосписания запрещены',
        );
        my $reason = $d->{cancellation_details}->{reason};
        respond_json(406, {
            status => 406,
            msg    => $reason || 'payment_failed',
            ( exists $i18n{$reason} ? ( msg_ru => $i18n{$reason} ) : () ),
            raw    => $d,
        });
        return;
    }

    print_header( status => 402 );
    print $response->content;
    return;
}

# ==========================
# WEBHOOKS (POST)
# ==========================
if (!$is_post) {
    respond_json(400, { status => 400, msg => 'Error: bad request' });
    return;
}

# If engine did not parse JSON body -> ACK 200 (do not break payments), but log loudly.
unless ( $params{event} || ($params{object} && ref $params{object} eq 'HASH') ) {
    logger->error('YooKassa webhook: body not parsed (no event/object)');
    logger->dump({
        ct  => ($ENV{CONTENT_TYPE} || $ENV{HTTP_CONTENT_TYPE} || ''),
        len => 0 + ($ENV{CONTENT_LENGTH} || $ENV{HTTP_CONTENT_LENGTH} || 0),
        ua  => ($ENV{HTTP_USER_AGENT} || ''),
    });
    ok_text('ok');
    return;
}

my $event = $params{event} || '';

my %allowed_events = (
    'payment.succeeded' => 1,
    'refund.succeeded'  => 1,
    'payment.canceled'  => 1,
);

unless ( $allowed_events{$event} ) {
    ok_text('ok');
    return;
}

# For known events we expect object
unless ( $params{object} && ref $params{object} eq 'HASH' ) {
    logger->error("YooKassa webhook: event=$event but no object (not parsed)");
    logger->dump({
        ct  => ($ENV{CONTENT_TYPE} || $ENV{HTTP_CONTENT_TYPE} || ''),
        len => 0 + ($ENV{CONTENT_LENGTH} || $ENV{HTTP_CONTENT_LENGTH} || 0),
        ua  => ($ENV{HTTP_USER_AGENT} || ''),
        event => $event,
    });
    ok_text('ok');
    return;
}

# config sanity
unless ($account_id) {
    logger->error('YooKassa webhook: missing config.pay_systems.yookassa.account_id');
    ok_text('ok');
    return;
}

# recipient check for non-refund
if ( $event ne 'refund.succeeded' ) {
    my $in_acc = $params{object}->{recipient}->{account_id} // '';
    if ( $in_acc ne ($account_id // '') ) {
        logger->error('YooKassa webhook: wrong recipient.account_id');
        logger->dump({ got => $in_acc, expected => ($account_id // '') });
        ok_text('ok');
        return;
    }
}

# ==========================
# REFUND (Вариант A):
# - создаём отдельный pay с отрицательной суммой (yookassa-refund)
# - оригинальный pay (по payment_id) помечаем как refund: event=refund.succeeded + refund объект
# - в refund-pay пишем ссылку на оригинал
# ==========================
if ( $event eq 'refund.succeeded' ) {

    my $refund = $params{object} || {};
    my $refund_id   = $refund->{id}         || '';
    my $payment_id  = $refund->{payment_id} || '';

    unless ($payment_id) {
        logger->error('refund.succeeded: no object.payment_id');
        ok_text('ok');
        return;
    }

    # find original pay by uniq_key = YooKassa payment id
    my ($pay_row) = get_service('pay')->_list( where => { uniq_key => $payment_id } );

    unless ($pay_row && $pay_row->{id}) {
        logger->error("refund.succeeded: original pay not found (uniq_key=$payment_id) => retry");
        retry_text('retry');
        return;
    }

    my $pay_obj = get_service('pay')->id( $pay_row->{id} );
    my $orig_user_id = eval { $pay_obj->user_id } || $pay_row->{user_id};

    unless ($orig_user_id) {
        logger->error("refund.succeeded: cannot get user_id from pay_id=$pay_row->{id}");
        ok_text('ok');
        return;
    }

    my $u = SHM->new( skip_check_auth => 1 )->id($orig_user_id);
    unless ($u) {
        logger->error("refund.succeeded: user not found user_id=$orig_user_id");
        ok_text('ok');
        return;
    }

    unless ( $u->lock( timeout => 5 ) ) {
        logger->error("refund.succeeded: user lock timeout user_id=$orig_user_id => retry");
        retry_text('retry');
        return;
    }

    # refund amount (YooKassa: amount.value)
    my $refund_amount = 0;
    if ($refund->{amount} && ref $refund->{amount} eq 'HASH') {
        $refund_amount = 0 + ($refund->{amount}->{value} // 0);
    } elsif (defined $refund->{amount}) {
        $refund_amount = 0 + ($refund->{amount} // 0);
    }

    unless ($refund_amount > 0) {
        logger->error("refund.succeeded: refund amount not positive (refund_id=$refund_id)");
        logger->dump({ refund => $refund });
        ok_text('ok');
        return;
    }

    my $money_delta = 0 - $refund_amount;

    # ---- 1) помечаем ОРИГИНАЛ как refund (event + refund info) ----
    mark_original_pay_as_refund($pay_obj, $refund);

    # ---- 2) создаём отдельный refund-pay (идемпотентно) ----
    my $refund_uniq_key = $refund_id ? ("refund-" . $refund_id) : ("refund-" . $payment_id . "-" . $refund_amount);

    my ($exists_ref) = get_service('pay')->_list( where => { uniq_key => $refund_uniq_key } );
    if ($exists_ref && $exists_ref->{id}) {
        $u->recash;
        $u->commit;
        ok_text('ok');
        return;
    }

    my %comment_params = %params;
    params_object_to_payment(\%comment_params);   # object->payment (и удалить object)

    $comment_params{event}  = 'refund.succeeded';
    $comment_params{refund} = $refund;

    # связь с оригиналом
    $comment_params{orig_pay_id}     = $pay_obj->id;
    $comment_params{orig_payment_id} = $payment_id;
    $comment_params{orig_uniq_key}   = $payment_id;

    $u->payment(
        user_id       => $orig_user_id,
        money         => $money_delta,
        pay_system_id => 'yookassa-refund',
        comment       => \%comment_params,
        uniq_key      => $refund_uniq_key,
    );

    $u->recash;
    $u->commit;

    ok_text('ok');
    return;
}

# ==========================
# PAYMENT EVENTS (metadata.user_id expected on payment object)
# ==========================
my $payment = $params{object};
my $user_id = $payment->{metadata}->{user_id};

unless ( $user_id ) {
    logger->error("payment webhook without metadata.user_id event=$event");
    ok_text('ok');
    return;
}

my $user = SHM->new( skip_check_auth => 1 )->id($user_id);
unless ($user) {
    logger->error("User [$user_id] not found");
    ok_text('ok');
    return;
}

unless ( $user->lock( timeout => 5 ) ) {
    logger->error("User lock timeout for [$user_id] => retry");
    retry_text('retry');
    return;
}

# Save payment method if requested by YooKassa
if ( $payment->{payment_method} && $payment->{payment_method}->{saved} ) {
    $user->set_settings({
        pay_systems => {
            yookassa => {
                name       => $payment->{payment_method}->{title},
                payment_id => $payment->{payment_method}->{id},
            },
        },
    });
}

my $amount   = $payment->{amount}->{value};
my $uniq_key = $payment->{id};

if ( $event eq 'payment.canceled' ) {
    $uniq_key = "canceled-" . $payment->{id};
    $amount   = 0;
}

# idempotency
my ($exists) = get_service('pay')->_list( where => { uniq_key => $uniq_key } );
if ($exists && $exists->{id}) {
    $user->commit;
    ok_text('ok');
    return;
}

# store as comment.payment (not object)
my %comment_params = %params;
params_object_to_payment(\%comment_params);
$comment_params{event} = $event;

$user->payment(
    user_id       => $user_id,
    money         => $amount,      # YooKassa gives amount.value
    pay_system_id => 'yookassa',    # ALWAYS "yookassa"
    comment       => \%comment_params,
    uniq_key      => $uniq_key,
);

$user->commit;
ok_text('ok');
return;

{{ END }}
