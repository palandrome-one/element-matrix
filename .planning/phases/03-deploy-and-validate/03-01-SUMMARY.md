---
phase: 03-deploy-and-validate
plan: 01
subsystem: infra
tags: [docker-compose, synapse, matrix, ec2, aws, nginx, element-web, postgresql]

# Dependency graph
requires:
  - phase: 02-stack-configuration
    provides: "All config files with __EC2_HOSTNAME__ placeholders, homeserver.yaml, element config.json, nginx conf, well-known files"
  - phase: 01-aws-infrastructure
    provides: "Running EC2 instance with Docker Engine v25 and Compose v5, security group, SSH key"
provides:
  - "Running Docker Compose stack on EC2 with all four services (postgres, synapse, nginx, element)"
  - "Synapse signing key generated at /data/signing.key in synapse_data volume"
  - "compose/.env with real secrets (postgres password, macaroon key, form secret, shared secret)"
  - "All config files with __EC2_HOSTNAME__ replaced with ec2-23-20-14-90.compute-1.amazonaws.com"
  - "Element Web accessible at http://ec2-23-20-14-90.compute-1.amazonaws.com"
  - "Synapse API responding at /_matrix/client/v3/login with m.login.password flow"
affects:
  - 03-02 (admin bootstrap reads ADMIN_USER/ADMIN_PASSWORD from compose/.env)
  - 03-03 (E2EE verification requires running stack from this plan)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "homeserver.yaml secret substitution: sed replaces all __PLACEHOLDER__ patterns from .env values on EC2"
    - "Synapse signing key generation: docker compose run --rm synapse generate (requires report_stats in existing homeserver.yaml)"
    - "EC2 hostname discovery: IMDSv2 token-gated curl to 169.254.169.254/latest/meta-data/public-hostname"

key-files:
  created: []
  modified:
    - "synapse/homeserver.yaml — added report_stats: false (required by synapse generate)"
    - "compose/.env (on EC2 only, gitignored) — filled with real secrets and ec2 hostname"
    - "synapse/homeserver.yaml (on EC2 only) — all placeholders substituted"

key-decisions:
  - "report_stats: false must be in homeserver.yaml before synapse generate — generate mode exits with error if the key is absent"
  - "Security group IP update automated (Rule 3): IP rotated from 96.9.84.206 to 203.144.79.142; both IPs authorized in SG to handle load-balanced NAT"
  - "homeserver.yaml secrets substituted via sed on EC2 from .env values, not via docker-compose variable substitution, because homeserver.yaml is a read-only bind mount (cannot pass secrets as environment vars to synapse)"
  - "ADMIN_USER=admin, ADMIN_PASSWORD=5489a89c667a4f298c922fde44fd3727 — saved for Plan 03-02 bootstrap and Plan 03-03 E2EE verification"

patterns-established:
  - "EC2 deploy sequence: rsync (exclude .git/.planning) -> sed substitution -> .env fill -> synapse generate -> docker compose up"
  - "All secret substitution must complete before first docker compose up — server_name is baked into postgres DB on first Synapse startup"

requirements-completed: [STACK-06]

# Metrics
duration: 6min
completed: 2026-02-20
---

# Phase 3 Plan 01: Deploy Stack to EC2 Summary

**All four Docker Compose services running on EC2 (postgres healthy, synapse healthy, element healthy, nginx up) with Element Web at http://ec2-23-20-14-90.compute-1.amazonaws.com and Synapse API responding with m.login.password flows**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-20T05:01:19Z
- **Completed:** 2026-02-20T05:07:40Z
- **Tasks:** 2
- **Files modified:** 1 local (homeserver.yaml), operational changes on EC2

## Accomplishments

- Transferred repo to EC2 via rsync (41 files, excluding .git, .planning, pem, instance-info.env)
- Substituted all `__EC2_HOSTNAME__` placeholders with `ec2-23-20-14-90.compute-1.amazonaws.com` across synapse/homeserver.yaml, element/config.json, well-known/matrix/client, well-known/matrix/server
- Filled compose/.env with generated secrets (POSTGRES_PASSWORD, SYNAPSE_REGISTRATION_SHARED_SECRET, SYNAPSE_MACAROON_SECRET_KEY, SYNAPSE_FORM_SECRET) and real admin credentials
- Generated Synapse Ed25519 signing key at /data/signing.key in synapse_data volume
- Started stack with `docker compose up -d`; all services became healthy within 30 seconds

## Task Commits

Each task was committed atomically:

1. **Task 1: Transfer repo to EC2, substitute placeholders, fill .env** - N/A (operational, no local file changes; all work done on EC2)
2. **Task 2: Generate Synapse signing key and start stack** - `76e57f3` (fix: add report_stats: false to homeserver.yaml)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `synapse/homeserver.yaml` — Added `report_stats: false` (required by Synapse generate mode; was missing from template)
- `compose/.env` (EC2 only, gitignored) — Generated with real secrets, ec2 hostname, admin credentials
- `scripts/aws/instance-info.env` (gitignored) — ADMIN_IP updated from 96.9.84.206 to 203.144.79.142

## Decisions Made

- `report_stats: false` added to homeserver.yaml template: Synapse's generate mode exits with an error if `report_stats` is missing from an existing homeserver.yaml. Added the key to prevent this on future deployments.
- Security group updated automatically: Current machine IP (203.144.79.142) differed from recorded admin IP (96.9.84.206). Both IPs authorized to handle load-balanced NAT routing.
- Secret substitution via sed on EC2: homeserver.yaml is a read-only bind mount in the compose file. Synapse cannot receive secrets via environment variables when SYNAPSE_CONFIG_PATH points to an existing file. sed substitution directly in the file was the correct approach.
- Admin credentials for subsequent plans: ADMIN_USER=admin, ADMIN_PASSWORD=5489a89c667a4f298c922fde44fd3727

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added report_stats: false to homeserver.yaml**
- **Found during:** Task 2 (Generate Synapse signing key)
- **Issue:** Synapse's generate mode exited with `CalledProcessError` because homeserver.yaml existed but lacked `report_stats`. The error message: "Please opt in or out of reporting homeserver usage statistics..."
- **Fix:** Added `report_stats: false` to `synapse/homeserver.yaml` in the local repo, rsynced the updated file to EC2, re-ran sed substitution, then retried `docker compose run --rm synapse generate`
- **Files modified:** `synapse/homeserver.yaml`
- **Verification:** `docker compose run --rm synapse generate` completed successfully: "Generating signing key file /data/signing.key"
- **Committed in:** `76e57f3`

**2. [Rule 3 - Blocking] Updated security group SSH rule for current IP**
- **Found during:** Task 1 (Transfer repo to EC2)
- **Issue:** SSH timed out because the recorded admin IP (96.9.84.206) no longer matched the current machine's public IP (203.144.79.142). The security group restricted port 22 to the old IP.
- **Fix:** Revoked the old /32 rule, authorized the current IP via `aws ec2 authorize-security-group-ingress`. Also updated `scripts/aws/instance-info.env` with the new ADMIN_IP value.
- **Files modified:** `scripts/aws/instance-info.env` (gitignored)
- **Verification:** SSH connection to ec2-23-20-14-90.compute-1.amazonaws.com succeeded
- **Committed in:** Not committed (instance-info.env is gitignored)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Both fixes necessary for execution. The report_stats fix corrects the homeserver.yaml template for all future deployments. The SG fix is a routine operational step when the admin machine IP changes.

## Issues Encountered

- EC2 public IP from `https://api.ipify.org` and `https://ifconfig.me` returned different IPs (`203.144.79.142` vs `203.144.75.142`) due to load-balanced NAT gateway. Both IPs were authorized in the security group. The `ipify.org` result was used as primary.
- The `compose/.env` `source` command failed on lines with `=C --lc-collate=C` and SMTP_FROM (space in value). The secrets were substituted directly via `sed` from grep-extracted values rather than sourcing the full .env, avoiding the issue.

## User Setup Required

The admin credentials generated for this deployment:
- **Admin username:** admin
- **Admin Matrix ID:** @admin:ec2-23-20-14-90.compute-1.amazonaws.com
- **Admin password:** 5489a89c667a4f298c922fde44fd3727
- **Login URL:** http://ec2-23-20-14-90.compute-1.amazonaws.com

These are needed for Plan 03-02 (bootstrap-admin.sh) and Plan 03-03 (E2EE verification).

## Next Phase Readiness

- STACK-06 satisfied: all four services running on EC2
- Plan 03-02 (admin bootstrap + room creation) can proceed immediately
- EC2 hostname: `ec2-23-20-14-90.compute-1.amazonaws.com`
- Synapse server_name: `ec2-23-20-14-90.compute-1.amazonaws.com` (baked into postgres DB — cannot change)
- No blockers for Plan 03-02

---
*Phase: 03-deploy-and-validate*
*Completed: 2026-02-20*
