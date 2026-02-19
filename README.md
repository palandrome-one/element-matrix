# YourBrand Chat — Self-Hosted Matrix/Element Stack

A white-label, self-hosted Matrix homeserver with a branded Element Web client.
Designed for privacy-conscious communities migrating from Discord or similar platforms.

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │              Internet                    │
                    └───────────────────┬─────────────────────┘
                                        │
                              ┌─────────▼─────────┐
                              │   Nginx (TLS)      │
                              │   ports 80/443/8448│
                              └──┬──────┬──────┬───┘
                                 │      │      │
              ┌──────────────────┘      │      └──────────────────┐
              ▼                         ▼                         ▼
    ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
    │  Element Web     │   │  Synapse          │   │  .well-known     │
    │  chat.example.com│   │  matrix.example   │   │  example.com     │
    │  (static SPA)    │   │  .com             │   │  (static JSON)   │
    └──────────────────┘   └────────┬──────────┘   └──────────────────┘
                                    │
                           ┌────────▼──────────┐
                           │  PostgreSQL 15    │
                           │  (persistent vol) │
                           └───────────────────┘
```

## Quick Start

### Prerequisites
- Linux server (Ubuntu 22.04+ recommended)
- Docker Engine 24+ with Compose plugin
- Domain name with DNS configured
- SMTP credentials for email

### 1. Clone and configure

```bash
git clone <this-repo> && cd element-matrix
cp compose/.env.example compose/.env
# Edit compose/.env — fill in ALL placeholder values
```

### 2. DNS records

Create A records pointing to your server IP:

| Record | Value |
|--------|-------|
| `example.com` | `YOUR_SERVER_IP` |
| `chat.example.com` | `YOUR_SERVER_IP` |
| `matrix.example.com` | `YOUR_SERVER_IP` |

### 3. TLS certificates

```bash
# Install certbot on host (or use Docker)
sudo apt install certbot
sudo certbot certonly --standalone \
  -d chat.example.com \
  -d matrix.example.com \
  -d example.com \
  --email admin@example.com --agree-tos

# Copy certs into Docker volume
docker volume create compose_certbot_conf
sudo cp -rL /etc/letsencrypt/* /var/lib/docker/volumes/compose_certbot_conf/_data/
```

### 4. Generate Synapse signing key

```bash
cd compose
docker compose run --rm synapse generate
cd ..
```

### 5. Replace placeholders in homeserver.yaml

Edit `synapse/homeserver.yaml` and replace all `__PLACEHOLDER__` values
with the corresponding values from your `.env` file.

### 6. Launch

```bash
cd compose && docker compose up -d
```

### 7. Create admin user

```bash
./scripts/bootstrap-admin.sh
```

### 8. Create default rooms

```bash
pip3 install matrix-nio
python3 ./scripts/create-default-rooms.py
```

### 9. Verify

- Open `https://chat.example.com` — Element should load with your branding
- Register/login as admin
- Check `.well-known`: `curl https://example.com/.well-known/matrix/client`

## Day-to-Day Operations

| Task | Command |
|------|---------|
| Start stack | `cd compose && docker compose up -d` |
| Stop stack | `cd compose && docker compose down` |
| View logs | `cd compose && docker compose logs -f synapse` |
| Backup | `./scripts/backup.sh` |
| Restore | `./scripts/restore.sh /path/to/backup.tar.gz.gpg` |
| Update images | `cd compose && docker compose pull && docker compose up -d` |
| Create invite token | See docs/runbook.md |

## Repo Layout

```
compose/          Docker Compose stack + .env
synapse/          Homeserver config + logging
element/          Element Web config + branding assets
proxy/            Nginx config, TLS params, security headers
scripts/          Admin bootstrap, backup/restore, room creation
well-known/       Matrix client/server discovery files
docs/             Runbooks, security docs, migration guide
```

## Documentation

- [Ops Runbook](docs/runbook.md) — backup, restore, upgrades, incidents, scaling
- [Security](docs/security.md) — threat model, hardening checklist, compliance
- [Migration Guide](docs/migration-guide.md) — onboarding Discord communities

## Phases

- **Phase 1** (Week 1-2): Core stack — Synapse + Element + Nginx + Postgres + TLS
- **Phase 2** (Week 2-3): coturn for VoIP, monitoring, automated backups, alerting
- **Phase 3** (Week 3-4): Migration tooling, onboarding guides, room templates, bridges roadmap
