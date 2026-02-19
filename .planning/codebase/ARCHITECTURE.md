# Architecture

**Analysis Date:** 2026-02-20

## Pattern Overview

**Overall:** Layered reverse-proxy architecture with three distinct service tiers running in Docker containers. The pattern is a classic N-tier design with external routing → presentation → business logic → persistence.

**Key Characteristics:**
- TLS termination at the reverse proxy (Nginx) for all inbound traffic
- Separated concerns: web client (Element Web), API server (Synapse), database persistence (PostgreSQL)
- Internal Docker network isolation with external routing through single ingress point
- Configuration-driven deployment via environment variables and static config files
- Declarative infrastructure via Docker Compose

## Layers

**Reverse Proxy & TLS Termination (`proxy/`):**
- Purpose: Handle HTTPS/HTTP, certificate management, route requests to appropriate service, enforce security headers
- Location: `proxy/nginx.conf`, `proxy/conf.d/element.conf`, `proxy/snippets/`
- Contains: Nginx main config, per-domain server blocks, TLS cipher configuration, security header policies
- Depends on: Certbot for certificate management, system's letsencrypt volumes
- Used by: All client connections from the internet; routes to Element Web, Synapse, and static .well-known files

**Web Client Layer (Element Web, `element/`):**
- Purpose: Serve the static Single Page Application (SPA) for chat UI; provide white-label branding
- Location: `element/config.json`, `element/branding/`
- Contains: Element Web configuration (server URL, theme colors, brand name, feature flags), SVG logo asset
- Depends on: Nginx routing, Docker image `vectorim/element-web:latest`
- Used by: End users opening https://chat.example.com; communicates directly with Synapse API

**Homeserver API Layer (Synapse, `synapse/`):**
- Purpose: Matrix protocol implementation; handles client API (registration, login, messaging), room management, user federation setup, database queries
- Location: `synapse/homeserver.yaml`, `synapse/log.config`
- Contains: Server configuration (database connection, registration policy, rate limiting, email), logging setup
- Depends on: PostgreSQL for state and message persistence, email (SMTP) for notifications
- Used by: Element Web client (/_matrix/client APIs), other Matrix servers (if federation enabled), admin scripts

**Persistence Layer (PostgreSQL, `compose/`):**
- Purpose: Store all Synapse state, messages, user accounts, room metadata, media references
- Location: Configured in `compose/docker-compose.yml` and `synapse/homeserver.yaml`
- Contains: Synapse database schema, persistent volumes (postgres_data)
- Depends on: Nothing; self-contained storage
- Used by: Synapse exclusively for all state queries and mutations

**Configuration & Orchestration (`compose/`):**
- Purpose: Define and manage the Docker container topology, environment variables, volume mounts, networking
- Location: `compose/docker-compose.yml`, `compose/.env`
- Contains: Service definitions (postgres, synapse, element, nginx, certbot), network topology, volume mounts, health checks
- Depends on: Docker Engine + Compose plugin
- Used by: All initialization and day-to-day operations (docker compose up/down)

## Data Flow

**User Registration & Login:**

1. User opens https://chat.example.com
2. Nginx routes request to Element Web container, serves SPA (HTML/JS)
3. Browser executes Element JavaScript, requests POST /_matrix/client/register to Synapse
4. Nginx proxies request (matrix.example.com) to Synapse container (port 8008)
5. Synapse validates registration token, queries PostgreSQL to check username availability
6. Synapse creates user record in postgres_data volume
7. Synapse returns access token to Element
8. Element stores token locally, uses it for future API calls

**Message Sending:**

1. User types message in Element Web, presses Enter
2. Element client calls PUT /_matrix/client/v3/rooms/{roomId}/send/m.room.message
3. Nginx proxies to Synapse port 8008
4. Synapse inserts message event into PostgreSQL
5. Synapse broadcasts to connected clients via WebSocket (same /_matrix API)
6. Other connected Element clients receive message in real-time
7. For offline users, Synapse stores event; delivered on next sync

**Encryption & Security:**

1. Element client generates per-room encryption keys (Megolm)
2. Message payload encrypted client-side before sending to Synapse
3. Synapse receives encrypted blob, stores in PostgreSQL without decryption ability
4. Receiving client decrypts locally using received key material
5. Server cannot read encrypted content; only metadata visible

**State Management:**

- Synapse holds canonical room state in PostgreSQL
- Element Web holds ephemeral UI state (sidebar scroll, draft messages) in browser localStorage
- No shared state cache layer; PostgreSQL is source of truth

## Key Abstractions

**Well-Known Matrix Discovery (`well-known/`):**
- Purpose: Serve standardized JSON files for Matrix client/server discovery without federation
- Examples: `well-known/matrix/client`, `well-known/matrix/server`
- Pattern: Static JSON files served at /.well-known/matrix/* endpoints, cached by browser/client (3600s TTL)
- Contents: Homeserver base URL (https://matrix.example.com), identity server (empty)

**Configuration Templating:**
- Purpose: Single source of truth (.env) for all domains, secrets, and settings
- Examples: `compose/.env.example`, `synapse/homeserver.yaml` (with __PLACEHOLDER__ tokens)
- Pattern: Environment variables substituted at runtime via docker-compose; static placeholders replaced via bootstrap scripts
- Impact: Avoids hard-coded domain names; enables reuse of configs across different deployments

**Signing Key Management:**
- Purpose: Cryptographic identity of the Synapse instance for federation and request signing
- Location: Generated at `synapse/signing.key` (inside docker volume synapse_data, not in repo)
- Pattern: Generated once via `docker compose run --rm synapse generate`, stored securely in volume
- Impact: Enables federation (if enabled); if key is lost, federation trust breaks

## Entry Points

**Primary Entry Point — Internet:**
- Location: Nginx listening on 0.0.0.0:80 (HTTP redirect), 0.0.0.0:443 (HTTPS), 0.0.0.0:8448 (federation, if enabled)
- Triggers: Any incoming HTTP/HTTPS request to chat.example.com, matrix.example.com, or example.com
- Responsibilities: TLS termination, routing to appropriate backend, enforcing security headers, ACME challenge handling

**Docker Compose Orchestration Entry Point:**
- Location: `compose/docker-compose.yml`
- Triggers: `docker compose up -d` (from compose/ directory)
- Responsibilities: Spin up all containers, establish internal network, mount volumes, configure health checks

**Admin Bootstrap Entry Point:**
- Location: `scripts/bootstrap-admin.sh`
- Triggers: Run after stack is initialized and healthy
- Responsibilities: Create first admin user via register_new_matrix_user CLI, using shared secret from .env

**Default Rooms Creation Entry Point:**
- Location: `scripts/create-default-rooms.py`
- Triggers: Run after admin user created
- Responsibilities: Connect to Synapse as admin, create initial Space and 6 default rooms (Lobby, Announcements, General, Support, Off-Topic, Voice), set encryption on all rooms

**Backup Entry Point:**
- Location: `scripts/backup.sh`
- Triggers: Manual execution or scheduled cron job
- Responsibilities: Dump PostgreSQL, archive media store, compress configs, encrypt with GPG, optionally upload to rclone remote, rotate old backups

**Restore Entry Point:**
- Location: `scripts/restore.sh [backup-file.tar.gz.gpg]`
- Triggers: Manual execution during disaster recovery
- Responsibilities: Decrypt backup, stop Synapse, drop/recreate database, restore from pg_dump, restore media store, restart Synapse

## Error Handling

**Strategy:** Defensive configuration with health checks + graceful degradation. Synapse continues operating with limited functionality if optional services (email, TURN) fail.

**Patterns:**

- **Container Health Checks:** Each service has `healthcheck` directive; Docker marks containers unhealthy if they fail. Used by dependent services (e.g., Synapse depends_on postgres with condition service_healthy)
  - Postgres: `pg_isready` command every 10s
  - Synapse: HTTP GET /health every 15s
  - Nginx/Element: No explicit health check (depends_on without condition)

- **Rate Limiting:** Synapse applies per-IP rate limits for registration, login, message sending (`rc_*` settings in homeserver.yaml)
  - Registration: 0.17/sec, burst 3 (prevents account enumeration)
  - Login: 0.17/sec per account/IP, burst 3 (password attack mitigation)
  - Messages: 2/sec, burst 10 (spam prevention)

- **Registration Barriers:** No open registration; requires shared secret token (must be from admin) + invite-only by default
  - `enable_registration: false` (users cannot self-register)
  - `registration_requires_token: true` (admin must generate token first)
  - Controlled via `registration_shared_secret` in homeserver.yaml

- **Database Connection Pooling:** Synapse uses psycopg2 with `cp_min: 5, cp_max: 10` to prevent connection exhaustion (5-10 concurrent connections to postgres)

- **Missing Optional Services:** If SMTP unreachable, email notifications disabled but chat continues; if TURN unreachable, VoIP falls back to peer-to-peer (Phase 2)

## Cross-Cutting Concerns

**Logging:**
- Synapse: Configurable via `synapse/log.config` (YAML); outputs to container stdout (captured by Docker logs driver)
- Nginx: Access log at /var/log/nginx/access.log (inside container), error log at /var/log/nginx/error.log
- Element Web: Browser console only (no server-side logging)
- Inspection: `docker compose logs -f synapse` (follows Synapse logs in real-time)

**Validation:**
- Matrix Protocol: Synapse enforces JSON Schema validation for all client API requests (part of Matrix spec)
- Configuration: .env variables must be set (scripts check for __PLACEHOLDER__ values and exit if found)
- Certificates: Certbot validates Let's Encrypt ACME challenges, auto-renews 30 days before expiry

**Authentication:**
- User Sessions: Matrix access tokens (long, random strings) used for all subsequent API calls after login
- Admin Operations: Shared secret (`registration_shared_secret`) used to sign one-time registration tokens via `register_new_matrix_user` CLI
- Federation (future): Synapse signs requests with its private signing key; receiving servers verify signature
- TLS Mutual: Not currently used; TLS client certificates not required

**Privacy:**
- E2EE Default: All new rooms created with `m.room.encryption` state event (Megolm)
- URL Previews: Disabled (`url_preview_enabled: false`) to prevent Synapse from making HTTP requests to preview links
- Media Caching: Synapse stores uploaded media in /data/media_store; accessible only via authenticated API
- Federation: Disabled by default (`federation_domain_whitelist: []`); traffic isolated to internal network

**TLS & Security:**
- Certificate Source: Let's Encrypt via Certbot (renews every 60 days automatically)
- Cipher Suite: Modern TLS 1.2+, ECDHE-based ciphers, no RC4 or weak algorithms (tls-params.conf)
- Security Headers: HSTS, X-Content-Type-Options, X-Frame-Options, CSP (security-headers.conf)
- OCSP Stapling: Enabled (secures certificate validation chain)

---

*Architecture analysis: 2026-02-20*
