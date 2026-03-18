# SHM Project Overview

## Purpose
SHM (Service Hosting Manager) — open-source universal billing system with external actions support.
Written in Perl 5.14+. Manages users, services, payments, servers, domains, DNS, and task execution via multiple transports (HTTP, SSH, Mail, Telegram, Local).

- **Author**: DaNuk (DNk), mail@danuk.ru
- **License**: Apache 2.0
- **Upstream**: https://github.com/danuk/shm.git
- **Fork**: https://github.com/qwertyhq/shm-fork-from-orig

## Tech Stack
- **Language**: Perl 5.14+ (v5.14 minimum, some modules use v5.32)
- **Database**: MySQL 8+ (InnoDB, UTF-8mb4, DBI + SQL::Abstract ORM)
- **Cache**: Redis
- **Web**: CGI + Router::Simple, Nginx as reverse proxy
- **Templates**: Template Toolkit (Template.pm)
- **Testing**: Test::More, Test::Deep
- **Deploying**: Docker + Kubernetes (Helm charts)
- **CI/CD**: GitHub Actions

## Key Architectural Patterns
1. **Service Locator** (Core::System::ServiceManager) — all inter-module communication via `get_service('name')` or `$self->srv('name')`
2. **ORM via SQL::Abstract** (Core::Sql::Data) — CRUD, query builder, field validation from `structure()`
3. **Inheritance chain**: Core::System::Service → Core::Sql::Data → Core::Base → Domain Models
4. **AUTOLOAD** in Base.pm — auto-generates field accessors from DB data
5. **Events + Spool** — event-driven task execution with transports

## Architecture Flow
```
HTTP → v1.cgi (Router::Simple) → Auth (SHM.pm) → Controller (Core::*) → JSON response
Events → Spool → spool.pl → Core::Task::make_task → Transport::send()
```

## Default API Method Mapping
- GET → list_for_api()
- POST → api_set()
- PUT → api_add()
- DELETE → delete()

## Custom Overrides (Docker Volume Mounts)
- `prod-files/Const.pm` → `/app/lib/Core/Const.pm` — GROUP_ID_MAIL=13 (Brevo)
- `prod-files/v1.cgi`, `prod-files/User.pm`, `prod-files/Passkey.pm`, `prod-files/Telegram.pm` — custom API extensions
- Email delivery via Brevo HTTP API (server_id=20, gid=13) — see memory `brevo_email_integration`
