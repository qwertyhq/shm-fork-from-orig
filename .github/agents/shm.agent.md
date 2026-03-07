# SHM Project — Copilot Agent Instructions

## Project Overview

SHM (Service Hosting Manager) is an open-source universal billing system with external actions support, written in **Perl 5.14+**. It manages users, services, payments, servers, domains, DNS, and task execution via multiple transports (HTTP, SSH, Mail, Telegram, Local).

- **Documentation**: https://docs.myshm.ru
- **License**: Apache 2.0
- **Deployment**: Docker + Kubernetes (Helm)

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
# Access any service from any module:
my $user = $self->srv('user');           # Returns Core::User instance
my $cfg  = $self->srv('config');         # Returns Core::Config instance
my $spool = $self->srv('spool');         # Returns Core::Spool instance

# Internal implementation:
Core::System::ServiceManager::get_service('user')
# → Resolves 'user' to 'Core::User'
# → Lazy-loads the module
# → Returns cached instance (scoped by user_id if applicable)
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

# Business logic methods go here (keep them flat, no deep nesting)

1;
```

### Step 3: Add API Routes

In `app/public_html/shm/v1.cgi`, add to the `$routes` hash:

```perl
# User-facing routes
'/user/my_entity' => {
    GET => {
        controller => 'MyEntity',
    },
    PUT => {
        controller => 'MyEntity',
        required => ['name'],
    },
},
'/user/my_entity/*' => {
    splat_to => 'my_entity_id',
    GET => {
        controller => 'MyEntity',
        method => 'list_for_api',
    },
    POST => {
        controller => 'MyEntity',
    },
    DELETE => {
        controller => 'MyEntity',
    },
},
# Admin routes
'/admin/my_entity' => {
    GET => {
        controller => 'MyEntity',
    },
    PUT => {
        controller => 'MyEntity',
        required => ['name'],
    },
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

# Test creation
my $new = $entity->add(
    name => 'Test Entity',
    settings => { key => 'value' },
);
ok( $new, 'Entity created' );

# Test retrieval
my $got = $entity->id( $new->{my_entity_id} );
is( $got->name, 'Test Entity', 'Name matches' );

# Test update
$got->set( name => 'Updated Entity' );
is( $got->reload->name, 'Updated Entity', 'Name updated' );

# Test deletion
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
- `STATUS_INIT` (0) — Initialized
- `STATUS_WAIT_FOR_PAY` (1) — Awaiting payment
- `STATUS_PROGRESS` (2) — In progress
- `STATUS_ACTIVE` (3) — Active
- `STATUS_BLOCK` (4) — Blocked
- `STATUS_REMOVED` (5) — Removed
- `STATUS_ERROR` (6) — Error

### Event Types
- `EVENT_CREATE`, `EVENT_BLOCK`, `EVENT_REMOVE`
- `EVENT_PROLONGATE`, `EVENT_ACTIVATE`
- `EVENT_CHANGED_TARIFF`, `EVENT_NOT_ENOUGH_MONEY`

### Task Status
- `TASK_NEW`, `TASK_SUCCESS`, `TASK_FAIL`
- `TASK_DELAYED`, `TASK_STUCK`, `TASK_PAUSED`

---

## Code Style Rules

### 1. No Deep Nesting ("Christmas Trees")

**Bad** — deeply nested conditionals:
```perl
sub process {
    my ($self, %args) = @_;
    if ($args{user_id}) {
        my $user = $self->srv('user')->id($args{user_id});
        if ($user) {
            if ($user->status == STATUS_ACTIVE) {
                my $service = $self->srv('service')->id($args{service_id});
                if ($service) {
                    if ($service->cost > 0) {
                        # ... actual logic buried deep
                    }
                }
            }
        }
    }
}
```

**Good** — early returns (guard clauses):
```perl
sub process {
    my ($self, %args) = @_;

    return unless $args{user_id};

    my $user = $self->srv('user')->id($args{user_id});
    return unless $user;
    return unless $user->status == STATUS_ACTIVE;

    my $service = $self->srv('service')->id($args{service_id});
    return unless $service;
    return unless $service->cost > 0;

    # ... actual logic at the top level
}
```

### 2. Use `srv()` for Service Access

```perl
# Good: use the service locator
my $user = $self->srv('user');
my $config = $self->srv('config');

# Bad: direct instantiation
my $user = Core::User->new();
```

### 3. Modular Methods

Keep methods small and focused. Each method does one thing:

```perl
# Good: separate concerns
sub calculate_discount {
    my ($self, %args) = @_;
    my $base_discount = $self->_get_base_discount(%args);
    my $promo_discount = $self->_get_promo_discount(%args);
    return $base_discount + $promo_discount;
}

sub _get_base_discount { ... }
sub _get_promo_discount { ... }
```

### 4. Use `structure()` for Schema Definition

Always define the complete schema in `structure()`. This drives:
- Field validation on add/set
- API safety (what fields users can see/edit)
- JSON auto-serialization
- Required field checks

### 5. Use Events Instead of Direct Calls

```perl
# Good: trigger event, let the system handle it
$self->make_event('event_name');

# Bad: calling execution logic directly
$self->srv('transport_http')->send($task);
```

### 6. Return Early on Errors

```perl
# Good: return report on error
sub my_method {
    my ($self, %args) = @_;

    return $self->srv('report')->add_error('Missing name')
        unless $args{name};

    # ... proceed with logic
}
```

### 7. Naming Conventions

- **Modules**: `Core::PascalCase` (e.g., `Core::UserService`, `Core::ServerGroups`)
- **Methods**: `snake_case` (e.g., `list_for_api`, `api_safe_args`)
- **Private methods**: prefix with `_` (e.g., `_get_base_discount`)
- **Tables**: `snake_case` plural (e.g., `users`, `user_services`, `pays_history`)
- **Primary keys**: `table_singular_id` (e.g., `user_id`, `service_id`)
- **Constants**: `UPPER_SNAKE_CASE` (e.g., `STATUS_ACTIVE`, `EVENT_CREATE`)

---

## Key Methods Reference

### Core::Base (inherited by all domain models)

| Method              | Description                                           |
|---------------------|-------------------------------------------------------|
| `add(%args)`        | Create new record, returns hash with new ID           |
| `set(%args)`        | Update current record                                 |
| `get(%args)`        | Load record by fields (usually primary key)           |
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
| `sort($field)`      | Sort ascending by field                               |
| `rsort($field)`     | Sort descending by field                              |

### Core::Sql::Data (ORM layer)

| Method                       | Description                                     |
|------------------------------|-------------------------------------------------|
| `query_select(%args)`        | Build and execute SELECT query                  |
| `convert_sql_structure_data` | Convert data according to structure types        |
| `query_for_filtering`        | Build WHERE clause from filter params            |
| `sum($field)` / `avg()` / `count()` | Aggregate functions                      |
| `dbh()`                      | Get database handle                             |
| `commit()` / `rollback()`   | Transaction control                              |

### Filter Syntax (in API queries)

| Filter          | SQL Equivalent       |
|-----------------|----------------------|
| `gt:5`          | `> 5`                |
| `lt:10`         | `< 10`               |
| `ge:5`          | `>= 5`               |
| `le:10`         | `<= 10`              |
| `between:5:10`  | `BETWEEN 5 AND 10`   |
| `like:pattern`  | `LIKE '%pattern%'`   |
| `not:value`     | `!= value`           |
| `in:1,2,3`      | `IN (1, 2, 3)`       |
| `null:`         | `IS NULL`            |
| `not_null:`     | `IS NOT NULL`        |

---

## Route Definition Reference

```perl
'/path/to/resource' => {
    splat_to => 'id_field',              # Maps wildcard (*) to this param name
    GET => {
        controller => 'ModuleName',       # Maps to Core::ModuleName
        method => 'custom_method',        # Optional: override default list_for_api
        skip_check_auth => 1,             # Optional: allow unauthenticated access
        required => ['field1', 'field2'], # Optional: required request params
        args => { key => 'value' },       # Optional: pre-set arguments
    },
    PUT => {
        controller => 'ModuleName',
        required => ['name'],
    },
    POST => {
        controller => 'ModuleName',
    },
    DELETE => {
        controller => 'ModuleName',
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

---

## Database

- **Engine**: MySQL 8+ (InnoDB, UTF-8mb4)
- **Migrations**: `app/bin/migrations/<version>.sql`
- **Init script**: `app/bin/init.pl` runs migrations automatically
- **Connection**: Configured via `app/conf/shm.conf` or environment variables

---

## Docker & Deployment

- **`Dockerfile`**: API service (Perl + nginx)
- **`Dockerfile-base`**: Base image with Perl dependencies
- **`docker-compose.yml`**: Full stack (API, Core, MySQL, Redis, Admin UI, Client UI, WebDAV)
- **`helm/`**: Kubernetes Helm charts
- **CI/CD**: GitHub Actions (build, push, release, Telegram notifications)
