# Requirements: Matrix Element White-Label POC

**Defined:** 2026-02-20
**Core Value:** Users can access a branded, self-hosted chat platform where registration, messaging, and E2E encryption work end-to-end on AWS.

## v1 Requirements

Requirements for POC deployment. Each maps to roadmap phases.

### AWS Infrastructure

- [ ] **INFRA-01**: EC2 t3.small instance (2 vCPU, 2 GB RAM, ~$15/mo) provisioned via AWS CLI in us-east-1 — sized for ~20 POC users
- [ ] **INFRA-02**: Security group allows only port 80 (0.0.0.0/0) and port 22 (admin IP only) inbound
- [ ] **INFRA-03**: EBS gp3 root volume (30 GB minimum) attached to instance
- [ ] **INFRA-04**: Docker Engine and Docker Compose plugin installed via user-data on Amazon Linux 2023
- [ ] **INFRA-05**: SSH key pair created and used for instance access

### Stack Configuration

- [ ] **STACK-01**: Nginx config replaced with HTTP-only server block (no TLS, no HSTS, path-based routing)
- [ ] **STACK-02**: Synapse `public_baseurl` set to `http://<EC2-public-hostname>`
- [ ] **STACK-03**: Synapse `server_name` set to a deliberate POC value (documented as non-migratable)
- [ ] **STACK-04**: Element `config.json` updated with HTTP base_url matching EC2 hostname
- [ ] **STACK-05**: `enable_registration: true` with `registration_requires_token: true` (both required for invite flow)
- [ ] **STACK-06**: `docker compose up -d` starts all services with healthy status on EC2

### Application Verification

- [ ] **VERIFY-01**: Admin user created via bootstrap script and can log in at `http://<EC2-hostname>`
- [ ] **VERIFY-02**: Default Space and rooms created and visible after login
- [ ] **VERIFY-03**: Two users can exchange messages in a room with E2EE lock icon visible
- [ ] **VERIFY-04**: Branded Element UI loads with custom name, logo, and theme colors

## v2 Requirements

Deferred to production phase. Tracked but not in current roadmap.

### Reliability

- **RELY-01**: Elastic IP assigned for stable hostname across reboots
- **RELY-02**: Systemd unit auto-restarts Docker Compose stack after EC2 reboot
- **RELY-03**: IAM instance profile with S3 and CloudWatch permissions
- **RELY-04**: Automated daily backup to S3 bucket (Postgres dump + media)
- **RELY-05**: Restore from S3 backup tested and documented

### Observability

- **OBSV-01**: CloudWatch agent collecting memory and disk metrics
- **OBSV-02**: CloudWatch alarms on CPU > 80% and disk > 80% with SNS email alerts
- **OBSV-03**: Container logs shipped to CloudWatch via awslogs driver

### Administration

- **ADMN-01**: synapse-admin UI deployed as additional container
- **ADMN-02**: SSM Session Manager replaces SSH access (close port 22)
- **ADMN-03**: KMS-encrypted EBS volume

### Production

- **PROD-01**: Custom domain mapped with Route 53
- **PROD-02**: TLS via ACM + Application Load Balancer
- **PROD-03**: Synapse workers + Redis for 50K user scaling
- **PROD-04**: RDS PostgreSQL replacing Docker Postgres
- **PROD-05**: S3 media backend replacing local disk

## Out of Scope

| Feature | Reason |
|---------|--------|
| TLS / Let's Encrypt on EC2 hostname | Cannot issue certs for amazonaws.com; deferred to custom domain phase |
| RDS PostgreSQL | No benefit for POC; adds cost and VPC complexity |
| ECS / EKS | Incompatible with existing Docker Compose workflow without rewrite |
| Multi-AZ high availability | Synapse is stateful; requires workers architecture not in POC scope |
| CloudFront CDN | Element Web is 3 MB; no measurable benefit under 1K users |
| VPC private subnets + NAT Gateway | $32/mo minimum; security group is sufficient for POC |
| CI/CD pipeline | `git pull && docker compose up` is the entire deploy for POC |
| Federation | Off by default; increases attack surface; enable post-POC with whitelist |
| coturn / VoIP | Requires dedicated TURN server; broken calls harm POC credibility |
| Discord bridge | ToS risk; roadmap item only |
| SSO / OIDC | Future phase |
| Mobile app customization | Element mobile works as-is with server URL |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 1 | Pending |
| INFRA-02 | Phase 1 | Pending |
| INFRA-03 | Phase 1 | Pending |
| INFRA-04 | Phase 1 | Pending |
| INFRA-05 | Phase 1 | Pending |
| STACK-01 | Phase 2 | Pending |
| STACK-02 | Phase 2 | Pending |
| STACK-03 | Phase 2 | Pending |
| STACK-04 | Phase 2 | Pending |
| STACK-05 | Phase 2 | Pending |
| STACK-06 | Phase 3 | Pending |
| VERIFY-01 | Phase 3 | Pending |
| VERIFY-02 | Phase 3 | Pending |
| VERIFY-03 | Phase 3 | Pending |
| VERIFY-04 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0 ✓

---
*Requirements defined: 2026-02-20*
*Last updated: 2026-02-20 after initial definition*
