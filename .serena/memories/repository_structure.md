# Repository Structure

## Main Directories
```
app/                          # Core application
  bin/                        # Executables
    init.pl                   # DB migrations runner
    spool.pl                  # Task queue processor
    shm-server.pl             # HTTP server
    migrations/               # SQL migration files (versioned)
  conf/shm.conf               # App config (DB creds, logging)
  lib/
    SHM.pm                    # HTTP entry point (auth, session, DB connect)
    Core/
      Base.pm                 # Base class for all domain models (AUTOLOAD, srv, events)
      Const.pm                # Constants: STATUS_*, EVENT_*, TASK_*
      Utils.pm                # Utilities: JSON, dates, crypto, IP validation
      Sql/Data.pm             # ORM layer: CRUD, SQL::Abstract, query builder
      System/
        ServiceManager.pm     # Service locator (dependency injection)
        Service.pm            # Base service registration
        Logger.pm             # Logging: TRACE..FATAL
        Cache.pm              # Redis-based caching
      Transport/              # Task execution transports
        Http.pm               # HTTP (LWP::UserAgent)
        Ssh.pm                # SSH (Net::OpenSSH)
        Mail.pm               # Email (SMTP)
        Telegram.pm           # Telegram Bot API
        Local.pm              # Local command execution
      Billing/
        Simpler.pm            # Simple period billing
        Honest.pm             # Exact days billing
      # Domain Models:
      User.pm, Service.pm, UserService.pm, USObject.pm
      Server.pm, ServerGroups.pm, Events.pm, Spool.pm
      Task.pm, Pay.pm, Template.pm, Config.pm
      App.pm, Domain.pm, Dns.pm, Storage.pm, S3.pm
      Invoice.pm, Analytics.pm, Jobs.pm, Bonus.pm
      Passkey.pm, OTP.pm, Identities.pm, Profile.pm
      Sessions.pm, Console.pm, Swagger.pm, Report.pm
  public_html/shm/
    v1.cgi                    # REST API router (~1743 lines)
    healthcheck.cgi           # Health probe
  sql/shm/shm_structure.sql   # Full DB schema
  t/                          # Tests
    unit/                     # Unit tests by module
    api/                      # API integration tests (curl-based)
    integration/              # Integration tests

prod-files/                   # Production overrides (custom auth, passkey, telegram, v1.cgi)
tempaltes/                    # Project-specific SHM templates (typo in dir name is intentional)
contributing/docker-compose.yml  # Dev docker-compose
docker-compose.yml            # Production docker-compose
helm/                         # Kubernetes Helm charts
```

## Docker Services (docker-compose.yml)
- **api** — Nginx + Perl CGI (SHM API)
- **core** — Perl application (migrations, workers)
- **spool** — Task queue processors (2 replicas)
- **admin** — Admin UI (danuk/shm-admin)
- **client** — Client UI (danuk/shm-client-2)
- **mysql** — MySQL LTS
- **redis** — Redis cache

## prod-files/ — Custom Overrides
These files are project-specific modifications to upstream SHM:
- `v1.cgi` — custom API routes
- `auth.cgi` — custom authentication with rate limiting
- `User.pm` — extended User model
- `Passkey.pm` — WebAuthn passkey support
- `Telegram.pm` — Telegram bot integration
- `security.html/js` — security UI pages
