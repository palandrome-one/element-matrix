# Testing Patterns

**Analysis Date:** 2026-02-20

## Overview

This project does not use automated unit or integration test frameworks. There are no Jest, Vitest, pytest, or similar test suites. Instead, testing relies on:

1. **Manual testing procedures** documented in `docs/` (runbooks)
2. **Infrastructure validation** (health checks in Docker Compose)
3. **Operational scripts** with built-in validation (env var checks, file existence, error handling)
4. **Acceptance criteria** defined in `implementation.md` for each phase

The codebase consists of operational scripts and configuration files, not application code requiring unit test coverage.

## Testing Strategy

### What Gets Tested

**Infrastructure components:**
- Docker Compose health checks (PostgreSQL readiness, Synapse HTTP health)
- Certificate availability and TLS grade
- `.well-known` endpoint responses
- Static file serving (Element Web, branding)
- Reverse proxy routing (Nginx)

**Operational scripts:**
- Environment variable validation
- File existence checks
- Directory creation and permissions
- GPG encryption/decryption
- Docker Compose integration

**Manual acceptance tests:**
- User registration with invite token
- End-to-end encryption (E2EE) in rooms and DMs
- Message sending and delivery
- Room creation and space hierarchies
- Voice/video calls (Phase 2)
- Backup encryption and restore success

### What Does NOT Get Tested Automatically

- Synapse business logic (relies on upstream project's tests)
- Element Web UI (relies on upstream project's tests)
- PostgreSQL internals (relies on upstream tests)
- Custom Nginx directives (validated through curl checks)

## Docker Compose Health Checks

### PostgreSQL Health Check

**Location:** `compose/docker-compose.yml` lines 19-23

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
  interval: 10s
  timeout: 5s
  retries: 5
```

**Purpose:** Ensures database is ready before Synapse starts

**Validation:**
- Command: `pg_isready` (standard PostgreSQL utility)
- Check frequency: Every 10 seconds
- Failure threshold: 5 failed checks before marked unhealthy
- Used by: Synapse service depends on this condition

### Synapse Health Check

**Location:** `compose/docker-compose.yml` lines 43-47

```yaml
healthcheck:
  test: ["CMD", "curl", "-fSs", "http://localhost:8008/health"]
  interval: 15s
  timeout: 5s
  retries: 3
```

**Purpose:** Ensures Synapse HTTP API is responding

**Validation:**
- Endpoint: `/health` (Synapse's built-in health check)
- Check frequency: Every 15 seconds
- Failure threshold: 3 failed checks
- Used by: Nginx depends on Synapse being healthy before accepting traffic

**Verify health manually:**
```bash
cd compose && docker compose ps
# All services should show "healthy" or "running" status

# Or check directly
cd compose && docker compose exec synapse curl -s http://localhost:8008/health
```

## Script Validation Patterns

### Environment Variable Validation

**Used in all operational scripts.** Pattern from `bootstrap-admin.sh`:

```bash
for var in ADMIN_USER ADMIN_PASSWORD SYNAPSE_REGISTRATION_SHARED_SECRET; do
    if [[ -z "${!var:-}" ]] || [[ "${!var}" == __* ]]; then
        echo "ERROR: $var is not set or still has a placeholder value in .env"
        exit 1
    fi
done
```

**What this tests:**
- Variable is set (not empty)
- Variable is not a placeholder (`__*` pattern)

**Where used:**
- `bootstrap-admin.sh` — checks admin credentials
- `backup.sh` — checks backup encryption passphrase and database credentials
- `restore.sh` — checks database credentials

### File Existence Checks

**Pattern from `backup.sh`:**

```bash
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found."
    exit 1
fi
```

**Pattern from `create-default-rooms.py`:**

```python
def load_env():
    env_path = Path(__file__).resolve().parent.parent / "compose" / ".env"
    if not env_path.exists():
        print(f"ERROR: {env_path} not found.")
        sys.exit(1)
```

**What this tests:**
- Required files (`.env`) exist before operations
- Fails fast with clear error message

### Docker Compose Dependency Checks

**Pattern from `restore.sh`:**

```bash
COMPOSE_FILE="$REPO_ROOT/compose/docker-compose.yml"

# Later, when needed:
docker compose -f "$COMPOSE_FILE" stop synapse
docker compose -f "$COMPOSE_FILE" exec -T postgres dropdb ...
```

**What this validates:**
- Docker Compose file is found
- Services (postgres, synapse) are reachable
- Docker daemon is running
- Network connectivity between services works

## Acceptance Criteria Testing (Manual)

### Phase 1 — Core Stack

**From `implementation.md` lines 101-107:**

```
- [ ] https://chat.example.com loads branded Element
- [ ] User can register with invite token and message in default rooms
- [ ] E2EE works in DMs and encrypted rooms
- [ ] .well-known endpoints resolve correctly
- [ ] TLS grade A+ (or near) on SSL Labs
- [ ] Security headers present (test with securityheaders.com)
```

**How to test:**

**1. Element Web loads with branding:**
```bash
curl -s https://chat.example.com/ | head -5
# Should return HTML with branding (brand name, logo, theme colors)
```

**2. User registration and messaging:**
- Manual testing in browser or Matrix client
- Create invite token (documented in `docs/runbook.md`)
- Register user with token
- Send message in default rooms
- Verify message appears for other users

**3. E2EE verification:**
- In Element Web client settings: verify E2EE is enabled
- Create DM with another user
- Verify green shield icon indicating encrypted messages
- Verify message history shows encryption status

**4. Well-known endpoints:**
```bash
curl -s https://example.com/.well-known/matrix/client | python3 -m json.tool
curl -s https://example.com/.well-known/matrix/server | python3 -m json.tool
# Both should return valid JSON with correct homeserver URLs
```

**5. TLS grade testing:**
```bash
# Use SSL Labs tester (online tool):
https://www.ssllabs.com/ssltest/

# Or check locally with curl:
curl -sI https://chat.example.com | grep -i "strict-transport"
# Should show HSTS header

# Or with openssl:
openssl s_client -connect chat.example.com:443 -tls1_2
```

**6. Security headers:**
```bash
curl -I https://chat.example.com | grep -iE "strict-transport|x-content-type|x-frame|permissions-policy"
# Should output headers from proxy/snippets/security-headers.conf
```

### Phase 2 — Reliability & Observability

**From `implementation.md` lines 124-128:**

```
- [ ] Voice/video calls work reliably via coturn
- [ ] Daily backups run and upload offsite
- [ ] Restore from backup tested and documented
- [ ] Alert fires on: Synapse down, cert expiry < 14d, disk > 80%
```

**How to test:**

**1. Voice/video calls (coturn):**
- Manual: Start call between two users in Element Web
- Verify call connects and media flows
- Check coturn logs for TURN allocations

**2. Backup automation:**
```bash
# Run backup manually first
./scripts/backup.sh

# Verify encrypted archive created
ls -lh backups/*.tar.gz.gpg

# Check timestamp is recent
date

# Verify file is actually GPG-encrypted
file backups/matrix-backup-*.tar.gz.gpg
# Should show: "data" (binary GPG)
```

**3. Restore test:**
```bash
# Create a test backup
./scripts/backup.sh --local-only

# Restore from it
./scripts/restore.sh /path/to/backup.tar.gz.gpg
# Follow prompts, verify database and media restored

# Verify data integrity
# Log in as admin and check messages/rooms still present
```

**4. Alerting (manual setup, not automated):**
- Configure Uptime Kuma or similar monitoring tool
- Add checks for:
  - HTTP/HTTPS endpoints up
  - Certificate expiry (check every 24h)
  - Disk usage thresholds
- Document in `docs/monitoring.md` (future)

## Backup & Restore Validation

### Backup Script Tests

**From `scripts/backup.sh`:**

**What the script validates:**
1. `.env` file exists and is readable
2. Required env vars set: `POSTGRES_DB`, `POSTGRES_USER`, `BACKUP_ENCRYPTION_PASSPHRASE`
3. Docker Compose is running
4. PostgreSQL volume is accessible
5. GPG is available and encryption passphrase is set

**Outputs:**
- Timestamped backup directory: `$BACKUP_DIR/matrix-backup-YYYY-MM-DD_HHMMSS`
- Contains: `synapse.pgdump`, `media.tar`, `configs.tar`
- Final encrypted archive: `matrix-backup-YYYY-MM-DD_HHMMSS.tar.gz.gpg`
- Size reported: `du -sh` for each component

**Test procedure:**
```bash
./scripts/backup.sh --local-only
# Should complete with no errors
# Output should show: [1/4], [2/4], [3/4], [4/4] progress
# Should show final archive size and filename
```

### Restore Script Tests

**From `scripts/restore.sh`:**

**What the script validates:**
1. Backup file provided as argument
2. Backup file exists and is readable
3. `.env` file exists
4. Required env vars set
5. User confirms destructive operation (interactive prompt)
6. Docker Compose is running
7. PostgreSQL can be stopped and restarted
8. Media volume is writable (may require sudo)

**Outputs:**
- Decrypted and extracted to temp directory
- PostgreSQL database replaced (dropped, recreated, restored)
- Media store cleared and restored
- Synapse restarted
- Post-restore checklist provided

**Test procedure:**
```bash
# After a successful backup
./scripts/restore.sh /path/to/matrix-backup-YYYY-MM-DD_HHMMSS.tar.gz.gpg

# At confirmation prompt, type 'y'
# Wait for [1/4], [2/4], [3/4], [4/4] progress
# Verify completion message

# Then manually verify:
curl -s https://example.com/.well-known/matrix/client
# Should respond normally

# Log in to Element and verify data
# Check messages/rooms are present
```

## Python Script Validation

### create-default-rooms.py

**What the script validates:**

1. **Prerequisites:**
   - `matrix-nio` library installed
   - `.env` file in `compose/` directory
   - Admin credentials set in `.env`

2. **Runtime validation:**
   - Login response has `access_token` attribute
   - Room creation response is `RoomCreateResponse` type
   - Encryption state events are accepted

3. **Async safety:**
   - Client connection closed on any error
   - All await calls properly awaited

**Test procedure:**
```bash
# Install prerequisites
pip3 install matrix-nio

# Run with valid .env
python3 scripts/create-default-rooms.py

# Expected output:
# - "Logging in as..."
# - "Creating Space: ..."
# - "  Space created: ..."
# - "Creating room: #Lobby"
# - "  Room created: ..."
# - "  Added to space."
# - Repeat for each room
# - "Done! Space and 6 rooms created."

# Verify in Element Web:
# - Space appears in left sidebar
# - 6 rooms listed under space
# - Each room has encryption enabled (lock icon)
```

## Error Handling Tests

### What happens on common failures

**Missing .env file:**
```bash
rm compose/.env
./scripts/bootstrap-admin.sh
# Output: "ERROR: /path/to/compose/.env not found. Copy .env.example to .env and fill in values."
# Exit code: 1
```

**Unset environment variable:**
```bash
unset ADMIN_PASSWORD
./scripts/bootstrap-admin.sh
# Output: "ERROR: ADMIN_PASSWORD is not set or still has a placeholder value in .env"
# Exit code: 1
```

**Docker not running:**
```bash
docker compose down
./scripts/backup.sh
# Output: "ERROR: Cannot connect to Docker daemon"
# Exit code: 1 (from docker compose command)
```

**GPG encryption failure:**
```bash
# With invalid passphrase or corrupted data
./scripts/restore.sh backup.tar.gz.gpg
# Output: "gpg: decryption failed: Bad session key"
# Exit code: 1
```

**Non-destructive failures (warnings, not errors):**
```bash
# From backup.sh, if media volume not found:
# Output: "WARNING: Media volume not found, skipping."
# Backup still completes with exit code 0 (partial success)
```

## Coverage Analysis

### What is tested

- **High coverage:** Environment setup, file operations, Docker integration
- **Medium coverage:** Error paths (via script error handling)
- **Low coverage:** Synapse internals, Element UI, PostgreSQL internals (delegated to upstream)

### What is not tested

- Unit tests for script functions (scripts are procedural, not modular)
- Integration tests for multi-user scenarios (manual only)
- Load/performance testing (not in scope for Phase 1)
- Security penetration testing (recommend external audit for production)

### Coverage gaps & recommendations

**Gap 1 — No automated script testing**
- Scripts validated only through manual runs
- Recommendation: Create simple shell test harness (Phase 2+)
- Impact: Medium (catches breaking changes late)

**Gap 2 — No E2EE encryption validation**
- Only manual client testing
- Recommendation: Use test bot with encryption support
- Impact: Medium (E2EE is core feature)

**Gap 3 — No backup recovery rehearsal**
- Restore tested manually once; not regularly
- Recommendation: Monthly restore-from-backup test
- Impact: High (untested recovery = data loss risk)

## Manual Testing Checklist

### Pre-deployment (Phase 1 completion)

```
□ DNS records resolve correctly (dig, nslookup)
□ TLS certificates installed in Nginx volume
□ .env all placeholders replaced
□ synapse/homeserver.yaml all __PLACEHOLDER__ replaced
□ Docker Compose builds and starts: docker compose up -d
□ All services healthy: docker compose ps
□ Element loads at https://chat.example.com
□ .well-known/matrix/client returns valid JSON
□ .well-known/matrix/server returns valid JSON
□ Can register user with invite token
□ Can send message in public room
□ E2EE encrypts DM messages (green shield in Element)
□ TLS grade A on SSL Labs
□ Security headers present (curl -I https://chat.example.com)
```

### Post-deployment (Phase 2+ operational testing)

```
□ Daily backup runs: ls -lh backups/ shows recent file
□ Backup is encrypted: file backups/*.tar.gz.gpg shows "data"
□ Monthly: Restore from backup, verify data intact
□ Voice/video call works: Create call, verify media
□ Update Synapse: docker compose pull && docker compose up -d
□ Check logs for errors: docker compose logs -f synapse | grep ERROR
□ Certificate renewal works: Check cert expiry date
```

## Continuous Integration (Not Implemented)

**Current state:** No CI/CD pipeline

**Recommended additions (Phase 3+):**
- Pre-commit hooks (shellcheck, yamllint)
- Syntax validation (JSON, YAML, Nginx)
- Docker build test
- Integration test (spin up stack, verify endpoints)

**Tools to consider:**
- `shellcheck` — Bash linting
- `yamllint` — YAML validation
- `jsonlint` or `jq` — JSON validation
- `docker compose config` — Compose validation
- GitHub Actions — CI/CD runner

---

*Testing analysis: 2026-02-20*
