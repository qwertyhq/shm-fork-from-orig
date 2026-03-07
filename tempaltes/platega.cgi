#!/usr/bin/perl

#https://docs.platega.io
# Комиссию добавляет Platega на странице оплаты.
# Клиент вводит 200₽ → Platega показывает 200₽ + комиссия → на баланс зачисляется 200₽.

use v5.14;
use Core::Base;
use LWP::UserAgent ();
use Core::Utils qw(
    encode_json
    decode_json
    get_random_value
    hash_merge
);
use CGI;
our $cgi = CGI->new;

use SHM qw(:all);
our %vars = parse_args();

my $user = SHM->new( skip_check_auth => 1 );
my $ps = 'platega';

my $config = get_service('config', _id => 'pay_systems')->get_data;

my $ps_name = $vars{ps} || $ps;

# Проверяем что конфиг существует
unless ( ref $config->{$ps_name} eq 'HASH' ) {
    print_json({ status => 400, msg => "Error: payment system `$ps_name` not configured" });
    exit 0;
}

# Мержим базовый конфиг (platega) с переопределённым (platega_crypto и т.д.)
# Используем {} как базу чтобы не мутировать оригинальный конфиг
my %ps_config = %{ hash_merge(
    {},
    $config->{$ps} || {},
    $ps_name ne $ps ? ($config->{$ps_name} || {}) : {},
)};

if ( $vars{action} && $vars{action} eq 'create' ) {

    if ( $vars{user_id} ) {
        $user = $user->id( $vars{user_id} );
        unless ( $user ) {
            print_json({ status => 400, msg => 'Error: unknown user' });
            exit 0;
        }
        if ($vars{message_id}) {
            get_service('Transport::Telegram')->deleteMessage(message_id => $vars{message_id});
        }
    } else {
        $user = SHM->new();
    }

    my $merchant_id = $ps_config{merchant_id};
    my $api_key     = $ps_config{api_key};
    my $currency    = $ps_config{currency} || 'RUB';
    my $return_url  = $ps_config{return_url} || 'https://google.com';
    my $fail_url    = $ps_config{fail_url} || 'https://google.com';
    my $description = get_random_value( $vars{description} || $ps_config{description} || 'Пополнение баланса' );
    my $method      = $ps_config{payment_method} || $ps_config{paymentMethod} || 2;

    print_json({ status => 400, msg => 'Error: merchant_id required. Please set it in config' }) unless $merchant_id;
    print_json({ status => 400, msg => 'Error: api_key required. Please set it in config'     }) unless $api_key;
    exit 0 unless ( $merchant_id && $api_key );

    my $amount = $vars{amount} || 100;
    
    # Передаём user_id, ps_name и сумму зачисления в payload
    my $payload = $ps_name ne $ps
        ? "$vars{user_id}:$ps_name:$amount"
        : "$vars{user_id}::$amount";

    my $body = {
        paymentMethod => 0 + $method,
        paymentDetails => {
            amount => $amount + 0,
            currency => $currency,
        },
        description => $description,
        return => "$return_url",
        payload => $payload,
        failedUrl => "$fail_url",
    };

    my $ua = LWP::UserAgent->new( timeout => 30 );
    my $req = HTTP::Request->new( POST => 'https://app.platega.io/transaction/process' );

    $req->header('content-type' => 'application/json');
    $req->header('X-MerchantId' => $merchant_id);
    $req->header('X-Secret' => $api_key);
    $req->content( encode_json( $body ) );
    my $response = $ua->request( $req );

    if ( $response->is_success ) {
        my $response_data = decode_json( $response->decoded_content );
        if ( my $location = $response_data->{redirect} ) {
            print_header(
                location => $location,
                status => 301,
            );
        } else {
            print_json({
                status => 406,
                msg => "This response does not have a body",
            });
        }
    } else {
        print_header( status => 402 );
        print $response->content;
    }

    exit 0;
}

# ============ WEBHOOK (Callback) ============

my $merchant_id = $cgi->http('X-MerchantId');
my $api_key = $cgi->http('X-Secret');

unless ( $merchant_id && $api_key ) {
    print_json({ status => 400, msg => 'Error: bad request' });
    exit 0;
}

if ( $api_key ne $ps_config{api_key} ) {
    print_json({ status => 400, msg => "Error: X-Secret did not match." });
    exit 0;
}

if ( $merchant_id ne $ps_config{merchant_id} ) {
    print_json({ status => 400, msg => "Error: X-MerchantId not found" });
    exit 0;
}

# Парсим payload: "user_id" или "user_id:ps_name:original_amount"
my $payload_raw = $vars{payload} || '';
my ($user_id, $payload_ps, $original_amount) = split(/:/, $payload_raw, 3);

# Если в payload был ps_name - используем его для pay_system_id
$ps_name = $payload_ps if $payload_ps;

# Тестовый webhook (без payload/amount) - возвращаем OK
unless ( $user_id && defined $vars{amount} ) {
    print_json({ status => 200, msg => 'OK' });
    exit 0;
}

unless ( $user = $user->id( $user_id ) ) {
    print_json({ status => 404, msg => "User [$user_id] not found" });
    exit 0;
}

unless ( $user->lock( timeout => 10 )) {
    print_json({ status => 408, msg => "The service is locked. Try again later" });
    exit 0;
}

my $amount = $vars{amount};
my $uniq_key = $vars{id};

if ( $vars{status} eq 'CANCELED' ) {
    $ps_name .= '-canceled';
    $uniq_key = sprintf("canceled-%s", $vars{id} );
    $amount = 0;
}

if ( $vars{status} eq 'CONFIRMED' ) {

    # Зачисляем сумму из payload (то что клиент ввёл, без комиссии Platega)
    my $credit_amount = ($original_amount && $original_amount > 0) ? $original_amount : $amount;

    $user->payment(
        user_id => $user_id,
        money => $credit_amount,
        pay_system_id => $ps_name,
        comment => \%vars,
        uniq_key => $uniq_key,
    );

    $user->commit;
    
    print_json( { status => 200, msg => "operation successful" } );

    exit 0;
}

print_json({ status => 400, msg => 'Error: bad request' });

exit 0;
