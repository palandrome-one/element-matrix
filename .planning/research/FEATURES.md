# Feature Research

**Domain:** AWS EC2 Docker Compose deployment — Matrix/Element white-label chat platform
**Researched:** 2026-02-20
**Confidence:** MEDIUM — Security group, IAM, and S3 backup patterns verified via official AWS docs and multiple sources. Synapse-specific sizing at 50K users is LOW confidence (official docs do not publish concrete numbers for that scale).

---

## Context: What "Features" Means Here

This file answers: **What does the AWS deployment layer need to provide so the existing Docker Compose stack can run reliably on EC2?**

The Docker Compose stack (Synapse + Element + Nginx + PostgreSQL) is already built. The AWS deployment layer wraps it with: instance configuration, network security, IAM, storage, observability, and backup.

The milestone constraint: **No TLS on the POC** (using EC2 public hostname, HTTP only). Goal is to demonstrate branded chat works. Must eventually scale to 50K users.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features stakeholders/testers assume exist. Missing = POC cannot function or is operationally untenable.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| EC2 instance (correct type + size) | Everything runs on it; undersized = performance failure in demo | LOW | t3.medium minimum (2 vCPU, 4 GB). t3.large recommended for headroom. Synapse + Postgres + Nginx need ~2 GB active RAM. |
| Security group: open ports 80 + 22 | Port 80 = HTTP access for testers. Port 22 = operator access for setup. Neither open = unreachable. | LOW | Inbound: 80/tcp from anywhere (0.0.0.0/0), 22/tcp from operator IP only. No 443 needed for HTTP-only POC. |
| Security group: block all other inbound | EC2 instances are internet-facing by default; open PostgreSQL (5432) or Synapse internal port (8008) = instant compromise | LOW | Default deny all other inbound. Outbound unrestricted (Docker pulls images, backup.sh writes to S3). |
| EBS volume sized adequately | Disk full = containers crash, data loss | LOW | 30 GB gp3 minimum. Synapse media + Postgres data + Docker images + logs. gp3 is cheaper and faster than gp2 at same size. |
| Docker + Docker Compose installed on instance | Stack can't start without them | LOW | Bootstrap via EC2 UserData. Amazon Linux 2023 + `dnf install docker`, Ubuntu 22.04 + `apt install docker.io`. Docker Compose v2 plugin preferred over standalone v1. |
| HTTP-only Nginx configuration | Existing config has `return 301 https://` redirect — blindly copying to EC2 = infinite redirect loop on port 80 | LOW | Must override: remove TLS redirect, configure `server { listen 80; }` for all virtual hosts. Two files to edit: `proxy/conf.d/element.conf`. |
| `public_baseurl` set to EC2 hostname | Matrix clients auto-discover homeserver using this URL. Wrong value = login fails, well-known breaks | LOW | `public_baseurl: "http://ec2-X-X-X-X.compute-1.amazonaws.com"` in `homeserver.yaml`. Must match EC2 public DNS. |
| `docker compose up -d` runs successfully | The stack must start; failure here = nothing to test | LOW | Requires .env configured, volumes created, healthchecks passing. |
| Systemd unit wrapping docker compose | Without this, the stack does NOT restart after EC2 reboot (Docker's `restart: unless-stopped` doesn't help on host reboot) | LOW | `/etc/systemd/system/element-matrix.service` calling `docker compose -f /opt/element-matrix/compose/docker-compose.yml up -d`. Single unit file. |
| SSH or SSM access to instance | Can't operate, configure, or debug without access | LOW | SSH key pair is minimum for POC. SSM Session Manager is the production upgrade. |

### Differentiators (Competitive Advantage)

Features that separate a working POC from a production-grade deployment. Not required for POC, but required before real users.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| IAM instance profile (EC2 role) | Containers get AWS credentials from instance metadata — no hardcoded keys, no leaked secrets | LOW | Attach role with `s3:PutObject`, `s3:GetObject` on backup bucket + `cloudwatch:PutMetricData`, `logs:*`. Required before S3 backups or CloudWatch agent work. Attach at launch or via console after launch. |
| S3 bucket for backups | Durable off-instance storage for Postgres dumps and Synapse media | LOW | Versioning: ON. Block all public access: ON. Lifecycle rule: move to S3 Glacier after 30 days. Region: same as EC2 instance to avoid cross-region transfer cost. |
| Automated S3 backup (Postgres + media) | Instance termination or EBS failure = total data loss without backup | MEDIUM | `pg_dumpall` piped to gzip + AWS CLI `s3 cp`. Cron or systemd timer (daily). `backup.sh` script already exists in repo — needs S3 bucket name and IAM role to function. |
| CloudWatch agent (CPU, disk, memory metrics) | EC2 default metrics exclude memory and disk usage. Can't detect Postgres filling disk or Synapse OOM without custom metrics. | LOW | Install `amazon-cloudwatch-agent`. Config: collect `mem_used_percent`, `disk_used_percent`. Default EC2 metrics cover CPU only. IAM role prerequisite. |
| CloudWatch alarms + SNS email alerts | Silent failures are undetected outages. Someone needs to know when the instance is at 90% disk. | LOW | Two alarms minimum: CPU > 80% sustained 5 min, disk > 80%. One SNS topic → email confirmation required after creation. |
| Elastic IP address | EC2 public DNS changes on every stop/start. Stale `public_baseurl` = broken login after any restart. | LOW | Allocate Elastic IP, associate with instance. $0 while associated with running instance. $0.005/hr if allocated but unassociated — release when done. |
| SSM Session Manager (no port 22) | Eliminates SSH key management. Every session logged to CloudTrail. Reduces attack surface by closing port 22. | LOW | Requires `AmazonSSMManagedInstanceCore` IAM policy on instance role. SSM agent pre-installed on Amazon Linux 2023. Close port 22 in security group after validating SSM works. Medium confidence: [SSM vs SSH analysis](https://thehiddenport.dev/posts/aws-securing-ec2-access-with-ssm/) |
| KMS-encrypted EBS volume | Compliance requirement for data at rest in most regulated environments. Protects against volume snapshot exfiltration. | LOW | Enable at volume creation time — cannot be added retroactively without snapshot + restore cycle. Zero performance impact on all current-gen instance types. AWS-managed KMS key is free; customer-managed key is $1/month. |
| CloudWatch log groups (awslogs Docker driver) | Container logs survive instance termination. Searchable without SSH. Central log access for on-call ops. | LOW | Set Docker logging driver `awslogs` in compose file or `/etc/docker/daemon.json`. IAM role needs `logs:CreateLogGroup`, `logs:PutLogEvents`. Log retention: 7-30 days. |
| AMI snapshot on schedule (Data Lifecycle Manager) | Faster full-instance recovery than restore-from-backup. Useful if EBS volume corrupts. | MEDIUM | AWS Data Lifecycle Manager policy. Weekly AMI, retain 4. Snapshot cost ~$0.05/GB/month for incremental after first. |
| Automated restore test | Backups are worthless if restore doesn't work. Silent backup corruption is common with pg_dump across version mismatches. | MEDIUM | Monthly: launch test EC2 instance, restore from S3 backup, verify Synapse starts and data is intact. Document results. |

### Anti-Features (Commonly Requested, Often Problematic)

Features to explicitly NOT build for the POC. Document the rejection reason so scope creep doesn't re-introduce them.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| TLS / Let's Encrypt on EC2 hostname | "It should be secure" | EC2 public hostnames (`ec2-X.compute.amazonaws.com`) cannot get Let's Encrypt certificates — they're not under the operator's control. ACM also requires a real domain. Attempting TLS here wastes time and will fail. | Accept HTTP for POC. Plan TLS in production phase via ACM + ALB (requires real domain). |
| RDS PostgreSQL instead of Docker Postgres | "Managed database is better" | True for production. But RDS adds: VPC private subnet routing, security groups for DB access, ~$30-50/month minimum cost, and connection string changes. No benefit for a POC proving branded chat works. | Keep Postgres in Docker Compose for POC. Migrate to RDS if SLA requires managed DB. |
| ECS / EKS instead of Docker Compose | "Containers should be on a container platform" | ECS requires: task definitions, service definitions, ECR, task IAM roles, ALB target groups — none compatible with the existing Docker Compose workflow without rework. Zero benefit for single-app deployment. | Keep Docker Compose on EC2. It works. The stack is already built for it. |
| Multi-AZ high availability | "We need HA" | Synapse is not stateless. It stores media locally and holds state in memory. Multi-AZ requires: shared storage (EFS), session affinity at the load balancer, and a fundamentally different Synapse deployment model (workers). Incompatible with current architecture. | Single-instance for POC and early production. Document the HA path for post-50K milestone. |
| CloudFront CDN for Element Web | "Static assets should be on CDN" | Element Web is ~3 MB gzipped. CDN adds: cache invalidation complexity, origin configuration, and cost (~$0.01/GB). Imperceptible benefit for <1000 users. | Nginx on EC2 serves Element Web directly. Fast enough. Add CDN only if global latency becomes measurable. |
| VPC with private subnets + NAT Gateway | "Best practice network architecture" | NAT Gateway costs $32/month minimum plus data transfer. For a single-instance POC in a public subnet with a tight security group (only ports 80 + 22 open), private subnets add no meaningful security benefit. | Public subnet + restrictive security group for POC. Private subnets are a post-POC hardening step. |
| CI/CD pipeline (CodePipeline / GitHub Actions deploy) | "We need automated deployments" | Adds: CodePipeline, CodeBuild, ECR, IAM for deployment, trigger configuration. Significant overhead for a POC where `git pull && docker compose up -d` is the entire deploy. | Manual deploy for POC. Add CI/CD when deployment frequency justifies it. |
| Synapse workers + Redis (horizontal scaling) | "We need to scale to 50K users" | Synapse workers require Redis for coordination, a fundamentally different Nginx upstream config, and multiple Synapse containers. The single-process Synapse is the correct POC substrate. Workers are a post-validation architecture decision. | Single-process Synapse for POC. Add workers when single-process CPU saturation is observed (~500-1000 concurrent active users in large rooms). |

---

## Feature Dependencies

```
[EC2 instance with correct size]
    └──requires──> [EBS volume sized adequately (30 GB gp3)]
    └──requires──> [Security group: ports 80 + 22 open]
    └──requires──> [UserData: Docker + Docker Compose installed]
                       └──enables──> [docker compose up -d runs]

[docker compose up -d runs]
    └──requires──> [.env configured with EC2 hostname]
    └──requires──> [HTTP-only Nginx config (no TLS redirect)]
    └──requires──> [public_baseurl set in homeserver.yaml]

[Stack restarts after EC2 reboot]
    └──requires──> [Systemd unit: element-matrix.service]

[S3 automated backup]
    └──requires──> [IAM instance profile with S3 permissions]
    └──requires──> [S3 bucket created]
    └──requires──> [backup.sh configured with bucket name and region]

[CloudWatch alarms → SNS email]
    └──requires──> [CloudWatch agent installed + configured]
    └──requires──> [IAM instance profile with CloudWatch permissions]
    └──requires──> [SNS topic created + email subscription confirmed]

[IAM instance profile]
    └──enables──> [S3 backup without hardcoded keys]
    └──enables──> [CloudWatch agent metrics]
    └──enables──> [SSM Session Manager access]
    └──enables──> [CloudWatch log groups (awslogs driver)]

[Elastic IP]
    └──enables──> [Stable EC2 hostname for public_baseurl]
    └──prerequisite for──> [TLS / ACM certificate (production)]

[SSM Session Manager]
    └──requires──> [IAM instance profile with AmazonSSMManagedInstanceCore]
    └──conflicts──> [Open port 22] — close port 22 after validating SSM works

[TLS via ALB + ACM] (production, not POC)
    └──requires──> [Real domain name (not EC2 hostname)]
    └──requires──> [Route 53 hosted zone or DNS delegation]
    └──requires──> [Elastic IP or ALB DNS target]
    └──requires──> [ACM certificate validated]

[Synapse workers] (50K users, not POC)
    └──requires──> [Redis container added to compose]
    └──requires──> [Worker-aware Nginx upstream config]
    └──requires──> [PostgreSQL connection pool tuning]
    └──conflicts──> [Single-process Synapse config]
```

### Dependency Notes

- **IAM instance profile is the multiplier feature**: It unlocks S3 backups, CloudWatch agent, SSM Session Manager, and CloudWatch log groups. Create the role before instance launch. Attach policy `AmazonSSMManagedInstanceCore` + custom inline policy for S3 and CloudWatch. Can be attached/detached from a running instance via console.
- **HTTP-only Nginx config must be explicitly created**: The existing `proxy/conf.d/element.conf` has `return 301 https://`. Deploying as-is to EC2 on port 80 = infinite redirect loop. A POC-specific override or environment variable substitution is required.
- **Elastic IP before DNS**: If a domain will be used later (production), allocate Elastic IP before setting DNS records. Without it, every EC2 stop/start generates a new hostname requiring `public_baseurl` updates.
- **Synapse workers conflict with single-process config**: Do not add workers until the POC proves the product. Worker mode changes how Synapse handles the replication stream, Redis coordination, and how Nginx routes to Synapse processes.

---

## MVP Definition

### Launch With (POC v1)

Minimum viable AWS deployment — proves branded chat works on EC2.

- [ ] EC2 instance (t3.large, Amazon Linux 2023 or Ubuntu 22.04, 30 GB gp3 EBS) — compute substrate
- [ ] Security group: inbound 80/tcp + 22/tcp, all else blocked — network security
- [ ] EC2 UserData bootstrap script: installs Docker + Compose, clones repo, creates systemd service — automated setup
- [ ] HTTP-only Nginx config override — makes stack reachable on port 80
- [ ] `.env` and `homeserver.yaml` configured with EC2 public hostname — Matrix client discovery
- [ ] Systemd service unit: element-matrix.service — auto-restart on reboot
- [ ] IAM instance profile (S3 + CloudWatch permissions) — prerequisite for backups and monitoring
- [ ] S3 bucket with versioning + public access blocked — backup target
- [ ] First manual backup run (`backup.sh`) — validates backup path works

### Add After Validation (v1.x)

Add once POC is stable and stakeholders have validated the concept.

- [ ] Elastic IP — trigger: need stable hostname before pointing a domain at instance
- [ ] CloudWatch agent + disk/memory alarms + SNS email — trigger: anyone needs to know when things break
- [ ] SSM Session Manager — trigger: security review or SSH key management becomes painful; close port 22 after confirming SSM works
- [ ] KMS-encrypted EBS — trigger: compliance review or data protection requirement

### Future Consideration (v2+ Production)

Defer until POC is validated and production is planned.

- [ ] TLS via ALB + ACM — requires real domain; required before external users
- [ ] CloudWatch log groups (awslogs driver) — required for SSH-less log access at scale
- [ ] Automated restore test — required before claiming backup SLA
- [ ] AMI snapshot schedule — required for sub-hour RTO
- [ ] Synapse workers + Redis — required when single-process CPU saturates (~500-1000 concurrent active users)
- [ ] Multi-AZ + Auto Scaling + EFS — required for 50K user HA; architectural rethink needed

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| EC2 instance + security group + EBS | HIGH (stack can't run) | LOW | P1 |
| Docker install + UserData bootstrap | HIGH (stack can't run) | LOW | P1 |
| HTTP-only Nginx config | HIGH (testers can't connect) | LOW | P1 |
| Hostname in .env / homeserver.yaml | HIGH (login breaks without it) | LOW | P1 |
| Systemd auto-restart | HIGH (survives reboot) | LOW | P1 |
| IAM instance profile | HIGH (unlocks backups + monitoring) | LOW | P1 |
| S3 bucket + first backup | HIGH (data safety) | LOW | P1 |
| Elastic IP | MEDIUM (stable hostname) | LOW | P2 |
| CloudWatch agent + SNS alarms | MEDIUM (operational visibility) | LOW | P2 |
| SSM Session Manager | MEDIUM (security hardening) | LOW | P2 |
| KMS EBS encryption | MEDIUM (compliance) | LOW | P2 |
| CloudWatch log groups | MEDIUM (ops convenience) | LOW | P2 |
| TLS via ALB + ACM | HIGH (production requirement) | MEDIUM | P2 |
| Automated restore test | HIGH (backup integrity proof) | MEDIUM | P2 |
| AMI snapshot schedule | MEDIUM (fast RTO) | LOW | P3 |
| Synapse workers + Redis | HIGH (at 500+ concurrent users) | HIGH | P3 |
| Multi-AZ + ASG + EFS | HIGH (at 50K users) | HIGH | P3 |
| CI/CD pipeline | LOW (manual deploy works) | HIGH | P3 |

**Priority key:**
- P1: Must have for POC launch
- P2: Production hardening — add before real users
- P3: Scale — required at 50K users, not for POC

---

## AWS-Specific Constraints for This Deployment

These are gotchas specific to running Docker Compose on EC2 without a custom domain.

| Constraint | Impact | Handling |
|------------|--------|----------|
| EC2 public DNS changes on stop/start | `public_baseurl` in homeserver.yaml and config.json becomes stale; login breaks | Allocate Elastic IP before any stop/start OR document re-substitution procedure |
| No TLS = browsers show "Not Secure" | Acceptable for internal POC on controlled network; not acceptable for external users | Accepted for POC. Flag for TLS enforcement in production phase. |
| EC2 hostname not Let's Encrypt-eligible | Can't get a cert for `*.compute.amazonaws.com` subdomains | Requires real domain for TLS. Not a POC concern. |
| Docker metadata service vs EC2 IMDS | Docker containers on EC2 cannot access `169.254.169.254` (IMDS) by default — IAM role credentials not inherited | Use `--network host` on the backup container, or pass credentials via env vars from instance, or use instance profile correctly with IMDSv2 hop limit set to 2 |
| Port 8448 (federation) not needed | Federation is disabled in homeserver.yaml; the port need not be opened | Do not open 8448 in security group for POC |
| Security group is stateful | Outbound rules rarely need editing — EC2 security groups track connection state | Leave outbound rule as default allow-all; only restrict inbound |

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Security group requirements | HIGH | AWS official EC2 docs verified |
| IAM instance profile patterns | HIGH | AWS official IAM docs verified |
| S3 backup for Postgres + Docker volumes | MEDIUM | Multiple sources agree; established community pattern |
| Systemd for Docker Compose on reboot | MEDIUM | Docker official docs confirm restart policies don't handle host reboot; systemd is the documented solution |
| SSM vs SSH recommendation | HIGH | AWS official docs + multiple 2025 sources consistently recommend SSM |
| CloudWatch agent requirements | HIGH | AWS official CloudWatch docs verified |
| Synapse sizing at 50K users | LOW | Official Synapse docs do not publish concrete instance sizing. Workers doc confirms single-process saturation; specific thresholds are community estimates only |
| Synapse workers architecture | MEDIUM | Official workers.md in Synapse GitHub repo documents Redis requirement and worker types |

---

## Sources

- [Amazon EC2 Security Groups — AWS Official Docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html) — HIGH confidence
- [IAM Roles for Amazon EC2 — AWS Official Docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html) — HIGH confidence
- [Amazon EBS Encryption — AWS Official Docs](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-encryption.html) — HIGH confidence
- [Start Containers Automatically — Docker Official Docs](https://docs.docker.com/engine/containers/start-containers-automatically/) — HIGH confidence
- [Secure EC2 Setup with Docker Compose — Ridwan Sukri](https://www.ridwansukri.com/post/secure-ec2-setup-with-docker-compose/) — MEDIUM confidence (practical guide consistent with AWS docs)
- [Securing EC2 with SSM Session Manager — The Hidden Port](https://thehiddenport.dev/posts/aws-securing-ec2-access-with-ssm/) — MEDIUM confidence
- [CloudWatch Logs and Metrics for Docker Containers — AWS re:Post](https://repost.aws/questions/QUzWfv7BlLRbKGsybPZN19TQ/cloudwatch-logs-metrics-for-docker-containers) — MEDIUM confidence
- [Synapse Workers Documentation — matrix-org GitHub](https://matrix-org.github.io/synapse/latest/workers.html) — HIGH confidence (official)
- [Understanding Synapse Hosting — Matrix.org](https://matrix.org/docs/older/understanding-synapse-hosting/) — MEDIUM confidence (official but marked "older")
- [postgres-backup-s3 — GitHub eeshugerman](https://github.com/eeshugerman/postgres-backup-s3) — MEDIUM confidence (community, widely used)
- [How to Backup Postgres in Docker to S3 — sanjeevan.co.uk](https://sanjeevan.co.uk/blog/backup-postgres-in-docker-to-s3/) — MEDIUM confidence

---

*Feature research for: AWS EC2 Docker Compose deployment — Matrix/Element white-label chat platform*
*Researched: 2026-02-20*
