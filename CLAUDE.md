# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

White-label Element/Matrix self-hosted "Discord alternative" for privacy-conscious communities.
Uses Matrix protocol (Synapse homeserver) + Element Web client, deployed via Docker Compose
behind a hardened Nginx reverse proxy with TLS via Let's Encrypt (certbot).

## Architecture

```
Internet
  |
  v
Nginx (TLS termination, reverse proxy, security headers)
  |
  +-- chat.example.com      -> Element Web (static files)
  +-- matrix.example.com    -> Synapse (client + federation APIs)
  +-- example.com/.well-known -> static JSON for Matrix discovery
  |
Synapse homeserver
  +-- PostgreSQL (persistent data)
  +-- coturn (TURN/STUN for VoIP, Phase 2)
```

All services run via `docker compose` from the `compose/` directory.
Configuration uses `.env` for secrets/domain and template configs with placeholder values.

## Key Commands

```bash
# Full stack up/down (run from repo root)
cd compose && docker compose up -d
cd compose && docker compose down

# Generate Synapse signing key + initial config (first time only)
cd compose && docker compose run --rm synapse generate

# Create admin user
./scripts/bootstrap-admin.sh

# Create default rooms/spaces
pip3 install matrix-nio && python3 ./scripts/create-default-rooms.py

# Backup (postgres dump + media archive, encrypted, uploaded offsite)
./scripts/backup.sh

# Restore from backup
./scripts/restore.sh /path/to/backup-YYYY-MM-DD.tar.gz.gpg

# Check TLS grade
curl -sI https://chat.example.com | head -20

# Validate .well-known
curl -s https://example.com/.well-known/matrix/client | jq .
curl -s https://example.com/.well-known/matrix/server | jq .

# View logs
cd compose && docker compose logs -f synapse
cd compose && docker compose logs -f nginx
```

## Repo Layout

- `compose/` — Docker Compose stack and `.env` config
- `synapse/` — Synapse homeserver.yaml template and logging config
- `element/` — Element Web config.json and branding assets (logo, theme)
- `proxy/` — Nginx config: main site conf, TLS params, security headers
- `scripts/` — Operational scripts: bootstrap, backup, restore, room creation
- `well-known/` — Static .well-known/matrix JSON files for client/server discovery
- `docs/` — Runbooks (ops, migration, security), checklists

## Configuration Flow

1. Copy `compose/.env.example` to `compose/.env` and fill in all values
2. Domain placeholders throughout configs read from `.env` at compose time
3. Synapse config at `synapse/homeserver.yaml` references env vars via docker-compose variable substitution where possible; some values are static placeholders (`__PLACEHOLDER__`) that must be replaced
4. Element `config.json` must have `default_server_config` pointing to the real domain

## Security Stance

- Federation: OFF by default (private community network)
- Registration: invite-only (no open signup)
- E2EE: supported and encouraged; server cannot read encrypted content
- TLS: A+ target via strong cipher config and HSTS
- Rate limiting enabled on Synapse
- URL previews disabled by default (privacy)

## Tech Stack

- Synapse (Matrix homeserver) — Python
- PostgreSQL 15 — database
- Nginx — reverse proxy + TLS termination
- Certbot — Let's Encrypt certificate management
- Element Web — React SPA (static build served by Nginx)
- coturn — TURN/STUN relay for VoIP (Phase 2)
- Scripts: Bash + Python (matrix-nio library for admin automation)
