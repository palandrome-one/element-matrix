# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Users can access a branded, self-hosted chat platform where registration, messaging, and E2E encryption work end-to-end on AWS
**Current focus:** Phase 2 — Stack Configuration

## Current Position

Phase: 2 of 3 (Stack Configuration) — COMPLETE
Plan: 2 of 2 completed in current phase
Status: Phase 2 complete — all application configs aligned to __EC2_HOSTNAME__ with HTTP and invite-only registration
Last activity: 2026-02-20 — Plan 02-02 complete (homeserver.yaml, config.json, well-known files updated for HTTP POC)

Progress: [███████░░░] 67% (4 of 6 plans across all phases)

## Performance Metrics

**Velocity:**
- Total plans completed: 4
- Average duration: ~3 min
- Total execution time: ~0.2 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-aws-infrastructure | 2 | ~9 min | ~5 min |
| 02-stack-configuration | 2 | ~4 min | ~2 min |

**Recent Trend:**
- Last 5 plans: 4 min, ~5 min, ~2 min, ~2 min
- Trend: fast execution on config-only plans

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

### Pending Todos

None yet.

### Blockers/Concerns

- [Pre-phase] `server_name` strategy: MITIGATED by server_name _ catch-all in Plan 01; still need to decide on stable hostname before Phase 3 smoke test (options: public IP with EIP, short placeholder like `poc.internal`)
- [RESOLVED in Plan 01] Docker CE AL2023 `$releasever` issue: avoided entirely by using AL2023 built-in `dnf install docker` package instead of Docker CE CentOS repo
- [Pre-phase] Backup script IMDS hop limit: if backup runs inside a container, `aws ec2 modify-instance-metadata-options --http-put-response-hop-limit 2` is required for IAM credential access; verify which approach `backup.sh` uses

## Session Continuity

Last session: 2026-02-20
Stopped at: Completed 02-stack-configuration 02-02-PLAN.md — Phase 2 complete; all app configs aligned to __EC2_HOSTNAME__ with HTTP (STACK-02 through STACK-05 satisfied); Phase 3 (Deployment) ready to begin
Resume file: None
