# API Routes Complete Reference

## Public Routes

### Auth
- POST /user/auth (login, password) → session_id
- PUT /user (login, password) → registration
- POST /user/passwd/reset → password reset request
- GET|POST /user/passwd/reset/verify → token validate + change
- POST /user/password-auth/enable → enable password login
- DELETE /user/password-auth/disable → disable password login
- GET /user/password-auth/status → check if enabled

### 2FA & WebAuthn
- POST /user/otp/setup → 2FA registration
- POST /user/otp → verify/enable/disable OTP
- GET /user/passkey → list passkeys
- POST /user/passkey/register → FIDO2 registration
- GET|POST /user/auth/passkey → passkey auth

### User Profile
- GET /user → current user
- POST /user → update profile
- GET|POST|DELETE /user/email → email management

### Services
- GET /user/service → active services
- POST /user/service/change (usi, sid) → tariff change
- POST /user/service/stop → block service
- DELETE /user/service → delete service

### Billing
- GET /user/pay → payment history
- GET /user/pay/forecast → projected dates
- GET /user/pay/paysystems → payment methods
- GET /user/withdraw → withdrawals
- GET /user/autopayment → auto-payments

### Templates & Storage
- GET|POST /template/* → execute user template
- GET|POST /public/* → execute public template
- GET|POST /storage/manage/* → CRUD
- GET /storage/download/* → download

### Promo
- GET /promo → user's promo codes
- GET /promo/apply/* → apply promo

### Telegram
- POST /telegram/bot → webhook (skip auth)
- GET /telegram/webapp/auth (initData) → webapp login
- GET /telegram/user → bot settings
- POST /telegram/set_webhook → register webhook

## Admin Routes (all require gid=1)
- CRUD: /admin/service, /admin/user, /admin/server, /admin/spool, /admin/config, /admin/template, /admin/storage
- Special: /admin/user/passwd, /admin/user/payment, /admin/user/session
- Spool: /admin/spool/statuses, /admin/spool/history, /admin/spool/manual/*
- Events: /admin/service/event CRUD
- Server: /admin/server/group, /admin/server/identity
- Analytics: /admin/analytics, /admin/system/version
