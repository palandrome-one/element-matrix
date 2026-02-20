---
phase: 02-stack-configuration
plan: 01
subsystem: infra
tags: [nginx, docker-compose, matrix, synapse, http-proxy]

# Dependency graph
requires:
  - phase: 01-aws-infrastructure
    provides: EC2 instance with Docker and Docker Compose installed, port 80 open
provides:
  - HTTP-only Nginx reverse proxy config with path-based routing to Synapse and Element
  - docker-compose.yml without certbot, without TLS ports — HTTP-only stack
  - proxy_pass to Synapse with no trailing slash (Matrix signature verification safe)
affects: [03-smoke-test, any phase that starts the Docker stack]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single server block with server_name _ catch-all — works with any EC2 public hostname"
    - "Path-based routing: /_matrix and /_synapse/client to Synapse, / to Element"
    - "proxy_pass with no trailing slash for Synapse (per official Synapse reverse_proxy.md)"

key-files:
  created: []
  modified:
    - proxy/conf.d/element.conf
    - proxy/nginx.conf
    - compose/docker-compose.yml

key-decisions:
  - "Use server_name _ catch-all to avoid hardcoding EC2 public hostname that may change between restarts"
  - "WebSocket upgrade headers preserved on Synapse location for Matrix sync endpoint"
  - "Nginx comment updated from 'reverse proxy + TLS' to 'reverse proxy — HTTP only for POC'"

patterns-established:
  - "HTTP-only POC pattern: single :80 block, catch-all server_name, path-based routing"

requirements-completed:
  - STACK-01

# Metrics
duration: 2min
completed: 2026-02-20
---

# Phase 2 Plan 01: Stack Configuration — HTTP-only Nginx Proxy Summary

**HTTP-only Nginx reverse proxy with path-based routing to Synapse (no trailing slash) and Element, docker-compose.yml stripped of certbot service and TLS ports**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-02-20T03:55:38Z
- **Completed:** 2026-02-20T03:57:30Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Replaced 4-server-block TLS config with single HTTP :80 server block using `server_name _` catch-all
- Removed certbot service, certbot volumes, and 443/8448 port mappings from docker-compose.yml
- Stripped `include tls-params.conf` from nginx.conf — no SSL directives in HTTP-only context

## Task Commits

Each task was committed atomically:

1. **Task 1: Replace Nginx element.conf with HTTP-only config and strip TLS from nginx.conf** - `71ae249` (feat)
2. **Task 2: Remove certbot service and TLS ports from docker-compose.yml** - `63944d5` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `proxy/conf.d/element.conf` - Replaced with single HTTP :80 server block; path-based routing to Synapse and Element; WebSocket headers on Synapse location; static .well-known with CORS
- `proxy/nginx.conf` - Removed `include /etc/nginx/snippets/tls-params.conf` line; all other config preserved
- `compose/docker-compose.yml` - Removed certbot service block, certbot volumes (certbot_conf, certbot_webroot), 443:443 and 8448:8448 port mappings; nginx comment updated

## Decisions Made
- `server_name _` catch-all chosen over specific hostname — EC2 public hostnames are impermanent without Elastic IP; catch-all ensures Nginx starts regardless of hostname
- WebSocket upgrade headers retained on Synapse location — Matrix sync long-polling uses HTTP upgrade; omitting breaks real-time updates
- Certbot volumes removed entirely (not just commented out) — prevents Docker from creating empty named volumes that would shadow future TLS setup in Phase 4+

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. The plan's verify command `grep -c "listen 80"` technically returns 1 (not 2 as documented) because `listen [::]:80;` doesn't contain the literal string "listen 80". Both IPv4 and IPv6 listen directives are present and correct. Plan documentation artifact, not a real issue.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Nginx and docker-compose.yml are HTTP-only POC ready
- Stack can be started with `cd compose && docker compose up -d` once Synapse homeserver.yaml is configured (Phase 2 Plan 02)
- No blockers for Phase 3 smoke test once remaining Phase 2 plans complete

## Self-Check: PASSED

- proxy/conf.d/element.conf: FOUND
- proxy/nginx.conf: FOUND
- compose/docker-compose.yml: FOUND
- 02-01-SUMMARY.md: FOUND
- Commit 71ae249 (Task 1): FOUND
- Commit 63944d5 (Task 2): FOUND

---
*Phase: 02-stack-configuration*
*Completed: 2026-02-20*
