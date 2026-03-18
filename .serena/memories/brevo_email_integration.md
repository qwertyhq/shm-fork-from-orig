# Brevo Email Integration

## Overview
Email notifications via Brevo HTTP API. SMTP ports (25/587/465) are blocked on the server.
All email delivery goes through `POST https://api.brevo.com/v3/smtp/email`.

## Infrastructure

### Server
- **server_id**: 20
- **name**: brevo-email
- **host**: `https://api.brevo.com/v3/smtp/email`
- **server_gid**: 13 (brevo group, http transport)
- **settings**: `{content_type, headers.api-key, method: post, template_id: brevo_system_email}`
- **Sender**: `noreply@z-hq.com` / "HQ VPN"

### GROUP_ID_MAIL Override
- **Original**: `GROUP_ID_MAIL => 2` (VPN/SSH group — cannot send email)
- **Custom**: `GROUP_ID_MAIL => 13` (Brevo HTTP group)
- **File**: `prod-files/Const.pm` mounted via Docker volume
- **Mounted in**: core + spool containers in `docker-compose-prop.yml`
- **Reason**: `verify_email()` and `passwd_reset_request()` in User.pm hardcode `server_gid => GROUP_ID_MAIL`

### Template Priority in Http.pm (line 42-44)
```
1. event_settings.template_id  → for 6 transactional events
2. task.settings.template_id   → not used currently
3. server.settings.template_id → fallback for verify_email/passwd_reset
```

## Templates (7 total)

### Transactional (6) — triggered by service events
| Template ID | Event | Event ID |
|-------------|-------|----------|
| brevo_service_created | create | 46 |
| brevo_service_blocked | block | 47 |
| brevo_low_balance | not_enough_money | 48 |
| brevo_service_prolonged | prolongate | 49 |
| brevo_payment_received | payment | 50 |
| brevo_forecast | forecast | 51 |

All use `{{ IF user.emails }}` guard to skip Telegram-only users.
Located in `tempaltes/email/brevo_*.tpl`.

### System (1) — fallback for verify/reset
| Template ID | Purpose | Data Source |
|-------------|---------|-------------|
| brevo_system_email | Email verification code, password reset | task.settings.{to, subject, message} |

This template is set as `server.settings.template_id` on server_id=20.
Used when verify_email() or passwd_reset_request() creates spool entries
that don't include their own template_id.

## Flows

### Transactional Email
```
Event → Events::make() → Spool(server_gid=13)
  → Http.pm picks template_id from event_settings
  → Template parses user/us data
  → POST to Brevo API
```

### Email Verification
```
User.pm::verify_email() → Spool(server_gid=GROUP_ID_MAIL=13)
  → task.settings = {to, subject, message}
  → Http.pm: no template_id in event_settings or task.settings
  → Fallback: server.settings.template_id = "brevo_system_email"
  → Template uses task.settings.to/subject/message
  → POST to Brevo API
```

### Password Reset
Same flow as email verification, from `passwd_reset_request()`.

## Files
- `prod-files/Const.pm` — custom Const.pm (GROUP_ID_MAIL=13)
- `tempaltes/email/brevo_system_email.tpl` — universal system email template
- `tempaltes/email/brevo_*.tpl` — 6 transactional templates
- `docker-compose-prop.yml` — volume mounts for core + spool
- `docs/brevo-email-integration.md` — deployment guide

## Future: Feature Request for SHM
To eliminate the Const.pm mount, SHM should support configuring
`GROUP_ID_MAIL` via `shm.conf` or the config API, e.g.:
```perl
# In shm.conf or config table:
group_id_mail = 13
```
Then Const.pm would read: `GROUP_ID_MAIL => config->{group_id_mail} || 2`
