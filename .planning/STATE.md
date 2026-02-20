# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Users can access a branded, self-hosted chat platform where registration, messaging, and E2E encryption work end-to-end on AWS
**Current focus:** Phase 1 — AWS Infrastructure

## Current Position

Phase: 1 of 3 (AWS Infrastructure) — COMPLETE
Plan: 2 of 2 completed in current phase
Status: Phase 1 complete — ready to begin Phase 2 (Stack Configuration)
Last activity: 2026-02-20 — Plan 02 complete (all Phase 1 success criteria verified)

Progress: [████░░░░░░] 33% (2 of 6 plans across all phases)

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: ~5 min
- Total execution time: ~0.2 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-aws-infrastructure | 2 | ~9 min | ~5 min |

**Recent Trend:**
- Last 5 plans: 4 min, ~5 min
- Trend: baseline established

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

### Pending Todos

None yet.

### Blockers/Concerns

- [Pre-phase] `server_name` strategy unresolved: must decide on a stable logical name before Phase 3 begins (EC2 public hostname is impermanent without Elastic IP; options: public IP with EIP, short placeholder like `poc.internal`)
- [RESOLVED in Plan 01] Docker CE AL2023 `$releasever` issue: avoided entirely by using AL2023 built-in `dnf install docker` package instead of Docker CE CentOS repo
- [Pre-phase] Backup script IMDS hop limit: if backup runs inside a container, `aws ec2 modify-instance-metadata-options --http-put-response-hop-limit 2` is required for IAM credential access; verify which approach `backup.sh` uses

## Session Continuity

Last session: 2026-02-20
Stopped at: Completed 01-aws-infrastructure 01-02-PLAN.md — Phase 1 complete; all success criteria verified (SSH, Docker Compose v2, 30 GB disk, SG rules confirmed); Phase 2 (Stack Configuration) ready to begin
Resume file: None
