# Переводы названий услуг / Service Name Translations

## Где хранится перевод

Английское название услуги хранится в поле `config` (JSON) каждой услуги, в ключе **`name_en`**.

## API Response

```
GET /shm/v1/user/service
GET /shm/v1/admin/service
```

Пример ответа:

```json
{
  "service_id": 12,
  "name": "VPN 1 Месяц",
  "config": {
    "name_en": "VPN 1 Month"
  },
  "cost": 150,
  "category": "vpn-m-1"
}
```

## Использование в Web App

```js
function getServiceName(service, lang) {
  if (lang === 'en' && service.config?.name_en) {
    return service.config.name_en;
  }
  return service.name; // русское название из БД
}
```

## Текущие значения

| service_id | name (RU)                        | config.name_en            |
|------------|----------------------------------|---------------------------|
| 12         | VPN 1 Месяц                     | VPN 1 Month               |
| 15         | VPN 2 Месяца                    | VPN 2 Months              |
| 16         | VPN 3 Месяца                    | VPN 3 Months              |
| 17         | VPN 6 Месяцев                   | VPN 6 Months              |
| 18         | VPN 12 Месяцев                  | VPN 12 Months             |
| 21         | 🎁 Бесплатный период - 7 дней 🎁 | Free Trial - 7 Days       |
| 28         | Семейный 1 Месяц                | Family 1 Month            |
| 29         | Семейный 12 Месяцев             | Family 12 Months          |
| 30         | Сброс трафика                   | Traffic Reset             |

## Добавление перевода для новой услуги

```bash
curl -X POST -u login:pass \
  https://admin.ev-agency.io/shm/v1/admin/service \
  -d 'service_id=NEW_ID' \
  -d 'config={"name_en": "English Name"}'
```

> **Важно:** если у услуги уже есть другие поля в `config` (например `no_money_back`, `order_only_once`), их нужно включить в JSON, иначе они будут перезаписаны.
