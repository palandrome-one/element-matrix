# Implementation Plan — White-Label Element/Matrix Stack

## Executive Overview

This project deploys a self-hosted, white-labeled Matrix communication platform
as a privacy-respecting alternative to Discord. It targets communities concerned
by Discord's age-verification/KYC policies and seeking self-sovereign communication
infrastructure.

The stack uses **Synapse** (Matrix homeserver) + **Element Web** (client) behind a
hardened **Nginx** reverse proxy, with **PostgreSQL** for persistence. Everything runs
in Docker Compose on a single VPS. Federation is disabled by default to create a
private community network.

**Key properties:**
- One-command deploy (`docker compose up -d`)
- One-command backup (`./scripts/backup.sh`) and restore
- Invite-only registration (no open signup, no KYC)
- E2EE enabled by default for all rooms
- White-labeled: custom brand name, logo, colors, domains
- No telemetry, no external identity server, no phone/email directory

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         INTERNET                                    │
└───────┬───────────────────────┬─────────────────────┬───────────────┘
        │ :80 (→301 HTTPS)      │ :443                │ :8448 (fed)
┌───────▼───────────────────────▼─────────────────────▼───────────────┐
│                     NGINX (TLS termination)                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────────┐  │
│  │ chat.example.com│  │matrix.example   │  │ example.com        │  │
│  │ → Element Web   │  │.com → Synapse   │  │ → .well-known JSON │  │
│  └────────┬────────┘  └────────┬────────┘  └────────────────────┘  │
└───────────┼─────────────────────┼──────────────────────────────────-┘
            │                     │          (internal Docker network)
   ┌────────▼────────┐  ┌────────▼────────┐
   │  Element Web    │  │    Synapse      │
   │  (static SPA)   │  │  (homeserver)   │
   │  vectorim/      │  │  :8008 internal │
   │  element-web    │  └────────┬────────┘
   └─────────────────┘           │
                        ┌────────▼────────┐
                        │  PostgreSQL 15  │
                        │  (Docker vol)   │
                        └─────────────────┘

Phase 2 additions:
  ┌─────────────────┐  ┌─────────────────┐
  │     coturn       │  │   Prometheus    │
  │  (TURN/STUN)     │  │   (metrics)     │
  │  :3478, :5349    │  │   :9090         │
  └─────────────────┘  └─────────────────┘
```

---

## Phased Project Plan

### Phase 0 — Discovery & Requirements (Week 1)

**Decisions (defaults chosen — override as needed):**
| Decision | Default | Rationale |
|----------|---------|-----------|
| Federation | OFF | Private community; reduces attack surface |
| Registration | Invite-only (token) | Abuse prevention |
| SSO | OFF (Phase 2 option) | Simplicity |
| CAPTCHA | OFF (token gates suffice) | UX simplicity |
| Retention | Unlimited | Users control deletion; server doesn't purge |
| URL previews | OFF | Privacy (prevents SSRF, metadata leak) |
| Identity server | OFF | No email/phone discovery |

**Deliverables:**
- [x] This implementation plan
- [x] Threat model (see docs/security.md)
- [x] Decision log (table above)

---

### Phase 1 — Core Stack (Week 1–2)

**Deliverables:**
| Item | File | Status |
|------|------|--------|
| Docker Compose stack | `compose/docker-compose.yml` | Created |
| Environment template | `compose/.env.example` | Created |
| Synapse config | `synapse/homeserver.yaml` | Created |
| Synapse logging | `synapse/log.config` | Created |
| Element config | `element/config.json` | Created |
| Element branding | `element/branding/logo.svg` | Placeholder |
| Nginx config | `proxy/nginx.conf` + `proxy/conf.d/element.conf` | Created |
| TLS hardening | `proxy/snippets/tls-params.conf` | Created |
| Security headers | `proxy/snippets/security-headers.conf` | Created |
| Well-known files | `well-known/matrix/{client,server}` | Created |
| Admin bootstrap | `scripts/bootstrap-admin.sh` | Created |
| Room creation | `scripts/create-default-rooms.py` | Created |

**Acceptance Criteria:**
- [ ] `https://chat.example.com` loads branded Element
- [ ] User can register with invite token and message in default rooms
- [ ] E2EE works in DMs and encrypted rooms
- [ ] `.well-known` endpoints resolve correctly
- [ ] TLS grade A+ (or near) on SSL Labs
- [ ] Security headers present (test with securityheaders.com)

---

### Phase 2 — Reliability & Observability (Week 2–3)

**Deliverables:**
| Item | Status |
|------|--------|
| coturn for voice/video | TODO — add to docker-compose.yml |
| Automated backup cron | TODO — cron entry + script ready |
| Offsite backup (rclone) | TODO — configure rclone remote |
| Restore test | TODO — perform and document |
| Health check monitoring | TODO — Uptime Kuma or similar |
| Log rotation | Synapse log.config handles 7-day rotation |
| Prometheus metrics | TODO — uncomment in homeserver.yaml |

**Acceptance Criteria:**
- [ ] Voice/video calls work reliably via coturn
- [ ] Daily backups run and upload offsite
- [ ] Restore from backup tested and documented
- [ ] Alert fires on: Synapse down, cert expiry < 14d, disk > 80%

---

### Phase 3 — Migration & Onboarding (Week 3–4)

**Deliverables:**
| Item | File | Status |
|------|------|--------|
| Migration guide | `docs/migration-guide.md` | Created |
| Room template script | `scripts/create-default-rooms.py` | Created (customizable) |
| User setup guide | In migration-guide.md | Created |
| Admin runbook | `docs/runbook.md` | Created |
| Security docs | `docs/security.md` | Created |

**Acceptance Criteria:**
- [ ] Discord admin can replicate channel structure in < 30 min
- [ ] New user can onboard (install, register, join) in < 10 min
- [ ] Moderator can kick/ban/manage rooms with documented procedures

---

## Fresh Server Install Steps

```bash
# 1. Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in, then:
docker --version

# 2. Clone repo
git clone <your-repo-url> /opt/element-matrix
cd /opt/element-matrix

# 3. Configure
cp compose/.env.example compose/.env
nano compose/.env    # Fill in ALL __CHANGE_ME__ values

# Generate secrets:
#   openssl rand -hex 32   (run 3x for macaroon, form_secret, registration_shared_secret)

# 4. DNS (create A records before this step)
# Verify DNS:
dig +short chat.example.com
dig +short matrix.example.com
dig +short example.com

# 5. TLS certificates
sudo apt install certbot -y
sudo certbot certonly --standalone \
  -d chat.example.com \
  -d matrix.example.com \
  -d example.com \
  --email admin@example.com --agree-tos --non-interactive

# Copy into Docker volume
cd compose && docker compose up -d nginx   # Creates the volume
docker compose down
sudo cp -rL /etc/letsencrypt/* \
  /var/lib/docker/volumes/compose_certbot_conf/_data/ 2>/dev/null || \
  sudo cp -rL /etc/letsencrypt/* \
  /var/lib/docker/volumes/element-matrix_certbot_conf/_data/

# 6. Update homeserver.yaml placeholders
# Replace __POSTGRES_PASSWORD__, __REGISTRATION_SHARED_SECRET__,
# __MACAROON_SECRET_KEY__, __FORM_SECRET__, __SMTP_*__ with values from .env
cd /opt/element-matrix
sed -i "s/__POSTGRES_PASSWORD__/$(grep POSTGRES_PASSWORD compose/.env | cut -d= -f2)/" synapse/homeserver.yaml
sed -i "s/__REGISTRATION_SHARED_SECRET__/$(grep SYNAPSE_REGISTRATION_SHARED_SECRET compose/.env | cut -d= -f2)/" synapse/homeserver.yaml
sed -i "s/__MACAROON_SECRET_KEY__/$(grep SYNAPSE_MACAROON_SECRET_KEY compose/.env | cut -d= -f2)/" synapse/homeserver.yaml
sed -i "s/__FORM_SECRET__/$(grep SYNAPSE_FORM_SECRET compose/.env | cut -d= -f2)/" synapse/homeserver.yaml
sed -i "s/__SMTP_HOST__/$(grep SMTP_HOST compose/.env | cut -d= -f2)/" synapse/homeserver.yaml
sed -i "s/__SMTP_USER__/$(grep SMTP_USER compose/.env | cut -d= -f2)/" synapse/homeserver.yaml
sed -i "s/__SMTP_PASSWORD__/$(grep SMTP_PASSWORD compose/.env | cut -d= -f2)/" synapse/homeserver.yaml

# 7. Update Element config.json and well-known with real domain
# Replace example.com with your actual domain throughout:
#   element/config.json
#   well-known/matrix/client
#   well-known/matrix/server
#   proxy/conf.d/element.conf

# 8. Generate Synapse signing key
cd /opt/element-matrix/compose
docker compose run --rm -e SYNAPSE_SERVER_NAME=example.com synapse generate
cd ..

# 9. Launch
cd compose && docker compose up -d

# 10. Wait for healthy
docker compose ps   # All should show "healthy" or "running"

# 11. Create admin user
cd /opt/element-matrix
chmod +x scripts/bootstrap-admin.sh
./scripts/bootstrap-admin.sh

# 12. Create default rooms
pip3 install matrix-nio
python3 scripts/create-default-rooms.py

# 13. Validate
curl -s https://chat.example.com/ | head -5
curl -s https://example.com/.well-known/matrix/client | python3 -m json.tool
curl -s https://example.com/.well-known/matrix/server | python3 -m json.tool
curl -s https://matrix.example.com/health

# 14. Firewall
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8448/tcp
sudo ufw --force enable

# 15. First backup
./scripts/backup.sh --local-only
```

---

## Repo File Index

```
element-matrix/
├── CLAUDE.md                          # Claude Code guidance
├── README.md                          # Project overview + quick start
├── implementation.md                  # This file — full project plan
├── .gitignore                         # Excludes .env, backups, OS files
├── compose/
│   ├── docker-compose.yml             # Full stack definition
│   └── .env.example                   # All configuration variables
├── synapse/
│   ├── homeserver.yaml                # Synapse config (with placeholders)
│   └── log.config                     # Logging: console + 7-day file rotation
├── element/
│   ├── config.json                    # Element Web config (branding, defaults)
│   └── branding/
│       └── logo.svg                   # Placeholder logo (replace with yours)
├── proxy/
│   ├── nginx.conf                     # Main Nginx config
│   ├── conf.d/
│   │   └── element.conf               # Virtual hosts: Element, Synapse, well-known
│   └── snippets/
│       ├── tls-params.conf            # TLS 1.2+, strong ciphers, OCSP
│       └── security-headers.conf      # HSTS, X-Frame-Options, etc.
├── well-known/
│   └── matrix/
│       ├── client                     # .well-known/matrix/client JSON
│       └── server                     # .well-known/matrix/server JSON
├── scripts/
│   ├── bootstrap-admin.sh             # Create first admin user
│   ├── create-default-rooms.py        # Create Space + default rooms
│   ├── backup.sh                      # Encrypted backup + offsite upload
│   └── restore.sh                     # Restore from encrypted backup
└── docs/
    ├── Discord Exodus_ Age Verification Deep Dive.pdf
    ├── runbook.md                     # Ops: backup, upgrade, incidents, scaling
    ├── security.md                    # Threat model, checklists, day-1/day-30
    └── migration-guide.md             # Discord→Matrix migration playbook
```
