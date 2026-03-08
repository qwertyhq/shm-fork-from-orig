# Suggested Commands

## System Info
- macOS (Darwin) — use `brew` for package management
- Git remotes: origin (qwertyhq fork), upstream (danuk/shm)

## Development Environment
```bash
# Start dev environment
cd contributing && docker-compose up -d

# Start production stack
docker-compose up -d

# View logs
docker-compose logs -f core
docker-compose logs -f spool
```

## Docker
```bash
# Build base image
./build-base.sh

# Build main image
./build.sh

# Environment variables in .env file
```

## Database
```bash
# Migrations run automatically via app/bin/init.pl
# Schema: app/sql/shm/shm_structure.sql
# Migration files: app/bin/migrations/*.sql
```

## Testing
```bash
# Run unit tests (inside Docker container)
cd app && prove -r t/unit/

# Run API tests
cd app && prove -r t/api/

# Run specific test
prove -v t/unit/billing/simpler.t

# Test setup: $ENV{SHM_TEST} = 1, SHM->new(skip_check_auth => 1)
```

## Git
```bash
# Fetch upstream changes
git fetch upstream
git merge upstream/master

# Push to fork
git push origin master
```

## Utility Scripts
```bash
# Get admin access
perl app/scripts/get_admin_access.cgi

# Reset admin password
perl app/scripts/reset_admin_pass.cgi

# Enable password auth
perl app/scripts/enable_password_auth.cgi
```

## Perl
```bash
# Install dependencies (inside Docker)
cpanm Module::Name

# Note: Perl::LanguageServer NOT installed — Serena symbolic tools unavailable.
# Use grep_search, read_file, semantic_search instead.
```
