# Phase 3: Deploy and Validate - Research

**Researched:** 2026-02-20
**Domain:** Docker Compose deployment, Synapse signing key generation, hostname substitution, admin bootstrap, Matrix E2EE validation
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| STACK-06 | `docker compose up -d` starts all services with healthy status on EC2 | Deploy sequence, `__EC2_HOSTNAME__` substitution via `sed`, Synapse signing key pre-generation, Docker healthchecks already defined in compose file |
| VERIFY-01 | Admin user created via bootstrap script and can log in at `http://<EC2-hostname>` | `register_new_matrix_user` command confirmed; `bootstrap-admin.sh` reads secrets from `.env`; login via Element Web at root path |
| VERIFY-02 | Default Space and rooms created and visible after login | `create-default-rooms.py` uses matrix-nio 0.25.2; `room_create(space=True)` supported; Space shown in left sidebar in Element |
| VERIFY-03 | Two users can exchange messages in a room with E2EE lock icon visible | `encryption_enabled_by_default_for_room_type: all` already in homeserver.yaml; admin must create a registration token for second user; E2EE lock appears on messages |
| VERIFY-04 | Branded Element UI loads with custom name, logo, and theme colors applied | `element/config.json` has `brand`, `custom_themes`, `default_theme`; logo mounted at `/app/themes/custom/img/logo.svg` |
</phase_requirements>

---

## Summary

Phase 3 is an operations phase, not a code-writing phase. All configs have been written and committed in Phases 1 and 2. The work is: (1) SCP the repo to EC2, (2) substitute the actual EC2 hostname for `__EC2_HOSTNAME__` in four config files and fill in secrets in `.env`, (3) generate Synapse's signing key, (4) start the stack, and (5) run the three verification scripts (bootstrap admin, create rooms, test E2EE with a second user).

The central critical dependency is the `__EC2_HOSTNAME__` substitution that must happen before any `docker compose` command runs. The EC2 public hostname (e.g., `ec2-23-20-14-90.compute-1.amazonaws.com`) is already recorded in `scripts/aws/instance-info.env` on the local machine. All four config files (`synapse/homeserver.yaml`, `element/config.json`, `well-known/matrix/client`, `well-known/matrix/server`) use this placeholder. A simple `sed` pass at deploy time replaces all occurrences with the real hostname. Critically, `server_name` is baked into the database on first `docker compose up` — if the placeholder is present when Synapse first starts, all user IDs will be permanently wrong.

The stack has healthchecks defined for postgres and synapse. Element and nginx have no explicit healthcheck in the compose file — `docker compose ps` will show them as "running" but not report a health status for those two. This is expected behavior: "healthy" status in `docker compose ps` only appears for services that define a `healthcheck` block. STACK-06's requirement "all services show healthy status" must be interpreted accurately: postgres and synapse will show `healthy`; element and nginx will show `running`. The plan must clarify this to the executor.

**Primary recommendation:** Transfer repo via SCP, substitute `__EC2_HOSTNAME__` with `sed` across all four placeholder files plus fill in `.env` secrets, generate signing key with `docker compose run --rm synapse generate` (uses `SYNAPSE_SERVER_NAME` env var from `.env`), then `docker compose up -d`, then run the three verification steps in sequence.

---

## Standard Stack

### Core — Already Decided, Versions Verified

| Component | Image/Version | Purpose | Status |
|-----------|--------------|---------|--------|
| Synapse | `matrixdotorg/synapse:latest` | Matrix homeserver | Already in compose file |
| PostgreSQL | `postgres:15-alpine` | Persistent database | Already in compose file |
| Element Web | `vectorim/element-web:latest` | React SPA web client | Already in compose file |
| Nginx | `nginx:alpine` | Reverse proxy, HTTP termination | Already in compose file |
| matrix-nio | `0.25.2` (pip) | Python Matrix client for room creation script | Used in `create-default-rooms.py` |

### Supporting — Operational Tools

| Tool | Purpose | When Used |
|------|---------|-----------|
| `sed` (GNU/BSD) | In-place substitution of `__EC2_HOSTNAME__` in config files | Before first `docker compose up` on EC2 |
| `openssl rand -hex 32` | Generate secret values for `.env` | Before deploy |
| `curl` (on EC2) | Used by Synapse healthcheck; also for manual verification | During verification |
| `register_new_matrix_user` | CLI tool bundled in Synapse image | Creating admin user |
| Registration Tokens API | `POST /_synapse/admin/v1/registration_tokens/new` | Creating second test user invite |
| `m.login.password` login API | `POST /_matrix/client/v3/login` | Getting admin access token for API calls |

### No Installation Needed

Docker Engine v25.0.14 and Docker Compose v5.0.2 are already installed on the EC2 instance (verified in Phase 1). Python 3 is available on AL2023 by default. matrix-nio must be installed with `pip3 install matrix-nio` on the EC2 instance before running `create-default-rooms.py`.

---

## Architecture Patterns

### Recommended Deploy Sequence

```
[local machine]
  1. source scripts/aws/instance-info.env         # get PUBLIC_DNS, KEY_FILE
  2. scp -r repo to EC2 ~/element-matrix           # transfer full repo
  3. ssh into EC2

[EC2 instance]
  4. cd ~/element-matrix
  5. cp compose/.env.example compose/.env          # create .env
  6. Edit compose/.env — fill in EC2 hostname and secrets
  7. sed -i "s/__EC2_HOSTNAME__/$EC2_HOST/g" \
       synapse/homeserver.yaml \
       element/config.json \
       well-known/matrix/client \
       well-known/matrix/server
  8. docker compose -f compose/docker-compose.yml run --rm \
       -e SYNAPSE_SERVER_NAME=$EC2_HOST \
       -e SYNAPSE_REPORT_STATS=no \
       synapse generate              # generates signing.key only (homeserver.yaml already exists)
  9. docker compose -f compose/docker-compose.yml up -d
  10. docker compose -f compose/docker-compose.yml ps  # confirm healthy
  11. ./scripts/bootstrap-admin.sh   # create admin user
  12. pip3 install matrix-nio && python3 ./scripts/create-default-rooms.py
  13. Create registration token via API
  14. Register second user via Element Web with token
  15. Exchange E2EE message, verify lock icon
```

### Pattern 1: `__EC2_HOSTNAME__` Substitution with `sed`

**What:** Replace all occurrences of the placeholder across four config files atomically before any Docker command runs.

**Command:**
```bash
EC2_HOST="ec2-23-20-14-90.compute-1.amazonaws.com"   # from instance-info.env or curl IMDS
sed -i "s/__EC2_HOSTNAME__/$EC2_HOST/g" \
  synapse/homeserver.yaml \
  element/config.json \
  well-known/matrix/client \
  well-known/matrix/server
```

**Verification after sed:**
```bash
grep "__EC2_HOSTNAME__" synapse/homeserver.yaml element/config.json well-known/matrix/client well-known/matrix/server
# Should return nothing — all placeholders replaced
grep "$EC2_HOST" synapse/homeserver.yaml | head -5
# Should show the actual hostname in all four config fields
```

**Critical:** This must run BEFORE `docker compose up -d`. The `server_name` in `homeserver.yaml` is baked into the database on first Synapse startup. Running with the placeholder still present makes all user IDs permanently `@user:__EC2_HOSTNAME__` — an unrecoverable error without dropping the DB.

**macOS note:** On macOS, `sed -i` requires an extension argument: `sed -i '' "s/__EC2_HOSTNAME__/$EC2_HOST/g"`. On AL2023 (Linux), `sed -i` works without the empty string. The substitution runs on EC2, so Linux `sed` applies.

### Pattern 2: Synapse Signing Key Generation

**What:** The `synapse generate` command creates the signing key at `/data/<server_name>.signing.key` in the `synapse_data` volume. The repo's `homeserver.yaml` already has `signing_key_path: "/data/signing.key"` — so the generated key will be at a path that matches the config.

**Key insight from research:** When `SYNAPSE_CONFIG_PATH` points to an existing file (`/data/homeserver.yaml`), the Docker generate mode does NOT overwrite the existing `homeserver.yaml` — it only generates the signing key and log config if they don't exist. (Source: Synapse Docker README — generate is designed to work with mounted configs.)

**Command (from repo root on EC2):**
```bash
docker compose -f compose/docker-compose.yml run --rm \
  -e SYNAPSE_SERVER_NAME="$EC2_HOST" \
  -e SYNAPSE_REPORT_STATS=no \
  synapse generate
```

The compose file already sets `SYNAPSE_CONFIG_PATH: /data/homeserver.yaml`, which points to the mounted `synapse/homeserver.yaml`. After generate, the `synapse_data` volume will contain `signing.key` and the Synapse run can proceed.

**Alternative if generate is problematic:** Generate the signing key manually:
```bash
docker compose -f compose/docker-compose.yml run --rm synapse \
  python -m synapse.app.homeserver \
  --config-path /data/homeserver.yaml \
  --generate-keys
```

### Pattern 3: Healthcheck Status Interpretation

**What:** `docker compose ps` shows health status for services with a `healthcheck` block. The compose file defines healthchecks only for `postgres` (pg_isready) and `synapse` (curl /health). `element` and `nginx` have no healthcheck defined.

**Expected `docker compose ps` output:**
```
NAME            STATUS              PORTS
element-matrix-nginx-1      running (healthy)    ... (actually NO health column)
element-matrix-element-1    running             (no health)
element-matrix-synapse-1    running (healthy)
element-matrix-postgres-1   running (healthy)
```

Wait: nginx and element have no healthcheck. They show `Up X minutes` without a `(healthy)` suffix. The correct reading of STACK-06 "all services show healthy status" is:
- postgres: `Up (healthy)` — has healthcheck
- synapse: `Up (healthy)` — has healthcheck
- element: `Up` — no healthcheck defined; "running" is success
- nginx: `Up` — no healthcheck defined; "running" is success

**How to verify nginx works:** `curl -s http://localhost/ | head -5` — should return Element Web HTML. This is the functional verification, not `docker compose ps`.

**Wait for synapse healthy:** Synapse takes 30-60 seconds to be ready on a fresh database (running migrations). Do not run `bootstrap-admin.sh` until synapse shows `(healthy)`:
```bash
docker compose -f compose/docker-compose.yml ps synapse
# Wait until STATUS shows (healthy)
```

### Pattern 4: Admin User Bootstrap

**What:** `bootstrap-admin.sh` runs `register_new_matrix_user` inside the running synapse container. It reads `ADMIN_USER`, `ADMIN_PASSWORD`, `SYNAPSE_REGISTRATION_SHARED_SECRET` from `compose/.env`.

**Source:** `scripts/bootstrap-admin.sh` — already in repo, uses `docker compose exec synapse register_new_matrix_user -u $ADMIN_USER -p $ADMIN_PASSWORD -a -c /data/homeserver.yaml http://localhost:8008`

**Prerequisite:** Synapse must be running and healthy before this runs.

**Run from repo root:**
```bash
./scripts/bootstrap-admin.sh
```

If it fails with "User already exists" (e.g., after a retry), that is OK — the admin user is already there.

### Pattern 5: Get Admin Access Token for API Calls

**What:** To call the registration token API to invite a second user, you need an admin access token. The standard `m.login.password` login endpoint returns one.

**Note on MAS:** The search result warning about `m.login.password` not having admin scope applies ONLY when Matrix Authentication Service (MAS) is deployed as a separate service. This POC uses standard Synapse without MAS. The `m.login.password` token gives full admin API access when the user is an admin.

```bash
ACCESS_TOKEN=$(curl -s -X POST \
  "http://localhost:8008/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"m.login.password\",\"user\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASSWORD\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
echo "Token: $ACCESS_TOKEN"
```

### Pattern 6: Create Registration Token for Second User

**What:** Create a single-use registration token so the second test user can register.

```bash
curl -s -X POST \
  "http://localhost:8008/_synapse/admin/v1/registration_tokens/new" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"uses_allowed": 1}' \
  | python3 -m json.tool
# Returns: {"token": "AbCdEfGh12345678", ...}
```

Share the printed token with the second user account. The second user enters it in Element Web's registration form.

### Pattern 7: E2EE Verification Flow

**What:** Two user accounts must exchange a message in an E2EE room and the lock icon must be visible.

**Setup:**
1. Admin creates a registration token (Pattern 6)
2. Second user account registers via Element Web (`http://$EC2_HOST`) using the token
3. Admin invites second user to an existing E2EE room (e.g., "General")
4. Second user accepts the invite and logs in via a different browser or incognito window
5. Both users send a message; the padlock icon appears on each message bubble

**What the lock icon looks like:** In Element Web, each message in an E2EE room shows a small padlock icon in the bottom-right corner of the message bubble. In current Element Web versions, hovering over messages may be required to see the icon. The rooms created by `create-default-rooms.py` are all E2EE-enabled (`m.room.encryption` initial state event with `m.megolm.v1.aes-sha2`).

**Key config already in place:** `encryption_enabled_by_default_for_room_type: "all"` in `homeserver.yaml` — any new room created on this server is E2EE by default.

**Troubleshooting:** If messages show a strikethrough padlock or "Unable to decrypt" error, this means the key exchange failed. This typically happens when the second user's client has not yet exchanged keys with the first user's client. Refreshing the page or waiting a few seconds usually resolves it on first message.

### Anti-Patterns to Avoid

- **Running `docker compose up` before sed substitution:** Leaves `__EC2_HOSTNAME__` as the `server_name` — permanently wrong user IDs in the database.
- **Running bootstrap-admin.sh before synapse is healthy:** `register_new_matrix_user` will fail with connection errors if Synapse's HTTP listener is not ready.
- **Using `docker compose up` from wrong directory:** Must specify `-f compose/docker-compose.yml` or run from `compose/` directory. The compose file is in `compose/`, not the repo root.
- **Forgetting to fill .env before generate:** The `SYNAPSE_REGISTRATION_SHARED_SECRET`, `POSTGRES_PASSWORD`, `MACAROON_SECRET_KEY`, and `FORM_SECRET` values in `.env` must be set before the stack starts, as they are read by homeserver.yaml at Synapse startup.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Admin user creation | Custom Python user registration script | `register_new_matrix_user` in Synapse image | Already bundled; handles shared secret signing correctly |
| Signing key generation | Manual `openssl` key generation | `docker compose run --rm synapse generate` | Synapse requires specific key format (`ed25519`); hand-rolled keys will fail |
| Hostname substitution across files | Per-file Python/awk scripts | Single `sed -i` command across all four files | One command, verifiable with grep; less error-prone |
| Invite flow | Email invite system | Registration token API | Email not configured; token flow works in Element Web natively |
| Secret generation | Hardcoded test values | `openssl rand -hex 32` | Random 32-byte hex strings are the documented format for `macaroon_secret_key` and `form_secret` |
| Space/room creation | Element Web UI clicks | `create-default-rooms.py` (matrix-nio) | Scripted; repeatable; already written and in repo |

**Key insight:** Every operational step in Phase 3 has an existing tool or script in the repo. The planner's job is to sequence those tools correctly, not build new ones.

---

## Common Pitfalls

### Pitfall 1: Placeholder Still Present When Synapse First Starts

**What goes wrong:** If `__EC2_HOSTNAME__` is still in `homeserver.yaml` when `docker compose up -d` runs for the first time, Synapse's database is initialized with `server_name = "__EC2_HOSTNAME__"`. Every subsequent user ID is `@user:__EC2_HOSTNAME__`. This cannot be fixed without dropping `postgres_data` volume and starting over.

**Why it happens:** The sed substitution step is easy to skip or forget, especially when iterating.

**How to avoid:** Make the verification `grep "__EC2_HOSTNAME__" synapse/homeserver.yaml` a required gate before `docker compose up`. The plan must make this a blocking check.

**Warning signs:** Synapse starts successfully but `curl http://$EC2_HOST/_matrix/client/v3/login` returns a server_name that is literally `__EC2_HOSTNAME__` or a garbled string.

### Pitfall 2: `.env` Secrets Left as Placeholders

**What goes wrong:** `homeserver.yaml` references `__POSTGRES_PASSWORD__`, `__REGISTRATION_SHARED_SECRET__`, `__MACAROON_SECRET_KEY__`, `__FORM_SECRET__` — these are sourced from `compose/.env`. If `.env` has placeholder values (starting with `__`), Synapse and Postgres will fail to start or start with insecure settings.

**Why it happens:** `.env.example` has placeholder strings; operators must generate real values.

**How to avoid:** Generate all secrets before the stack starts:
```bash
openssl rand -hex 32   # for POSTGRES_PASSWORD, MACAROON_SECRET_KEY, FORM_SECRET
openssl rand -hex 64   # for SYNAPSE_REGISTRATION_SHARED_SECRET (longer recommended)
```

`bootstrap-admin.sh` already validates that `SYNAPSE_REGISTRATION_SHARED_SECRET` is not a placeholder.

### Pitfall 3: `docker compose` Run from Wrong Directory

**What goes wrong:** The compose file is at `compose/docker-compose.yml`, not at the repo root. Running `docker compose up -d` from the repo root without `-f` will fail with "no configuration file provided".

**How to avoid:** Always specify `-f compose/docker-compose.yml` from the repo root, OR `cd compose && docker compose up -d`. All plans should use the explicit `-f` form to avoid ambiguity.

### Pitfall 4: Signing Key Generation Behavior

**What goes wrong:** If `docker compose run --rm synapse generate` is run without `SYNAPSE_SERVER_NAME` set, it may attempt to auto-generate a homeserver.yaml, potentially overwriting the mounted one.

**Why it happens:** In generate mode without `SYNAPSE_CONFIG_PATH` pointing to an existing file, Synapse generates a new config. The compose file sets `SYNAPSE_CONFIG_PATH: /data/homeserver.yaml` which points to the mounted, already-configured file. As long as the `synapse_data` volume does NOT already contain a `homeserver.yaml` (it shouldn't — the file is bind-mounted from the repo), generate will create only the signing key.

**How to avoid:** Always pass `-e SYNAPSE_SERVER_NAME=$EC2_HOST -e SYNAPSE_REPORT_STATS=no` when running generate. After generate, verify the signing key exists:
```bash
docker compose -f compose/docker-compose.yml run --rm synapse \
  ls -la /data/signing.key
```

**Verify key exists before first `up`:** If this command returns an error, the signing key was not generated and Synapse will fail to start.

### Pitfall 5: matrix-nio Not Installed on EC2

**What goes wrong:** `create-default-rooms.py` starts with `from nio import AsyncClient, RoomCreateResponse` — if matrix-nio is not installed, it exits immediately with an ImportError.

**How to avoid:** Run `pip3 install matrix-nio` on EC2 before running the script. Python 3 is available on AL2023 by default; pip3 may need `python3-pip` package:
```bash
which pip3 || sudo dnf install -y python3-pip
pip3 install matrix-nio
```

### Pitfall 6: `create-default-rooms.py` Uses `PUBLIC_BASEURL` from `.env`

**What goes wrong:** The script reads `PUBLIC_BASEURL` from `compose/.env` as the homeserver URL. If this is still `https://matrix.example.com` (the example value), the script will try to connect to the wrong host.

**How to avoid:** Ensure `.env` has `PUBLIC_BASEURL=http://$EC2_HOST` (with the actual hostname, no trailing slash, `http://` protocol). This should be set as part of the `.env` fill-in step.

### Pitfall 7: Element and Nginx Show No Health Status

**What goes wrong:** The executor sees that `docker compose ps` shows element and nginx without `(healthy)` and thinks something is broken. They waste time debugging non-existent issues.

**Why it happens:** No `healthcheck` block in the compose file for element or nginx services.

**How to avoid:** Document this explicitly in the plan. The functional test for element and nginx is `curl http://$EC2_HOST/` returning Element Web HTML with HTTP 200. This is the correct verification, not `docker compose ps` health status.

### Pitfall 8: `bootstrap-admin.sh` Prints Wrong Login URL

**What goes wrong:** `bootstrap-admin.sh` line 41 prints `Login at: https://${ELEMENT_DOMAIN:-chat.example.com}`. This URL is wrong for the POC — the correct URL is `http://$EC2_HOST`. The admin must know to ignore this printed URL and go to the correct one.

**Why it happens:** The script still references `ELEMENT_DOMAIN` (from `.env.example`) which is not relevant for the single-hostname EC2 POC.

**How to avoid:** Note in the plan that the printed login URL from `bootstrap-admin.sh` is misleading — the actual URL is `http://<EC2 hostname>`. The script still creates the admin user correctly; only the printed message is wrong.

---

## Code Examples

Verified patterns from official sources and codebase inspection:

### Hostname Substitution (runs on EC2 before first up)

```bash
# Source: operation derived from Phase 2 research; sed is standard Linux utility
# Get hostname from local instance-info.env before SCP, or from IMDS on EC2
EC2_HOST=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)

# Substitute in all four placeholder files
sed -i "s/__EC2_HOSTNAME__/$EC2_HOST/g" \
  synapse/homeserver.yaml \
  element/config.json \
  well-known/matrix/client \
  well-known/matrix/server

# Verify: should print nothing
grep "__EC2_HOSTNAME__" synapse/homeserver.yaml element/config.json \
  well-known/matrix/client well-known/matrix/server && echo "FAIL: placeholder remains" || echo "OK: all replaced"
```

### Generate Signing Key

```bash
# Source: Synapse Docker README (element-hq/synapse, docker/README.md)
docker compose -f compose/docker-compose.yml run --rm \
  -e SYNAPSE_SERVER_NAME="$EC2_HOST" \
  -e SYNAPSE_REPORT_STATS=no \
  synapse generate

# Verify signing key was created
docker compose -f compose/docker-compose.yml run --rm synapse \
  test -f /data/signing.key && echo "OK: signing.key exists" || echo "FAIL: signing.key missing"
```

### Start Stack and Check Status

```bash
# Source: Docker Compose v2 documentation; healthcheck defined in compose/docker-compose.yml
docker compose -f compose/docker-compose.yml up -d

# Wait for synapse to become healthy (up to 2 minutes on first start due to DB migration)
echo "Waiting for synapse to be healthy..."
for i in $(seq 1 24); do
  STATUS=$(docker compose -f compose/docker-compose.yml ps --format json synapse 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Health',''))" 2>/dev/null || echo "")
  if [[ "$STATUS" == "healthy" ]]; then
    echo "Synapse is healthy."
    break
  fi
  echo "  attempt $i: status=$STATUS — waiting 5s..."
  sleep 5
done

# Check all services are up
docker compose -f compose/docker-compose.yml ps
```

### Create Admin User

```bash
# Source: scripts/bootstrap-admin.sh — already in repo
# Run from repo root
./scripts/bootstrap-admin.sh
# Expected output: "Admin user created successfully."
# Note: ignore the printed "Login at: https://..." URL — that URL is wrong for POC
# Correct login URL: http://<EC2_HOST>
```

### Get Admin Access Token via Login API

```bash
# Source: Matrix Client-Server Spec v1.x (standard m.login.password flow)
# Note: works without MAS; MAS admin scope restriction does not apply to this POC
ADMIN_USER=$(grep '^ADMIN_USER=' compose/.env | cut -d= -f2)
ADMIN_PASSWORD=$(grep '^ADMIN_PASSWORD=' compose/.env | cut -d= -f2)

LOGIN_RESPONSE=$(curl -s -X POST \
  "http://localhost:8008/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"m.login.password\",\"user\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASSWORD\"}")

ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
echo "Access token: $ACCESS_TOKEN"
```

### Create Registration Token for Second User

```bash
# Source: https://element-hq.github.io/synapse/latest/usage/administration/admin_api/registration_tokens.html
TOKEN_RESPONSE=$(curl -s -X POST \
  "http://localhost:8008/_synapse/admin/v1/registration_tokens/new" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"uses_allowed": 1}')

INVITE_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
echo "Registration token: $INVITE_TOKEN"
echo "Second user registers at: http://$EC2_HOST with this token"
```

### Create Default Rooms

```bash
# Source: scripts/create-default-rooms.py — already in repo
# Prerequisite: matrix-nio installed, .env has correct PUBLIC_BASEURL
sudo dnf install -y python3-pip 2>/dev/null || true
pip3 install matrix-nio --quiet
python3 scripts/create-default-rooms.py
# Expected: "Done! Space and 6 rooms created."
```

### Verify Element Branding

```bash
# VERIFY-04: Check brand name appears in the HTML
curl -s "http://localhost/" | grep -i "yourbrand\|element" | head -5

# Check config.json is served correctly
curl -s "http://localhost/config.json" | python3 -m json.tool | grep -E '"brand"|"default_theme"'
# Expected: "brand": "YourBrand Chat", "default_theme": "custom"
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `docker-compose` (v1, standalone) | `docker compose` (v2, built-in plugin) | Docker 20.10+ | v2 is installed on EC2 (v5.0.2); all commands use `docker compose` not `docker-compose` |
| Manual Matrix server setup | Docker Compose multi-service stack | — | Entire Phase 2 output; stack is self-contained |
| Registration via open signup | Registration tokens (MSC3231) | Synapse 1.42.0, Matrix v1.2 | Invite-only flow without email; stable and in use since 2021 |
| Matrix Authentication Service (MAS) | Standard Synapse password auth | MAS is optional separate service | This POC does NOT use MAS; `m.login.password` gives full admin API access |
| `docker-compose run --rm synapse generate` (v1) | `docker compose run --rm synapse generate` (v2) | Compose v2 | Same semantics, different command prefix |

**Deprecated/outdated in context of this project:**
- `matrixdotorg/synapse` image: Note that the Synapse Docker image maintainer changed from `matrixdotorg` to `ghcr.io/element-hq/synapse` in recent versions. The compose file uses `matrixdotorg/synapse:latest` which still exists and works on Docker Hub, but the upstream source is now `element-hq/synapse`. For the POC this is fine; for production, consider pinning to `ghcr.io/element-hq/synapse:latest`.
- `vectorim/element-web`: Still the current Docker Hub image for Element Web. No migration needed for POC.

---

## Open Questions

1. **Does `synapse generate` overwrite the existing `homeserver.yaml` bind-mounted from the repo?**
   - What we know: When `SYNAPSE_CONFIG_PATH` points to an existing file and generate is run, Synapse is documented to only create the signing key and log config files if they don't exist, NOT overwrite the config file.
   - What's unclear: Edge case behavior when the signing key path in homeserver.yaml (`/data/signing.key`) does not match the default generated path (`/data/<server_name>.signing.key`). The repo's homeserver.yaml has `signing_key_path: "/data/signing.key"` — this is a static path, not the default `<server_name>.signing.key`. The generate command may produce the key at the default name, not at `/data/signing.key`.
   - Recommendation: After running generate, run `docker compose -f compose/docker-compose.yml run --rm synapse ls -la /data/` to see what files were created. If the key is at `/data/<server_name>.signing.key`, either update `signing_key_path` in homeserver.yaml OR manually copy/symlink the file. The plan should include this verification step.
   - **Confidence:** LOW — this is the one area where behavior was not confirmed from official docs.

2. **Does `PUBLIC_BASEURL` in `.env` need to match the post-substitution URL exactly for `create-default-rooms.py`?**
   - What we know: The script reads `PUBLIC_BASEURL` from `.env` as the `homeserver` parameter to `AsyncClient`. This is the URL the Python client connects to.
   - What's unclear: Whether the URL needs a trailing slash or not for matrix-nio.
   - Recommendation: Set `PUBLIC_BASEURL=http://$EC2_HOST` (no trailing slash) in `.env` to match Element Web conventions. matrix-nio is generally tolerant of both forms.
   - **Confidence:** MEDIUM

3. **Will the E2EE lock icon be visible on first message in Element Web (current version)?**
   - What we know: E2EE rooms are created with `m.room.encryption` initial state event. Element Web shows a padlock icon on encrypted messages.
   - What's unclear: Recent Element Web UI changes (device verification becoming mandatory) may affect the UX. There have been discussions about making the lock icon less prominent. The icon may require hovering.
   - Recommendation: If the padlock is not immediately visible, hover over the message timestamp area. An alternate verification is checking the room info panel — it should show "Messages in this room are end-to-end encrypted."
   - **Confidence:** MEDIUM

---

## Sources

### Primary (HIGH confidence)

- `compose/docker-compose.yml` — confirmed: postgres and synapse have healthchecks; element and nginx do not
- `synapse/homeserver.yaml` — confirmed: `__EC2_HOSTNAME__` placeholder in 4 locations; `signing_key_path: "/data/signing.key"`; `encryption_enabled_by_default_for_room_type: "all"`
- `element/config.json` — confirmed: `brand: "YourBrand Chat"`, `default_theme: "custom"`, `custom_themes` defined
- `scripts/bootstrap-admin.sh` — confirmed: uses `docker compose exec synapse register_new_matrix_user`; reads ADMIN_USER, ADMIN_PASSWORD, SYNAPSE_REGISTRATION_SHARED_SECRET from .env
- `scripts/create-default-rooms.py` — confirmed: reads PUBLIC_BASEURL from .env; uses matrix-nio AsyncClient; creates Space and 6 rooms with E2EE enabled
- [element-hq/synapse Docker README](https://github.com/element-hq/synapse/blob/develop/docker/README.md) — generate command syntax, environment variables
- [Synapse Admin API — Registration Tokens](https://element-hq.github.io/synapse/latest/usage/administration/admin_api/registration_tokens.html) — POST endpoint, authentication requirement confirmed

### Secondary (MEDIUM confidence)

- [Synapse Docker Hub](https://hub.docker.com/r/matrixdotorg/synapse) — generate command usage confirmed
- [Matrix Client-Server Spec — Login](https://matrix.org/docs/older/client-server-api/) — `m.login.password` flow; admin access token usable for admin API without MAS
- [Element Web issue #2882](https://github.com/element-hq/element-web/issues/2882) — E2EE lock icon behavior context
- Multiple community writeups on Synapse Docker Compose deployment — consistent with official docs

### Tertiary (LOW confidence)

- `synapse generate` behavior with existing bind-mounted homeserver.yaml — no official doc explicitly describes this edge case; LOW confidence on signing key path behavior

---

## Metadata

**Confidence breakdown:**
- Deploy sequence: HIGH — directly derived from existing repo files (Phases 1 and 2 outputs)
- `sed` substitution pattern: HIGH — standard Linux tool, placeholder format is well-defined
- Synapse signing key generation: MEDIUM — `synapse generate` behavior with existing homeserver.yaml has one open question (signing key output path)
- `register_new_matrix_user` admin bootstrap: HIGH — confirmed in bootstrap-admin.sh; command syntax from Synapse Docker README
- Registration token API: HIGH — official Synapse admin API docs confirmed
- matrix-nio room creation: HIGH — script is in repo and tested (confirmed functional in prior implementation context)
- E2EE lock icon visibility: MEDIUM — current Element Web UX behavior not confirmed from official docs; may require hover

**Research date:** 2026-02-20
**Valid until:** 2026-03-22 (30 days; Synapse and Element are active projects but core Docker deployment patterns are stable)
