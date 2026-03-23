# Workspace Overview

This workspace contains 3 interconnected repositories:

| Repo | Path | Stack | Purpose |
|------|------|-------|---------|
| **shm-fork-from-orig** | `/Users/qwertyhq/code/shm-fork-from-orig` | Perl 5.14+, MySQL, Redis | SHM billing system (backend API, billing, spool, transports) |
| **wbap** | `/Users/qwertyhq/code/wbap` | React, TypeScript, Vite, Zustand, TailwindCSS | Telegram Mini App (frontend for VPN service management) |
| **remna-configs** | `/Users/qwertyhq/code/remna-configs` | Xray-core JSON, Bash | VPN proxy configs, Remnawave panel setup, bridge architectures |

## How They Connect

- **SHM** is the billing backend — manages users, services, payments, events, tasks
- **WBAP** is the Telegram Web App frontend — calls SHM API for user/service/payment operations
- **remna-configs** holds Xray-core configs for Remnawave VPN nodes that SHM provisions via events/transports
- SHM Telegram bot template interacts with Remnawave API for VPN subscription provisioning

Each repo has its own `CLAUDE.md` with detailed instructions. Read the relevant one when working in that repo.

---

## Plugins & MCP Servers

All MCP servers are provided via plugins (no separate `.mcp.json` needed).

| Plugin | Purpose | Key Skills / Tools |
|--------|---------|--------------------|
| **superpowers** | Development workflow: TDD, planning, debugging, code review | `brainstorming`, `writing-plans`, `executing-plans`, `test-driven-development`, `systematic-debugging`, `subagent-driven-development`, `dispatching-parallel-agents`, `requesting-code-review`, `receiving-code-review`, `verification-before-completion`, `finishing-a-development-branch`, `using-git-worktrees`, `writing-skills` |
| **context7** | Up-to-date library documentation lookup | `query-docs`, `resolve-library-id` |
| **serena** | Semantic code navigation and editing | `find_symbol`, `get_symbols_overview`, `find_referencing_symbols`, `replace_symbol_body`, `insert_after_symbol`, `search_for_pattern` |
| **playwright** | Browser automation and testing | `browser_navigate`, `browser_click`, `browser_snapshot`, `browser_fill_form`, `browser_take_screenshot` |
| **frontend-design** | Production-grade UI/UX design | `frontend-design` |
| **code-review** | Pull request code review | `code-review` |
| **figma** | Figma design-to-code workflows | `implement-design`, `code-connect-components`, `create-design-system-rules` |
| **claude-md-management** | CLAUDE.md audit and improvement | `revise-claude-md`, `claude-md-improver` |
| **claude-code-setup** | Automation recommendations | `claude-automation-recommender` |
| **typescript-lsp** | TypeScript language server | LSP integration |
| **security-guidance** | Security best practices | Security analysis |
| **github** | GitHub integration | Issues, PRs, actions |

### Workflow Guidelines

- Use **superpowers:brainstorming** before any new feature or design work
- Use **superpowers:systematic-debugging** before proposing fixes for bugs
- Use **superpowers:test-driven-development** before writing implementation code
- Use **superpowers:verification-before-completion** before claiming work is done
- Use **context7** to look up library docs instead of guessing APIs
- Use **serena** for navigating unfamiliar code symbolically

---

# SHM Project Instructions

## Project Overview

SHM (Service Hosting Manager) — open-source universal billing system with external actions support, written in **Perl 5.14+**. Manages users, services, payments, servers, domains, DNS, and task execution via multiple transports (HTTP, SSH, Mail, Telegram, Local).

- **Documentation**: https://docs.myshm.ru
- **License**: Apache 2.0
- **Deployment**: Docker + Kubernetes (Helm)
- **Tech Stack**: Perl 5.14+, MySQL 8+ (InnoDB, UTF-8mb4), Redis, CGI, Template Toolkit, Docker/K8s

---

## Repository Structure

```
app/
├── bin/                  # Executables: init.pl (DB migrations), spool.pl (task processing)
│   └── migrations/       # SQL migration files (e.g. 0.18.0.sql)
├── conf/shm.conf         # App configuration (DB credentials, logging)
├── lib/
│   ├── SHM.pm            # HTTP entry point: auth, session, DB connection
│   └── Core/
│       ├── Base.pm       # Abstract base class for all domain models
│       ├── Const.pm      # Constants: STATUS_*, EVENT_*, TASK_*, CLIENT_*
│       ├── Utils.pm      # Utilities: JSON, dates, crypto, IP validation
│       ├── Sql/Data.pm   # ORM layer: CRUD, query builder, SQL::Abstract
│       ├── System/
│       │   ├── ServiceManager.pm  # Service locator (dependency injection)
│       │   ├── Service.pm         # Base service registration
│       │   ├── Logger.pm          # Logging: TRACE..FATAL, colored output
│       │   ├── Cache.pm           # Redis-based caching
│       │   └── Object.pm          # Object helper
│       ├── Transport/
│       │   ├── Http.pm     # HTTP transport (LWP::UserAgent)
│       │   ├── Ssh.pm      # SSH transport (Net::OpenSSH)
│       │   ├── Mail.pm     # Email transport (SMTP)
│       │   ├── Telegram.pm # Telegram Bot API transport
│       │   └── Local.pm    # Local command execution
│       ├── Billing/
│       │   ├── Simpler.pm  # Simple period calculations
│       │   └── Honest.pm   # Honest billing (exact days)
│       ├── Services/
│       │   ├── Dns.pm      # DNS service transport handler
│       │   └── Web.pm      # Web service transport handler
│       ├── Cloud/
│       │   ├── Currency.pm
│       │   ├── Jobs.pm
│       │   └── Subscription.pm
│       ├── Domain/
│       │   └── Registrator/ # Domain registrar integrations
│       └── [Domain Models]  # App, User, UserService, Service, Server, etc.
├── public_html/
│   └── shm/
│       ├── v1.cgi          # REST API router (Router::Simple)
│       ├── healthcheck.cgi # Health probe
│       ├── admin/          # Admin CGI endpoints
│       ├── user/           # User-facing CGI endpoints
│       └── pay_systems/    # Payment gateway integrations
├── sql/shm/
│   └── shm_structure.sql  # Database schema (MySQL InnoDB, UTF-8mb4)
├── scripts/               # Utility scripts (admin access, password reset, etc.)
└── t/                     # Tests (Test::More, Test::Deep)
    ├── user/              # User unit tests
    ├── api/               # API integration tests (curl-based)
    ├── billing/           # Billing calculation tests
    ├── storage/           # Storage tests
    └── ...
build/                     # Build scripts
contributing/              # Dev docker-compose.yml
docs/                      # Helm chart documentation
helm/                      # Kubernetes Helm charts
nginx/                     # Nginx configuration
prod-files/                # Production overrides (mounted as Docker volumes)
templates/                 # Template Toolkit templates (notifications, etc.)
Dockerfile, Dockerfile-base, docker-compose.yml
```

---

## Architecture

### Inheritance Chain

```
Core::System::Service  (register/unregister in ServiceManager)
        ↑
Core::Sql::Data        (ORM: CRUD, query builder, SQL::Abstract, field validation)
        ↑
Core::Base             (Domain logic: AUTOLOAD, srv(), events, API safety, filtering)
        ↑
Domain Models          (User, Service, Server, App, Events, Pay, Spool, etc.)
```

### Service Locator Pattern

All inter-module communication goes through `ServiceManager`:

```perl
my $user = $self->srv('user');           # Returns Core::User instance
my $cfg  = $self->srv('config');         # Returns Core::Config instance
my $spool = $self->srv('spool');         # Returns Core::Spool instance
```

### API Request Flow

```
HTTP Request → v1.cgi
  → Router::Simple matches METHOD:PATH
  → Auth check (SHM.pm: validate_session, Basic Auth, or header)
  → Required args validation
  → get_service($controller) loads service module
  → Default method mapping:
      GET    → list_for_api()
      POST   → api_set()
      PUT    → api_add()
      DELETE → delete()
  → Or explicit method from route definition
  → JSON response
```

### Task Execution Flow

```
Event triggered → Core::Events::make()
  → Spool entry created (TASK_NEW)
  → spool.pl picks up task
  → Core::Spool::process_one()
    → Core::Task::make_task()
      → Resolves transport (Http/Ssh/Mail/Telegram/Local)
      → Parses template for payload
      → Transport::send() executes
    → finish_task() or retry_task() (exponential backoff: 3^n seconds)
```

---

## How to Create a New Module

### Step 1: Define the Database Table

Add to `app/sql/shm/shm_structure.sql` (and create a migration in `app/bin/migrations/`):

```sql
CREATE TABLE IF NOT EXISTS `my_entities` (
  `my_entity_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(10) unsigned NOT NULL DEFAULT 0,
  `name` varchar(255) NOT NULL,
  `settings` text,
  `created` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`my_entity_id`),
  KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### Step 2: Create the Perl Module

Create `app/lib/Core/MyEntity.pm`:

```perl
package Core::MyEntity;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { 'my_entities' }

sub structure {
    return {
        my_entity_id => {
            type => 'number',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
        },
        name => {
            type => 'text',
            required => 1,
        },
        settings => {
            type => 'json',
        },
        created => {
            type => 'now',
        },
    };
}

1;
```

### Step 3: Add API Routes

In `app/public_html/shm/v1.cgi`, add to the `$routes` hash:

```perl
'/user/my_entity' => {
    GET => { controller => 'MyEntity' },
    PUT => { controller => 'MyEntity', required => ['name'] },
},
'/user/my_entity/*' => {
    splat_to => 'my_entity_id',
    GET => { controller => 'MyEntity', method => 'list_for_api' },
    POST => { controller => 'MyEntity' },
    DELETE => { controller => 'MyEntity' },
},
'/admin/my_entity' => {
    GET => { controller => 'MyEntity' },
    PUT => { controller => 'MyEntity', required => ['name'] },
},
```

### Step 4: Add Tests

Create `app/t/my_entity/functions.t`:

```perl
use v5.14;
use Test::More;
use Test::Deep;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw(get_service);
use SHM;

SHM->new( skip_check_auth => 1 );

my $entity = get_service('MyEntity');

my $new = $entity->add( name => 'Test Entity', settings => { key => 'value' } );
ok( $new, 'Entity created' );

my $got = $entity->id( $new->{my_entity_id} );
is( $got->name, 'Test Entity', 'Name matches' );

$got->set( name => 'Updated Entity' );
is( $got->reload->name, 'Updated Entity', 'Name updated' );

$got->delete;

done_testing();
```

---

## Field Types in `structure()`

| Type     | Description                          | Example                        |
|----------|--------------------------------------|--------------------------------|
| `number` | Integer or decimal                   | `user_id`, `amount`            |
| `text`   | String/varchar                       | `name`, `login`                |
| `json`   | Auto-serialized JSON (hash/array)    | `settings`, `data`             |
| `now`    | Auto-filled timestamp on creation    | `created`, `date`              |
| `label`  | Display-only label, not stored       | Status labels                  |

### Field Flags

| Flag                    | Description                                            |
|-------------------------|--------------------------------------------------------|
| `required => 1`         | Must be provided on creation                           |
| `auto_fill => 1`        | Auto-filled from context (e.g. `user_id`)              |
| `hide_for_user => 1`    | Hidden from non-admin API responses                    |
| `allow_update_by_user`  | User can update via POST (otherwise admin-only)        |
| `default => value`      | Default value if not provided                          |

---

## Constants (Core::Const)

### Service Status
- `STATUS_INIT` (0), `STATUS_WAIT_FOR_PAY` (1), `STATUS_PROGRESS` (2)
- `STATUS_ACTIVE` (3), `STATUS_BLOCK` (4), `STATUS_REMOVED` (5), `STATUS_ERROR` (6)

### Event Types
- `EVENT_CREATE`, `EVENT_BLOCK`, `EVENT_REMOVE`
- `EVENT_PROLONGATE`, `EVENT_ACTIVATE`
- `EVENT_CHANGED_TARIFF`, `EVENT_NOT_ENOUGH_MONEY`

### Task Status
- `TASK_NEW`, `TASK_SUCCESS`, `TASK_FAIL`
- `TASK_DELAYED`, `TASK_STUCK`, `TASK_PAUSED`

---

## Code Style Rules

### 1. No Deep Nesting — Use Early Returns (Guard Clauses)
```perl
sub process {
    my ($self, %args) = @_;
    return unless $args{user_id};

    my $user = $self->srv('user')->id($args{user_id});
    return unless $user;
    return unless $user->status == STATUS_ACTIVE;

    # ... actual logic at the top level
}
```

### 2. Use `srv()` for Service Access
```perl
my $user = $self->srv('user');       # Good
# my $user = Core::User->new();     # Bad — direct instantiation
```

### 3. Modular Methods — Keep Methods Small and Focused

### 4. Use `structure()` for Schema Definition (drives validation, API safety, JSON serialization)

### 5. Use Events Instead of Direct Transport Calls
```perl
$self->make_event('event_name');     # Good — trigger event
# $self->srv('transport_http')->send($task);  # Bad — direct call
```

### 6. Return Early on Errors
```perl
return $self->srv('report')->add_error('Missing name') unless $args{name};
```

### 7. Naming Conventions
- **Modules**: `Core::PascalCase` (e.g., `Core::UserService`)
- **Methods**: `snake_case` (e.g., `list_for_api`)
- **Private methods**: prefix with `_` (e.g., `_get_base_discount`)
- **Tables**: `snake_case` plural (e.g., `users`, `user_services`)
- **Primary keys**: `table_singular_id` (e.g., `user_id`, `service_id`)
- **Constants**: `UPPER_SNAKE_CASE` (e.g., `STATUS_ACTIVE`)

---

## Key Methods Reference

### Core::Base (inherited by all domain models)

| Method              | Description                                           |
|---------------------|-------------------------------------------------------|
| `add(%args)`        | Create new record, returns hash with new ID           |
| `set(%args)`        | Update current record                                 |
| `get(%args)`        | Load record by fields                                 |
| `delete(%args)`     | Delete current or specified record                    |
| `id($id)`           | Load record by primary key, returns self              |
| `items(%filter)`    | Returns array of objects matching filter              |
| `list_for_api()`    | Safe listing for API (respects hide_for_user)         |
| `api_add(%args)`    | Safe add for API (filters args via structure)         |
| `api_set(%args)`    | Safe update for API                                   |
| `srv($name)`        | Get service instance via ServiceManager               |
| `make_event($name)` | Trigger domain event                                  |
| `reload()`          | Reload data from database                             |
| `res()`             | Get raw data hash                                     |
| `filter(%args)`     | Set query filter conditions                           |
| `limit($n)`         | Limit query results                                   |
| `sort($field)`      | Sort ascending / `rsort($field)` descending           |

### Filter Syntax (in API queries)

| Filter          | SQL Equivalent       |
|-----------------|----------------------|
| `gt:5`          | `> 5`                |
| `lt:10`         | `< 10`               |
| `ge:5` / `le:10`| `>= 5` / `<= 10`    |
| `between:5:10`  | `BETWEEN 5 AND 10`   |
| `like:pattern`  | `LIKE '%pattern%'`   |
| `not:value`     | `!= value`           |
| `in:1,2,3`      | `IN (1, 2, 3)`       |
| `null:` / `not_null:` | `IS NULL` / `IS NOT NULL` |

---

## Route Definition Reference

```perl
'/path/to/resource' => {
    splat_to => 'id_field',              # Maps wildcard (*) to param name
    GET => {
        controller => 'ModuleName',       # Maps to Core::ModuleName
        method => 'custom_method',        # Optional: override default
        skip_check_auth => 1,             # Optional: unauthenticated access
        required => ['field1', 'field2'], # Optional: required params
        args => { key => 'value' },       # Optional: pre-set arguments
    },
},
```

---

## Testing

- **Framework**: `Test::More`, `Test::Deep`
- **Test mode**: Set `$ENV{SHM_TEST} = 1`
- **Init context**: `SHM->new(skip_check_auth => 1)` for unit tests
- **Service access**: `get_service('ModuleName')` after SHM init
- **API tests**: Use `curl` for integration testing against running instance
- **Test location**: `app/t/<module_name>/` directory
- **Run tests**: `cd app && perl -I lib t/<module_name>/functions.t`

---

## Database

- **Engine**: MySQL 8+ (InnoDB, UTF-8mb4)
- **Migrations**: `app/bin/migrations/<version>.sql`
- **Init script**: `app/bin/init.pl` runs migrations automatically

---

## Docker & Deployment

- **`docker-compose.yml`**: Full stack (API, Core, MySQL, Redis, Admin UI, Client UI, WebDAV)
- **`helm/`**: Kubernetes Helm charts
- **CI/CD**: GitHub Actions (build, push, release, Telegram notifications)
- **Custom overrides**: `prod-files/` directory — mounted as Docker volumes to override core files (e.g. `prod-files/Const.pm`)

---

## Development Commands

```bash
# Start dev environment
docker-compose -f contributing/docker-compose.yml up -d

# Run unit tests
cd app && perl -I lib t/<module>/functions.t

# Run all tests
cd app && prove -I lib t/

# View logs
docker-compose logs -f api

# Database migrations
docker-compose exec core perl /app/bin/init.pl
```
