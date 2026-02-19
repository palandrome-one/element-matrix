# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Users can access a branded, self-hosted chat platform where registration, messaging, and E2E encryption work end-to-end on AWS
**Current focus:** Phase 1 — AWS Infrastructure

## Current Position

Phase: 1 of 3 (AWS Infrastructure)
Plan: 1 of 2 completed in current phase
Status: In progress — Plan 01 complete, Plan 02 pending
Last activity: 2026-02-20 — Plan 01 complete (EC2 instance running)

Progress: [██░░░░░░░░] 17% (1 of 6 plans across all phases)

## Performance Metrics

**Velocity:**
- Total plans completed: 1
- Average duration: 4 min
- Total execution time: 0.1 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-aws-infrastructure | 1 | 4 min | 4 min |

**Recent Trend:**
- Last 5 plans: 4 min
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

### Pending Todos

None yet.

### Blockers/Concerns

- [Pre-phase] `server_name` strategy unresolved: must decide on a stable logical name before Phase 3 begins (EC2 public hostname is impermanent without Elastic IP; options: public IP with EIP, short placeholder like `poc.internal`)
- [RESOLVED in Plan 01] Docker CE AL2023 `$releasever` issue: avoided entirely by using AL2023 built-in `dnf install docker` package instead of Docker CE CentOS repo
- [Pre-phase] Backup script IMDS hop limit: if backup runs inside a container, `aws ec2 modify-instance-metadata-options --http-put-response-hop-limit 2` is required for IAM credential access; verify which approach `backup.sh` uses

## Session Continuity

Last session: 2026-02-20
Stopped at: Completed 01-aws-infrastructure 01-01-PLAN.md — EC2 instance i-0788240f8e1ae5807 running in us-east-1; Plan 02 (Matrix stack deploy) ready to begin
Resume file: None
