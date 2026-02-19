# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Users can access a branded, self-hosted chat platform where registration, messaging, and E2E encryption work end-to-end on AWS
**Current focus:** Phase 1 — AWS Infrastructure

## Current Position

Phase: 1 of 3 (AWS Infrastructure)
Plan: 0 of ? in current phase
Status: Ready to plan
Last activity: 2026-02-20 — Roadmap created

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Pre-phase: `server_name` must be finalized before first `docker compose up` — permanently baked into all user IDs; cannot be changed without dropping the database
- Pre-phase: No TLS for POC — EC2 public hostnames cannot receive Let's Encrypt certs; HTTP-only is intentional
- Pre-phase: Federation OFF — reduces attack surface; enable post-POC with whitelist once moderation tools exist

### Pending Todos

None yet.

### Blockers/Concerns

- [Pre-phase] `server_name` strategy unresolved: must decide on a stable logical name before Phase 3 begins (EC2 public hostname is impermanent without Elastic IP; options: public IP with EIP, short placeholder like `poc.internal`)
- [Pre-phase] Docker CE AL2023 install requires `$releasever` substitution workaround (`sed -i 's/$releasever/9/g'`) — not in official Docker docs; MEDIUM confidence; verify during Phase 1
- [Pre-phase] Backup script IMDS hop limit: if backup runs inside a container, `aws ec2 modify-instance-metadata-options --http-put-response-hop-limit 2` is required for IAM credential access; verify which approach `backup.sh` uses

## Session Continuity

Last session: 2026-02-20
Stopped at: Roadmap created, STATE.md initialized — ready to plan Phase 1
Resume file: None
