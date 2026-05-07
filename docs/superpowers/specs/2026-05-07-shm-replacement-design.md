# SHM Replacement — Design Spec

- **Date:** 2026-05-07
- **Author:** qwertyhq + Claude (brainstorming session)
- **Status:** Draft, awaiting user review
- **Successor of:** SHM (Perl billing system, fork at `/Users/qwertyhq/code/shm-fork-from-orig`)

---

## 1. Problem Statement & Goals

### 1.1 What we're replacing

SHM is an open-source Perl 5.14+ billing system that currently powers a VPN-service product with ~8 200 active users (`users.user_id` AUTO_INCREMENT = 8 717), ~9 400 user-services, ~3 270 historical payments, ~12 332 historical withdrawals. It exposes a CGI REST API consumed by the WBAP Telegram Mini App (React/TS frontend). The backend handles users, subscriptions, payments, promo codes, bonuses, server-fleet provisioning (Remnawave VPN nodes via HTTP transport), and notifications (Telegram bot via Telegram transport). Data lives in MySQL 8 + Redis.

### 1.2 Why replace it

Owner reports four converging pains:

1. Perl is hard to extend; switching languages between the React frontend and Perl backend is friction.
2. SHM's admin UI/UX is dated and rough.
3. Billing logic (periods, discounts) is opaque and mistrusted.
4. SHM is a third-party fork — keeping up with upstream is painful, and the owner wants full ownership of a smaller, focused codebase.

### 1.3 Goals

- Replace SHM end-to-end with a TypeScript backend the owner controls.
- Zero-downtime cutover. No lost payments, no lost provisioning events.
- Significantly improved security posture vs. current state (see threat findings in §3).
- Postgres as the long-term database (a Postgres instance already exists in the owner's infra for unrelated business data; the new backend gets its **own** PG instance).
- Same WBAP frontend, with a swap of `baseURL` to the new API once routes are ported.

### 1.4 Non-goals

- Changing the WBAP frontend stack (it stays React/Vite/Zustand).
- Re-architecting the Remnawave fleet (it stays as is; the new backend talks to it the same way SHM does).
- Building a generic "billing platform". This is a focused replacement for the owner's VPN-service use case.
- Real-time event-bus infrastructure (Kafka/NATS) — out of scope; BullMQ on Redis is sufficient at current scale.

### 1.5 Constraints

- 10 k+ live users (owner's stated estimate; dump shows ~8.2 k active accounts) with live money flowing through.
- Cutover downtime budget: **0 minutes** (CDC + reverse-proxy switch).
- Timeline: not bounded. Quality > speed.
- Security is the explicit top priority.

---

## 2. Current System: Findings From the SHM DB Dump

Source: `shm-backup/shm_shm_20260507-0600.sql` (313 MB).

### 2.1 Tables in actual use (will be migrated)

| Table             | Rows (≈) | Role |
|-------------------|----------|------|
| `users`           | 8 200    | accounts |
| `user_services`   | 9 400    | active subscriptions |
| `services`        | 30       | tariff catalogue |
| `servers`         | 11       | Remnawave nodes |
| `servers_groups`  | 8        | fleet groupings |
| `events`          | 29       | event definitions (CREATE/BLOCK/ACTIVATE/PROLONG…) |
| `spool`           | 6        | live task queue (cycles fast: AI = 352 462) |
| `spool_history`   | 83 248   | task history |
| `pays_history`    | 3 270    | money in |
| `withdraw_history`| 12 332   | money out |
| `bonus_history`   | 1 631    | bonus credits/debits |
| `promo_codes`     | 351      | promo codes |
| `sessions`        | 803      | active sessions |
| `identities`      | 9        | SSH/API keys for transports |
| `templates`       | 40       | Template Toolkit notification templates |
| `config`          | 12       | global key-value config |
| `storage`         | 3 968    | Remnawave HWID-tracking KV (under `user_id=1` admin scope) |

### 2.2 Tables that are dead/marginal for the VPN use case (will NOT be migrated)

`acts`, `acts_data`, `apps`, `profiles`, `domains`, `dns_services`, `zones`, `domains_services`, `console` (40 k rows of stale spool logs), `spool_history` older than 30 days.

The full SHM dump remains in cold storage (S3-compatible) for retrospective audit, but is not loaded into the new system.

### 2.3 Security findings in current data

These are documented to set the bar for the new system:

- **Passwords stored as SHA-1 hex without salt** (`users.password` is `char(64)`, contents are 40-char hex, e.g. `6a1fce257feb6f3451a28994c5f251e2768802ce`). Vulnerable to rainbow tables and offline brute force.
- **TOTP secrets stored in plaintext** inside `users.settings.otp.secret`. Backup codes also plaintext in `users.settings.otp.backup_codes`.
- **Password-reset tokens** live in `users.settings.reset_password_verify_token` with no separate TTL/invalidation mechanism.
- **Telegram identity data** (chat_id, username, language, premium status, bot membership) is dumped into `users.settings.telegram` — mixing identity and profile.
- **Login fragmentation:** `users.login` = email, `users.login2` = `@<telegram_id>` (literally with `@` prefix). Two separate string identifiers per user.

### 2.4 Currency & timezone

- All money columns are `decimal(10,2)`.
- `datetime` columns have no TZ. SHM sets MySQL session TZ from the `TZ` env var (`app/lib/Core/Sql/Data.pm:94`: `SET time_zone = '$ENV{TZ}'`). Empirical evidence from `pays_history` row 1 (`date = 2023-01-29 13:15:21`, `comment.datetime = 2023-01-29T10:15:20Z` from YooMoney) confirms the offset is **UTC+3 / Europe/Moscow**.

---

## 3. Target Architecture

### 3.1 Service topology

Four runtime components, no more:

```
                         ┌──────────────────────┐
   Telegram WebApp ───►  │   wbap (frontend)    │  unchanged
                         └──────────┬───────────┘
                                    │ HTTPS, opaque session cookie
                          ┌─────────▼─────────┐
                          │     wbap-api      │   Node 20 LTS + Hono
                          │  (auth, billing,  │   ────────────►
                          │   services CRUD,  │   PG-billing
                          │   wallet module,  │
                          │   admin RBAC)     │
                          └────────┬──────────┘
                                   │ enqueues jobs into BullMQ on Redis
                                   ▼
                          ┌────────────────────┐
                          │  spool-worker      │   transports: Telegram,
                          │  (BullMQ consumer, │   HTTP (Remnawave), Mail
                          │   retries+backoff) │
                          └────────────────────┘

  During migration only (removed at Phase 9):
  ┌──────────────┐    Debezium CDC (1-way)     ┌─────────────┐
  │  MySQL-SHM   │ ───────────────────────────►│ PG-billing  │
  │  (prod)      │                             │             │
  └──────────────┘                             └─────────────┘
                  ▲   migration-bridge:        ▲
                  │   reads MySQL binlog,      │
                  │   applies to PG via        │
                  │   schema mapping           │
                  └────────────────────────────┘
```

The wallet **lives inside `wbap-api`** as a separate module with its own DB role and module-isolation rules (see §3.4). It is not a separate service.

### 3.2 Data stores

| Store | Purpose | Notes |
|-------|---------|-------|
| `PG-billing` | New primary database | New PG 16 instance, separate from owner's existing PG. Schemas: `auth`, `core`, `billing`, `spool`, `wallet`, `audit`, `migration`. |
| `Redis` | Sessions, cache, rate-limit, BullMQ queue | Single-instance fine; persisted with AOF + RDB. |
| `MySQL-SHM` | Source of truth during migration only | Retired at Phase 8. |
| `S3 / MinIO` | Cold archive for SHM dump, audit-log archive, future invoice PDFs | Encrypted at rest, lifecycle to glacier-equivalent after 1 y. |

### 3.3 Stack

| Layer | Choice | Why |
|-------|--------|-----|
| Runtime | **Node.js 20 LTS** | "Boring tech for money." Battle-tested in financial production for years. |
| HTTP framework | **Hono** | ~5 kLOC, explicit middleware, auditable. No magic DI like Nest. |
| ORM / SQL | **Drizzle** | Type-safe SQL by construction, no runtime query generation, prevents SQL injection at the type level. |
| Validation | **Zod** | Schema validation at every API boundary. Nothing untyped reaches a handler. |
| DB | **Postgres 16** | RLS, jsonb, generated columns, robust replication. |
| Auth | **Telegram initData (HMAC) + email/password (Argon2id) + WebAuthn (admins) + optional TOTP/backup codes** | See §3.5. |
| Sessions | **Opaque session IDs in Redis** | Easier to revoke than JWT, no key-rotation pain. |
| Queue | **BullMQ on Redis** | Battle-tested, supports rate-limit, retries with backoff, scheduled jobs, deduplication. |
| Hashing | **Argon2id** (m=64 MiB, t=3, p=4 — RFC 9106) | Modern KDF; Bcrypt is acceptable but Argon2id is the current best practice. |
| Encryption | **AES-256-GCM** with envelope (per-tenant DEK, master KEK in vault) | For TOTP secrets and other reversible secrets. |
| Secrets | **SOPS + age** at rest, **systemd-creds** at runtime | No secrets in repo, no secrets in env files committed anywhere. |
| Containers | **Distroless, non-root, read-only FS** | Minimal attack surface. |
| Observability | **pino → loki, prom-client → prometheus, OTel → tempo, all surfaced via Grafana, Sentry self-hosted** | Standard, all open-source. |
| CI security gates | **Renovate, Semgrep, npm audit, Trivy, Cosign + SBOM** | Block high-severity findings at PR. |

### 3.4 Wallet — module inside wbap-api

The owner explicitly chose a single-process layout (wallet inside wbap-api) for simplicity, accepting that we lose process-level isolation. The mitigations that bring isolation back:

1. **Separate Postgres role.** Schema `wallet` is owned by a role `wallet_writer` with `INSERT/SELECT` on `wallet.ledger_entries` and `wallet.transactions`, `UPDATE` on `wallet.accounts.balance_cached` only via trigger, and `NO DELETE`. The default `app_user` role used by the rest of wbap-api has **zero grants** on `wallet.*`. Wallet code uses a separate connection pool with `wallet_writer`.
2. **Separate TS module** at `src/wallet/` with a tiny public surface: `reserve`, `commit`, `refund`, `transfer`. ESLint rule forbids importing anything from `src/wallet/internal/*` outside of `src/wallet/`.
3. **Idempotency by construction.** Every wallet operation requires an `idempotency_key`; the `ledger_entries` table has `UNIQUE (idempotency_key)`, so retries can never double-charge.
4. **Double-entry by DB invariant.** A trigger enforces that for every `transaction_id`, `SUM(amount) WHERE direction='D' = SUM(amount) WHERE direction='C'`. Violations reject the INSERT.
5. **Append-only audit log** for every wallet call — actor, idempotency key, before/after, request id, ip, user agent.
6. **100% coverage + property-based tests** on `src/wallet/` enforced as a CI gate. Mutation testing (Stryker) with ≥90% threshold.

### 3.5 Authentication (full spec)

#### 3.5.1 Identity model

```
auth.identities (
  identity_id   uuid7   PRIMARY KEY,
  user_id       uuid7   NOT NULL REFERENCES core.users,
  kind          text    NOT NULL CHECK (kind IN ('telegram','email','password','webauthn','totp')),
  external_id   text,                 -- tg: chat_id; email: address; webauthn: cred_id; password/totp: NULL
  metadata      jsonb,                -- tg: username/lang/premium; email: verified_at; webauthn: aaguid
  is_primary    boolean DEFAULT false,
  created_at    timestamptz DEFAULT now(),
  last_used_at  timestamptz,
  UNIQUE (kind, external_id)
)
```

A user can have multiple identities; SHM's `login`/`login2` becomes two rows (`kind='email'` + `kind='telegram'`).

#### 3.5.2 Login flows

**A. Telegram WebApp (primary path for Mini App users):**

```
POST /auth/telegram { initData }
  → verify HMAC against bot token (per Telegram WebApp spec)
  → reject if auth_date older than 5 minutes
  → identity = SELECT WHERE kind='telegram' AND external_id = chat_id
  → if missing: create user + identity, emit event 'user.registered'
  → issue session: 32-byte random opaque ID, stored in Redis
                    cookie __Host-session, HttpOnly, Secure, SameSite=Strict, Max-Age=7d, rotated every 24h on use
```

**B. Email/password (or Telegram-username/password, for users who log in outside Mini App):**

```
POST /auth/login { identity: <email or @tg_username>, password, mfa_code? }
  → constant-time across user-existence to prevent enumeration
  → resolve identity → user_id
  → look up auth.password_credentials WHERE user_id = $1
  → if hash_legacy_sha1 set and hash NULL: SHA-1 compare; on success force a password reset to upgrade to Argon2id
  → else: argon2id verify
  → on failure: increment failed_attempts; lock at 5 fails for 5 min, escalate to 15 min; admin-unlock-only after 20 fails/24h
  → if user has TOTP enabled and mfa_code missing → 200 + { mfa_required: true, mfa_token } (5-min token in Redis, not a cookie)
  → on full success: issue session as above, audit log entry
```

**C. Admin WebAuthn:**

Admin login path is a separate route (e.g., `/admin/auth/webauthn`) requiring a registered WebAuthn credential. RBAC checked in middleware via `auth.admin_roles`. New admins are bootstrapped via single-use invite tokens (TTL 1 h) issued by an existing admin.

#### 3.5.3 Password storage

```
auth.password_credentials (
  user_id           uuid7 PRIMARY KEY REFERENCES core.users,
  hash              text,                 -- '$argon2id$...'
  hash_legacy_sha1  text,                 -- transient, dropped at Phase 9 +90d
  hash_legacy_at    timestamptz,
  must_reset        boolean DEFAULT false,
  failed_attempts   int DEFAULT 0,
  locked_until      timestamptz,
  changed_at        timestamptz DEFAULT now()
)
```

- **Argon2id parameters:** m=65536 (64 MiB), t=3, p=4. Salt 16 bytes generated by the library. ~100 ms per hash on modern x86 CPU. Final params benchmarked on production hardware before launch.
- **Password policy:**
  - Minimum length 12.
  - HIBP "Pwned Passwords" check via k-anonymity API (only the SHA-1 prefix is sent, never the full password). Reject if pwned.
  - zxcvbn score ≥ 3 client-side, re-validated server-side.
  - No mandatory rotation, no enforced character classes (per current NIST SP 800-63B guidance).
  - Custom blocklist of the ~100 most common Russian-language patterns.
- **Throttling:**
  - Per-account: 5 fails → 5 min lock, escalating to 15 min, admin-unlock after 20/24 h.
  - Per-IP: 30/h, 100/d sliding window in Redis.
  - Constant-time response regardless of whether the email exists.

#### 3.5.4 Migration of legacy SHA-1 passwords

1. **Migration:** copy `users.password` into `auth.password_credentials.hash_legacy_sha1`, set `must_reset = true`. The `hash` column stays NULL until the user logs in.
2. **Notification:** 7 days before cutover, send a Telegram message to all active users explaining the upcoming hash upgrade and noting that Mini App users won't be affected.
3. **At cutover:** login flow detects `hash IS NULL AND hash_legacy_sha1 IS NOT NULL`. On a successful SHA-1 match, the user is forced to set a new password before the session is issued. The new password is stored as Argon2id; `hash_legacy_sha1` is nulled out.
4. **30 days after cutover:** Telegram + email reminder to users who haven't logged in.
5. **90 days after cutover:** drop all remaining `hash_legacy_sha1` values; users who haven't logged in must use forgot-password recovery.

#### 3.5.5 Forgot-password / recovery

```
POST /auth/password/forgot { identity }
  → rate-limit: 1/min, 5/day per identity
  → 6-digit code, hashed with Argon2id, TTL 15 min, single-use, stored in auth.email_otp
  → delivered via spool-worker to Telegram bot if linked, otherwise email
  → constant-time response (do not leak existence)

POST /auth/password/reset { identity, code, new_password }
  → verify code hash, single-use, not expired
  → enforce password policy
  → INVALIDATE ALL existing sessions for this user_id
  → audit event 'password.reset'
  → notification: "your password was changed" via Telegram/email
```

#### 3.5.6 Two-factor

- **TOTP** (RFC 6238). Secret stored encrypted (AES-256-GCM with per-user DEK), encryption key in envelope (master KEK in vault).
- **Backup codes:** 10 single-use codes, hashed with Argon2id, plaintext shown once at generation.
- **WebAuthn as second factor for non-admin users** is a future option, not in scope for the initial cutover.

#### 3.5.7 Encryption of sensitive data

| Data | SHM today | New target | Protection |
|------|-----------|------------|------------|
| TOTP secret | `users.settings.otp.secret` plaintext | `auth.totp_secrets.secret_encrypted` | AES-256-GCM, per-user DEK, master KEK from SOPS+age |
| TOTP backup codes | `users.settings.otp.backup_codes` plaintext | `auth.totp_backup_codes.code_hash` | Argon2id, single-use |
| Email verify codes | `users.settings.email_verify_code` plaintext | `auth.email_otp.code_hash` | Argon2id, TTL, single-use |
| Reset tokens | `users.settings.reset_password_*` | merged into `auth.email_otp` | as above |
| Identity (transport) credentials | `identities` table plaintext | secret manager (SOPS), only refs in DB | DB never sees the secret |

Master KEK lives **outside the database and outside the application image**. SOPS-encrypted file decryptable only with an age key held in `systemd-creds` (or the platform-equivalent secret manager). Without the age key, a database dump is useless for key extraction.

#### 3.5.8 Database roles and grants

| Role | Grants |
|------|--------|
| `app_user` | SELECT/INSERT/UPDATE/DELETE on `auth.identities` (read-side only), `core.*`, `billing.*`, `spool.*`, `migration.*`. **No grants on `wallet.*`.** No UPDATE on `auth.password_credentials.hash`. |
| `auth_writer` | SELECT/INSERT/UPDATE on `auth.password_credentials`, `auth.email_otp`, `auth.totp_*`, `auth.webauthn_credentials`, `audit.auth_events`. Used by the auth module exclusively. |
| `wallet_writer` | INSERT on `wallet.ledger_entries`, `wallet.transactions`. UPDATE on `wallet.accounts.balance_cached` via trigger. SELECT on all `wallet.*`. **No DELETE.** |
| `read_only` | SELECT on read-views only, used by analytics/admin reports. |
| `migration_admin` | DDL within `migration` schema, used only by migration-bridge. |

Row-level security:

```sql
ALTER TABLE core.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_self ON core.users
  USING (user_id = current_setting('app.current_user', true)::uuid);
```

Each request `SET LOCAL app.current_user = '<uuid>'` after auth; admin role is `BYPASSRLS`. Same policy on `core.user_services` and others where applicable.

#### 3.5.9 Session, CSRF, CORS, CSP

- **Sessions:** 32-byte opaque IDs in Redis (`session:<id> → { user_id, created_at, fingerprint }`). Cookie `__Host-session` (HttpOnly, Secure, SameSite=Strict). Server-side rotation on use every 24 h. Logout = DELETE in Redis.
- **CSRF:** double-submit cookie `__Host-csrf` for any cookie-authenticated POST/PUT/DELETE.
- **CORS:** strict allowlist (wbap production domain + Telegram Mini App origin). No wildcard.
- **CSP:** `default-src 'self'`, no inline scripts, nonce for the few wbap inline scripts that need it.
- **Other headers:** HSTS (max-age 1y, includeSubDomains), X-Frame-Options DENY, X-Content-Type-Options nosniff, Referrer-Policy strict-origin-when-cross-origin.

#### 3.5.10 Audit log

```
audit.events (
  event_id    uuid7 PRIMARY KEY,
  actor_kind  text,             -- 'user' | 'admin' | 'system' | 'migration'
  actor_id    uuid,
  action      text,
  target      jsonb,            -- { kind, id }
  diff        jsonb,            -- before/after for sensitive ops
  ip          inet,
  user_agent  text,
  request_id  uuid,
  created_at  timestamptz DEFAULT now()
)
```

`REVOKE UPDATE, DELETE` from all roles. Logged events:

- All `/auth/*` calls.
- All wallet operations.
- All admin actions.
- All changes to `core.user_services` (manual changes only; automatic billing has its own log) and `core.services`.
- All payment-system callbacks.

---

## 4. Data Model

The new database has six application schemas (plus a transient `migration` schema). Layout below; field-level details captured during writing-plans.

### 4.1 Schema `auth`

`identities`, `password_credentials`, `email_otp`, `totp_secrets`, `totp_backup_codes`, `webauthn_credentials`, `sessions_meta` (Redis is source of truth; this table holds revocation tombstones if needed), `admin_roles`, `admin_invites`.

### 4.2 Schema `core`

`users`, `services` (catalog), `user_services` (subscriptions), `servers`, `server_groups`, `events` (event-type definitions), `user_gamification` (extracted from `users.settings.roulette`), `user_trials` (extracted from `users.settings.trial` and `cancel`), `hwid_state` (extracted from SHM `storage` Remnawave HWID tracking, keyed by `user_service_id` + `remna_uuid`), `feature_flags` per user if needed.

### 4.3 Schema `billing`

`billing_periods`, `discounts`, `promos`, `bonuses`, `invoices`, `payment_attempts`.

### 4.4 Schema `spool`

`tasks` (live queue, but BullMQ on Redis is the actual hot path; this table is for visibility/admin), `task_history` (append-only).

### 4.5 Schema `wallet`

`accounts` (one per `(owner, kind)` — main / bonus / system-hold / system-revenue / system-pays-clearing / system-bonus-pool / system-migration-adjust), `ledger_entries` (append-only, double-entry, `idempotency_key UNIQUE`), `transactions` (groups ledger entries, holds `kind`, `meta`, `reversed_by`), `holds`.

### 4.6 Schema `audit`

`events` (described in §3.5.10).

### 4.7 Schema `migration` (transient)

`shm_id_map (domain text, legacy_id bigint, new_id uuid)`, `cdc_state` (Debezium offsets), `divergence_log` (verifier findings), `feature_flags` (per-route routing for Caddy).

### 4.8 Cross-cutting conventions

- **Primary keys:** UUIDv7 everywhere new. Original SHM `int` PKs preserved as `legacy_id` columns + via `migration.shm_id_map`. UUIDv7 keeps temporal ordering and lets us avoid leaking row counts.
- **Money:** `numeric(20,4)` (room for multi-currency and fee precision).
- **Timestamps:** `timestamptz` everywhere. Migration converts MySQL `datetime` from Europe/Moscow to UTC.
- **JSON:** `jsonb` (not `text`).
- **Booleans:** native `boolean`, not `tinyint(1)`.
- **Strings:** `text` (no `char(N)`).
- **Audit tables:** `REVOKE UPDATE, DELETE` from every role.

---

## 5. Migration Strategy

### 5.1 Pattern

**Strangler Fig + one-way CDC + dual-write at the application layer + reverse-proxy with per-route routing.** No reverse CDC (PG → MySQL); we avoid that complexity by using application-level dual-write only for specific domains during their cutover windows.

### 5.2 Migration stack

| Component | Tool | Where |
|-----------|------|-------|
| CDC source | Debezium Server (standalone) | Docker container, reads MySQL binlog |
| CDC sink | Custom TS consumer | Lives in `migration-bridge` service |
| Initial bulk load | `pgloader` | One-shot at start of Phase 1 |
| ID mapping | `migration.shm_id_map` | PG-billing `migration` schema |
| Verifier | TS process, scheduled | In `migration-bridge` |
| Reverse proxy | Caddy | Existing instance |
| Feature flags | `migration.feature_flags` table + in-memory cache | PG + cache |

### 5.3 Schema mapping rules (applied automatically by migration-bridge)

| MySQL | Postgres | Notes |
|-------|----------|-------|
| `int(*) AUTO_INCREMENT` PK | `uuid7` PK + `legacy_id int` | mapped via `shm_id_map` |
| `tinyint(1)` | `boolean` | |
| `tinyint` (enum-like) | `smallint` or text-enum | by context |
| `char(N)` | `text` | |
| `datetime` | `timestamptz` | trade Europe/Moscow → UTC |
| `decimal(10,2)` (money) | `numeric(20,4)` | |
| `json` | `jsonb` | |
| `mediumblob` (logs) | not migrated | |
| MyISAM | InnoDB-equivalent in PG | initial snapshot uses brief FLUSH TABLES READ LOCK |

### 5.4 Wallet bootstrap from history

The hardest single step. Goal: produce a `wallet.ledger_entries` history such that for every user, `SUM(ledger ON main account) = users.balance` and `SUM(ledger ON bonus account) = users.bonus`, all at the snapshot time.

Algorithm:

1. Create system accounts: `system.pays_clearing`, `system.revenue`, `system.bonus_pool`, `system.migration_adjust`.
2. For each user, create `user.<uuid>.main` and `user.<uuid>.bonus` accounts.
3. For each `pays_history` row (money in): one transaction `kind='migration:pay'` with two ledger entries — debit `system.pays_clearing` / credit `user.main`, both at `pays_history.date`.
4. For each `withdraw_history` row (money out): debit `user.main` / credit `system.revenue`. If `bonus > 0`, additionally debit `user.bonus` / credit `system.revenue` for that bonus portion.
5. For each `bonus_history` row: if `bonus > 0` (credit), debit `system.bonus_pool` / credit `user.bonus`. If `bonus < 0` (debit), debit `user.bonus` / credit `user.main` (bonus-to-main transfer is the typical pattern in SHM).
6. Sanity check per user: if computed balance differs from `users.balance` by more than 0.005, log to `migration.divergence_log` and insert a single correction transaction (`kind='migration:adjust'`) from `system.migration_adjust` to `user.main` of the diff amount.

Acceptance criterion: post-bootstrap, no user balance differs from SHM by more than 0.005 RUB. All adjusts are reviewed manually before Phase 2.

### 5.5 Phased rollout

| Phase | Scope | Risk | Exit criteria |
|-------|-------|------|---------------|
| 0. Foundation | wbap-api skeleton, PG instance, Caddy with feature-flag routing (default 100% to SHM), CI, observability | low | hello-world via wbap-api succeeds, observability working |
| 1. Read-mirror | Initial pgloader snapshot, wallet bootstrap, Debezium running, migration-bridge applies CDC, verifier on hourly basis | low | divergence_log empty for 24 h, CDC lag < 5 s under load |
| 2. Notifications (Spool→TG) | New spool-worker shadows SHM execution of notification tasks; payload identity check | low | 0% mismatch over 7 days |
| 3. Spool→HTTP / Remnawave provisioning | activate/block/remove events idempotent via `event_dedup_key`; both systems try, first wins | high (touches users' VPN) | 0 lost events vs Remnawave-side state for 14 days |
| 4. Read endpoints | All GETs (services list, user info, balance, history) routed to wbap-api; canary 1 → 10 → 50 → 100% over 2 weeks | low | error rate ≤ SHM, p95 latency within 20% |
| 5. Promo / Bonus / Discounts writes | wbap-api writes PG, sends event hook to SHM (HTTP, idempotent) for legacy mirror | medium | 0% mismatch for 14 days |
| 6. Pay-systems | Pay callbacks routed to wbap-api, which validates and creates wallet transactions; per-minute reconciliation `SUM(pays_history) ↔ SUM(wallet deposit entries)` | **highest** | 21 days, 0 divergence > 0.01, 0 unknown callbacks |
| 7. Users / UserServices writes | wbap-api primary writer, canary by `user_id` ranges | high | 30 days clean divergence_log |
| 8. Cutover | SHM into READ-ONLY mode, all writes return 503, CDC stopped | — | 7 days observation |
| 9. Tear-down | SHM containers stopped, migration-bridge stopped, `migration` schema dropped, dump archived to cold storage | — | — |

Realistic timeline at quality-first pace: **3–4 months for Phases 0–7**, plus **1–2 months** for tail items (acts/legal exports, accounting reports). The owner has not set a deadline.

### 5.6 Verifier

| Level | What | Frequency |
|-------|------|-----------|
| L1 | Row counts per table | every 5 min |
| L2 | Checksum of random 1 000-row sample per table | every 30 min |
| L3 | Aggregate invariants (per-user balance, FK consistency, sum totals) | every 1 h |
| L4 | Full table chunk-by-chunk comparison | nightly |
| L5 | Wallet invariants (per-transaction debit/credit equality, per-user balance vs ledger sum) | continuous, on every transaction |

Findings → `migration.divergence_log`, Grafana dashboard, Telegram alert.

### 5.7 Rollback strategy

| Trigger | Action |
|---------|--------|
| CDC lag > 30 s persistently | Pause CDC, debug, replay from offset. |
| Phase 2-7 divergence > 0.5% | Flip feature flag back to SHM, fix code, retry. |
| Phase 6 payment divergence | Immediate revert; manual reconciliation of callback logs SHM vs wbap-api. |
| Post-Phase 8 critical bug | Re-enable SHM from read-only mode, switch reverse proxy. Window for clean rollback: 7 days; after that, divergence may make it impractical. |
| Post-Phase 9 critical bug | Restore SHM from cold archive; lose changes since tear-down. Worst-case scenario; should not happen if previous phases were clean. |

---

## 6. Testing & Quality Gates

### 6.1 Test pyramid

| Level | What | Tool |
|-------|------|------|
| Unit | Pure functions: billing math, password validation, schema validators | Vitest |
| Integration | Handlers + real PG (testcontainers) + real Redis | Vitest + testcontainers |
| Property-based | Wallet invariants under arbitrary operation sequences | fast-check |
| Contract | OpenAPI conformance (wbap client ↔ wbap-api) | Schemathesis or hand-rolled |
| E2E | Playwright against the running stack | Playwright |
| Migration | Run the migrator against a snapshot of the SHM dump, compare output to a frozen golden dataset | Vitest + dump fixture |
| Security | Semgrep, npm audit, Trivy, OWASP ZAP scan | CI |
| Load | k6 sustained 100 RPS on pay-callback and `/auth`, 1 000 RPS on read | k6 |

### 6.2 Wallet quality gate

- 100% line + branch coverage on `src/wallet/`. Hard CI gate.
- Property-based tests covering reserve / commit / refund / transfer combinations.
- Mutation testing (Stryker) ≥ 90% on `src/wallet/`. Hard gate.
- Two-reviewer rule on PRs touching `src/wallet/` (or one human + a senior code-review subagent).

### 6.3 Migration quality gate

- Golden dataset: current SHM dump, frozen.
- Test: run migrator → compare output. Must be byte-identical between runs (deterministic UUIDv7 generation seeded from input keys).
- Regression set: hand-picked edge-case users with known balance histories; their post-migration ledgers must match expectations.

---

## 7. Observability & Operations

### 7.1 Stack

```
Logs       pino (JSON)     → loki        ↘
Metrics    prom-client     → prometheus  → Grafana
Traces     OTel SDK        → tempo       ↗
Errors     Sentry (self-hosted)
Alerts     alertmanager → Telegram channel
Health     /health (liveness), /ready (readiness with DB + Redis check)
```

### 7.2 Key metrics

- `wbap_api_requests_total{route,status}` — RPS and error rate.
- `wbap_api_request_duration_seconds{route}` — p50/p95/p99.
- `wallet_transactions_total{kind}` — deposits / withdrawals / refunds.
- `wallet_balance_invariant_violations_total` — must always be 0; P0 alert.
- `migration_cdc_lag_seconds` — alert at > 30 s.
- `migration_divergence_total{domain}` — alert on growth.
- `auth_failures_total{kind}` — alert on spikes (possible brute force).
- `spool_tasks_pending{kind}` — alert if > 1 000 (worker stuck).

### 7.3 Alerts

| Severity | Trigger | Channel |
|----------|---------|---------|
| P0 (page) | Wallet invariant violation | TG + phone |
| P0 (page) | Pay-callback failures > 5/min | TG + phone |
| P1 | CDC lag > 60 s | TG |
| P2 | Auth failure spike | TG |
| P2 | Spool pending > 1 000 | TG |

### 7.4 Backups

| Store | Backup | Retention |
|-------|--------|-----------|
| PG-billing | `pg_basebackup` nightly + WAL archiving (PITR with 1-min granularity) | 30 d hot, 1 y cold |
| Redis | RDB hourly + AOF enabled | 30 d |
| SHM dump | Cold archive in S3-compatible storage, daily during migration → weekly after Phase 7 → kept 1 y after Phase 9 | 1 y |

Quarterly restore drill on staging — required.

---

## 8. Deployment & Supply Chain

- **Dockerfile:** multi-stage (`node:20-alpine` build → `gcr.io/distroless/nodejs20-debian12:nonroot` runtime). Non-root UID 65532, read-only root FS, dropped caps, `--security-opt no-new-privileges`. Healthcheck endpoint. Tagged with git SHA; `latest` tag is forbidden.
- **CI on push:** lint, typecheck, unit + integration tests (testcontainers), coverage gate (≥ 85%), Semgrep, npm audit, Trivy, build distroless image, push, attach SBOM (CycloneDX), sign with Cosign.
- **CD on tag:** deploy to staging → smoke tests → manual approval → rolling deploy to prod with health checks → automatic rollback on failure.
- **Secrets:** SOPS-encrypted YAML in repo; age key on host; resolved at runtime via systemd-creds.
- **Renovate:** auto-PR on dependencies; security patches auto-merge after CI green; major versions manual review.

---

## 9. Out of Scope (Explicitly)

- Reverse CDC (PG → MySQL): not built; we use application-level dual-write only during cutover windows.
- Migration of `acts`, `acts_data`, `apps`, `profiles`, `domains`, `dns_services`, `zones`, `domains_services`, `console`, and `spool_history` older than 30 days.
- Generic billing platform features (multi-tenancy, subscription metering primitives beyond what the VPN product needs).
- Full event-bus infrastructure (Kafka/NATS).
- Frontend changes to wbap (other than `baseURL` switch when routes are ready).

---

## 10. Open Questions to Resolve in writing-plans

These items did not block the design but need a concrete answer before code:

1. Exact production MySQL `TZ` env value — to be confirmed by reading the running container before Phase 1 cutover.
2. Whether `services.children` composite-service mechanic is still in active use (the catalog has a few `[{"qnt":1,"service_id":N}]` rows). Needs a quick audit before Phase 4.
3. Whether `users.settings.roulette` represents a feature still in production use (8 200 users have varying state). If yes → `core.user_gamification` design needs detail; if no → drop the field.
4. Final Argon2id parameters after benchmarking on the target host (current target: m=64 MiB, t=3, p=4).
5. SOPS / age-key custody policy: who holds the keys, recovery procedure if the holder is unavailable.
6. Whether the existing Postgres instance on the owner's infra is on the same host as the new PG-billing instance (resource contention if so).
7. Confirmation that no payment provider sends callbacks to a hardcoded SHM URL we cannot route via Caddy (would block Phase 6).
8. Empirical verification that `bonus_history` rows with `bonus < 0` represent bonus→main transfers (current §5.4 step 5 assumption). If some are net write-offs (bonus burned without crediting main), the wallet bootstrap algorithm needs an additional case mapping to `system.revenue`.

---

## 11. Glossary

- **Strangler Fig.** Migration pattern where a new system grows around the legacy one and progressively takes over.
- **CDC (Change Data Capture).** Streaming database changes from a source to a destination. We use Debezium to read MySQL binlog.
- **Double-entry ledger.** Accounting model where every transaction has equal debits and credits across two or more accounts.
- **Idempotency key.** Client-supplied unique key on a write so that retries don't double-apply the operation.
- **Envelope encryption.** Pattern where a per-record DEK encrypts data, and a master KEK encrypts the DEKs. Limits blast radius of a key leak.
- **HIBP / Pwned Passwords.** Have-I-Been-Pwned breach corpus. We check candidate passwords via the k-anonymity API.
- **WebAuthn / Passkey.** Phishing-resistant credentialed auth standard, used here for admin login.
- **RLS (Row-Level Security).** Postgres feature enforcing per-row visibility/mutation rules at the database engine.
- **SOPS + age.** Mozilla SOPS for encrypted-at-rest config files; age (by Filippo Valsorda) for the underlying encryption.
