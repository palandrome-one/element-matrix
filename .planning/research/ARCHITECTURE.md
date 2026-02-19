# Architecture Research

**Domain:** Matrix/Element AWS EC2 deployment — HTTP-only, EC2 public hostname
**Researched:** 2026-02-20
**Confidence:** HIGH (based on official Synapse docs, Matrix spec, and direct codebase inspection)

---

## Standard Architecture

### System Overview — EC2 POC (No TLS)

```
┌──────────────────────────────────────────────────────────────────────┐
│                          INTERNET                                    │
│                  (browser, Element mobile client)                    │
└──────┬──────────────────────────┬───────────────────────────────────┘
       │ :80 (HTTP)               │ :80 (HTTP)
       │ GET /                    │ GET /_matrix/*
       │                          │
┌──────▼──────────────────────────▼───────────────────────────────────┐
│           AWS Security Group (inbound rules)                        │
│   22/tcp (SSH, my-ip/32)   80/tcp (0.0.0.0/0)                      │
│   [443/tcp reserved for TLS phase — closed during POC]             │
│   [8448/tcp reserved for federation — closed, federation OFF]      │
└──────┬──────────────────────────┬───────────────────────────────────┘
       │                          │
┌──────▼──────────────────────────▼───────────────────────────────────┐
│                   EC2 Instance (t3.medium)                          │
│                   Ubuntu 22.04, Docker Engine                       │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                  Nginx (HTTP only, :80)                     │    │
│  │                                                              │    │
│  │  server_name: ec2-<ip>.compute-1.amazonaws.com              │    │
│  │                                                              │    │
│  │  /              → Element Web container (:80 internal)     │    │
│  │  /_matrix/*     → Synapse container (:8008 internal)       │    │
│  │  /_synapse/*    → Synapse container (:8008 internal)       │    │
│  │  /.well-known/  → Static JSON files (served by nginx)      │    │
│  └──────┬───────────────────────────┬────────────────────────┘    │
│         │ internal Docker network   │                               │
│  ┌──────▼──────────┐       ┌────────▼────────────┐                 │
│  │  Element Web    │       │      Synapse         │                 │
│  │  (static SPA)   │       │    (homeserver)      │                 │
│  │  :80 internal   │       │    :8008 internal    │                 │
│  └─────────────────┘       └────────┬────────────┘                 │
│                                      │                               │
│                             ┌────────▼────────────┐                 │
│                             │    PostgreSQL 15     │                 │
│                             │   :5432 internal     │                 │
│                             │   EBS volume         │                 │
│                             └─────────────────────┘                 │
│                                                                      │
│  Docker Volumes (EBS-backed):                                        │
│    postgres_data   → /var/lib/postgresql/data                        │
│    synapse_data    → /data (signing key, config state)               │
│    synapse_media   → /data/media_store                               │
│    [certbot volumes REMOVED — not needed without TLS]                │
└──────────────────────────────────────────────────────────────────────┘
                       │ S3 sync (aws cli / cron)
               ┌───────▼──────────────────────┐
               │   S3 Bucket (backup store)   │
               │   s3://matrix-backup-<name>/ │
               │   Encrypted GPG archives      │
               └──────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Communicates With |
|-----------|----------------|-------------------|
| AWS Security Group | Stateful firewall — controls which ports are open to internet; replaces UFW/iptables role from original VPS setup | EC2 instance (gate on inbound traffic) |
| Nginx (HTTP-only) | Single HTTP server block on :80; routes by path prefix to Element or Synapse; serves static .well-known JSON; sets X-Forwarded-For | Element Web, Synapse (internal Docker network) |
| Element Web | Serves static SPA (HTML/JS/CSS); client-side app that makes Matrix API calls to Synapse | Synapse (browser makes direct API calls via Nginx proxy) |
| Synapse | Matrix homeserver; handles registration, login, message events, E2EE key distribution, room state | PostgreSQL (exclusive), Nginx (inbound), optionally SMTP |
| PostgreSQL 15 | Persistent store for all Synapse state: users, rooms, messages, encrypted event blobs | Synapse only (isolated on internal Docker network) |
| S3 Bucket | Offsite backup store for encrypted GPG archives of pg_dump + media + configs | EC2 via aws-cli (outbound only) |

---

## What Changes from the Existing Stack

The existing stack was built for TLS + custom domain operation. The EC2 POC requires targeted adaptations.
No rewrites — only config edits.

### Change 1: Nginx — Replace TLS server blocks with HTTP-only

**What exists:** Four server blocks in `proxy/conf.d/element.conf`:
- HTTP→HTTPS redirect block (`:80 → 301`)
- Element Web on `443 ssl http2` (chat.example.com)
- Synapse API on `443 ssl http2` (matrix.example.com)
- Federation on `8448 ssl http2`
- .well-known on `443 ssl http2` (example.com)

**What to replace it with:** A single HTTP server block on `:80` with path-based routing
using the EC2 public DNS hostname as `server_name` (or `_` for wildcard):

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name _;   # Accept any hostname (EC2 public DNS)

    # Element Web — root
    location / {
        proxy_pass         http://element:80;
        proxy_set_header   Host               $host;
        proxy_set_header   X-Real-IP          $remote_addr;
        proxy_set_header   X-Forwarded-For    $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto  $scheme;
    }

    # Synapse Matrix client + admin API
    location ~ ^(/_matrix|/_synapse/client) {
        proxy_pass         http://synapse:8008;
        proxy_set_header   Host               $host;
        proxy_set_header   X-Real-IP          $remote_addr;
        proxy_set_header   X-Forwarded-For    $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto  $scheme;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade            $http_upgrade;
        proxy_set_header   Connection         "upgrade";
        client_max_body_size 50m;
    }

    # Health check passthrough
    location /health {
        proxy_pass http://synapse:8008/health;
    }

    # .well-known Matrix discovery
    location /.well-known/matrix/ {
        alias            /var/www/well-known/matrix/;
        default_type     application/json;
        add_header       Access-Control-Allow-Origin "*" always;
        add_header       Cache-Control "public, max-age=3600";
    }
}
```

**What to remove:**
- `proxy/snippets/tls-params.conf` include from `nginx.conf` (ssl_* directives fail without certificates)
- All `ssl_certificate` and `ssl_certificate_key` directives
- All `listen 443 ssl` and `listen 8448 ssl` blocks
- `include /etc/nginx/snippets/tls-params.conf;` line in `nginx.conf`
- HSTS header from `security-headers.conf` (`Strict-Transport-Security` must not be sent over HTTP)

**What to keep:**
- `X-Content-Type-Options`, `X-Frame-Options`, `X-XSS-Protection`, `Referrer-Policy` security headers (safe over HTTP)
- gzip compression
- `client_max_body_size 50m`
- WebSocket upgrade headers on `/_matrix` location

### Change 2: docker-compose.yml — Remove Certbot, simplify ports

**Remove Certbot service entirely.** No TLS = no certificate management needed.

```yaml
# REMOVE these services:
certbot:
  image: certbot/certbot
  ...

# REMOVE these volumes:
certbot_conf:
certbot_webroot:

# REMOVE from nginx volumes:
- certbot_conf:/etc/letsencrypt:ro
- certbot_webroot:/var/www/certbot:ro

# SIMPLIFY nginx ports — only 80 needed for POC:
ports:
  - "80:80"
  # 443 and 8448 removed; re-add in TLS phase
```

### Change 3: Synapse homeserver.yaml — Update public_baseurl

**Existing values (example.com):**
```yaml
server_name: "example.com"
public_baseurl: "https://matrix.example.com/"
web_client_location: "https://chat.example.com/"
```

**EC2 POC values:**
```yaml
server_name: "ec2-<ip>.compute-1.amazonaws.com"
public_baseurl: "http://ec2-<ip>.compute-1.amazonaws.com/"
web_client_location: "http://ec2-<ip>.compute-1.amazonaws.com/"
```

**Critical distinction:** `server_name` determines Matrix user IDs (`@user:hostname`).
For a POC this is the EC2 hostname. When custom domain is added later, this value
CANNOT be changed without breaking all existing user accounts and room addresses.
For POC use, this tradeoff is acceptable — accounts will be recreated on the production domain.

**Synapse HTTP support:** The listener in `homeserver.yaml` already has `tls: false` and
`x_forwarded: true` — no change needed there. Synapse itself only listens on :8008 without
TLS; TLS termination was always the proxy's job. HTTP `public_baseurl` is explicitly supported
in Synapse for reverse-proxy-behind configurations.

### Change 4: Element config.json — Update homeserver URL

```json
{
  "default_server_config": {
    "m.homeserver": {
      "base_url": "http://ec2-<ip>.compute-1.amazonaws.com",
      "server_name": "ec2-<ip>.compute-1.amazonaws.com"
    },
    "m.identity_server": {
      "base_url": ""
    }
  }
}
```

Element Web does not enforce HTTPS for the `base_url`. It will connect over HTTP for POC.

### Change 5: .well-known files — Update URLs

`well-known/matrix/client`:
```json
{
    "m.homeserver": {
        "base_url": "http://ec2-<ip>.compute-1.amazonaws.com"
    },
    "m.identity_server": {
        "base_url": ""
    }
}
```

`well-known/matrix/server`:
```json
{
    "m.server": "ec2-<ip>.compute-1.amazonaws.com:80"
}
```

**Note on .well-known and discovery:** The Matrix spec says `/.well-known/matrix/client`
should be fetched from `https://hostname/...` — requiring HTTPS for auto-discovery.
For a POC with no custom domain, this does not matter because:
1. Element config.json hardcodes the homeserver URL directly (bypasses auto-discovery)
2. Federation is disabled (`.well-known/matrix/server` is unused)
3. Auto-discovery only helps when users type just their username/domain — not needed here

The .well-known files should still be served (they validate correctly when Element reads
them via config.json), but they are not relied upon for connection.

---

## Security Group as Firewall Layer

AWS Security Groups operate at the VPC level, before traffic reaches the EC2 instance.
They replace UFW (`ufw allow 80/tcp` etc.) used in the VPS setup.

### Required Inbound Rules for EC2 POC

| Type | Protocol | Port | Source | Purpose |
|------|----------|------|--------|---------|
| SSH | TCP | 22 | your-ip/32 | Admin access — restrict to specific IP, not 0.0.0.0/0 |
| HTTP | TCP | 80 | 0.0.0.0/0 | Web traffic — Element + Synapse API via Nginx |
| Custom TCP | TCP | 8448 | — | Federation port — **keep closed**; federation is OFF for POC |
| HTTPS | TCP | 443 | — | TLS — **keep closed**; re-open in TLS phase |

### Key differences from UFW approach:

- **Security groups are stateful** — if inbound port 80 is open, return traffic is automatically allowed
- **No `deny all` rule needed** — AWS default denies all inbound not matched by a rule
- **Applied at VPC, not OS level** — UFW/iptables on the instance are redundant (but not harmful)
- **Docker port mapping bypasses iptables** — Docker's own NAT rules (via iptables) handle port
  forwarding inside the instance; the security group is the effective exterior firewall

### Outbound Rules

Leave AWS default: **all outbound traffic allowed**. Required for:
- Docker image pulls
- Synapse dependency resolution
- S3 backup uploads (`aws s3 cp`)
- SMTP for email notifications (port 587)

---

## Data Flow on EC2

### Request Flow — HTTP POC

```
Browser or Element mobile app
    │
    ▼ HTTP GET http://ec2-<ip>.compute-1.amazonaws.com/
AWS Security Group → passes port 80
    │
    ▼
Nginx :80 (container, external port 80)
    │
    ├─── GET / → proxy_pass http://element:80
    │               Element Web container → returns index.html + JS bundle
    │               Browser loads SPA, reads embedded config.json
    │               config.json points to http://ec2-<ip>.compute-1.amazonaws.com
    │
    └─── Browser JS calls /_matrix/client/v3/login (HTTP, same origin)
         Nginx routes /_matrix/* → proxy_pass http://synapse:8008
             Synapse validates credentials → returns access_token
             Element stores token in browser localStorage
             All subsequent API calls: /_matrix/client/v3/* → Synapse via Nginx
             WebSocket for real-time sync: /_matrix/client/v3/sync → Nginx → Synapse

Message send:
    Browser PUT /_matrix/client/v3/rooms/{id}/send/m.room.message
        → Nginx → Synapse (port 8008)
        → Synapse INSERT INTO events (PostgreSQL) via psycopg2
        → Synapse pushes event to all connected WebSocket clients
        → Other browsers receive message in real-time
```

### Volume and Data Persistence on EC2

```
EC2 Instance (EBS root volume, 30GB recommended for POC)
    │
    ├── /var/lib/docker/volumes/
    │       │
    │       ├── compose_postgres_data/   ← PostgreSQL data directory
    │       │   (synapse database: rooms, users, events, crypto keys)
    │       │   Grows with message volume. For small POC: ~1-2GB
    │       │
    │       ├── compose_synapse_data/    ← Synapse state + signing key
    │       │   (signing.key, homeserver.pid, log files)
    │       │   Small: ~10-50MB
    │       │
    │       └── compose_synapse_media/  ← Uploaded media (images, files)
    │           (media_store/ directory)
    │           Grows with uploads. With 50M limit + few users: ~1-5GB
    │
    └── /opt/element-matrix/             ← Repo (config files, scripts)
        (homeserver.yaml, nginx.conf, etc. — small, versioned)
```

**EBS Volume Recommendation:**
- POC (< 50 users, chat-only): 30GB gp3 root volume is sufficient
- Backup overhead: encrypted archives are smaller than raw data; 7 local backups kept
- Resize later: EBS volumes can be expanded in-place with no downtime using `growpart` + `resize2fs`

### Backup Flow to S3

```
EC2 Instance (cron or manual)
    │
    ├── 1. docker exec postgres pg_dump → synapse.pgdump
    ├── 2. tar docker volume (synapse_media) → media.tar
    ├── 3. tar config files → configs.tar
    ├── 4. tar + gzip all three → archive.tar.gz
    ├── 5. gpg --symmetric AES256 → archive.tar.gz.gpg
    └── 6. aws s3 cp archive.tar.gz.gpg s3://matrix-backup-<name>/
              (uses EC2 IAM Role — no long-lived credentials on disk)
```

**Backup script adaptation:** The existing `scripts/backup.sh` uses `rclone` for offsite
upload. For S3 on EC2, replace the rclone step with `aws s3 cp` (AWS CLI). The AWS CLI
is pre-installed on Amazon Linux or easily installed on Ubuntu. Use an EC2 IAM Role with
an S3 write policy — avoids storing `AWS_ACCESS_KEY_ID` on disk.

**Required S3 bucket policy for IAM Role:**
```json
{
  "Effect": "Allow",
  "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
  "Resource": [
    "arn:aws:s3:::matrix-backup-<name>",
    "arn:aws:s3:::matrix-backup-<name>/*"
  ]
}
```

---

## Suggested Build Order

Deploy components in this sequence to validate each layer before adding complexity.

### Step 1: EC2 + Security Group
**What:** Launch EC2 instance, configure security group, SSH in, verify connectivity.
**Validates:** AWS CLI provisioning works, IAM permissions correct, instance reachable.
**Acceptance:** `ssh -i key.pem ubuntu@ec2-<ip>.compute-1.amazonaws.com` succeeds.

### Step 2: Docker Engine + Compose Plugin
**What:** Install Docker on the EC2 instance, add ubuntu user to docker group.
**Validates:** Container runtime functional on this AMI.
**Acceptance:** `docker run --rm hello-world` exits 0.

### Step 3: Postgres + Synapse (no Nginx yet)
**What:** Deploy Postgres and Synapse containers only, with updated homeserver.yaml pointing
to EC2 hostname. Test Synapse health check directly.
**Validates:** Synapse starts, connects to Postgres, signing key generated.
**Acceptance:** `curl http://localhost:8008/health` returns `{}`.

### Step 4: Nginx HTTP-only + Element
**What:** Add Nginx and Element containers with adapted HTTP-only config. Test routing.
**Validates:** Path-based routing works; Element loads; Synapse API reachable via Nginx.
**Acceptance:** `curl http://ec2-<ip>.compute-1.amazonaws.com/` returns HTML; `curl http://ec2-<ip>.compute-1.amazonaws.com/_matrix/client/versions` returns JSON.

### Step 5: Admin Bootstrap + Default Rooms
**What:** Run `bootstrap-admin.sh` to create admin user; run `create-default-rooms.py`.
**Validates:** Admin API accessible, room creation works.
**Acceptance:** Admin can log in to Element; Space and 6 default rooms visible.

### Step 6: Two-User E2EE Test
**What:** Register two users via invite token. Exchange encrypted messages.
**Validates:** Registration flow, invite tokens, E2EE key exchange end-to-end.
**Acceptance:** Message visible to recipient with lock icon; Synapse cannot read content.

### Step 7: S3 Backup
**What:** Configure IAM Role on EC2, adapt backup script to use `aws s3 cp`, run first backup.
**Validates:** Backup pipeline works; restore tested from S3 archive.
**Acceptance:** `aws s3 ls s3://matrix-backup-<name>/` shows encrypted archive.

---

## Architectural Patterns

### Pattern 1: Path-Based Routing on a Single Port

**What:** All traffic enters on port 80. Nginx routes by URL path prefix — `/` to Element,
`/_matrix/*` and `/_synapse/*` to Synapse. No subdomain separation needed.
**When to use:** When a single EC2 public hostname serves all services. Simplest config for POC.
**Trade-offs:** No virtual host separation; works fine because only one server is needed.
In TLS phase, virtual hosts (chat.example.com, matrix.example.com) provide clearer separation
but path-based routing works equivalently for a single-domain deployment.

### Pattern 2: Hardcoded homeserver URL in Element config.json

**What:** Element Web's `config.json` has the Synapse base URL hardcoded rather than relying
on `.well-known/matrix/client` auto-discovery.
**When to use:** When the server doesn't have a custom domain (EC2 hostname), or when
the `.well-known` endpoint can't be served over HTTPS (required by Matrix spec for discovery).
**Trade-offs:** Users can't use just `@user:hostname` in other clients — must enter the full
URL manually. Acceptable for a POC with a managed user population.

### Pattern 3: IAM Role Instead of Access Keys for S3

**What:** Attach an IAM Role to the EC2 instance that grants S3 write access.
AWS CLI picks up credentials automatically via instance metadata endpoint.
**When to use:** Always on EC2. Long-lived credentials on disk are a security risk.
**Trade-offs:** Requires IAM setup during provisioning; not applicable for non-EC2 environments.

---

## Anti-Patterns

### Anti-Pattern 1: Keeping TLS Snippets Active Without Certificates

**What people do:** Leave `include /etc/nginx/snippets/tls-params.conf;` in `nginx.conf`
after removing the certbot service.
**Why it's wrong:** The ssl_* directives in tls-params.conf (ssl_protocols, ssl_stapling,
ssl_session_cache) are only valid inside `server {}` blocks with `ssl on` or `listen ... ssl`.
Nginx will fail to start with parse errors.
**Do this instead:** Remove the `include /etc/nginx/snippets/tls-params.conf;` line from
`nginx.conf` when operating HTTP-only. The tls-params.conf file can stay on disk for the
TLS phase — just don't include it.

### Anti-Pattern 2: HSTS Header Over HTTP

**What people do:** Leave the `Strict-Transport-Security` header in `security-headers.conf`
when switching to HTTP-only operation.
**Why it's wrong:** HSTS tells browsers "always use HTTPS for this domain." If sent over HTTP,
browsers will refuse to make any HTTP connections to the same host for up to `max-age` seconds
(63072000s = 2 years in the current config). This will lock users out of the HTTP POC until
the HSTS max-age expires or headers are cleared manually.
**Do this instead:** Comment out or remove the `Strict-Transport-Security` line from
`security-headers.conf` for the POC. Re-add it when TLS is operational.

### Anti-Pattern 3: server_name as EC2 Hostname Without Acknowledging Permanence

**What people do:** Set `server_name` in `homeserver.yaml` to the EC2 public DNS hostname
thinking it can be updated to a custom domain later.
**Why it's wrong:** `server_name` is the Matrix domain — it appears in all user IDs
(`@user:ec2-<ip>.compute-1.amazonaws.com`) and room addresses. Changing it requires
complete database migration or user re-registration.
**Do this instead:** Accept this as a POC tradeoff. Document clearly that the custom domain
phase will require fresh user accounts and a new `server_name`. POC accounts are
temporary and not migrated to production.

### Anti-Pattern 4: Exposing Port 5432 in the Security Group

**What people do:** Accidentally open port 5432 in the security group for "database access."
**Why it's wrong:** PostgreSQL should never be internet-accessible. Synapse connects to
Postgres on the internal Docker network (`postgres:5432`). No external access is needed.
**Do this instead:** Keep 5432 absent from security group inbound rules. If direct Postgres
access is needed for admin, tunnel through SSH: `ssh -L 5432:localhost:5432 ubuntu@ec2-...`.

---

## Scaling Considerations

| Scale | Architecture | What Changes |
|-------|-------------|--------------|
| POC (1-50 users) | Single t3.medium, Docker Compose, Nginx HTTP | As described above |
| Early production (50-500 users) | Custom domain + TLS, same instance or t3.large, certbot re-added | Add Certbot back, update nginx.conf for HTTPS, re-add TLS snippets |
| Growth (500-5K users) | Custom domain + TLS + coturn for voice/video, EBS increase to 100GB+ | Add coturn service to Compose; upgrade EBS |
| Scale (5K-50K users) | Synapse workers, RDS PostgreSQL, S3 media backend, ALB, multiple EC2 | Significant rearchitect: Synapse workers process (message, federation, media) each run separately; requires Redis; ALB routes to workers |

### Scaling Priorities

1. **First bottleneck (Synapse single-process):** Synapse defaults to a single Python
   process. At ~1K concurrent users, the event persister becomes the bottleneck.
   Fix: Enable Synapse workers (requires Redis, application config changes).

2. **Second bottleneck (Postgres on EC2):** At ~5K users, the Postgres instance on the
   same EC2 will be I/O constrained. Fix: Migrate to AWS RDS PostgreSQL (read replicas,
   automated backups, no shared compute contention).

3. **Third bottleneck (media storage):** EBS is not scalable for media at scale.
   Fix: Configure Synapse S3 media backend (`media_storage_providers` in homeserver.yaml).

---

## Integration Points

### External Services

| Service | Integration Pattern | EC2 POC Notes |
|---------|---------------------|---------------|
| AWS S3 | `aws s3 cp` from backup script; IAM Role auth | Replace rclone in backup.sh with aws-cli command |
| SMTP (email) | Synapse → SMTP server on port 587 | Optional for POC; disable if no SMTP available |
| AWS IAM | EC2 Instance Role with S3 write permissions | No credentials on disk; automatic rotation |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Internet → Nginx | TCP port 80 via AWS Security Group | Security group is the exterior firewall |
| Nginx → Element | `proxy_pass http://element:80` on Docker internal network | Element serves static files only |
| Nginx → Synapse | `proxy_pass http://synapse:8008` on Docker internal network | X-Forwarded-For required; WebSocket upgrade required for sync |
| Synapse → Postgres | `postgres:5432` on Docker internal network (`internal` bridge) | Never exposed externally |
| EC2 → S3 | HTTPS outbound via aws-cli | IAM Role; no inbound ports needed |

---

## Sources

- Synapse Reverse Proxy Configuration: https://matrix-org.github.io/synapse/latest/reverse_proxy.html (HIGH confidence — official docs)
- Synapse Configuration Manual (public_baseurl, x_forwarded): https://matrix-org.github.io/synapse/latest/usage/configuration/config_documentation.html (HIGH confidence — official docs)
- Matrix Client-Server Spec (.well-known discovery): https://spec.matrix.org/latest/client-server-api/ (HIGH confidence — official spec)
- Element Web config.md: https://github.com/element-hq/element-web/blob/develop/docs/config.md (HIGH confidence — official source)
- EC2 Instance Hostnames: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-naming.html (HIGH confidence — official AWS docs)
- AWS Security Groups: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html (HIGH confidence — official AWS docs)
- Synapse issue #5346 (HTTP public_baseurl): https://github.com/matrix-org/synapse/issues/5346 (MEDIUM confidence — issue discussion confirms behavior)

---

*Architecture research for: Matrix/Element AWS EC2 deployment (HTTP-only POC)*
*Researched: 2026-02-20*
