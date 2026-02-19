# Project Research Summary

**Project:** element-matrix — Matrix/Element white-label chat platform on AWS EC2
**Domain:** AWS EC2 Docker Compose deployment — HTTP-only POC, path to 50K users
**Researched:** 2026-02-20
**Confidence:** MEDIUM-HIGH

## Executive Summary

This project deploys an already-built Docker Compose stack (Synapse homeserver + Element Web + PostgreSQL + Nginx) onto an AWS EC2 instance using only the AWS CLI. The application layer is complete; the research covers the AWS infrastructure layer: instance provisioning, Docker installation, network security, IAM, storage, and backup. The recommended approach is a t3.medium EC2 instance running Amazon Linux 2023, provisioned end-to-end via CLI, with Docker CE installed via user-data and the Compose stack deployed via SSH/SCP after boot. The entire POC runs over HTTP (no TLS) using the EC2 public hostname — this is an accepted tradeoff, not a deficiency.

The three most consequential decisions in this deployment are (1) choosing a stable `server_name` in `homeserver.yaml` before the first `docker compose up` — it is permanently baked into all user IDs and cannot be changed without dropping the entire database; (2) switching the Nginx config from TLS to HTTP-only before deployment — the existing config has `return 301 https://` which will cause an infinite redirect loop on port 80; and (3) creating an IAM instance profile at launch time — it is the prerequisite for S3 backups, CloudWatch monitoring, and SSM Session Manager, and is far simpler to attach at launch than to bolt on after the fact.

The path from POC to 50K users is well-understood but requires two architectural rethinks that should not be attempted on the POC substrate: Synapse workers (requires Redis and a restructured Nginx upstream) and multi-AZ HA (requires shared EFS storage and stateless session handling). The POC is explicitly a proving ground, not a scaling substrate. Keep it simple, validate the product, then re-architect for scale.

---

## Key Findings

### Recommended Stack

The infrastructure stack is AWS-native and minimal. Amazon Linux 2023 (AL2023) is the recommended host OS — it is AWS-supported through 2028+, ships with a kernel 6.1 LTS, and its `dnf` package manager is compatible with the Docker CE CentOS 9 repository. The critical installation detail: AL2023's default `dnf install docker` gives you Docker Engine but NOT the Compose v2 plugin. The Docker CE repository must be added with `sed -i 's/$releasever/9/g'` to substitute the CentOS 9 base URL. Without this, `docker compose` is unavailable.

For the EC2 instance, t3.medium (2 vCPU / 4 GB RAM) is the minimum and t3.large is recommended for headroom. The full stack (Synapse + Postgres + Nginx + Element) consumes approximately 2.5–3 GB RAM. EBS gp3 at 30 GB is the storage baseline — gp3 is strictly better than gp2 at equivalent size (3,000 baseline IOPS included, lower or equal cost). Use `resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64` in `run-instances` to avoid hardcoded AMI IDs that rotate every 90 days.

**Core technologies:**
- Amazon Linux 2023: EC2 host OS — AWS-native, actively maintained through 2028+, Docker CE-compatible via CentOS 9 repo workaround
- AWS CLI v2: all provisioning commands — v1 is deprecated; SSM AMI parameter resolution requires v2
- Docker CE 27.x + Compose v2 plugin: container runtime and stack orchestration — installed via Docker CE repo, not AL2023 default repo
- EC2 t3.medium (minimum) / t3.large (recommended): compute — burstable, 4 GB RAM minimum for this stack
- EBS gp3 30 GB: block storage — gp3 baseline IOPS included at no extra cost vs gp2
- IAM Instance Profile: EC2-to-S3 and EC2-to-CloudWatch access — no long-lived credentials on disk; IAM role attached at launch

### Expected Features

The feature scope is split into three tiers. The POC must deliver the P1 tier to be usable at all. P2 features are needed before real users. P3 features are required only at scale.

**Must have (P1 — POC launch):**
- EC2 instance with correctly sized EBS volume — compute substrate; undersized = demo failure
- Security group: ports 80 + 22 open, all else blocked — network access; default-deny protects Postgres (5432) and Synapse internal port (8008)
- Docker + Docker Compose v2 installed via EC2 user-data — container runtime prerequisite
- HTTP-only Nginx configuration override — existing config has `return 301 https://`; must be replaced before deployment
- `.env` and `homeserver.yaml` configured with EC2 public hostname — Matrix client discovery depends on `public_baseurl`
- Systemd unit wrapping `docker compose up -d` — without it, the stack does not restart after EC2 reboot
- IAM instance profile (S3 + CloudWatch permissions) — prerequisite for backups and monitoring
- S3 bucket with versioning + public access blocked — durable backup target
- First manual backup run to validate the backup path

**Should have (P2 — production hardening):**
- Elastic IP — EC2 public DNS changes on every stop/start; stale `public_baseurl` breaks login
- CloudWatch agent + disk/memory alarms + SNS email — EC2 default metrics exclude memory and disk
- SSM Session Manager — eliminates SSH key management; closes port 22; sessions logged to CloudTrail
- KMS-encrypted EBS — required for compliance; must be enabled at volume creation (cannot be added retroactively)
- CloudWatch log groups (awslogs driver) — container logs survive instance termination

**Defer (P3 — 50K users, not POC):**
- TLS via ALB + ACM — requires a real domain; not possible with EC2 public hostname
- Synapse workers + Redis — required at ~500-1000 concurrent active users; architectural rethink
- Multi-AZ + Auto Scaling + EFS — requires stateless Synapse architecture; not compatible with current stack
- CI/CD pipeline — manual `git pull && docker compose up -d` is the entire deploy for POC
- RDS PostgreSQL — correct for production SLA; adds VPC routing and cost overhead with no POC benefit

**Anti-features (explicitly rejected for POC):**
- TLS/Let's Encrypt on EC2 hostname — EC2 public hostnames cannot get Let's Encrypt certificates; attempting wastes time and will fail
- ECS/EKS instead of Docker Compose — incompatible with existing workflow; no benefit for single-app deployment
- VPC with private subnets + NAT Gateway — NAT Gateway costs $32/month minimum; restrictive security group on a public subnet is sufficient for POC

### Architecture Approach

The architecture is a single-port HTTP reverse proxy pattern: all external traffic enters on port 80 via AWS Security Group, hits Nginx, which routes by URL path prefix — `/` to Element Web container, `/_matrix/*` and `/_synapse/client/*` to Synapse on port 8008. PostgreSQL is isolated on the internal Docker network and never exposed externally. S3 backup is outbound-only via `aws s3 cp` using the EC2 IAM role (no credentials on disk). The five targeted configuration changes required to adapt the existing TLS-built stack to HTTP-only EC2 are: (1) replace Nginx server blocks with a single HTTP `:80` block, (2) remove Certbot service and TLS volume mounts from `docker-compose.yml`, (3) update `server_name` and `public_baseurl` in `homeserver.yaml`, (4) update `base_url` in Element `config.json`, and (5) update `.well-known` JSON files. No code rewrites — config edits only.

**Major components:**
1. AWS Security Group — stateful firewall at VPC level; replaces UFW/iptables; ports 22 (restricted to operator IP) and 80 (world) open; all else default-deny
2. Nginx (HTTP-only, :80) — single server block with path-based routing to Element and Synapse; serves static `.well-known` JSON; sets `X-Forwarded-For`; must NOT include TLS snippets or send HSTS header over HTTP
3. Element Web — static SPA served by Nginx; `config.json` must hardcode the homeserver URL (`.well-known` auto-discovery requires HTTPS per Matrix spec)
4. Synapse — Matrix homeserver; listens on `:8008` internal only; already has `tls: false` and `x_forwarded: true` on its listener; no Synapse changes needed beyond `homeserver.yaml` hostname values
5. PostgreSQL 15 — isolated on internal Docker network; must be initialized with `--encoding=UTF8 --lc-collate=C --lc-ctype=C` via `POSTGRES_INITDB_ARGS`
6. S3 Bucket + IAM Role — offsite encrypted backup; accessed via `aws s3 cp` using instance role credentials from IMDS

### Critical Pitfalls

1. **`server_name` set to EC2 hostname** — baked permanently into all user IDs and room addresses; any instance replacement or hostname change makes the database incompatible. Prevention: choose a stable logical name (short placeholder or public IP) before the first `docker compose up`; it cannot be changed without dropping the entire database.

2. **Nginx TLS config deployed to HTTP-only instance** — existing `element.conf` has `return 301 https://` redirect and TLS server blocks; deploying as-is causes infinite redirect loop and nginx startup failures from TLS directive parse errors. Prevention: replace all server blocks with a single `:80` HTTP block; remove `include tls-params.conf`; remove `Strict-Transport-Security` header (HSTS over HTTP locks browsers out for up to 2 years).

3. **`proxy_pass` trailing slash breaks Matrix signature verification** — `proxy_pass http://synapse:8008/;` causes nginx to canonicalize URIs; Matrix uses cryptographic signatures over exact request URIs; broken signatures make room invites and joins fail while `/health` continues to return 200. Prevention: use `proxy_pass http://synapse:8008;` with no trailing slash — documented explicitly in official Synapse reverse proxy docs.

4. **PostgreSQL created with wrong locale/encoding** — Synapse requires `ENCODING=UTF8`, `LC_COLLATE=C`, `LC_CTYPE=C`; default `postgres:15-alpine` container uses system locale; encoding error only surfaces on first non-ASCII message write, requiring a database rebuild to fix. Prevention: set `POSTGRES_INITDB_ARGS: "--encoding=UTF8 --lc-collate=C --lc-ctype=C"` in `docker-compose.yml` before first launch.

5. **`enable_registration: false` blocks token-based registration** — `false` is a master switch that overrides `registration_requires_token: true`; admin can create tokens via the API but users receive "Registration has been disabled." Prevention: for invite-only registration, set `enable_registration: true` AND `registration_requires_token: true` together.

---

## Implications for Roadmap

Based on combined research, the deployment has a clear sequential dependency chain. Each phase validates a layer before the next is added. Attempting to shortcut this order is the primary source of hard-to-debug failures (e.g., deploying Synapse before verifying Docker works, or testing user registration before verifying the full HTTP routing stack).

### Phase 1: AWS Infrastructure Provisioning
**Rationale:** Everything depends on a running, reachable EC2 instance. This phase has no application-level dependencies and its correctness can be verified before touching the Compose stack. IAM instance profile must be created here — it cannot be retroactively added without instance restart disruption.
**Delivers:** EC2 instance with Docker installed, security group configured, IAM role attached, SSH access confirmed.
**Addresses:** All P1 table-stakes features (instance + SG + EBS + Docker)
**Avoids:** Security group missing port 80 (Pitfall 7), port 8008 exposed externally (Pitfall 9), hardcoded AMI IDs (STACK.md anti-pattern), IAM credentials on disk (STACK.md anti-pattern)
**Research flag:** Standard patterns — well-documented AWS CLI commands, HIGH confidence across the board. Skip `research-phase`.

### Phase 2: Stack Configuration Adaptation
**Rationale:** The existing TLS-built stack cannot be deployed to EC2 as-is. The five targeted config changes (Nginx HTTP block, remove Certbot, update homeserver.yaml, update config.json, update well-known files) must be made and committed before deployment. `server_name` must be finalized here — it is permanently baked in after first launch.
**Delivers:** A deployable configuration that works over HTTP on an EC2 public hostname.
**Addresses:** HTTP-only Nginx config, `public_baseurl` configuration, `server_name` decision
**Avoids:** Infinite redirect loop (Pitfall 2), HSTS lockout (Architecture anti-pattern 2), server_name permanence trap (Pitfall 1), `proxy_pass` trailing slash (Pitfall 3)
**Research flag:** Standard patterns for Nginx and Synapse config — HIGH confidence from official docs. Skip `research-phase`.

### Phase 3: Incremental Stack Deployment and Validation
**Rationale:** Deploying the full stack in one shot makes failures impossible to isolate. The architecture research prescribes a 7-step incremental build order: EC2 connectivity → Docker → Postgres + Synapse only → add Nginx + Element → bootstrap admin → two-user E2EE test → S3 backup. Each step has a specific acceptance criterion.
**Delivers:** Fully functional Matrix/Element stack accessible over HTTP, with admin user, default rooms, and verified E2EE messaging.
**Addresses:** Systemd auto-restart, first backup run, `depends_on` healthcheck validation
**Avoids:** Postgres encoding error (Pitfall 4), `depends_on` race condition (Pitfall 8), signing key not persisted (Pitfall 5), `enable_registration` + token conflict (Pitfall 10), placeholder secrets left in config
**Research flag:** Standard patterns — Docker Compose, Synapse, Nginx all well-documented. Skip `research-phase`.

### Phase 4: Operational Hardening
**Rationale:** Once the POC is validated by stakeholders, add the P2 features before any real users touch the system. Elastic IP is the first priority — it must be allocated before setting a domain DNS record and prevents `public_baseurl` from going stale after any stop/start.
**Delivers:** Stable hostname (Elastic IP), operational visibility (CloudWatch agent + disk/memory alarms + SNS), secure access (SSM Session Manager, close port 22), compliance-ready storage (KMS EBS encryption), centralized logs (CloudWatch log groups).
**Addresses:** All P2 features from FEATURES.md
**Avoids:** Stale `public_baseurl` after reboot, silent disk-full failures, SSH key management sprawl
**Research flag:** Standard AWS patterns — HIGH confidence. Skip `research-phase`.

### Phase 5: Production Migration (post-POC)
**Rationale:** When the POC is validated and a real domain is obtained, the production path requires a fresh deployment — not an upgrade. The `server_name` in the POC is the EC2 hostname; production needs a real domain. This means new user accounts, new Synapse database, TLS via ALB + ACM. The architectural rethink for 50K users (Synapse workers, RDS, S3 media backend) belongs here.
**Delivers:** TLS-terminated deployment with a real domain, production-grade database (RDS), Synapse workers for horizontal scaling, S3 media backend.
**Addresses:** All P3 features — TLS, workers, RDS, multi-AZ
**Avoids:** Attempting to "upgrade" the POC `server_name` (impossible without database drop), premature workers configuration (conflicts with single-process Synapse config)
**Research flag:** Synapse workers architecture and RDS migration need deeper research. Recommend `research-phase` before this phase begins. Worker configuration, Redis coordination, ALB routing to workers, and Postgres connection pool tuning are moderately complex and have sparse community documentation for this specific stack.

### Phase Ordering Rationale

- Phase 1 before Phase 2: Infrastructure must exist before configuration can be tested against it. IAM role must be attached at launch.
- Phase 2 before Phase 3: Config changes must be committed before SCP transfer to EC2. Deploying the unmodified TLS config guarantees failure.
- Phase 3 incremental order: Each sub-step validates a layer. Postgres encoding can only be verified before data is written (before Synapse first boot). Signing key persistence must be verified before stakeholder demo.
- Phase 4 after stakeholder validation: Elastic IP, SSM, and KMS changes involve brief disruption. Do them after the POC demo, before opening to real users.
- Phase 5 is a fresh deployment, not an upgrade: The `server_name` permanence constraint makes in-place migration from POC domain to production domain impossible. Plan for this explicitly.

### Research Flags

Phases needing deeper research during planning:
- **Phase 5 (Production Migration):** Synapse workers configuration is moderately complex — Redis coordination, worker-aware Nginx upstream config, PostgreSQL connection pool tuning. Synapse sizing at 50K users has LOW confidence in the research (no official benchmarks). Recommend `research-phase` before this phase is scheduled.

Phases with standard patterns (skip `research-phase`):
- **Phase 1:** AWS CLI provisioning commands are HIGH confidence from official docs.
- **Phase 2:** Nginx HTTP config and Synapse `homeserver.yaml` patterns are HIGH confidence from official docs.
- **Phase 3:** Docker Compose deployment patterns are HIGH confidence; Synapse startup sequence is well-documented.
- **Phase 4:** CloudWatch agent, SSM, KMS EBS encryption are all standard AWS patterns with HIGH confidence.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | AWS CLI commands verified against official docs; Docker CE AL2023 install pattern verified via multiple 2025 community sources (one known workaround: `$releasever` substitution is MEDIUM confidence, not in official Docker docs) |
| Features | HIGH | Security group, IAM, and S3 backup patterns verified via official AWS docs; systemd Docker Compose integration confirmed via official Docker docs |
| Architecture | HIGH | Nginx HTTP-only config, Synapse reverse proxy patterns, and `.well-known` handling all verified against official Synapse and Matrix spec docs; codebase inspected directly |
| Pitfalls | HIGH | Critical pitfalls (server_name permanence, nginx trailing slash, Postgres encoding) all confirmed in official Synapse docs and specific GitHub issues |

**Overall confidence:** HIGH for POC phases (1-4). LOW for Phase 5 Synapse workers sizing at 50K users — no official benchmarks; community estimates only.

### Gaps to Address

- **Synapse memory footprint at POC scale:** The estimate of ~2.5-3 GB RAM for the full stack is inferred from Synapse hosting docs and community reports, not an official benchmark. If the t3.medium shows memory pressure during demo, have a plan to upgrade to t3.large or add 2 GB swap (the swap approach is documented in PITFALLS.md as a performance trap mitigation).
- **Docker IMDS hop limit for backup containers:** The research flags that Docker containers on EC2 cannot access `169.254.169.254` (IMDS) by default. The backup script uses `aws s3 cp` which needs IAM credentials. If backup runs inside a container, the IMDS hop limit must be set to 2 via `aws ec2 modify-instance-metadata-options`. If backup runs on the host (not in a container), this is not an issue. Verify which approach `backup.sh` uses.
- **`server_name` strategy for the POC:** Research recommends against using the EC2 public hostname as `server_name` due to its impermanence, but provides no guidance on what placeholder to use if no domain is available yet. Options: public IP (stable for EIP), `demo.internal`, or a short placeholder that operators agree to recreate. Decide this before Phase 3 begins.
- **Synapse workers scaling threshold:** The 500-1000 concurrent active users estimate for Synapse single-process saturation is a community estimate with LOW confidence. The actual threshold depends on room sizes, message volume, and E2EE key operations. Do not use this number for SLA commitments.

---

## Sources

### Primary (HIGH confidence)
- [Synapse Reverse Proxy Documentation](https://matrix-org.github.io/synapse/latest/reverse_proxy.html) — nginx proxy_pass patterns, X-Forwarded-For, WebSocket headers
- [Synapse Configuration Manual](https://matrix-org.github.io/synapse/latest/usage/configuration/config_documentation.html) — server_name permanence, public_baseurl, enable_registration
- [Synapse PostgreSQL Setup](https://matrix-org.github.io/synapse/latest/postgres.html) — POSTGRES_INITDB_ARGS encoding requirements
- [Matrix Client-Server Spec](https://spec.matrix.org/latest/client-server-api/) — .well-known discovery, HTTPS requirement
- [Element Web config.md](https://github.com/element-hq/element-web/blob/develop/docs/config.md) — base_url configuration
- [AWS EC2 User Data](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html) — user-data behavior, 16 KB limit, root execution
- [AWS CLI run-instances reference](https://docs.aws.amazon.com/cli/latest/reference/ec2/run-instances.html) — SSM parameter AMI resolution, block device mappings
- [IAM Roles for Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html) — instance profile patterns
- [Amazon EBS Encryption](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-encryption.html) — KMS volume encryption
- [Docker Compose Startup Order](https://docs.docker.com/compose/how-tos/startup-order/) — depends_on service_healthy

### Secondary (MEDIUM confidence)
- [Docker setup on AL2023 — GitHub gist, maintained 2025](https://gist.github.com/thimslugga/36019e15b2a47a48c495b661d18faa6d) — CentOS 9 repo workaround for AL2023
- [Docker + Compose on AL2023 — September 2025](https://medium.com/@fredmanre/how-to-configure-docker-docker-compose-in-aws-ec2-amazon-linux-2023-ami-ab4d10b2bcdc) — $releasever substitution pattern
- [Securing EC2 with SSM Session Manager](https://thehiddenport.dev/posts/aws-securing-ec2-access-with-ssm/) — SSM vs SSH analysis
- [Synapse Workers Documentation](https://matrix-org.github.io/synapse/latest/workers.html) — Redis requirement, worker types
- [GitHub issue #3031: server_name change](https://github.com/matrix-org/synapse/issues/3031) — confirms server_name is permanent
- [GitHub issue #3294: nginx trailing slash signature failure](https://github.com/matrix-org/synapse/issues/3294) — confirms proxy_pass trailing slash breaks Matrix
- [GitHub issue #5346: public_baseurl HTTPS/HTTP mismatch](https://github.com/matrix-org/synapse/issues/5346) — confirms silent misconfiguration

### Tertiary (LOW confidence)
- [Understanding Synapse Hosting — matrix.org](https://matrix.org/docs/older/understanding-synapse-hosting/) — memory requirements context; marked "older" docs, no official benchmarks

---
*Research completed: 2026-02-20*
*Ready for roadmap: yes*
