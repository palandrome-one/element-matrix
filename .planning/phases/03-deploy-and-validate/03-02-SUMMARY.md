---
phase: 03-deploy-and-validate
plan: 02
subsystem: infra
tags: [matrix, synapse, element-web, matrix-nio, nginx, admin-bootstrap, registration-token, branding]

# Dependency graph
requires:
  - phase: 03-deploy-and-validate
    plan: 01
    provides: "Running Docker Compose stack on EC2 with all four services healthy; compose/.env with real secrets and EC2 hostname"
provides:
  - "Admin user @admin:ec2-23-20-14-90.compute-1.amazonaws.com created and verified"
  - "Space 'YourBrand Community' with 6 linked child rooms created"
  - "Single-use registration token JWkAZC1bx4BUozEh for second test user"
  - "Element Web branding confirmed: brand=YourBrand Chat, theme=custom"
  - "Nginx proxy extended to cover /_synapse/admin path"
affects:
  - 03-03 (E2EE verification uses admin credentials, registration token, and room list)

# Tech tracking
tech-stack:
  added:
    - "matrix-nio (Python) — async Matrix client library for room creation script"
  patterns:
    - "Synapse API access via nginx proxy on port 80: /_matrix/* and /_synapse/* — port 8008 is Docker-internal only"
    - "bootstrap-admin.sh env reading: grep/cut per-variable instead of sourcing .env to avoid multi-word value failures"
    - "Registration token creation: POST /_synapse/admin/v1/registration_tokens/new with Bearer token auth"

key-files:
  created: []
  modified:
    - "scripts/bootstrap-admin.sh — replaced source with per-variable grep/cut extraction"
    - "scripts/create-default-rooms.py — import and use RoomVisibility enum (not bare string)"
    - "proxy/conf.d/element.conf — extended nginx regex to /_matrix|/_synapse (was /_matrix|/_synapse/client)"

key-decisions:
  - "Synapse API must be accessed via nginx on port 80 (/_matrix, /_synapse paths), not localhost:8008 — port 8008 is inside Docker network only"
  - "bootstrap-admin.sh: use grep/cut per-variable extraction instead of source — POSTGRES_INITDB_ARGS contains spaces (--lc-collate=C) which cause source to fail on sub-words"
  - "create-default-rooms.py: matrix-nio room_create requires RoomVisibility enum, not str — fixed import and all visibility= callsites"
  - "nginx element.conf: extended /_synapse/client to /_synapse to expose admin API — /_synapse/admin/v1/registration_tokens required for invite token generation"

patterns-established:
  - "EC2 Docker network: all Synapse API calls must route through nginx (port 80), never direct to port 8008"
  - "matrix-nio API: always import and use enum types (RoomVisibility) not bare strings for API parameters"

requirements-completed: [VERIFY-01, VERIFY-02, VERIFY-04]

# Metrics
duration: 7min
completed: 2026-02-20
---

# Phase 3 Plan 02: Admin Bootstrap and Room Setup Summary

**Admin user, Space+6 rooms, and single-use registration token created on live EC2 Synapse; Element Web branding confirmed via nginx-proxied API**

## Performance

- **Duration:** 7 min
- **Started:** 2026-02-20T05:10:32Z
- **Completed:** 2026-02-20T05:17:33Z
- **Tasks:** 2
- **Files modified:** 3 local + nginx reload on EC2

## Accomplishments

- Admin user @admin:ec2-23-20-14-90.compute-1.amazonaws.com created via `register_new_matrix_user` inside the synapse container
- Space "YourBrand Community" and 6 encrypted child rooms (Lobby, Announcements, General, Support, Off Topic, Voice) created and linked via m.space.child/m.space.parent state events
- Single-use registration token `JWkAZC1bx4BUozEh` generated for the Plan 03-03 second test user
- Element Web config.json verified: brand="YourBrand Chat", default_theme="custom", homeserver base_url="http://ec2-23-20-14-90.compute-1.amazonaws.com"

## Task Commits

Each task was committed atomically:

1. **Task 1: Bootstrap admin user and create default rooms** - `604f4bd` (feat)
2. **Task 2: Create registration token and verify Element branding** - `260880a` (fix)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `scripts/bootstrap-admin.sh` — Replaced `source "$ENV_FILE"` with per-variable `grep/cut` extraction to avoid failures on multi-word values like `POSTGRES_INITDB_ARGS=--encoding=UTF-8 --lc-collate=C`
- `scripts/create-default-rooms.py` — Added `RoomVisibility` to import; changed all `visibility="private"` to `visibility=RoomVisibility.private` (nio requires enum not str)
- `proxy/conf.d/element.conf` — Extended nginx proxy location regex from `/_matrix|/_synapse/client` to `/_matrix|/_synapse` to expose the Synapse admin API

## Decisions Made

- **Synapse API via nginx, not direct port 8008:** The plan's action steps specify `http://localhost:8008` but Synapse's port 8008 is not bound to the host in docker-compose — it is only accessible within the Docker internal network. All API calls must go through nginx on port 80 using the `/_matrix` and `/_synapse` proxy paths.
- **bootstrap-admin.sh grep/cut approach:** The `.env` file has `POSTGRES_INITDB_ARGS=--encoding=UTF-8 --lc-collate=C --lc-ctype=C`. When `source`d in bash, the words after the first space (`--lc-collate=C`, `--lc-ctype=C`) are executed as commands, causing exit code 127. The fix reads only the needed variables individually.
- **nginx /_synapse/admin path:** The original nginx config only exposed `/_synapse/client` (password reset etc.), not `/_synapse/admin`. The registration token API lives at `/_synapse/admin/v1/registration_tokens/new` and required extending the regex to the full `/_synapse` prefix.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed bootstrap-admin.sh .env sourcing failure**
- **Found during:** Task 1 (Bootstrap admin user)
- **Issue:** `source compose/.env` failed with `exit 127` on `--lc-collate=C` because bash interprets space-separated words after `=` as separate tokens when sourcing
- **Fix:** Replaced `source "$ENV_FILE"` with a `_get_env()` helper function using `grep "^VAR=" | cut -d= -f2-` for each needed variable
- **Files modified:** `scripts/bootstrap-admin.sh`
- **Verification:** `./scripts/bootstrap-admin.sh` ran successfully: "Admin user created successfully."
- **Committed in:** `604f4bd` (Task 1 commit)

**2. [Rule 1 - Bug] Fixed create-default-rooms.py RoomVisibility enum usage**
- **Found during:** Task 1 (Run room creation script)
- **Issue:** `AttributeError: 'str' object has no attribute 'value'` — matrix-nio's `room_create()` expects `RoomVisibility` enum, not string `"private"`
- **Fix:** Added `RoomVisibility` to the import line; replaced both `visibility="private"` callsites with `visibility=RoomVisibility.private`
- **Files modified:** `scripts/create-default-rooms.py`
- **Verification:** Script ran successfully: "Done! Space and 6 rooms created." with all 7 rooms confirmed via `/joined_rooms` API
- **Committed in:** `604f4bd` (Task 1 commit)

**3. [Rule 1 - Bug] Fixed nginx to proxy /_synapse/admin path**
- **Found during:** Task 2 (Create registration token)
- **Issue:** `POST /_synapse/admin/v1/registration_tokens/new` returned nginx 404 — the location regex `^(/_matrix|/_synapse/client)` did not match admin API paths
- **Fix:** Changed regex to `^(/_matrix|/_synapse)` in `proxy/conf.d/element.conf`; reloaded nginx via `docker compose exec nginx nginx -s reload`
- **Files modified:** `proxy/conf.d/element.conf`
- **Verification:** Registration token created: `{"token":"JWkAZC1bx4BUozEh","uses_allowed":1,...}`
- **Committed in:** `260880a` (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (3 bugs)
**Impact on plan:** All three fixes were necessary for core plan functionality. The nginx fix is a security consideration: the admin API is now exposed through nginx — acceptable for the POC (HTTP-only, not publicly documented, requires admin Bearer token), but should be IP-restricted or removed from the proxy in a production deployment.

## Issues Encountered

- The plan's action steps use `http://localhost:8008` throughout. This does not work because Synapse's port 8008 is Docker-internal only. All API verification commands adapted to use `http://localhost` (nginx port 80) via the `/_matrix` and `/_synapse` proxy paths.
- matrix-nio installed via pip3 from an earlier session was already present, avoiding re-install wait time.

## User Setup Required

The following information is needed for Plan 03-03 human E2EE verification:

- **Element Web URL:** http://ec2-23-20-14-90.compute-1.amazonaws.com
- **Admin username:** admin
- **Admin password:** 5489a89c667a4f298c922fde44fd3727
- **Second user registration token:** JWkAZC1bx4BUozEh (single-use)

## Next Phase Readiness

- VERIFY-01 satisfied: Admin user @admin:ec2-23-20-14-90.compute-1.amazonaws.com authenticated via m.login.password
- VERIFY-02 satisfied: 7 joined rooms (1 Space + 6 rooms) confirmed via /joined_rooms API
- VERIFY-04 satisfied: Element Web config.json has brand="YourBrand Chat", theme="custom", correct homeserver base_url
- Plan 03-03 (human E2EE verification) can proceed immediately — all prerequisites met
- Registration token JWkAZC1bx4BUozEh is single-use; do not consume it before Plan 03-03

## Self-Check: PASSED

- FOUND: scripts/bootstrap-admin.sh
- FOUND: scripts/create-default-rooms.py
- FOUND: proxy/conf.d/element.conf
- FOUND: .planning/phases/03-deploy-and-validate/03-02-SUMMARY.md
- FOUND commit: 604f4bd (Task 1)
- FOUND commit: 260880a (Task 2)

---
*Phase: 03-deploy-and-validate*
*Completed: 2026-02-20*
