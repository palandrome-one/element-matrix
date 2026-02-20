# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Users can access a branded, self-hosted chat platform where registration, messaging, and E2E encryption work end-to-end on AWS
**Current focus:** Phase 3 complete — ALL PHASES DONE

## Current Position

Phase: 3 of 3 (Deploy and Validate) — COMPLETE
Plan: 3 of 3 completed in current phase
Status: ALL PLANS COMPLETE — Human accepted POC end-to-end: VERIFY-01, VERIFY-02, VERIFY-03, VERIFY-04 all PASS
Last activity: 2026-02-20 — Plan 03-03 complete (human E2EE verification approved — admin login, Space+6 rooms, E2EE lock icon, YourBrand branding all confirmed in browser)

Progress: [██████████] 100% (7 of 7 plans across all phases)

## Performance Metrics

**Velocity:**
- Total plans completed: 7
- Average duration: ~4 min
- Total execution time: ~0.4 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-aws-infrastructure | 2 | ~9 min | ~5 min |
| 02-stack-configuration | 2 | ~4 min | ~2 min |
| 03-deploy-and-validate | 3 (of 3) | ~14 min | ~5 min |

**Recent Trend:**
- Last 5 plans: ~2 min, ~2 min, 6 min, 7 min, ~1 min (human checkpoint)
- Trend: human checkpoints are near-instant once user approves

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Pre-phase: `server_name` must be finalized before first `docker compose up` — permanently baked into all user IDs; cannot be changed without dropping the database
- Pre-phase: No TLS for POC — EC2 public hostnames cannot receive Let's Encrypt certs; HTTP-only is intentional
- Pre-phase: Federation OFF — reduces attack surface; enable post-POC with whitelist once moderation tools exist
- [Phase 01-aws-infrastructure]: Use AL2023 built-in dnf docker package instead of Docker CE CentOS repo to avoid releasever workaround
- [Phase 01-aws-infrastructure]: instance-info.env added to .gitignore — contains admin IP and instance IDs, must not be committed
- [Phase 01-aws-infrastructure]: Resolve AL2023 AMI via SSM parameter store (resolve:ssm:) to avoid hardcoded AMI IDs that expire
- [Phase 01-aws-infrastructure Plan 02]: Phase 1 verification complete — Docker Engine v25.0.14, Compose v5.0.2 (v2), 30 GB gp3, port 80 public, port 8008 blocked; NVMe naming (/dev/nvme0n1p1) is correct for Nitro instances
- [Phase 02-stack-configuration Plan 01]: Use server_name _ catch-all in Nginx — EC2 public hostnames are impermanent without Elastic IP; catch-all ensures Nginx starts regardless of hostname
- [Phase 02-stack-configuration Plan 01]: Certbot volumes removed entirely (not just commented out) — prevents Docker from creating empty named volumes that would shadow future TLS setup
- [Phase 02-stack-configuration Plan 01]: STACK-01 requirement satisfied — HTTP-only Nginx proxy with no trailing slash on Synapse proxy_pass
- [Phase 02-stack-configuration Plan 02]: email block commented out (not deleted) — preserves template for future SMTP, prevents Synapse crash on placeholder SMTP values
- [Phase 02-stack-configuration Plan 02]: well-known/matrix/server uses __EC2_HOSTNAME__:80 with explicit port — default Matrix server discovery is 8448 (federation); explicit :80 routes correctly for HTTP POC
- [Phase 02-stack-configuration Plan 02]: STACK-02, STACK-03, STACK-04, STACK-05 requirements satisfied — all configs aligned to __EC2_HOSTNAME__ with http://, invite-only registration enabled
- [Phase 03-deploy-and-validate Plan 01]: report_stats: false must be in homeserver.yaml before synapse generate — generate mode exits with error if the key is absent
- [Phase 03-deploy-and-validate Plan 01]: homeserver.yaml secret substitution done via sed on EC2 (not docker-compose env vars) — homeserver.yaml is a read-only bind mount; Synapse cannot receive secrets via environment variables when SYNAPSE_CONFIG_PATH points to existing file
- [Phase 03-deploy-and-validate Plan 01]: EC2 hostname = ec2-23-20-14-90.compute-1.amazonaws.com; server_name baked into postgres DB — cannot change without dropping DB
- [Phase 03-deploy-and-validate Plan 01]: ADMIN_USER=admin, ADMIN_PASSWORD=5489a89c667a4f298c922fde44fd3727 — needed for Plan 03-02 and Plan 03-03
- [Phase 03-deploy-and-validate Plan 02]: Synapse API access on EC2 must go through nginx on port 80 (/_matrix, /_synapse paths) — port 8008 is Docker-internal only, not bound to host
- [Phase 03-deploy-and-validate Plan 02]: bootstrap-admin.sh: use grep/cut per-variable extraction instead of source — POSTGRES_INITDB_ARGS has multi-word value that breaks bash source
- [Phase 03-deploy-and-validate Plan 02]: matrix-nio requires RoomVisibility enum not string — all visibility= args must use RoomVisibility.private/public
- [Phase 03-deploy-and-validate Plan 02]: nginx extended to /_synapse (not just /_synapse/client) — admin API at /_synapse/admin required for registration token creation
- [Phase 03-deploy-and-validate Plan 02]: Registration token JWkAZC1bx4BUozEh created (single-use) — for Plan 03-03 second user registration
- [Phase 03-deploy-and-validate Plan 03]: All four VERIFY requirements passed human acceptance in browser — VERIFY-01 (admin login), VERIFY-02 (Space+6 rooms), VERIFY-03 (E2EE lock icon), VERIFY-04 (YourBrand branding) all PASS

### Pending Todos

None. Project complete.

### Blockers/Concerns

- [RESOLVED in Plan 03-01] server_name strategy: resolved — server_name is ec2-23-20-14-90.compute-1.amazonaws.com, baked into DB
- [RESOLVED in Plan 01] Docker CE AL2023 `$releasever` issue: avoided entirely by using AL2023 built-in `dnf install docker` package instead of Docker CE CentOS repo
- [Pre-phase] Backup script IMDS hop limit: if backup runs inside a container, `aws ec2 modify-instance-metadata-options --http-put-response-hop-limit 2` is required for IAM credential access; verify which approach `backup.sh` uses
- [RESOLVED in Plan 03-02] bootstrap-admin.sh prints wrong login URL (https://chat.example.com) — resolved; script fixed to use grep/cut; login URL is http://ec2-23-20-14-90.compute-1.amazonaws.com

## Session Continuity

Last session: 2026-02-20
Stopped at: Completed 03-deploy-and-validate 03-03-PLAN.md — human E2EE verification approved; all VERIFY requirements PASS; Phase 3 complete; ALL PHASES DONE
Resume file: None
