# Stack Research

**Domain:** AWS EC2 deployment of Docker Compose application via AWS CLI (Matrix/Element POC)
**Researched:** 2026-02-20
**Confidence:** MEDIUM-HIGH (CLI commands verified against official AWS docs; Docker install patterns verified against multiple sources including updated 2025 guides; HTTP-only Synapse/Nginx patterns verified against official reverse proxy docs and community reports)

---

## Context

This research covers the AWS infrastructure layer only. The Matrix/Element application stack (Synapse, Postgres, Element Web, Nginx) is already built. The question is: what tooling, commands, and patterns provision the EC2 instance, install Docker, and get the Compose stack running — entirely via AWS CLI.

---

## Recommended Stack

### Core Infrastructure Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Amazon Linux 2023 (AL2023) | Latest via SSM | EC2 host OS | AWS-native, actively maintained (2023-2028+ support window), ships Docker in default dnf repos, kernel 6.1 LTS, SELinux enabled by default, optimized for EC2. Avoids the Amazon Linux 2 end-of-life trap (AL2 EOL June 2025). |
| AWS CLI v2 | 2.x (latest) | All provisioning commands | Current version; v1 is deprecated. SSM parameter resolution for AMI IDs only works in v2. |
| Docker Engine | 27.x (via Docker CE repo) | Container runtime | AL2023 dnf ships Docker 25.x; Docker CE repo provides 27.x. Either works for POC. Use Docker CE repo for production-grade install to track upstream releases. |
| Docker Compose v2 plugin | Latest (via Docker CE repo) | Stack orchestration | `docker compose` (no hyphen) is the current standard. Standalone `docker-compose` binary is legacy. Compose v2 plugin ships with Docker CE. |
| EC2 t3.medium | Current generation | Compute | 2 vCPU / 4 GB RAM. Sufficient for POC (Synapse + Postgres + Nginx + Element Web fit in ~2.5-3 GB RAM). t3 = burstable; launches in unlimited mode by default. Watch CPUCreditBalance in CloudWatch. |
| EBS gp3 | 30 GB root (minimum) | Block storage | gp3 is current generation: 3,000 baseline IOPS + 125 MiB/s included at no extra cost vs gp2 performance tiers. 30 GB root for POC; expand to 50+ GB before media/message volume grows. |

### AWS Supporting Services

| Service | Purpose | When to Use |
|---------|---------|-------------|
| EC2 Security Groups | Network access control | Required — open ports 22 (SSH), 80 (HTTP), 443 (HTTPS), 8448 (Matrix federation). Restrict port 22 to your IP. |
| EC2 Key Pairs (ED25519) | SSH authentication | Required for initial access and SCP file transfer. ED25519 preferred over RSA for modern SSH. |
| IAM Instance Profile + Role | EC2 → S3 backup access | Required for S3 backup without embedding credentials. Attach at launch via `--iam-instance-profile`. |
| S3 Bucket | Encrypted backup storage | Use existing `backup.sh` script; instance profile grants write access without IAM user keys. |
| SSM Parameter Store (public) | AMI ID resolution | Use `resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64` — always gets the latest patched AMI without hardcoding IDs. |

### What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Amazon Linux 2 | EOL June 2025; `amazon-linux-extras` install method is gone; Docker install is different | Amazon Linux 2023 |
| `amazon-linux-extras install docker` | AL2 command, does not exist on AL2023 | `dnf install docker` (AL2023 default repo) or Docker CE repo |
| Standalone `docker-compose` binary (hyphenated) | Legacy v1 Python tool; deprecated upstream; not maintained | `docker compose` v2 plugin from Docker CE repo |
| Hardcoded AMI IDs in scripts | AMIs rotate; hardcoded IDs break across regions and deprecate after 90 days | SSM parameter resolution in `run-instances` |
| AWS Access Keys in EC2 environment | Credentials in env/files = credential leak risk | IAM Instance Profile attached at launch |
| EC2 user-data for full Compose deployment | user-data 16 KB limit; runs once on first boot; debugging is painful (logs only in `/var/log/cloud-init-output.log`); no SSH retry loop | user-data for Docker install only; SSH + SCP for app code + `docker compose up` |
| ECS, EKS, Elastic Beanstalk | Correct for production scale, but significant operational overhead for a POC. ECS adds task definitions, ECR, IAM complexity with no benefit at this stage. | Plain EC2 + Docker Compose for POC |
| t3.nano / t3.micro | Synapse alone needs ~500 MB RAM; Postgres + Nginx + Element push total to 2.5+ GB | t3.medium (4 GB) minimum for this stack |

---

## CLI Command Patterns

### Step 1 — Create Key Pair

```bash
# ED25519 key pair; save private key locally
aws ec2 create-key-pair \
  --key-name matrix-poc \
  --key-type ed25519 \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/matrix-poc.pem

chmod 600 ~/.ssh/matrix-poc.pem
```

**Rationale:** ED25519 is smaller and faster than RSA 2048. The `--query KeyMaterial --output text` pattern pipes only the private key to the file, skipping JSON wrapping.

---

### Step 2 — Create Security Group

```bash
# Get your default VPC ID (or specify one you own)
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text)

# Create security group
SG_ID=$(aws ec2 create-security-group \
  --group-name matrix-poc-sg \
  --description "Matrix/Element POC security group" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' \
  --output text)

echo "Security group: $SG_ID"

# Get your current public IP
MY_IP=$(curl -s https://checkip.amazonaws.com)/32

# SSH — restricted to your IP only
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 22 --cidr "$MY_IP"

# HTTP — open to world (Matrix federation, Element Web)
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

# HTTPS — open to world
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 443 --cidr 0.0.0.0/0

# Matrix federation port — open to world (even with federation off, keeps options open)
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 8448 --cidr 0.0.0.0/0
```

**Port rationale:**
- Port 22: SSH — restrict to known IP to prevent brute-force bot traffic
- Port 80: HTTP — Nginx redirect to HTTPS (or POC plain-HTTP config)
- Port 443: HTTPS — main app traffic
- Port 8448: Matrix federation — open now even though federation is disabled; allows future enable without SG change

---

### Step 3 — Create IAM Role for S3 Backup (do once)

```bash
# Trust policy — allows EC2 to assume this role
cat > /tmp/ec2-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name matrix-poc-ec2-role \
  --assume-role-policy-document file:///tmp/ec2-trust.json

# Attach S3 write policy (scope to specific bucket in production)
aws iam put-role-policy \
  --role-name matrix-poc-ec2-role \
  --policy-name matrix-poc-s3-backup \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::YOUR-BACKUP-BUCKET",
        "arn:aws:s3:::YOUR-BACKUP-BUCKET/*"
      ]
    }]
  }'

# Create instance profile and add role
aws iam create-instance-profile \
  --instance-profile-name matrix-poc-instance-profile

aws iam add-role-to-instance-profile \
  --instance-profile-name matrix-poc-instance-profile \
  --role-name matrix-poc-ec2-role
```

**Rationale:** Instance profiles are the correct pattern for EC2-to-S3 access. Embedding AWS credentials in environment variables or files is an anti-pattern that creates credential leak risk. The instance metadata service (IMDS) provides temporary credentials automatically.

---

### Step 4 — Launch EC2 Instance

```bash
# User-data script: install Docker only (not the app)
cat > /tmp/userdata.sh << 'EOF'
#!/bin/bash
# Runs as root on first boot

# Update system
dnf update -y

# Add Docker CE repository (provides docker-compose-plugin, newer Engine)
dnf install -y dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
# AL2023 uses CentOS-compatible packages; pin to RHEL/CentOS 9
sed -i 's/$releasever/9/g' /etc/yum.repos.d/docker-ce.repo

# Install Docker CE + Compose plugin
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure Docker daemon
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'DAEMON'
{
  "log-driver": "json-file",
  "log-opts": {"max-size": "100m", "max-file": "3"},
  "live-restore": true
}
DAEMON

# Enable and start Docker
systemctl enable --now docker

# Add ec2-user to docker group (takes effect on next login)
usermod -aG docker ec2-user

# Mark completion
echo "Docker install complete" > /tmp/userdata-done.txt
EOF

# Launch instance
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --instance-type t3.medium \
  --key-name matrix-poc \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile Name=matrix-poc-instance-profile \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":30,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --user-data file:///tmp/userdata.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=matrix-poc}]' \
  --region us-east-1 \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Instance ID: $INSTANCE_ID"
```

**Key design decisions in this command:**
- `resolve:ssm:...` — dynamic AMI resolution, never stale
- `--block-device-mappings` with gp3/30GB — overrides the default 8GB root volume; 30 GB covers OS + Docker images + Postgres + Synapse media for a POC
- `--iam-instance-profile` at launch — avoids `associate-iam-instance-profile` call later
- user-data handles Docker install only — app deployment is done via SSH after boot (see Step 6)
- `--tag-specifications` — tags the instance for cost tracking and identification

---

### Step 5 — Wait for Instance + Get Hostname

```bash
# Wait for instance to reach running state (polls every 15s, timeout 10 min)
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

# Get public DNS hostname
PUBLIC_DNS=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicDnsName' \
  --output text)

echo "Public DNS: $PUBLIC_DNS"
# Example: ec2-54-123-45-67.compute-1.amazonaws.com

# Wait additional 60 seconds for cloud-init / user-data to complete Docker install
echo "Waiting for cloud-init..."
sleep 60

# Verify Docker install completed (optional)
ssh -i ~/.ssh/matrix-poc.pem \
  -o StrictHostKeyChecking=no \
  ec2-user@"$PUBLIC_DNS" \
  "cat /tmp/userdata-done.txt && docker --version && docker compose version"
```

**Rationale for `sleep 60`:** `aws ec2 wait instance-running` fires when the EC2 API sees the instance as running — but cloud-init (which runs the user-data script) is still executing. The Docker install takes 30-90 seconds. Without this wait, SSH attempts to run Docker commands will fail with "command not found".

---

### Step 6 — Deploy the Compose Stack

```bash
# Copy project files to EC2
scp -i ~/.ssh/matrix-poc.pem -r \
  /Users/myownip/workspace/element-matrix \
  ec2-user@"$PUBLIC_DNS":~/element-matrix

# SSH in and configure + launch
ssh -i ~/.ssh/matrix-poc.pem ec2-user@"$PUBLIC_DNS" << 'REMOTE'
cd ~/element-matrix/compose

# Copy env template and edit for EC2 (no TLS for POC)
cp .env.example .env
# Edit .env: set DOMAIN to $PUBLIC_DNS, disable TLS-related options

# Generate Synapse signing key
docker compose run --rm -e SYNAPSE_SERVER_NAME="$PUBLIC_DNS" synapse generate

# Start stack
docker compose up -d

# Check health
sleep 30
docker compose ps
curl -s http://localhost:8008/health
REMOTE
```

**Note on Nginx for POC (no TLS):** The existing `proxy/conf.d/element.conf` expects TLS. For EC2 public hostname POC, you need an alternate Nginx config that serves HTTP only. See the dedicated section below: "Adapting the Stack for HTTP-Only EC2 POC".

---

### Step 7 — Create S3 Backup Bucket

```bash
# Create bucket (bucket names must be globally unique)
BUCKET_NAME="matrix-poc-backup-$(date +%s)"

aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region us-east-1

# Enable versioning (cheap protection against overwrite)
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# Block all public access
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "Backup bucket: $BUCKET_NAME"
```

---

## Adapting the Stack for HTTP-Only EC2 POC

The existing stack was built for HTTPS + custom domain. Three files need changes for a no-TLS, EC2-public-DNS deployment.

### OS Choice: Ubuntu 22.04 LTS vs Amazon Linux 2023

Both work. The decision matters for Docker install commands and community troubleshooting support.

| Criterion | Ubuntu 22.04 LTS | Amazon Linux 2023 |
|-----------|-----------------|-------------------|
| Docker install | One command via `get.docker.com` — gives Docker 27.x + Compose plugin in one step | dnf install gives Docker 25.x without Compose plugin; Docker CE repo requires CentOS9 workaround (`sed -i 's/$releasever/9/g'`) |
| Default user | `ubuntu` | `ec2-user` |
| Matrix/Docker community troubleshooting | Large (most guides assume Ubuntu) | Smaller |
| AMI resolution | `--owners 099720109477` (Canonical) with name filter | `resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64` |
| AWS optimization | Good | Excellent (kernel, networking tuned for EC2) |
| EBS root device | `/dev/sda1` | `/dev/xvda` |
| EOL | April 2027 (standard) | 2028+ |
| **Recommendation** | Preferred for this POC | Use if team mandates AWS-native OS |

**Confidence:** MEDIUM — judgment call based on community patterns and install complexity.

**Ubuntu AMI lookup command:**

```bash
# Canonical's owner ID: 099720109477 — always verify with this, not just name filter
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters \
    'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*' \
    'Name=state,Values=available' \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text \
  --region us-east-1)
```

**Why `--owners 099720109477`:** Anyone can publish an AMI named "ubuntu-22.04-*". Without the Canonical owner ID filter, a malicious AMI could be returned. This is a documented supply chain risk. [Source: Ubuntu AWS official docs]

---

### Nginx: HTTP-Only Configuration for POC

Replace `proxy/conf.d/element.conf` (or create `proxy/conf.d/element-http.conf` in a POC branch).

**Changes from existing TLS config:**
- Remove all `ssl_certificate`, `ssl_certificate_key` directives
- Remove `listen 443 ssl http2` — use `listen 80` only
- Remove the 301 redirect block (no HTTPS to redirect to)
- Remove `include /etc/nginx/snippets/tls-params.conf` reference from nginx.conf
- Use `server_name _` (catch-all) to accept EC2 public DNS without hardcoding it
- Combine Element Web + Synapse into a single server block (POC simplicity)

```nginx
# proxy/conf.d/element-http.conf
# POC: HTTP-only, no TLS, no custom domain
# Handles all traffic on port 80: Element Web, Synapse API, .well-known

server {
    listen 80;
    listen [::]:80;
    server_name _;    # Catch-all accepts EC2 public DNS, IP, or any hostname

    # Element Web (served from root)
    location / {
        proxy_pass http://element:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Synapse client + admin API
    location ~ ^(/_matrix|/_synapse/client) {
        proxy_pass http://synapse:8008;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support (required for /sync long-polling)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Match Synapse upload limit from homeserver.yaml
        client_max_body_size 50m;

        # Prevent 504 on long /sync requests
        proxy_read_timeout 600s;
    }

    # Synapse health endpoint
    location /health {
        proxy_pass http://synapse:8008/health;
    }

    # Matrix client discovery
    location /.well-known/matrix/ {
        alias /var/www/well-known/matrix/;
        default_type application/json;
        add_header Access-Control-Allow-Origin "*" always;
        add_header Cache-Control "public, max-age=3600";
    }
}
```

**Also update `proxy/nginx.conf`:** Remove the TLS params include — without certificates, nginx will fail to start.

```nginx
# Remove this line from proxy/nginx.conf:
# include /etc/nginx/snippets/tls-params.conf;
```

**Confidence:** HIGH — standard Nginx reverse proxy config; Synapse official reverse proxy docs confirm these headers and the `proxy_pass http://synapse:8008` target. [Source: Synapse reverse proxy docs]

---

### Docker Compose: HTTP-Only Override File

Rather than editing the production `docker-compose.yml`, create a POC override file. Docker Compose merges override files at runtime.

```yaml
# compose/docker-compose.poc.yml
# Override for HTTP-only EC2 POC deployment
# Usage: docker compose -f docker-compose.yml -f docker-compose.poc.yml up -d

services:
  nginx:
    ports:
      - "80:80"
      # Removes 443:443 and 8448:8448 from base file via override
    volumes:
      - ../proxy/nginx.conf:/etc/nginx/nginx.conf:ro
      - ../proxy/conf.d:/etc/nginx/conf.d:ro
      # Note: snippets still mounted but tls-params.conf not included in nginx.conf
      - ../proxy/snippets:/etc/nginx/snippets:ro
      - ../well-known:/var/www/well-known:ro
      # No certbot volumes

  # Remove certbot from POC stack
  certbot:
    profiles:
      - production-only    # Excludes service unless --profile production-only specified

volumes:
  # Nullify certbot volumes for POC
  certbot_conf:
    driver: local
  certbot_webroot:
    driver: local
```

**Launch command:**

```bash
docker compose \
  -f /opt/element-matrix/compose/docker-compose.yml \
  -f /opt/element-matrix/compose/docker-compose.poc.yml \
  up -d
```

**Confidence:** MEDIUM — Docker Compose profiles and override semantics are well-documented; the specific override pattern for removing services uses `profiles` which requires Compose v2.x (bundled with Docker Engine 23+).

---

### Synapse homeserver.yaml: HTTP-Only Changes

Two settings must be updated to use the EC2 public DNS and HTTP scheme.

```yaml
# In synapse/homeserver.yaml — POC values

# server_name: the identity domain for Matrix IDs (@user:THIS_VALUE)
# WARNING: This is permanent — changing it later requires recreating all accounts
# For POC: EC2 public DNS is acceptable
server_name: "ec2-54-123-45-67.compute-1.amazonaws.com"

# public_baseurl: URL clients use to reach this server via the proxy
# Must match what's in element/config.json
public_baseurl: "http://ec2-54-123-45-67.compute-1.amazonaws.com/"

# web_client_location: where to redirect / to
web_client_location: "http://ec2-54-123-45-67.compute-1.amazonaws.com/"

# Listener stays unchanged — Synapse itself still uses HTTP internally
# x_forwarded: true is REQUIRED even without TLS (Nginx is still a proxy)
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true    # Keep this — tells Synapse to trust X-Forwarded-For
    bind_addresses: ["0.0.0.0"]
    resources:
      - names: [client, federation]
        compress: false
```

**Key warnings:**
1. `server_name` is baked permanently into all Matrix IDs. Do NOT use the EC2 DNS as `server_name` for any deployment you plan to keep. This is POC-only.
2. Synapse will log warnings about `public_baseurl` being HTTP. These are warnings, not errors — Synapse still starts. [Source: Synapse GitHub issue #5346 — enforcement was proposed but not implemented]
3. `x_forwarded: true` must stay set. Without it, Synapse thinks all requests come from the Nginx container IP, not the real client IP — breaking rate limiting.

**Confidence:** MEDIUM — Synapse docs confirm `public_baseurl` can be HTTP for development. GitHub issue #5346 shows Synapse considered rejecting it but did not enforce as of latest release. Community POC reports confirm this works.

---

### Element Web config.json: HTTP-Only Changes

```json
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "http://ec2-54-123-45-67.compute-1.amazonaws.com",
            "server_name": "ec2-54-123-45-67.compute-1.amazonaws.com"
        }
    }
}
```

**Note:** Element Web is a static SPA. It will load over HTTP. All its API calls to Synapse will also be HTTP (same origin). No mixed content warnings since everything is HTTP — mixed content only triggers when an HTTPS page loads HTTP resources.

---

### .well-known Files: HTTP-Only Changes

```json
// well-known/matrix/client
{
    "m.homeserver": {
        "base_url": "http://ec2-54-123-45-67.compute-1.amazonaws.com"
    }
}

// well-known/matrix/server
{
    "m.server": "ec2-54-123-45-67.compute-1.amazonaws.com:80"
}
```

---

### Browser HTTPS-Only Mode: POC Window Assessment

**Current state (HIGH confidence):** HTTP-only URLs work in all major browsers as of early 2026. Chrome, Firefox, and Safari default to permitting HTTP. HTTPS-only mode exists in Firefox but is opt-in (not enabled by default).

**Risk timeline:**
- **October 2025:** Google announced Chrome 154 will enable "HTTPS by default" (~October 2026). [Source: ghacks.net, October 2025 — MEDIUM confidence, news source not Google official]
- **Practical impact:** Chrome 154 will warn users or upgrade HTTP → HTTPS automatically. This would break an HTTP-only Matrix POC in late 2026.
- **POC window:** The HTTP-only approach is safe for POC testing through mid-2026. Plan to add TLS before Chrome 154 ships.

**No mixed content risk:** Because Element Web, Nginx, and Synapse are all HTTP-only (not HTTPS serving HTTP subrequests), there is no mixed content. Mixed content only occurs when an HTTPS page loads HTTP sub-resources.

**Confidence on Chrome timeline:** MEDIUM — announced in October 2025 per news sources; specific behavior in Chrome 154 not yet fully documented.

---

## Stack Patterns by Variant

**If POC succeeds and production is next:**
- Swap t3.medium for m5.large (2 vCPU / 8 GB, non-burstable, predictable performance)
- Add RDS PostgreSQL to remove DB from the EC2 instance
- Add S3 media backend for Synapse (remove local volume dependency)
- Add ALB in front for SSL termination and future horizontal scaling
- Synapse workers for 50K users (event_creator, federation_reader, etc.)

**If staying on EC2 for semi-production:**
- Keep t3.medium but monitor CPUCreditBalance — switch to `unlimited` mode or upgrade to m5 if credits drain consistently
- Increase EBS to 100 GB before media storage grows
- Add lifecycle policy on S3 backup bucket to expire old backups (cost control)

**If you need a domain before TLS:**
- Point Route 53 A record at EC2 public IP
- Replace EC2 hostname with domain in all configs
- Add Certbot to get Let's Encrypt cert (existing `certbot` service in Compose is ready)

---

## Version Compatibility

| Component | Version | Compatible With | Notes |
|-----------|---------|-----------------|-------|
| Amazon Linux 2023 | AL2023 (kernel 6.1) | Docker CE 24+ | No compatibility issues; Docker CE repo uses CentOS 9 packages which are AL2023-compatible |
| Docker CE | 27.x | docker-compose-plugin 2.x | v2 plugin is bundled with Docker CE repo install |
| docker-compose-plugin | 2.x | AL2023 dnf | Install via Docker CE CentOS repo with `$releasever` set to `9` |
| AL2023 default docker | 25.x | docker-compose-plugin | AL2023 default repo includes docker but NOT the compose plugin — requires manual CLI plugin install if using default repo |
| Synapse latest | Docker image | Docker Compose v2 | No version pinning issue; use specific Synapse tag in production |
| PostgreSQL 15 | Docker image | Docker Compose v2 | No version pinning issue |

**Known compatibility gotcha:** AL2023 default `dnf install docker` gives you Docker Engine but not the Compose plugin. The `docker-compose-plugin` package is only available via the Docker CE repository (using CentOS 9 base URL). This is documented in multiple 2025 sources and is the primary installation trap on AL2023.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Amazon Linux 2023 | Ubuntu 22.04 LTS | When team has strong Ubuntu expertise, or multi-cloud portability matters. Ubuntu's `get.docker.com` script is simpler (one command gives Docker 27.x + Compose plugin; no CentOS9 repo workaround needed). See OS comparison table above. |
| Docker CE repo install | AL2023 default repo docker | When you only need the Docker daemon (no Compose plugin). Default repo is simpler but requires separate Compose plugin install. |
| t3.medium | t3.large (8 GB RAM) | When running media-heavy rooms at POC scale, or when Synapse workers are added. t3.large at ~$60/mo is still budget-conscious. |
| EBS gp3 | EBS gp2 | Only use gp2 if restoring from an existing gp2 snapshot. gp3 is strictly better (same or lower price, guaranteed baseline IOPS). |
| IAM Instance Profile | AWS access keys in env | Never use access keys in env. Instance profiles are the correct pattern with no exceptions. |
| SSH + SCP for app deploy | Full user-data bootstrap | user-data is appropriate for Docker install (idempotent, runs once). Full app deploy in user-data is fragile: 16 KB limit, single-run, hard to debug. SSH deploy is explicit and repeatable. |
| Plain EC2 + Docker Compose | ECS Fargate / EKS | Use ECS/EKS for production scale (50K users, multiple Synapse workers). For POC, the operational overhead is unjustified. |

---

## Confidence Levels by Section

| Recommendation | Confidence | Basis |
|----------------|------------|-------|
| Amazon Linux 2023 as host OS | HIGH | Official AWS documentation; AL2 EOL confirmed |
| SSM parameter for AMI ID resolution | HIGH | Official AWS EC2 documentation |
| AWS CLI v2 commands syntax | HIGH | Official AWS CLI reference docs (2.33.x verified) |
| Docker CE repo for AL2023 with `sed -i 's/$releasever/9/g'` | MEDIUM | Multiple community sources (2025 dated), AWS re:Post, GitHub gists; not in official Docker docs as an explicit AL2023 step |
| user-data runs as root / no sudo needed | HIGH | Official AWS EC2 user-data documentation |
| user-data 16 KB limit | HIGH | Official AWS EC2 user-data documentation |
| t3.medium unlimited mode by default | HIGH | Official AWS EC2 T3 documentation |
| gp3 superiority over gp2 | HIGH | Official AWS EBS documentation |
| IAM instance profile for S3 access pattern | HIGH | Official AWS IAM + EC2 documentation |
| newgrp limitation in user-data (group change only on next SSH login) | MEDIUM | Multiple community sources, AWS re:Post; consistent across 2024-2025 guides |
| Docker memory footprint (~2.5-3 GB for full stack) | LOW | Inferred from Synapse hosting docs + community reports; no official benchmark for this exact stack |

---

## Ubuntu 22.04 Docker Install (Alternative to AL2023 User Data)

If Ubuntu 22.04 is chosen as the host OS, use this user-data script instead of the AL2023 one in Step 4:

```bash
cat > /tmp/userdata.sh << 'EOF'
#!/bin/bash
exec > /var/log/user-data.log 2>&1
set -euo pipefail

# Update system
apt-get update -y
apt-get upgrade -y

# Install Docker via official script — gives Docker 27.x + Compose plugin in one command
curl -fsSL https://get.docker.com | sh

# Add ubuntu user to docker group (takes effect on next login)
usermod -aG docker ubuntu

# Configure Docker daemon
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'DAEMON'
{
  "log-driver": "json-file",
  "log-opts": {"max-size": "100m", "max-file": "3"},
  "live-restore": true
}
DAEMON

# Enable on boot
systemctl enable docker

# Install supporting tools
apt-get install -y git python3-pip

echo "Docker install complete: $(date)" > /tmp/userdata-done.txt
EOF
```

**Block device mapping for Ubuntu (note different root device name):**

```bash
# Ubuntu uses /dev/sda1, not /dev/xvda (AL2023)
--block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":30,"VolumeType":"gp3","DeleteOnTermination":true}}]'
```

**SSH user for Ubuntu is `ubuntu`, not `ec2-user`:**

```bash
ssh -i ~/.ssh/matrix-poc.pem ubuntu@"$PUBLIC_DNS"
scp -i ~/.ssh/matrix-poc.pem -r /path/to/element-matrix ubuntu@"$PUBLIC_DNS":~/element-matrix
```

**Confidence:** HIGH — Docker official install script and Ubuntu EC2 patterns are well-documented and widely verified.

---

## Sources

- AWS EC2 User Data documentation — https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html (user-data behavior, root execution, 16 KB limit, `file://` auto-base64 encoding confirmed)
- AL2023 on EC2 documentation — https://docs.aws.amazon.com/linux/al2023/ug/ec2.html (SSM parameter AMI resolution, `resolve:ssm:` syntax)
- AWS CLI create-security-group reference — https://docs.aws.amazon.com/cli/v1/userguide/cli-services-ec2-sg.html (security group CLI commands)
- AWS CLI authorize-security-group-ingress — https://docs.aws.amazon.com/cli/latest/reference/ec2/authorize-security-group-ingress.html
- AWS CLI run-instances reference — https://docs.aws.amazon.com/cli/latest/reference/ec2/run-instances.html
- AWS CLI ec2 wait instance-running — https://docs.aws.amazon.com/cli/latest/reference/ec2/wait/instance-running.html
- IAM roles for EC2 — https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html
- Grant EC2 access to S3 — https://repost.aws/knowledge-center/ec2-instance-access-s3-bucket
- Docker setup on AL2023 (GitHub gist, maintained 2025) — https://gist.github.com/thimslugga/36019e15b2a47a48c495b661d18faa6d (AL2023 Docker install commands verified; MEDIUM confidence)
- Docker + Compose on AL2023 (September 2025 update) — https://medium.com/@fredmanre/how-to-configure-docker-docker-compose-in-aws-ec2-amazon-linux-2023-ami-ab4d10b2bcdc (confirmed CentOS9 repo workaround required; MEDIUM confidence)
- AWS EC2 T3 instances — https://aws.amazon.com/ec2/instance-types/t3/ (burstable behavior, unlimited mode; HIGH confidence)
- EBS volume types — https://docs.aws.amazon.com/whitepapers/latest/optimizing-postgresql-on-ec2-using-ebs/ebs-volume-types.html (gp3 vs gp2; HIGH confidence)
- Matrix.org Synapse hosting — https://matrix.org/docs/older/understanding-synapse-hosting/ (memory requirements context; MEDIUM confidence)
- Synapse Reverse Proxy documentation — https://matrix-org.github.io/synapse/latest/reverse_proxy.html (Nginx headers, proxy_pass target, no URI normalization requirement; HIGH confidence)
- Synapse Configuration Manual — https://matrix-org.github.io/synapse/latest/usage/configuration/config_documentation.html (public_baseurl, server_name, x_forwarded semantics; HIGH confidence)
- Synapse GitHub issue #5346 — https://github.com/matrix-org/synapse/issues/5346 (HTTP public_baseurl not enforced; MEDIUM confidence)
- Ubuntu AWS launch instance documentation — https://documentation.ubuntu.com/aws/aws-how-to/instances/launch-ubuntu-ec2-instance/ (run-instances syntax, Ubuntu-specific SSH user; HIGH confidence)
- Ubuntu AMI Finder — https://cloud-images.ubuntu.com/locator/ec2/ (Canonical owner ID 099720109477 confirmed; HIGH confidence)
- Google Chrome HTTPS by default announcement — https://www.ghacks.net/2025/10/30/google-chrome-to-enable-https-by-default-in-october-2026/ (Chrome 154 timeline; MEDIUM confidence — news source, not official Google)
- AWS EC2 Elastic IP documentation — https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/working-with-eips.html (allocate-address, associate-address CLI commands; HIGH confidence)

---

*Stack research for: AWS EC2 CLI deployment of Docker Compose Matrix/Element stack (HTTP-only POC)*
*Researched: 2026-02-20*
