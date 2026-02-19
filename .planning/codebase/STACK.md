# Technology Stack

**Analysis Date:** 2026-02-20

## Languages

**Primary:**
- Bash - Deployment, admin bootstrapping, and backup orchestration
- Python 3 - Room creation and admin utilities via `scripts/create-default-rooms.py` and `scripts/bootstrap-admin.sh`
- JSON - Configuration files for Element and Matrix homeserver
- YAML - Docker Compose definitions and Synapse configuration

**Secondary:**
- Nginx configuration language - Reverse proxy and TLS termination

## Runtime

**Environment:**
- Docker Engine 24+ with Compose plugin - Container orchestration and service deployment
- Linux server (Ubuntu 22.04+ recommended) - Host OS for Docker

**Package Manager:**
- pip3 - Python dependency management (for matrix-nio)
- docker compose - Container orchestration

## Frameworks

**Core:**
- Synapse (matrixdotorg/synapse:latest) - Matrix homeserver implementing client and federation APIs
- Element Web (vectorim/element-web:latest) - Client-side chat application (static SPA)

**Infrastructure:**
- Nginx (nginx:alpine) - Reverse proxy, TLS termination, rate limiting, security headers
- PostgreSQL 15 (postgres:15-alpine) - Persistent data storage for Synapse
- Let's Encrypt / Certbot (certbot/certbot) - Automated TLS certificate provisioning and renewal

**Testing/Admin:**
- matrix-nio (Python package) - Async Matrix client library for room creation and admin operations

## Key Dependencies

**Critical:**
- matrixdotorg/synapse - Matrix homeserver implementation; handles all chat API, user auth, encryption
- vectorim/element-web - Chat UI; served as static SPA, configurable for branding
- postgres:15-alpine - Data persistence for Synapse; all user accounts, messages, encryption keys stored here
- nginx:alpine - TLS termination, federation support, security headers, reverse proxy

**Infrastructure:**
- certbot/certbot - Automated TLS cert renewal via Let's Encrypt (12-hour renewal check)
- matrix-nio - Python async client for programmatic room creation and user management

**Development/Admin:**
- rclone (optional) - Offsite backup upload to remote storage (configured via `BACKUP_RCLONE_REMOTE` env var)
- gpg - Backup encryption using AES256 cipher (used in `scripts/backup.sh`)

## Configuration

**Environment:**
- `.env.example` template in `compose/.env.example` with placeholders for:
  - Domain names (DOMAIN, ELEMENT_DOMAIN, MATRIX_DOMAIN)
  - Synapse secrets (SYNAPSE_SIGNING_KEY, SYNAPSE_MACAROON_SECRET_KEY, SYNAPSE_FORM_SECRET)
  - Registration controls (SYNAPSE_ENABLE_REGISTRATION, SYNAPSE_REGISTRATION_SHARED_SECRET)
  - Database credentials (POSTGRES_PASSWORD)
  - SMTP credentials for email notifications
  - TURN server configuration (optional, Phase 2)
  - Backup encryption passphrase
  - Admin bootstrap credentials
  - Branding info (BRAND_NAME)

**Build:**
- `compose/docker-compose.yml` - Multi-service stack definition (Synapse, Element, Nginx, PostgreSQL, Certbot)
- `synapse/homeserver.yaml` - Synapse configuration with placeholders for substitution
- `synapse/log.config` - Python logging configuration (7-day rotation, warning-level minimum)
- `element/config.json` - Element Web configuration (homeserver URL, branding, custom theme)
- `proxy/nginx.conf` - Nginx base configuration (workers, TLS params, gzip)
- `proxy/conf.d/element.conf` - Nginx server blocks for three domains (chat, matrix, main)
- `proxy/snippets/tls-params.conf` - TLS 1.2+, strong ciphers, OCSP stapling
- `proxy/snippets/security-headers.conf` - HSTS, CSP, X-Frame-Options, etc.

## Platform Requirements

**Development:**
- Git for version control and deployment
- Docker Docker Compose plugin (v2+)
- certbot on host or via Docker for initial cert generation
- rclone for offsite backups (optional)

**Production:**
- Linux server (Ubuntu 22.04 LTS recommended)
- Minimum: 2 CPU, 4GB RAM, 50GB storage (scales with user count and message volume)
- Static public IP address
- Domain name with DNS A records configured
- Outbound SMTP access (port 587) for email notifications
- Persistent volumes: postgres_data, synapse_data, synapse_media, certbot_conf, certbot_webroot

## Service Ports

**External (from Nginx):**
- Port 80 - HTTP redirect to HTTPS
- Port 443 - HTTPS for Element Web and Synapse client API
- Port 8448 - HTTPS for Synapse federation API (optional, currently unused as federation disabled)

**Internal (Docker network only):**
- Synapse: port 8008 (health check at `/health`)
- Element: port 80
- PostgreSQL: port 5432
- Certbot: no exposed port (renews via Nginx webroot)

## Startup & Health Checks

**PostgreSQL:**
- Health check: `pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}`
- Interval: 10 seconds, timeout 5 seconds, retry 5 times

**Synapse:**
- Depends on: postgres (healthy)
- Health check: `curl -fSs http://localhost:8008/health`
- Interval: 15 seconds, timeout 5 seconds, retry 3 times

**Nginx:**
- Depends on: synapse, element (no explicit health check)
- Restart policy: unless-stopped

## Deployment Commands

```bash
# Initial setup
cd compose
docker compose run --rm synapse generate      # Generate signing key
cd ..

# Bootstrap admin user
./scripts/bootstrap-admin.sh

# Create default rooms
pip3 install matrix-nio
python3 ./scripts/create-default-rooms.py

# Launch stack
cd compose && docker compose up -d

# Backup
./scripts/backup.sh

# Restore
./scripts/restore.sh /path/to/backup.tar.gz.gpg

# View logs
docker compose logs -f synapse
```

---

*Stack analysis: 2026-02-20*
