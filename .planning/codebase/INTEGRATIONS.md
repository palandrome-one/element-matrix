# External Integrations

**Analysis Date:** 2026-02-20

## APIs & External Services

**Email Delivery:**
- SMTP - Used for email notifications and password reset links
  - Configured in: `synapse/homeserver.yaml` (lines 109-118)
  - Required env vars: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`
  - From address: `SMTP_FROM` (e.g., "Your Brand <noreply@example.com>")
  - Features: User notifications for messages, password recovery emails

**TLS Certificate Management:**
- Let's Encrypt - Automated certificate provisioning and renewal
  - Certbot client runs in Docker container
  - Renewal check: every 12 hours
  - Challenge type: ACME HTTP-01 via `.well-known/acme-challenge/`
  - Volumes: `certbot_conf` (certs), `certbot_webroot` (challenges)

**Matrix Federation (currently disabled):**
- Matrix Server-to-Server (S2S) API - For future federation
  - Port: 8448 (configured in `proxy/conf.d/element.conf` lines 89-106)
  - Status: Disabled by default - `federation_domain_whitelist: []` in `synapse/homeserver.yaml` (line 67)
  - When enabled: Synapse will accept connections from other Matrix homeservers
  - Key server: `trusted_key_servers: []` (line 135) - disables external key server trust

## Data Storage

**Databases:**
- PostgreSQL 15
  - Type: Relational database for all Synapse state
  - Client: psycopg2 (Python driver, embedded in Synapse)
  - Connection: `postgres:5432` (internal Docker network)
  - Credentials: `POSTGRES_USER`, `POSTGRES_PASSWORD` from env
  - Database name: `synapse` (configurable via `POSTGRES_DB`)
  - Initialization: UTF-8 encoding, C locale (`POSTGRES_INITDB_ARGS`)
  - Storage: Docker volume `postgres_data` (persistent)
  - Stored data:
    - User accounts, auth tokens, device trust
    - Room state, membership, power levels
    - Messages (encrypted payload + metadata)
    - Encryption keys (per-user, per-device)
    - Event history and retention policies
    - Rate limit tracking

**File Storage:**
- Local filesystem (Docker volume)
  - Media store: `/data/media_store` (volume: `synapse_media`)
  - Stores: User avatars, room pictures, uploaded files
  - Config: `max_upload_size: 50M` in `synapse/homeserver.yaml` (line 45)
  - Nginx config: `client_max_body_size 50m` in `proxy/conf.d/element.conf` (line 71)

**Caching:**
- None detected - Synapse uses in-memory caches for frequently accessed data
- PostgreSQL indexes provide query optimization

## Authentication & Identity

**Auth Provider:**
- Custom Matrix-native authentication
  - Type: Username/password stored in PostgreSQL
  - Implementation: `synapse/homeserver.yaml` (lines 49-53)
  - Registration:
    - Invite-only via registration tokens
    - `enable_registration: false` (line 51)
    - `registration_requires_token: true` (line 52)
    - Shared secret for token generation: `SYNAPSE_REGISTRATION_SHARED_SECRET`
  - No external SSO configured (Phase 2 option)
  - No identity server: `"m.identity_server": {"base_url": ""}` in `element/config.json` (line 8)
  - Email-based password reset: Configured via SMTP

**Secrets Management:**
- Macaroon secret key: `SYNAPSE_MACAROON_SECRET_KEY` (env var, used for session tokens)
- Form secret: `SYNAPSE_FORM_SECRET` (env var, CSRF protection)
- Signing key: Stored in `/data/signing.key` (generated during setup)

## Monitoring & Observability

**Error Tracking:**
- None detected - No external error tracking (Sentry, etc.)
- Errors logged to stdout and `/data/homeserver.log`

**Logs:**
- Synapse logging: Python logging configured in `synapse/log.config`
  - Output: Console (stdout) and file (`/data/homeserver.log`)
  - Format: `%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(request)s - %(message)s`
  - Rotation: Midnight, keeps 7 days of backups
  - Level: WARNING (minimum) except SQL logging is WARNING level
- Nginx logging: Access and error logs to stdout
  - Format: `$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"`

**Metrics (Phase 2):**
- Prometheus - Commented out in `synapse/homeserver.yaml` (lines 139-143)
  - Can be enabled via:
    ```yaml
    enable_metrics: true
    metrics_flags:
      known_servers: true
    ```

## CI/CD & Deployment

**Hosting:**
- Self-hosted on Linux VPS (not cloud-managed)
- Docker Compose for orchestration
- No cloud provider vendor lock-in

**CI Pipeline:**
- None detected - Manual deployment via Docker Compose

## Environment Configuration

**Required env vars (from `compose/.env.example`):**
- Domain config: `DOMAIN`, `ELEMENT_DOMAIN`, `MATRIX_DOMAIN`, `PUBLIC_BASEURL`
- Synapse: `SYNAPSE_SERVER_NAME`, `SYNAPSE_SIGNING_KEY`, `SYNAPSE_REGISTRATION_SHARED_SECRET`, `SYNAPSE_MACAROON_SECRET_KEY`, `SYNAPSE_FORM_SECRET`
- Database: `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- SMTP: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`
- Admin: `ADMIN_USER`, `ADMIN_PASSWORD`
- Backup: `BACKUP_ENCRYPTION_PASSPHRASE`, `BACKUP_RCLONE_REMOTE` (optional)
- TLS: `CERTBOT_EMAIL`
- Branding: `BRAND_NAME`
- TURN (Phase 2): `TURN_DOMAIN`, `TURN_SECRET` (commented out)

**Secrets location:**
- `compose/.env` - Contains all secrets (not committed to git)
- Template: `compose/.env.example` (safe, has placeholders)
- Values substituted at runtime or via bootstrap scripts

**Config file substitution:**
- `synapse/homeserver.yaml` contains `__PLACEHOLDER__` values
- Must be replaced with actual env values before startup
- Bootstrap script (`scripts/bootstrap-admin.sh`) validates that placeholders are replaced

## Webhooks & Callbacks

**Incoming:**
- ACME challenges: Let's Encrypt validates domain ownership via HTTP-01 at `/.well-known/acme-challenge/`
  - Handled by Nginx, stored in `certbot_webroot` volume
- Email delivery: No webhooks for SMTP delivery (fire-and-forget)

**Outgoing:**
- Email notifications: Synapse sends SMTP to configured `SMTP_HOST`
- No outbound webhooks to external services detected
- Message events: Internal only (Element to Synapse, no external callbacks)

## Matrix-Specific Discovery & Delegation

**Well-Known Endpoints (client discovery):**

**`/.well-known/matrix/client`** - Discovery for Element Web clients:
- Served at: `example.com/.well-known/matrix/client` (configured in `proxy/conf.d/element.conf` lines 121-126)
- Returns: JSON in `well-known/matrix/client` with homeserver base URL
- Content:
  ```json
  {
    "m.homeserver": { "base_url": "https://matrix.example.com" },
    "m.identity_server": { "base_url": "" }
  }
  ```
- Cache: `max-age=3600` (1 hour)
- CORS: `Access-Control-Allow-Origin: *`

**`/.well-known/matrix/server`** - Discovery for federation (S2S):
- Served at: `example.com/.well-known/matrix/server` (same block)
- Returns: JSON in `well-known/matrix/server` with server address
- Content:
  ```json
  {
    "m.server": "matrix.example.com:443"
  }
  ```
- Used by external homeservers to discover federation endpoint

## Rate Limiting

**Configured in `synapse/homeserver.yaml` (lines 72-87):**
- Message sending: 2 per second, burst 10
- Registration: 0.17 per second (1 per 6 seconds), burst 3
- Login: 0.17 per second per address/account, burst 3

## Security Headers

**Set by Nginx (`proxy/snippets/security-headers.conf`):**
- Strict-Transport-Security: max-age=63072000 (2 years), includeSubDomains, preload
- X-Content-Type-Options: nosniff
- X-Frame-Options: SAMEORIGIN
- X-XSS-Protection: 0
- Referrer-Policy: strict-origin-when-cross-origin
- Permissions-Policy: camera=(), microphone=(), geolocation=()
- Content-Security-Policy: frame-ancestors 'self' (for Element)

## Admin Operations

**User Management API:**
- Matrix admin endpoints at `/_synapse/client/` (proxied through Nginx)
- Requires admin token (obtained via login as admin user)
- Used by: `scripts/bootstrap-admin.sh` (via `register_new_matrix_user` CLI)

**Room Management:**
- Matrix client API `/createRoom` endpoint
- Implementation: `scripts/create-default-rooms.py` uses matrix-nio library
- Creates encrypted rooms, configures power levels, sets up space hierarchy

---

*Integration audit: 2026-02-20*
