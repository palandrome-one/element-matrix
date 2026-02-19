# Coding Conventions

**Analysis Date:** 2026-02-20

## Overview

This project consists primarily of infrastructure-as-code (Bash scripts, Python scripts, configuration files, and Docker Compose definitions). There is no compiled application code, TypeScript, JavaScript, or traditional unit-tested software components. Conventions focus on operational scripts, deployment configuration, and maintainability.

## Languages & Code Types

**Primary languages:**
- **Bash** — Operational scripts for backup/restore, admin bootstrap
- **Python 3** — Room creation and admin automation (matrix-nio library)
- **YAML** — Docker Compose definitions and Synapse homeserver config
- **JSON** — Element Web configuration, well-known discovery files
- **Nginx** — Reverse proxy configuration

**No linting/formatting tools detected.** Project uses manual conventions rather than automated enforcement.

## Naming Patterns

### Files

**Bash scripts:**
- kebab-case with `.sh` extension
- Examples: `backup.sh`, `bootstrap-admin.sh`, `create-default-rooms.py`, `restore.sh`
- Descriptive names matching their primary function
- Location: `scripts/` directory

**Configuration files:**
- YAML: lowercase, underscores: `homeserver.yaml`, `docker-compose.yml`
- JSON: same as source: `config.json`, `Element Web` config uses exact JSON format
- Nginx config: descriptive kebab-case: `element.conf`, `tls-params.conf`, `security-headers.conf`

**Environment variables:**
- UPPERCASE_WITH_UNDERSCORES
- Location: `compose/.env` and `.env.example`
- Examples: `POSTGRES_DB`, `ADMIN_PASSWORD`, `SYNAPSE_SERVER_NAME`, `BACKUP_ENCRYPTION_PASSPHRASE`
- Placeholder values: `__PLACEHOLDER__` (intentionally verbose to catch before deploy)

### Functions & Variables

**Bash:**
- Function names: lowercase_with_underscores
- Variable names: lowercase for local vars, UPPERCASE for exported/env vars
- Example from `backup.sh`: `load_env()`, `BACKUP_DIR`, `ARCHIVE_SIZE`
- Constants defined at script start: `SCRIPT_DIR`, `REPO_ROOT`, `ENV_FILE`

**Python:**
- Function names: snake_case
- Example from `create-default-rooms.py`: `load_env()`, `main()`
- Class/module structure: use Python conventions (snake_case for functions, UPPERCASE for constants)
- Constant names: UPPERCASE (e.g., `ROOMS`, `SPACE_NAME`, `SPACE_TOPIC`)

## Code Style

### Shell Scripts

**Shebang & strictness:**
```bash
#!/usr/bin/env bash
set -euo pipefail
```
- Used in all scripts: `bootstrap-admin.sh`, `backup.sh`, `restore.sh`
- `set -e` — Exit on error
- `set -u` — Fail on undefined variables
- `set -o pipefail` — Fail if any command in pipe fails
- Ensures fast failure and no silent errors

**Variable usage:**
- Quote variables: `"$VARIABLE"` not `$VARIABLE`
- Use `${VARIABLE:-default}` for optional values
- Example from `bootstrap-admin.sh`: `[[ -z "${!var:-}" ]]` checks unset or empty

**Comments:**
- Descriptive headers: `# ──────────────────────────────────────────────`
- Section markers separate logical blocks
- Examples from `backup.sh`:
  ```bash
  # 1. PostgreSQL dump
  # 2. Synapse media store
  # etc.
  ```

**Error handling:**
- Exit with status code on error: `exit 1`
- User-facing error messages prefixed with `ERROR:`
- Example: `echo "ERROR: $ENV_FILE not found."`

**Loops & conditionals:**
- Use `for var in LIST:` not C-style `for ((i=0; i<n; i++))`
- Use `[[ ]]` for conditionals (safer than `[ ]`)
- Multiline conditionals: continuation lines aligned

### Python

**Shebang & docstring:**
```python
#!/usr/bin/env python3
"""
create-default-rooms.py — [Single-line summary]

[Multiline description of prerequisites, usage, behavior]
"""
```
- Used in `create-default-rooms.py`
- Docstring includes purpose, prerequisites, usage example

**Function docstrings:**
- Not consistently used; focus on clarity through naming and comments
- Example: `load_env()` function has inline comments explaining steps

**Variable naming:**
- Constants at module level: UPPERCASE (`ROOMS`, `SPACE_NAME`)
- Local variables: lowercase_with_underscores
- Boolean conditions: descriptive (`if not admin_pass or admin_pass.startswith("__")`)

**Error handling:**
- Try/except for imports with user-friendly error message
  ```python
  try:
      from nio import AsyncClient, RoomCreateResponse
  except ImportError:
      print("ERROR: matrix-nio not installed. Run: pip3 install matrix-nio")
      sys.exit(1)
  ```
- Type checking: `isinstance(resp, RoomCreateResponse)` before using response
- Exit codes: `sys.exit(1)` on failure

**Async/await:**
- Used in `create-default-rooms.py` with `asyncio.run(main())`
- Async functions: `async def main():`
- Await all async calls: `await client.login(...)`, `await client.close()`

### Configuration Files

**Docker Compose:**
- YAML with 2-space indentation
- Structured sections with ASCII dividers
- Comments explain each service's purpose
- Environment variables referenced with `${VAR_NAME}`
- Healthchecks included for persistence layer
- Volumes and networks explicitly named

**Nginx:**
- 2-space indentation
- Section headers with ASCII dividers
- Includes for modularity: `include /etc/nginx/snippets/*`
- TLS configuration in separate file: `snippets/tls-params.conf`
- Security headers in separate file: `snippets/security-headers.conf`
- Comments explain each server block's purpose

**JSON (Element Web config):**
- Formatted with 4-space indentation
- Structure mirrors Element Web's expected schema
- String placeholders: `example.com` (replaced at deploy time)
- Color values: hex codes (`#6366f1`)
- Features flagged in `features` object

## Import Organization

### Python

**Order:**
1. Standard library imports (built-in)
2. Third-party library imports
3. Local imports

**Example from `create-default-rooms.py`:**
```python
import asyncio      # std lib
import os           # std lib
import sys          # std lib
from pathlib import Path  # std lib

try:
    from nio import AsyncClient, RoomCreateResponse  # third-party
except ImportError:
    ...
```

### Bash

**Not applicable.** Shell scripts use command line tools with explicit `command -v` checks for optional tools (e.g., `rclone`).

## Error Handling

### Bash Pattern

**Validation at start:**
```bash
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found."
    exit 1
fi
```

**Variable validation:**
```bash
for var in POSTGRES_DB POSTGRES_USER BACKUP_ENCRYPTION_PASSPHRASE; do
    if [[ -z "${!var:-}" ]] || [[ "${!var}" == __* ]]; then
        echo "ERROR: $var not set in .env"
        exit 1
    fi
done
```

**Safe file operations:**
```bash
RESTORE_DIR=$(mktemp -d)
trap 'rm -rf "$RESTORE_DIR"' EXIT  # Cleanup on exit
```

**Graceful degradation:**
- Missing optional components (e.g., media volume) logged as WARNING, not failure
- Example from `backup.sh`:
  ```bash
  if [[ -n "$MEDIA_VOLUME" && -d "$MEDIA_VOLUME" ]]; then
      tar -cf "$WORK_DIR/media.tar" -C "$MEDIA_VOLUME" .
  else
      echo "  WARNING: Media volume not found, skipping."
  fi
  ```

### Python Pattern

**Import errors with fallback instructions:**
```python
try:
    from nio import AsyncClient, RoomCreateResponse
except ImportError:
    print("ERROR: matrix-nio not installed. Run: pip3 install matrix-nio")
    sys.exit(1)
```

**Response type checking before use:**
```python
if not isinstance(space_resp, RoomCreateResponse):
    print(f"Failed to create space: {space_resp}")
    await client.close()
    sys.exit(1)
```

**Explicit attribute checks:**
```python
if hasattr(resp, "access_token"):
    print("Logged in successfully.")
else:
    print(f"Login failed: {resp}")
```

## Logging

### Shell Scripts

**Approach:**
- Use `echo` for all output (no dedicated logger)
- Progress indicators: `[1/4]`, `[2/4]`, etc.
- Formatted headers: `echo "=== Matrix Backup: $TIMESTAMP ==="`
- Info lines indented: `echo "  Backup complete: $ARCHIVE"`
- Errors prefixed: `echo "ERROR: ..."`
- Warnings prefixed: `echo "WARNING: ..."`

**Example from `backup.sh`:**
```bash
echo "=== Matrix Backup: $TIMESTAMP ==="
echo "[1/4] Dumping PostgreSQL..."
docker compose -f "$COMPOSE_FILE" exec -T postgres ...
echo "  Database dump: $(du -sh "$WORK_DIR/synapse.pgdump" | cut -f1)"
```

### Python Scripts

**Approach:**
- Use `print()` for output (no logging library)
- Progress lines: `print(f"Creating room: #{name}")`
- Success indicators: `print(f"  Room created: {room_id}")`
- Errors prefixed: `print("ERROR: ...")`

**Example from `create-default-rooms.py`:**
```python
print(f"Logging in as {user_id} at {homeserver}...")
print("Logged in successfully.")
print(f"\nCreating Space: {SPACE_NAME}")
print(f"  Space created: {space_id}")
```

## Comments

### When to Comment

**Document the why, not the what:**
- Code should be self-explanatory through naming
- Comments explain decisions, workarounds, security rationale

**Examples from codebase:**

✓ Good — explains intent and security concern:
```bash
# 4. Compress + encrypt
# (Ensures backup is encrypted at rest)
tar -czf - -C "$BACKUP_DIR" "$BACKUP_NAME" | \
    gpg --batch --yes --symmetric ...
```

✓ Good — explains non-obvious behavior:
```python
# For Announcements, restrict who can post
power_overrides = None
if name == "Announcements":
    power_overrides = {
        "events_default": 50,  # Only mods+ can send messages
    }
```

✓ Good — section headers for navigation:
```bash
# ──────────────────────────────────────────────
# 1. PostgreSQL dump
# ──────────────────────────────────────────────
```

### Documentation in Configuration

**Inline comments:**
- Nginx: Explain server block purpose
- Docker Compose: Explain each service's role
- YAML config: Explain security settings

**Example from `docker-compose.yml`:**
```yaml
# ──────────────────────────────────────────────
# PostgreSQL
# ──────────────────────────────────────────────
postgres:
    image: postgres:15-alpine
    ...
```

## Function Design

### Bash Functions

**Size:** Keep under 50 lines where possible. Example: `load_env()` in `create-default-rooms.py` is ~12 lines.

**Parameters:** Explicit and validated
- Example: `backup.sh` takes optional `--local-only` flag, validated at top
- Always validate required env vars before use

**Return values:** Exit code convention
- Exit 0 on success
- Exit 1 on any error
- Use `set -e` so failures cascade

### Python Functions

**Size:** Keep under 100 lines for procedural scripts

**Parameters:** Type-hinted where helpful; async where needed

**Return values:** Explicit returns for clarity
```python
def load_env():
    env = {}
    # ... build dict
    return env

async def main():
    # ... operations
    await client.close()
```

## Module Design

### File Structure

**Single-responsibility principle:**
- `backup.sh` — only backup logic
- `restore.sh` — only restore logic
- `bootstrap-admin.sh` — only admin creation
- `create-default-rooms.py` — only room/space creation

**No shared libraries.** Each script is self-contained.

**Configuration loading:**
- Each script loads `.env` independently
- Validation happens in each script separately
- Allows scripts to run independently

### Exports & Defaults

**Bash:**
- No functions exported; scripts are standalone executables
- Environment variables sourced from `.env` using `source "$ENV_FILE"`
- shellcheck directive used: `# shellcheck source=/dev/null`

**Python:**
- Main entry point: `if __name__ == "__main__": asyncio.run(main())`
- No module exports; designed as standalone CLI tools

## Deployment & Configuration

### Environment Variables

**Source:** `compose/.env` (not committed; `.env.example` provided)

**Validation pattern used in all scripts:**
```bash
for var in REQUIRED_VAR1 REQUIRED_VAR2; do
    if [[ -z "${!var:-}" ]] || [[ "${!var}" == __* ]]; then
        echo "ERROR: $var not set in .env"
        exit 1
    fi
done
```

**Placeholder values:** `__CHANGE_ME__` or `__placeholder__` format
- Intentionally verbose and searchable
- Must be replaced before deployment
- Not valid defaults

### Docker Configuration

**Images:**
- Use official/maintained images: `postgres:15-alpine`, `nginx:alpine`, `matrixdotorg/synapse:latest`
- Alpine variants preferred for small footprint
- Pin versions where stability matters (postgres:15), use latest for frequently updated (Synapse)

**Health checks:**
- PostgreSQL: `pg_isready -U ${POSTGRES_USER}`
- Synapse: `curl -fSs http://localhost:8008/health`
- Interval: 10-15 seconds, timeout: 5 seconds, retries: 3-5

## Special Conventions

### Backup/Restore Scripts

**Timestamp format:** `YYYY-MM-DD_HHMMSS` (sortable, readable)
```bash
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
```

**Encryption:** GPG symmetric encryption with passphrase from `.env`
```bash
gpg --batch --yes --symmetric --cipher-algo AES256 --passphrase "$BACKUP_ENCRYPTION_PASSPHRASE"
```

**Cleanup:** Automatic removal of working directory using trap
```bash
RESTORE_DIR=$(mktemp -d)
trap 'rm -rf "$RESTORE_DIR"' EXIT
```

**User confirmation:** For destructive operations
```bash
read -rp "This will REPLACE the current database. Continue? [y/N] " confirm
```

### Matrix-Specific Conventions

**Room creation:**
- Rooms include encryption by default
- History visibility: `shared` (readable history before join)
- Space relationships: rooms linked to parent space with `m.space.parent` state

**Admin automation:**
- Uses `matrix-nio` library (async)
- Credentials from environment (`ADMIN_USER`, `ADMIN_PASSWORD`, `SYNAPSE_SERVER_NAME`)
- Graceful error handling with `isinstance()` checks on responses

---

*Convention analysis: 2026-02-20*
