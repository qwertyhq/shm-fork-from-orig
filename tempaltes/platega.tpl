{{ PERL }}
use v5.14;
use Core::Base;
use LWP::UserAgent ();
use Core::Utils qw(
    encode_json
    decode_json
    get_random_value
    hash_merge
);
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

sub ok_json {
    my ($msg) = @_;
    $msg ||= 'OK';
    respond_json(200, { status => 200, msg => $msg });
    return;
}

# -------------------------
# params
# -------------------------
my %params = parse_args();

# fallback from Template::Perl vars
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
$params{ps}          ||= $Template::Perl::vars{ps}          if defined $Template::Perl::vars{ps};
$params{description} ||= $Template::Perl::vars{description} if defined $Template::Perl::vars{description};
$params{message_id}  ||= $Template::Perl::vars{message_id}  if defined $Template::Perl::vars{message_id};

my $is_post = (($ENV{REQUEST_METHOD}||'') eq 'POST') ? 1 : 0;

# -------------------------
# config
# -------------------------
my $ps_base = 'platega';
my $ps_name = $params{ps} || $ps_base;

my $config = get_service('config', _id => 'pay_systems');
my $cfg_data = $config ? $config->get_data : {};

# Проверяем что конфиг существует
unless ( ref $cfg_data->{$ps_name} eq 'HASH' ) {
    respond_json(400, { status => 400, msg => "Error: payment system `$ps_name` not configured" });
    return;
}

# Мержим базовый конфиг (platega) с переопределённым (platega_crypto и т.д.)
my %ps = %{ hash_merge(
    {},
    $cfg_data->{$ps_base} || {},
    $ps_name ne $ps_base ? ($cfg_data->{$ps_name} || {}) : {},
)};

my $merchant_id = $ps{merchant_id};
my $api_key     = $ps{api_key};
my $currency    = $ps{currency} || 'RUB';
my $return_url  = $ps{return_url} || 'https://google.com';
my $fail_url    = $ps{fail_url} || 'https://google.com';
my $method      = $ps{payment_method} || $ps{paymentMethod} || 2;

# ==========================
# CREATE PAYMENT (action=create)
# ==========================
if ( ($params{action} || '') eq 'create' ) {

    my $user;
    if ( $params{user_id} ) {
        $user = SHM->new( user_id => $params{user_id} );
        unless ( $user ) {
            respond_json(400, { status => 400, msg => 'Error: unknown user' });
            return;
        }
        if ( $params{message_id} ) {
            get_service('Transport::Telegram')->deleteMessage( message_id => $params{message_id} );
        }
    } else {
        $user = SHM->new();
    }

    unless ( $merchant_id ) {
        respond_json(400, { status => 400, msg => 'Error: merchant_id required. Please set it in config' });
        return;
    }
    unless ( $api_key ) {
        respond_json(400, { status => 400, msg => 'Error: api_key required. Please set it in config' });
        return;
    }

    my $amount = $params{amount} || 100;
    my $description = get_random_value( $params{description} || $ps{description} || 'Пополнение баланса' );

    my $body = {
        paymentMethod => 0 + $method,
        paymentDetails => {
            amount => 0 + $amount,
            currency => $currency,
        },
        description => $description,
        return => $return_url,
        payload => "" . $user->id,
        failedUrl => $fail_url,
    };

    my $ua = LWP::UserAgent->new( timeout => 10 );
    my $req = HTTP::Request->new( POST => 'https://app.platega.io/transaction/process' );

    $req->header('Content-Type' => 'application/json');
    $req->header('X-MerchantId' => $merchant_id);
    $req->header('X-Secret' => $api_key);
    $req->content( encode_json($body) );

    my $response = $ua->request($req);

    if ( $response->is_success ) {
        my $data = decode_json( $response->decoded_content );
        if ( my $location = $data->{redirect} ) {
            print_header( status => 301, location => $location );
            print '';
            return;
        } else {
            respond_json(406, { status => 406, msg => "This response does not have redirect", raw => $data });
            return;
        }
    } else {
        print_header( status => 402 );
        print $response->content;
        return;
    }
}

# ==========================
# WEBHOOK (POST from Platega)
# ==========================
unless ( $is_post ) {
    respond_json(400, { status => 400, msg => 'Error: bad request (not POST)' });
    return;
}

# Platega sends X-MerchantId and X-Secret in headers
my $hdr_merchant = $ENV{HTTP_X_MERCHANTID} || '';
my $hdr_secret   = $ENV{HTTP_X_SECRET} || '';

unless ( $hdr_merchant && $hdr_secret ) {
    respond_json(400, { status => 400, msg => 'Error: missing X-MerchantId or X-Secret headers' });
    return;
}

if ( $hdr_secret ne $api_key ) {
    respond_json(400, { status => 400, msg => 'Error: X-Secret did not match' });
    return;
}

if ( $hdr_merchant ne $merchant_id ) {
    respond_json(400, { status => 400, msg => 'Error: X-MerchantId not found' });
    return;
}

my $user_id = $params{payload};

# Тестовый webhook (без payload/amount) - OK
unless ( $user_id && defined $params{amount} ) {
    ok_json('OK');
    return;
}

my $user = SHM->new( skip_check_auth => 1 )->id($user_id);
unless ( $user ) {
    respond_json(404, { status => 404, msg => "User [$user_id] not found" });
    return;
}

unless ( $user->lock( timeout => 10 ) ) {
    respond_json(408, { status => 408, msg => 'The service is locked. Try again later' });
    return;
}

my $amount   = $params{amount};
my $uniq_key = $params{id};
my $status   = $params{status} || '';

# CANCELED
if ( $status eq 'CANCELED' ) {
    $ps_name .= '-canceled';
    $uniq_key = "canceled-" . $params{id};
    $amount = 0;
}

# CONFIRMED - зачисляем
if ( $status eq 'CONFIRMED' ) {

    # idempotency
    my ($exists) = get_service('pay')->_list( where => { uniq_key => $uniq_key } );
    if ( $exists && $exists->{id} ) {
        $user->commit;
        ok_json('already processed');
        return;
    }

    $user->payment(
        user_id       => $user_id,
        money         => $amount,
        pay_system_id => $ps_name,
        comment       => \%params,
        uniq_key      => $uniq_key,
    );

    $user->commit;

    ok_json('operation successful');
    return;
}

respond_json(400, { status => 400, msg => 'Error: unknown status', received_status => $status });
return;

{{ END }}
