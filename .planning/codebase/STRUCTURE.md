# Codebase Structure

**Analysis Date:** 2026-02-20

## Directory Layout

```
element-matrix/
├── compose/                    # Docker Compose stack + environment config
│   ├── docker-compose.yml      # Service definitions, volumes, networks
│   └── .env                    # Runtime environment variables (secrets)
│
├── synapse/                    # Synapse homeserver configuration
│   ├── homeserver.yaml         # Main configuration (database, email, federation, rate limits)
│   └── log.config              # Logging configuration
│
├── element/                    # Element Web client configuration
│   ├── config.json             # Client configuration (theme, branding, servers)
│   └── branding/               # Brand assets (logo, colors)
│       └── logo.svg            # Company/community logo
│
├── proxy/                      # Nginx reverse proxy configuration
│   ├── nginx.conf              # Main Nginx configuration (workers, gzip, includes)
│   ├── conf.d/                 # Per-domain server blocks
│   │   └── element.conf        # Combined configuration for Element, Synapse, .well-known
│   └── snippets/               # Shared configuration fragments
│       ├── tls-params.conf     # TLS cipher suite and hardening
│       └── security-headers.conf # Security headers (HSTS, CSP, etc.)
│
├── well-known/                 # Matrix discovery files (static JSON)
│   └── matrix/
│       ├── client              # Client discovery: homeserver base URL
│       └── server              # Server discovery: federation target
│
├── scripts/                    # Operational scripts
│   ├── bootstrap-admin.sh      # Create first admin user after stack deployment
│   ├── create-default-rooms.py # Create initial Space and default chat rooms
│   ├── backup.sh               # Full backup (DB + media + configs) with encryption
│   └── restore.sh              # Restore from encrypted backup
│
├── docs/                       # Operations documentation
│   ├── runbook.md              # Day-to-day operations (logs, scaling, updates)
│   ├── security.md             # Security threat model, hardening, compliance
│   ├── migration-guide.md      # Discord migration guide and onboarding
│   └── quotation.md            # [Placeholder] Deployment quotation/planning
│
├── README.md                   # Quick start guide and overview
├── CLAUDE.md                   # Architecture guide for Claude Code
├── implementation.md           # [Reserved] Implementation phases and roadmap
└── .planning/                  # [Not deployed] Planning documents
    └── codebase/               # ARCHITECTURE.md, STRUCTURE.md, etc.
```

## Directory Purposes

**`compose/`:**
- Purpose: Docker Compose orchestration and environment configuration
- Contains: docker-compose.yml (service topology), .env (secrets and domain config)
- Key files: `docker-compose.yml` defines postgres, synapse, element, nginx, certbot services; ``.env.example`` shows all required variables
- Note: `.env` is not in git (listed in .gitignore); must be created from .env.example and populated by operator

**`synapse/`:**
- Purpose: Matrix homeserver configuration and logging
- Contains: homeserver.yaml (service configuration with __PLACEHOLDER__ values for operator to fill), log.config (structured logging setup)
- Key files: `homeserver.yaml` (7032 bytes; database connection, encryption defaults, rate limits, email SMTP, registration policy, federation whitelist)
- Note: log.config is immutable (ro volume mount); homeserver.yaml is ro but paths inside (signing.key, media_store) are writable volumes

**`element/`:**
- Purpose: Element Web client configuration and branding
- Contains: config.json (Element configuration), branding assets (logo.svg)
- Key files: `config.json` (2300 bytes; defines server URLs, theme colors, feature flags, disabled integrations)
- Note: Theme is defined inline as "YourBrand" with custom dark mode colors; logo mounted as volume override

**`proxy/`:**
- Purpose: Nginx reverse proxy and TLS termination
- Contains: Main nginx.conf, per-domain configs (element.conf), TLS hardening snippets, security headers
- Key files:
  - `nginx.conf`: Worker processes, gzip, includes for tls-params and conf.d/
  - `conf.d/element.conf`: 4 server blocks (HTTP redirect, Element Web, Synapse API, federation port 8448, .well-known)
  - `snippets/tls-params.conf`: TLS 1.2+, ECDHE ciphers, OCSP stapling, session cache
  - `snippets/security-headers.conf`: HSTS, CSP, X-Frame-Options, Permissions-Policy
- Note: All paths in configs use example.com; replaced at runtime by Nginx variables or hardcoded domain values

**`well-known/`:**
- Purpose: Static Matrix discovery JSON files served at /.well-known/matrix/*
- Contains: Two JSON files defining Matrix client/server discovery
- Key files:
  - `matrix/client`: Points to https://matrix.example.com for homeserver base URL
  - `matrix/server`: Points to matrix.example.com:443 for federation (if enabled)
- Note: Served with Access-Control-Allow-Origin: * and Cache-Control: 3600s; enables any client to discover the homeserver

**`scripts/`:**
- Purpose: Operational and administrative scripting
- Contains: Bash and Python scripts for setup, backup, restore, and room creation
- Key files:
  - `bootstrap-admin.sh`: Creates first admin user (depends on synapse container running, reads from .env)
  - `create-default-rooms.py`: Creates Space + 6 default encrypted rooms (uses matrix-nio Python library)
  - `backup.sh`: Dumps PostgreSQL, archives media, encrypts with GPG, optionally uploads to rclone
  - `restore.sh`: Decrypts backup, restores database and media (requires postgres container up, synapse must be stoppable)
- Note: All scripts check for __PLACEHOLDER__ values in .env and fail if found (safety mechanism)

**`docs/`:**
- Purpose: Operational and security documentation
- Contains: Markdown runbooks, security policies, migration guides
- Key files:
  - `runbook.md`: How to restart, scale, update, handle incidents
  - `security.md`: Threat model, hardening checklist, compliance notes
  - `migration-guide.md`: Onboarding guide for Discord communities
- Note: Not deployed to server; reference only

## Key File Locations

**Entry Points:**

- `compose/docker-compose.yml`: Starting point for infrastructure; defines all containers, volumes, networks. Run `docker compose up -d` from compose/ directory.
- `compose/.env`: Configuration source; all secrets, domains, and settings read from here by scripts and compose file.
- `scripts/bootstrap-admin.sh`: Post-deployment admin user creation; run after stack is healthy.
- `scripts/create-default-rooms.py`: Default room/space creation; run after bootstrap-admin.sh.

**Configuration:**

- `compose/.env.example`: Template for .env; copy and fill in all values.
- `synapse/homeserver.yaml`: Synapse service configuration; replace __PLACEHOLDER__ values before deploying.
- `element/config.json`: Element Web UI configuration; defines server URL, theme, features.
- `proxy/nginx.conf`: Nginx main config; includes tls-params and conf.d/*.
- `proxy/conf.d/element.conf`: All HTTP/HTTPS routing rules for Element, Synapse, .well-known.

**Core Logic:**

- `synapse/homeserver.yaml` (database, encryption, rate limits): Application-level security and performance
- `proxy/snippets/security-headers.conf`: Browser security policies
- `proxy/snippets/tls-params.conf`: TLS cipher suite hardening
- `scripts/backup.sh`: Data protection strategy (encrypted GPG, offsite upload via rclone)

**Testing & Verification:**

- No unit tests in repo; testing is operational:
  - Health checks in docker-compose.yml (pg_isready, curl /health)
  - Manual verification: `curl https://example.com/.well-known/matrix/client | jq .`
  - Log inspection: `docker compose logs -f synapse`

## Naming Conventions

**Files:**

- Bash scripts: Kebab-case, executable (e.g., `bootstrap-admin.sh`, `backup.sh`)
- Config files: All lowercase with extension (e.g., `homeserver.yaml`, `docker-compose.yml`)
- Documentation: Markdown with descriptive names (e.g., `migration-guide.md`)
- Environment variables: UPPER_SNAKE_CASE (e.g., `POSTGRES_PASSWORD`, `SYNAPSE_SERVER_NAME`)

**Directories:**

- Service names: Lowercase singular (e.g., `compose`, `synapse`, `element`, `proxy`)
- Config subdirs: Lowercase plural or abbreviated (e.g., `conf.d`, `snippets`, `branding`)
- Documentation: `docs` (plural)

**Variables in Files:**

- Placeholder values: `__UPPER_CASE_PLACEHOLDER__` (e.g., `__POSTGRES_PASSWORD__`, `__PLACEHOLDER__`)
- Domain placeholders: `example.com`, `chat.example.com`, `matrix.example.com` (operator must replace)

## Where to Add New Code

**New Feature (e.g., Discord bridge, monitoring):**
- Infrastructure: Add service to `compose/docker-compose.yml` (container definition, volumes, networks)
- Configuration: Add config file in appropriate subdirectory (e.g., `bridges/` for Discord bridge config) and mount in compose
- Secrets: Add env vars to `compose/.env.example` and reference in docker-compose.yml
- Script: If operational setup needed, add bash script to `scripts/` with same error-checking pattern as backup.sh

**New Nginx Routing (e.g., new reverse proxy target):**
- Location: Add new `server {}` block to `proxy/conf.d/element.conf` (or create new .conf file in conf.d/)
- Pattern: Follow existing blocks (listen, server_name, ssl_certificate, proxy_pass)
- Security headers: Include `proxy/snippets/security-headers.conf` in the new block

**New Documentation (e.g., troubleshooting guide):**
- Location: Create new .md file in `docs/`
- Pattern: Follow existing markdown structure (headings, code blocks, bullet lists)

**New Operational Script (e.g., migration tool, metrics export):**
- Location: Create executable script in `scripts/` with shebang and set +x
- Pattern: Load env from `$REPO_ROOT/compose/.env`, check required vars, provide clear output
- Error handling: Use `set -euo pipefail`, validate env vars, exit with error code if failed

**Utilities & Helpers:**
- Shared bash functions: Add to `scripts/` with `source` pattern (see bootstrap-admin.sh, backup.sh)
- Python utilities: Add to `scripts/` with `#!/usr/bin/env python3` shebang, use matrix-nio or subprocess for Docker calls

## Special Directories

**`compose/` — Generated/Runtime:**
- Generated: `.env` (created from .env.example, contains secrets)
- Committed: docker-compose.yml, .env.example
- Volumes created at runtime: postgres_data, synapse_data, synapse_media, certbot_conf, certbot_webroot

**`.planning/codebase/` — Planning & Analysis:**
- Purpose: GSD codebase mapping documents (ARCHITECTURE.md, STRUCTURE.md, etc.)
- Generated: ARCHITECTURE.md, STRUCTURE.md, TESTING.md, CONCERNS.md, etc.
- Committed: Yes (tracked in git for code planning reference)

**`.git/` — Version Control:**
- Contains: Git history, remotes, branches
- Not deployed

**`backups/` — Backup Storage:**
- Generated: At runtime via `scripts/backup.sh`
- Contains: Encrypted backup archives (*.tar.gz.gpg)
- Rotation: Keeps last 7 local backups; older ones deleted automatically
- Not committed

## Module Organization & Imports

**Synapse Configuration:**
- Single monolithic YAML file (`synapse/homeserver.yaml`); no modular config includes
- All sections sequential: listeners → database → logging → media → registration → secrets → federation → rate limiting → email → TURN → metrics → admin

**Nginx Configuration:**
- Modular by file:
  - `nginx.conf`: Main worker/event configuration, includes tls-params and conf.d
  - `conf.d/element.conf`: All server blocks (HTTP redirect, Element, Synapse, Federation, .well-known)
  - `snippets/tls-params.conf`: Included by all server blocks (ssl_protocols, ssl_ciphers)
  - `snippets/security-headers.conf`: Included by all server blocks (add_header directives)

**Shell Scripts:**
- Each script is self-contained; no shared library
- Common pattern: Load .env, validate vars, run docker compose commands
- See `bootstrap-admin.sh` and `backup.sh` for pattern reuse

**Python Scripts:**
- Single script per operation (`create-default-rooms.py`)
- Uses external library: `matrix-nio` (installed via `pip3 install matrix-nio`)
- Minimal dependencies; no local modules imported

---

*Structure analysis: 2026-02-20*
