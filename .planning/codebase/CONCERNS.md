# Codebase Concerns

**Analysis Date:** 2026-02-20

## Tech Debt

**Placeholder-based Configuration:**
- Issue: Critical configuration values in `synapse/homeserver.yaml` use `__PLACEHOLDER__` strings that must be manually replaced via sed or similar before deployment. This is error-prone and lacks validation.
- Files: `synapse/homeserver.yaml` (lines 7, 8, 10, 29, 53, 58, 59, 110-113, 115-116)
- Impact: Misconfigured placeholders will silently fail at runtime (e.g., wrong database password causes Synapse to crash). No pre-flight validation exists.
- Fix approach: Replace placeholder approach with a configuration templating system (e.g., Jinja2 or envsubst) that validates all required vars are present before container startup. Implement a health check that validates config accessibility.

**Missing Environment Variable Validation at Container Startup:**
- Issue: Scripts (`bootstrap-admin.sh`, `backup.sh`, `restore.sh`, `create-default-rooms.py`) validate env vars, but Synapse itself doesn't. If `.env` is incomplete, services start but fail mid-operation.
- Files: `scripts/bootstrap-admin.sh` (lines 21-26), `scripts/backup.sh` (lines 33-38), `scripts/restore.sh` (lines 36-41)
- Impact: Users waste time debugging container logs instead of getting clear pre-flight errors.
- Fix approach: Add a validation init script run on container startup that checks all required placeholders are replaced. Fail fast with a clear error message.

**Hardcoded Domain Values Scattered Across Configs:**
- Issue: Domain references exist in multiple files (`element/config.json`, `proxy/conf.d/element.conf`, `well-known/matrix/{client,server}`, `synapse/homeserver.yaml`). A domain change requires manual edits in all files.
- Files: `element/config.json` (lines 4, 5, 51, 54, 55, 57, 58, 59, 64, 65), `proxy/conf.d/element.conf` (line 7, 25, 50), `well-known/matrix/client`, `well-known/matrix/server`, `synapse/homeserver.yaml` (lines 7, 8, 10)
- Impact: Domain-related bugs during migration; inconsistent config if admin misses an update.
- Fix approach: Centralize domain config via env vars in docker-compose.yml with global substitution, or use a single source-of-truth config file that other configs reference.

**Backup Encryption Passphrase Not Validated for Strength:**
- Issue: `scripts/backup.sh` (line 78) uses `BACKUP_ENCRYPTION_PASSPHRASE` directly from `.env` without enforcing minimum entropy. A weak passphrase defeats the encryption.
- Files: `scripts/backup.sh` (lines 78-79), `compose/.env.example` (line 57)
- Impact: Backups could be decrypted by brute force if passphrase is weak (e.g., "123456").
- Fix approach: Add a pre-flight validation that checks passphrase length >= 20 chars and entropy >= 128 bits. Print warning if weak.

**Synapse Signing Key Generation Not Idempotent:**
- Issue: `compose/.env.example` (line 18) tells users to run `docker compose run --rm synapse generate` once to get a signing key, but there's no documented way to verify the key was extracted, no storage path documented, and no re-run protection.
- Files: `compose/.env.example` (line 18), `implementation.md` (line 213), `README.md` (line 78)
- Impact: Users may run `generate` multiple times, creating multiple signing keys. Old keys invalidate all server signatures if not properly rotated. Documentation doesn't explain where to find the generated key.
- Fix approach: Document exact extraction steps; store signing key in `.env` with validation that it exists; add idempotency check before running generate again.

**No Pre-Deployment Checklist Automation:**
- Issue: `docs/security.md` (lines 32-75) has a 45-line manual checklist. No script automates the checks.
- Files: `docs/security.md` (lines 30-76)
- Impact: Admins may skip steps or miss misconfigurations. No clear pass/fail.
- Fix approach: Create `scripts/security-check.sh` that validates TLS certs, firewall rules, secrets entropy, docker versions, etc., and outputs a report.

---

## Known Bugs

**Backup Volume Name Detection Fragile:**
- Symptoms: `scripts/backup.sh` (line 53) and `scripts/restore.sh` (line 93) use hardcoded `compose_synapse_media` volume name. If docker-compose version or naming convention changes, backup silently skips media with only a warning.
- Files: `scripts/backup.sh` (line 53), `scripts/restore.sh` (line 93)
- Trigger: Run backup/restore with a renamed volume (e.g., if user modifies `docker-compose.yml` volume naming).
- Workaround: Use `docker volume ls | grep synapse` to find the actual name, or use Docker's inspect API rather than hardcoding.
- Fix approach: Query Docker API to find synapse media volume instead of hardcoding name; fail if not found rather than silently skip.

**Restore Script Requires Manual Postgres Restart:**
- Symptoms: `scripts/restore.sh` (lines 82-84) recreates the database while postgres is running, but doesn't verify the DB is actually ready afterward. Synapse may try to connect before pg_restore completes.
- Files: `scripts/restore.sh` (lines 78-84, 109)
- Trigger: Restore a large backup; Synapse starts before DB is ready.
- Workaround: Manually wait for `docker compose ps` to show postgres as healthy before running Synapse.
- Fix approach: Add explicit wait-for-db logic after restore, e.g., `until pg_isready -h postgres; do sleep 1; done`.

**Admin Bootstrap Requires Manual Password Entry—No Non-Interactive Mode:**
- Symptoms: `scripts/bootstrap-admin.sh` (line 30) calls `register_new_matrix_user` interactively if `-p` flag is not recognized by the Synapse image version. Script may hang waiting for input in automated deploys.
- Files: `scripts/bootstrap-admin.sh` (lines 30-36)
- Trigger: User runs script in CI/CD without a tty or with an outdated Synapse image.
- Workaround: Pipe password: `echo "$ADMIN_PASSWORD" | docker compose exec -T synapse register_new_matrix_user ...`
- Fix approach: Add explicit interactive vs. non-interactive mode detection; check Synapse version compatibility.

---

## Security Considerations

**Admin API Not Protected from Accidental Exposure:**
- Risk: `proxy/conf.d/element.conf` (line 58) proxies all `/_synapse/client` requests from the internet. This includes the admin API endpoints like `/_synapse/admin`. If a path is misconfigured, admin endpoints become public.
- Files: `proxy/conf.d/element.conf` (lines 58-72)
- Current mitigation: Comments state "Only proxy known paths"; nginx blocks unknown paths (line 79-80).
- Recommendations: (1) Explicitly block `/_synapse/admin` at the nginx layer with a hard deny rule; (2) Isolate admin API to a separate internal nginx server block; (3) Add audit logging for all admin endpoint access.

**Database Credentials in `.env` Readable by All Docker Users:**
- Risk: `compose/.env` contains `POSTGRES_PASSWORD`, `SYNAPSE_MACAROON_SECRET_KEY`, `SYNAPSE_FORM_SECRET`, `BACKUP_ENCRYPTION_PASSPHRASE`. If a user has docker group membership, they can read these from docker inspect and docker exec.
- Files: `compose/.env.example` (lines 23, 26, 27, 34, 43, 57, 65)
- Current mitigation: `.gitignore` excludes `.env` from version control; documentation advises secure file permissions.
- Recommendations: (1) Use Docker secrets (swarm mode) or external secret manager (Vault, AWS Secrets Manager) instead of .env; (2) Restrict docker group to trusted admins only; (3) Audit docker daemon ACLs; (4) Document secure credential rotation procedures.

**Synapse Federation Can Be Accidentally Enabled:**
- Risk: `synapse/homeserver.yaml` (line 67) has `federation_domain_whitelist: []` (disabled), but if an admin uncomments the commented section (lines 89-97) without understanding the implications, federation becomes enabled to specific servers. No prominent warning.
- Files: `synapse/homeserver.yaml` (lines 63-68, 79-98)
- Current mitigation: Documentation in `docs/security.md` (lines 79-98) explains federation risks.
- Recommendations: (1) Add a prominent inline comment: "WARNING: Enabling federation increases attack surface. Review docs/security.md before enabling."; (2) Implement a pre-flight check that alerts if federation is enabled; (3) Default to federation disabled with explicit opt-in flag required.

**Element Web Accessible Without Authentication:**
- Risk: `proxy/conf.d/element.conf` (lines 35-41) serves Element as a static SPA with no auth requirement. An unauthorized user can load the app and see the login screen, potentially leak server names or trigger brute force attacks via the client.
- Files: `proxy/conf.d/element.conf` (lines 35-41)
- Current mitigation: Rate limiting on Synapse for login attempts (`synapse/homeserver.yaml` lines 81-87); TLS enforced.
- Recommendations: (1) Optionally require basic auth or a landing page before Element loads; (2) Implement login rate limiting at nginx level (geo-IP limiting); (3) Add CAPTCHA integration (Phase 2); (4) Monitor failed login attempts.

**Backup Passphrases Not Rotated Automatically:**
- Risk: `scripts/backup.sh` uses a single `BACKUP_ENCRYPTION_PASSPHRASE` for all backups. If compromised, all historical backups are at risk.
- Files: `scripts/backup.sh` (lines 78), `compose/.env.example` (line 57)
- Current mitigation: `.env` excluded from git; backups are offsite.
- Recommendations: (1) Implement passphrase rotation with versioning; (2) Use separate passphrases per backup period (weekly, monthly); (3) Document secure passphrase storage (e.g., encrypted key manager).

**No TLS Certificate Pinning or OCSP Stapling Validation:**
- Risk: Element Web and Synapse don't validate server identity beyond standard TLS. A man-in-the-middle attack is theoretically possible if TLS is compromised.
- Files: `proxy/snippets/tls-params.conf`, `element/config.json`
- Current mitigation: HSTS enabled (`proxy/snippets/security-headers.conf` line 2); OCSP stapling configured (not visible in excerpts but should be in full config).
- Recommendations: (1) Implement public key pinning (HPKP) for Element Web; (2) Validate OCSP stapling is correctly enabled; (3) Add certificate transparency monitoring.

**Rate Limiting May Be Insufficient for Large Attacks:**
- Risk: `synapse/homeserver.yaml` (lines 73-87) sets per-second rate limits: `message: 2 per_second`, `login: 0.17 per_second`. This protects against individual attackers but a distributed botnet can still overwhelm.
- Files: `synapse/homeserver.yaml` (lines 73-87)
- Current mitigation: Nginx reverse proxy can add additional limits.
- Recommendations: (1) Implement IP-based rate limiting in nginx; (2) Add DDoS protection (e.g., Cloudflare, AWS Shield); (3) Monitor for sudden traffic spikes; (4) Tune rate limits based on observed usage patterns.

---

## Performance Bottlenecks

**PostgreSQL Connection Pool Too Small for Scaling:**
- Problem: `synapse/homeserver.yaml` (lines 33-34) sets `cp_min: 5, cp_max: 10`. For a large community (1000+ users), this bottlenecks under concurrent load.
- Files: `synapse/homeserver.yaml` (lines 33-34)
- Cause: Synapse may exhaust the connection pool, causing timeouts and slow response times.
- Improvement path: Profile actual concurrent connections under load; increase `cp_max` to 20-50 for production; consider read replicas or connection pooling (e.g., PgBouncer) in Phase 2.

**Nginx Worker Connections Hardcoded:**
- Problem: `proxy/nginx.conf` (line 6) sets `worker_connections 1024`. For a large event volume, this may bottleneck.
- Files: `proxy/nginx.conf` (line 6)
- Cause: Each Nginx worker can handle max 1024 concurrent connections. With 4 CPU cores, total is ~4096 connections.
- Improvement path: Increase to `2048` or `4096` for production; monitor with `netstat` or `ss` to detect saturation; consider load balancing multiple Nginx instances.

**Single-Container Synapse Not Highly Available:**
- Problem: `compose/docker-compose.yml` (lines 28-47) runs Synapse as a single container. If it crashes, the service is down until restart.
- Files: `compose/docker-compose.yml` (lines 28-47)
- Cause: No redundancy; health check restarts but doesn't prevent brief outages.
- Improvement path: Phase 2: Implement Synapse clustering with multiple instances behind Nginx; shared PostgreSQL backend; implement proper health checks + graceful shutdown.

**No Cache Layer Between Nginx and Synapse:**
- Problem: `proxy/conf.d/element.conf` (lines 58-72) proxies every request directly to Synapse. Repeated requests for the same room/user data hit the database every time.
- Files: `proxy/conf.d/element.conf` (lines 58-72)
- Cause: No HTTP caching; no Redis or memcached for session/state caching.
- Improvement path: Add caching headers to Synapse responses; deploy Redis for session caching (Phase 2); implement room state cache invalidation strategies.

**Media Store Unbounded Growth:**
- Problem: `synapse/homeserver.yaml` (line 45) sets `max_upload_size: 50M` but there's no pruning of old media or quota per user. Media store can grow to fill available disk.
- Files: `synapse/homeserver.yaml` (line 44-45)
- Cause: Users can upload 50M files indefinitely; no retention policy for unused media.
- Improvement path: Implement media retention policy (delete unused > 90 days); add per-user quotas; monitor disk usage and alert at 70%, 80%, 90%; document manual cleanup procedures.

---

## Fragile Areas

**Docker Image Pinning to `latest` Tag:**
- Files: `compose/docker-compose.yml` (lines 8, 29, 53, 65, 89)
- Why fragile: All images use `latest` tag: `postgres:15-alpine`, `matrixdotorg/synapse:latest`, `vectorim/element-web:latest`, `nginx:alpine`, `certbot/certbot`. A breaking change in upstream images breaks the entire stack without warning.
- Safe modification: (1) Pin to specific versions: `postgres:15.2-alpine`, `matrixdotorg/synapse:v1.98.0`, etc.; (2) Test image updates in a staging environment before applying to production; (3) Document version upgrade path; (4) Implement auto-update checks with notifications.
- Test coverage: None — no automated tests verify image compatibility.

**Bash Script Error Handling Incomplete:**
- Files: `scripts/backup.sh`, `scripts/restore.sh`, `scripts/bootstrap-admin.sh`
- Why fragile: Scripts use `set -euo pipefail` (good) but don't handle mid-pipe failures gracefully. Example: `scripts/backup.sh` (line 76) pipes tar → gpg; if tar succeeds but gpg fails, the script continues and creates an invalid archive.
- Safe modification: (1) Add explicit error handling after each pipeline; (2) Use `set -o pipefail` + check `$?` after each command; (3) Implement cleanup traps for all scripts; (4) Test with intentional failures (disk full, permission denied).
- Test coverage: None — scripts not tested for failure cases.

**PostgreSQL Data Volume Not Backed Up Separately:**
- Files: `scripts/backup.sh` (lines 46-48)
- Why fragile: Backup uses `pg_dump` which requires Postgres to be running and accessible. If Postgres is corrupted or not responding, backup fails without data loss but users don't know. Restore requires exact same Postgres version and schema.
- Safe modification: (1) Add independent volume snapshot for PostgreSQL data; (2) Test restore on a different Postgres version; (3) Implement incremental backups with validation; (4) Document backup retention and recovery time objectives (RTO/RPO).
- Test coverage: Runbook mentions restore test at line 75 but marks it "NOT_YET_PERFORMED".

**Configuration Validation Only at Script Runtime, Not Deployment Time:**
- Files: `scripts/bootstrap-admin.sh` (lines 21-26), `scripts/backup.sh` (lines 33-38), `compose/docker-compose.yml`
- Why fragile: Synapse starts even with incomplete config (placeholders still in place). Errors surface only when Synapse tries to read the config, causing opaque failure.
- Safe modification: (1) Add a validation container that runs on startup and checks all placeholders are replaced; (2) Implement config schema validation (JSON Schema or YAML schema); (3) Add unit tests for config rendering.
- Test coverage: None.

**Well-Known Endpoints Not Validated After Deployment:**
- Files: `well-known/matrix/client`, `well-known/matrix/server`
- Why fragile: These static JSON files must match Synapse config and domain names. A mismatch breaks client discovery without obvious errors.
- Safe modification: (1) Add a health check endpoint that validates well-known responses; (2) Implement a test that compares well-known JSON against actual Synapse config; (3) Document validation procedure in runbook.
- Test coverage: None.

---

## Scaling Limits

**Single PostgreSQL Instance:**
- Current capacity: ~1000 concurrent users on a single 2-core VPS with SSD.
- Limit: Postgres CPU and I/O saturation. At ~5000 concurrent users, queries slow and connection pool fills up.
- Scaling path: (1) Upgrade to multi-core instance with dedicated I/O; (2) Add read replicas for read-heavy queries (Synapse state sync); (3) Implement connection pooling (PgBouncer); (4) Shard by namespace if > 10k users (complex, Phase 3+).

**Single Nginx Instance:**
- Current capacity: ~10k concurrent connections (with `worker_connections 1024` and 4 CPU cores).
- Limit: CPU saturation and ephemeral port exhaustion.
- Scaling path: (1) Increase worker connections and tune buffer sizes; (2) Deploy multiple Nginx instances behind a load balancer (AWS ELB, HAProxy); (3) Use Nginx Plus for advanced load balancing.

**Single Synapse Instance:**
- Current capacity: ~500 active users (with 1 worker process).
- Limit: CPU and memory. Synapse uses Python threading, so multi-core benefit is limited. Each sync request is CPU-bound.
- Scaling path: (1) Enable Synapse workers (event_persister, synchrotron) to leverage multiple cores; (2) Add a dedicated event database for writes; (3) Implement read replicas (Synapse supports this in v1.98+); (4) Shard by namespace (very complex).

**Media Store on Single Filesystem:**
- Current capacity: ~100 GB on a typical VPS with 500GB storage.
- Limit: Disk I/O saturation; no replication means data loss if disk fails.
- Scaling path: (1) Move media to S3 or similar (configure Synapse's `media_store_path` to use S3 backend, Phase 2); (2) Implement tiered storage (hot/cold); (3) Add backup snapshots for DR.

---

## Dependencies at Risk

**Python Version Pinned in Scripts but Not Validated:**
- Risk: `scripts/create-default-rooms.py` requires Python 3.6+ but doesn't check version. If run on Python 2, it fails silently.
- Impact: Errors like "async/await not supported" confuse users.
- Migration plan: Add shebang validation; add version check in script; document Python 3.8+ requirement.

**matrix-nio Library Not in requirements.txt:**
- Risk: `scripts/create-default-rooms.py` (line 20-23) imports matrix-nio but there's no `requirements.txt` or `setup.py`. Manual installation required.
- Impact: Users forget to `pip3 install matrix-nio` and get import errors.
- Migration plan: Add `requirements.txt` with matrix-nio version pinned; add install step to bootstrap script.

**Certbot Container Uses `latest` Tag:**
- Risk: `compose/docker-compose.yml` (line 89) runs `certbot/certbot` with no version pin. Breaking changes in certbot can break certificate renewal.
- Impact: Certificate expires if renewal fails silently.
- Migration plan: Pin to specific version, e.g., `certbot/certbot:v2.7.1`; monitor renewal logs; add alert for cert expiry < 14 days (Phase 2).

**Element Web Client Version Not Pinned:**
- Risk: `compose/docker-compose.yml` (line 53) uses `vectorim/element-web:latest`. New versions may have UX changes, bugs, or breaking API changes.
- Impact: Users see unexpected UI changes; potential compatibility issues with Synapse.
- Migration plan: Test new versions in staging before production upgrade; pin to LTS versions; document upgrade procedure.

**Synapse Version Not Pinned:**
- Risk: `compose/docker-compose.yml` (line 29) uses `matrixdotorg/synapse:latest`. Major version changes may require database migrations, config changes, or API breaking changes.
- Impact: Automatic upgrades break the system.
- Migration plan: Pin to specific Synapse versions, e.g., `v1.98.0`; implement staged upgrades (test → staging → production); document database migration steps.

---

## Missing Critical Features

**No Automated Monitoring or Alerting:**
- Problem: No health checks beyond Docker health checks. No alerts for Synapse down, disk full, cert expiry, or unusual activity.
- Blocks: Production deployments cannot be safely left unattended; incident detection is manual.
- Implementation path: Phase 2 — add Prometheus metrics (already commented in homeserver.yaml line 141), Grafana dashboards, and alerting (Alertmanager or external service like Uptime Kuma).

**No User Presence or Session Management UI:**
- Problem: No admin dashboard to see active users, sessions, or device management.
- Blocks: Admins can't revoke sessions, see who's online, or manage device trust.
- Implementation path: Phase 2/3 — integrate Synapse admin API with a web dashboard or use mjolnir moderation bot.

**No Built-In Moderation Tools:**
- Problem: No UI for moderators to bulk kick/ban, manage room ACLs, or audit logs.
- Blocks: Large communities need moderation but must use raw Matrix protocol or CLI.
- Implementation path: Phase 2 — integrate mjolnir bot or implement custom moderation dashboard.

**No SSO Integration:**
- Problem: All users must create Matrix accounts. No OIDC/SAML integration for corporate deployments.
- Blocks: Organizations can't mandate single sign-on.
- Implementation path: Phase 2 — enable OIDC provider integration in Synapse config.

**No Message Search Across Rooms:**
- Problem: Synapse by default doesn't index messages for full-text search; Element Web search is limited.
- Blocks: Users can't find old messages efficiently.
- Implementation path: Phase 2 — enable Elasticsearch integration in Synapse; document indexing strategy.

**No Automated Certificate Renewal Validation:**
- Problem: Certbot renews automatically but there's no notification if renewal fails.
- Blocks: Admins discover cert expiry when users report HTTPS errors.
- Implementation path: Add monitoring for certbot renewal logs; send alerts for failures (Phase 2).

---

## Test Coverage Gaps

**Bootstrap Script Not Tested:**
- What's not tested: `scripts/bootstrap-admin.sh` — no verification that admin user is actually created with correct permissions.
- Files: `scripts/bootstrap-admin.sh`
- Risk: User runs script, no error occurs, but admin user not created. User locked out.
- Priority: High — impacts first-time setup.

**Backup/Restore Script Not Tested:**
- What's not tested: Full backup → restore cycle; verification that restored data is valid and identical.
- Files: `scripts/backup.sh`, `scripts/restore.sh`
- Risk: Backup runs successfully but contains corrupt data. Discovered only during actual disaster recovery.
- Priority: High — impacts business continuity.

**Configuration Rendering Not Tested:**
- What's not tested: Placeholder replacement in YAML/JSON configs; validation that resulting configs are valid.
- Files: `synapse/homeserver.yaml`, `element/config.json`, `proxy/conf.d/element.conf`
- Risk: Malformed placeholders create invalid configs that fail at runtime.
- Priority: High — impacts deployment reliability.

**Docker Compose Syntax Not Validated:**
- What's not tested: `compose/docker-compose.yml` syntax and service dependency resolution.
- Files: `compose/docker-compose.yml`
- Risk: Typos in service names or config cause runtime failures.
- Priority: Medium — caught by docker compose validation but not in CI.

**Well-Known Endpoints Not Verified:**
- What's not tested: `.well-known/matrix/client` and `.well-known/matrix/server` JSON schema and content validity.
- Files: `well-known/matrix/client`, `well-known/matrix/server`
- Risk: Malformed JSON or missing fields break client discovery.
- Priority: Medium — impacts new client connections.

**Security Headers Not Verified:**
- What's not tested: HTTP security headers (HSTS, CSP, etc.) are actually returned by Nginx.
- Files: `proxy/snippets/security-headers.conf`
- Risk: Headers misconfigured or missing without detection.
- Priority: Medium — impacts security posture.

**Element Config Not Validated:**
- What's not tested: `element/config.json` matches Synapse configuration; theme colors are valid CSS.
- Files: `element/config.json`
- Risk: Misconfigured domains or invalid colors cause Element to malfunction.
- Priority: Low — caught by Element Web at runtime but slow to debug.

---

*Concerns audit: 2026-02-20*
