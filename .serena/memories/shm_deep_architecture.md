# SHM Deep Architecture Notes

## Inheritance Chain
Core::System::Service → Core::Sql::Data → Core::Base → Domain Models

## Core::Base Key Methods
- **AUTOLOAD**: Any field in structure() becomes callable method via $self->res->{$method}
- **srv($name)**: Service locator → get_service($name, user_id => $self->user_id)
- **make_event($name)**: Triggers Events → creates Spool entries
- **items()**: Returns array of new_obj instances from filtered query
- **api_safe_args()**: Strips fields NOT marked allow_update_by_user
- **filter(), limit(), sort(), rsort()**: Chainable query builder

## SHM.pm Auth Flow
1. HTTP_AUTHORIZATION header → Basic Auth (base64 decode → split : → ext_user_auth)
2. HTTP_LOGIN + HTTP_PASSWORD headers → ext_user_auth
3. Session ID from header/cookie → validate_session()
4. Admin check: /admin/* routes require gid == 1

## ServiceManager Resolution
- get_service('user') → 'Core::User' (lazy-load + cache)
- Scoped by user_id or _id parameter
- Protected: Logger, Cache, Sql::Data (never scoped)
- Aliases: logger, config, us, bill, wd

## Task Lifecycle
Event → Spool.add(TASK_NEW) → spool.pl picks up 
→ process_one() → lock US → resolve transport → send()
→ finish_task(SUCCESS) or retry_task(FAIL, exponential: 3^n, max 900s)
→ Periodic tasks: if event.period > 0, reschedule after period seconds

## ORM (Core::Sql::Data)
- AutoCommit=0, manual commit required
- query_for_filtering: gt:, lt:, ge:, le:, between:, like:, not:, in:, null:, not_null:
- JSON path queries: settings.telegram → JSON_EXTRACT(settings, '$.telegram')
- Aggregates: count(), sum($field), avg($field)

## Route Dispatcher (v1.cgi)
- Router::Simple matches METHOD:PATH
- Default: GET→list_for_api, POST→api_set, PUT→api_add, DELETE→delete
- splat_to: maps wildcard (*) to param name
- Required fields: validated before controller call

## Docker Services
- api: Nginx + Perl CGI (port 8080)
- core: Background workers (init.pl migrations)
- spool: Task processor (2 replicas prod, 1 dev)
- mysql, redis, admin, client

## prod-files/ Custom Overrides
- v1.cgi: Password auth + email routes reorganized
- User.pm: Custom events (payment → activate_services, registered, receipt)
- Passkey.pm: WebAuthn/FIDO2 credential management
- auth.cgi: Rate limiting (5 attempts/IP), 2FA, admin flag validation
- Telegram.pm: Identical upstream

## API Routes Summary
- Public: ~57 endpoints (auth, 2FA, profile, services, billing, templates, promo, telegram)
- Admin: ~40+ endpoints (service/user/server CRUD, spool, events, config, analytics)
