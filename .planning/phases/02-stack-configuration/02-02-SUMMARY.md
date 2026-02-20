---
phase: 02-stack-configuration
plan: 02
subsystem: infra
tags: [synapse, matrix, element-web, well-known, homeserver, configuration]

# Dependency graph
requires:
  - phase: 01-aws-infrastructure
    provides: EC2 instance with Docker Compose v2 running, port 80 open
provides:
  - Synapse homeserver.yaml configured for HTTP POC with __EC2_HOSTNAME__ placeholder
  - enable_registration true with registration_requires_token true (invite-only)
  - Email block commented out to prevent Synapse startup crash
  - Element Web config.json pointing to http://__EC2_HOSTNAME__ with broken example.com links removed
  - well-known/matrix/client and server referencing __EC2_HOSTNAME__ over HTTP
affects:
  - 03-deployment (phase 3 substitutes __EC2_HOSTNAME__ placeholder with actual EC2 hostname)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "__EC2_HOSTNAME__ placeholder pattern: substituted at deploy time via sed/envsubst in phase 3"
    - "HTTP-only for POC: no TLS, all URLs use http:// protocol"
    - "Invite-only registration: enable_registration true + registration_requires_token true"

key-files:
  created: []
  modified:
    - synapse/homeserver.yaml
    - element/config.json
    - well-known/matrix/client
    - well-known/matrix/server

key-decisions:
  - "email block commented out rather than removed — preserves template for future SMTP configuration in production"
  - "terms_and_conditions_links and embedded_pages cleared to empty ([] and empty strings) — broken example.com URLs would show error links in Element UI"
  - "well-known/matrix/server uses port 80 explicitly — default server discovery port is 8448 (federation); explicit :80 routes all traffic correctly for POC"

patterns-established:
  - "__EC2_HOSTNAME__ placeholder: used consistently across all four config files as the single substitution target for deploy-time hostname injection"

requirements-completed: [STACK-02, STACK-03, STACK-04, STACK-05]

# Metrics
duration: 2min
completed: 2026-02-20
---

# Phase 02 Plan 02: Stack Configuration (Application Configs) Summary

**Synapse homeserver.yaml and Element config.json aligned to http://__EC2_HOSTNAME__ with invite-only registration enabled and email block disabled, plus well-known discovery files updated for HTTP POC**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-02-20T03:55:43Z
- **Completed:** 2026-02-20T03:57:23Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Synapse `server_name` and `public_baseurl` updated to `__EC2_HOSTNAME__` with `http://` — ready for Phase 3 placeholder substitution
- `enable_registration: true` with `registration_requires_token: true` — invite-only registration working without open signup
- Email block commented out — prevents Synapse crash on startup when SMTP values are placeholders
- Element `config.json` base_url, server_name, and permalink_prefix aligned to `http://__EC2_HOSTNAME__`; broken example.com links cleared
- `well-known/matrix/client` and `well-known/matrix/server` updated to reference POC hostname over HTTP with explicit port 80

## Task Commits

Each task was committed atomically:

1. **Task 1: Update Synapse homeserver.yaml for HTTP POC with registration enabled** - `cb29d0b` (feat)
2. **Task 2: Update Element config.json and well-known files for HTTP POC** - `0aad5f5` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `synapse/homeserver.yaml` - server_name, public_baseurl, web_client_location set to __EC2_HOSTNAME__; enable_registration true; email block commented out
- `element/config.json` - base_url and server_name set to __EC2_HOSTNAME__ with http://; permalink_prefix updated; broken example.com links emptied
- `well-known/matrix/client` - base_url set to http://__EC2_HOSTNAME__
- `well-known/matrix/server` - m.server set to __EC2_HOSTNAME__:80

## Decisions Made

- Email block commented out (not deleted): preserves the template structure for future production SMTP configuration — operator just uncomments and fills placeholders
- `terms_and_conditions_links` set to `[]` and `embedded_pages` set to empty strings: the URLs pointed to `example.com` which does not exist in this deployment; broken links in Element UI would confuse users
- `well-known/matrix/server` uses `__EC2_HOSTNAME__:80` with explicit port: default Matrix server discovery port is 8448 (federation); explicit `:80` ensures all traffic routes correctly through the single HTTP listener for the POC

## Deviations from Plan

None — plan executed exactly as written.

Note: `synapse/homeserver.yaml` retains one `https://` reference — the documentation URL in the file header comment (`# Docs: https://element-hq.github.io/...`). This is not a configuration value and was out of scope per the plan's "Do NOT change" directive for the file header.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required at this step. The `__EC2_HOSTNAME__` placeholder substitution happens in Phase 3 (deployment).

## Next Phase Readiness

- All four application config files are aligned and consistent: `__EC2_HOSTNAME__` placeholder appears in `synapse/homeserver.yaml` (3 occurrences), `element/config.json` (3 occurrences), `well-known/matrix/client` (1 occurrence), `well-known/matrix/server` (1 occurrence)
- Phase 3 (deployment) can substitute `__EC2_HOSTNAME__` with the actual EC2 public hostname via a single sed/envsubst pass across all four files
- Stack is ready to run: `docker compose up` will start Synapse, PostgreSQL, Nginx, and Element Web once Phase 3 hostname substitution is applied
- No blockers

---
*Phase: 02-stack-configuration*
*Completed: 2026-02-20*

## Self-Check: PASSED

- FOUND: synapse/homeserver.yaml
- FOUND: element/config.json
- FOUND: well-known/matrix/client
- FOUND: well-known/matrix/server
- FOUND: .planning/phases/02-stack-configuration/02-02-SUMMARY.md
- FOUND: cb29d0b (Task 1 commit)
- FOUND: 0aad5f5 (Task 2 commit)
