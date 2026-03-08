# Code Style and Conventions

## Naming Conventions
- **Modules**: Core::PascalCase (e.g. Core::UserService, Core::ServerGroups)
- **Methods**: snake_case (e.g. list_for_api, api_safe_args)
- **Private methods**: prefix with _ (e.g. _get_base_discount)
- **Tables**: snake_case plural (e.g. users, user_services, pays_history)
- **Primary keys**: table_singular_id (e.g. user_id, service_id)
- **Constants**: UPPER_SNAKE_CASE (e.g. STATUS_ACTIVE, EVENT_CREATE)

## Module Structure Pattern
Every domain model follows this pattern:
```perl
package Core::MyModule;
use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;

sub table { 'table_name' }

sub structure {
    return {
        field_id => { type => 'number', key => 1 },
        user_id  => { type => 'number', auto_fill => 1 },
        name     => { type => 'text', required => 1 },
        settings => { type => 'json', value => {} },
        created  => { type => 'now' },
    };
}
1;
```

## Field Types in structure()
- `number` — integer or decimal
- `text` — string/varchar
- `json` — auto-serialized JSON
- `now` — auto-filled timestamp on creation
- `date` — date/datetime
- `label` — display-only, not stored

## Field Flags
- `required => 1` — must be provided on creation
- `auto_fill => 1` — auto-filled from context (e.g. user_id)
- `hide_for_user => 1` — hidden from non-admin API
- `allow_update_by_user` — user can update via POST
- `default => value` — default value
- `key => 1` — primary key field
- `readOnly => 1` — cannot be modified via API
- `enum => [...]` — allowed values

## Code Style Rules
1. **No deep nesting** — use early returns (guard clauses)
2. **Use srv() for service access** — never directly instantiate Core:: modules
3. **Modular methods** — each method does one thing
4. **Events over direct calls** — trigger events, let spool handle execution
5. **Return early on errors** — `return $self->srv('report')->add_error('...')`

## Constants (Core::Const)
- Status: STATUS_INIT, STATUS_WAIT_FOR_PAY, STATUS_PROGRESS, STATUS_ACTIVE, STATUS_BLOCK, STATUS_REMOVED, STATUS_ERROR
  (values are strings: 'INIT', 'NOT PAID', 'PROGRESS', 'ACTIVE', 'BLOCK', 'REMOVED', 'ERROR')
- Events: EVENT_CREATE, EVENT_BLOCK, EVENT_REMOVE, EVENT_PROLONGATE, EVENT_ACTIVATE, EVENT_NOT_ENOUGH_MONEY, EVENT_CHANGED, EVENT_CHANGED_TARIFF
- Tasks: TASK_NEW, TASK_SUCCESS, TASK_FAIL, TASK_DELAYED, TASK_STUCK, TASK_PAUSED

## Route Definition Pattern (v1.cgi)
```perl
'/path/to/resource' => {
    splat_to => 'id_field',
    GET => {
        controller => 'ModuleName',
        method => 'custom_method',       # optional
        skip_check_auth => 1,            # optional
        required => ['field1'],          # optional
        args => { key => 'value' },      # optional
        swagger => { ... },              # optional Swagger docs
    },
},
```
