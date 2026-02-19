# Phase 1: AWS Infrastructure - Research

**Researched:** 2026-02-20
**Domain:** AWS EC2 provisioning, Amazon Linux 2023, Docker CE installation via user-data
**Confidence:** MEDIUM-HIGH (AWS CLI commands verified against official docs; Docker-on-AL2023 patterns verified via multiple community sources; some AL2023-specific behavior validated Feb 2026)

---

## Summary

Phase 1 provisions a single t3.small EC2 instance in us-east-1 running Amazon Linux 2023 with Docker Engine and the Docker Compose v2 plugin. The full setup is expressible as a sequence of AWS CLI commands: create key pair, create security group, add ingress rules, and run-instances with a user-data script. No Terraform, CDK, or CloudFormation is required for a single-instance POC.

The most nuanced area is the Docker installation on AL2023. Two paths exist: (1) the AL2023 built-in `docker` package via `dnf install docker` — simple but does not include the `docker-compose-plugin`; and (2) Docker CE via Docker's official CentOS repo with a `$releasever` workaround — provides `docker-compose-plugin` as a package but requires a sed substitution that was "MEDIUM confidence" in prior notes. Both approaches work in 2026; the AL2023 built-in package route is simpler and the Compose plugin can be installed separately as a binary, which is equally well-supported.

The security group must expose only port 80 to 0.0.0.0/0 and port 22 to the admin IP. Port 8008 (Synapse internal) must NOT appear in the security group — it is Docker-network-internal only. The backup.sh script runs on the EC2 host (not inside a container), so the IMDS hop-limit issue does not apply to the current codebase; the hop limit only matters if a future containerized backup approach is adopted.

**Primary recommendation:** Use the AL2023 built-in `docker` package (avoids `$releasever` complexity), then install the Docker Compose v2 binary as a system-wide CLI plugin. Everything else is standard AWS CLI provisioning.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INFRA-01 | EC2 t3.small (2 vCPU, 2 GB RAM, ~$15/mo) in us-east-1 via AWS CLI | `aws ec2 run-instances --instance-type t3.small --region us-east-1`; AMI resolved via SSM parameter store |
| INFRA-02 | Security group: port 80 from 0.0.0.0/0, port 22 from admin IP only | `aws ec2 authorize-security-group-ingress` with `--cidr` per rule; port 8008 omitted entirely |
| INFRA-03 | EBS gp3 root volume 30 GB minimum | `--block-device-mappings` with `VolumeType=gp3,VolumeSize=30`; device name `/dev/xvda` in mapping |
| INFRA-04 | Docker Engine + Docker Compose plugin via user-data on AL2023 | AL2023 built-in `docker` package + compose binary; or Docker CE via releasever=9 workaround |
| INFRA-05 | SSH key pair created and used for instance access | `aws ec2 create-key-pair --key-name ... --query KeyMaterial --output text > key.pem; chmod 400 key.pem` |
</phase_requirements>

---

## Standard Stack

### Core AWS CLI Commands

| Command | Purpose | Notes |
|---------|---------|-------|
| `aws ec2 create-key-pair` | Create RSA or ED25519 key pair, save private key | `--key-type rsa --key-format pem`; pipe `--query KeyMaterial` to `.pem` file |
| `aws ec2 create-security-group` | Create named security group | Requires `--description`; returns `GroupId` |
| `aws ec2 authorize-security-group-ingress` | Add inbound rules per port | Called once per rule |
| `aws ec2 run-instances` | Launch instance | Takes AMI ID (SSM resolve), instance type, key, SG, block device, user-data |
| `aws ec2 wait instance-running` | Block until instance is running | Polls every 15 s, 40 attempts max; exits 255 on timeout |
| `aws ec2 describe-instances` | Query public DNS/IP after launch | Use `--query` to extract `PublicDnsName` |

### AMI Resolution (HIGH confidence)

Official AWS docs confirm SSM parameter store is the canonical approach for always-latest AL2023 AMI:

```bash
# Resolve the latest AL2023 x86_64 AMI at launch time
aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --region us-east-1 \
  ...
```

Alternatively, resolve ahead of time and capture:
```bash
AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --region us-east-1 \
  --query "Parameter.Value" \
  --output text)
```

Source: [AL2023 EC2 documentation](https://docs.aws.amazon.com/linux/al2023/ug/ec2.html)

### Docker Installation on AL2023

Two verified approaches exist in early 2026:

**Approach A — AL2023 built-in package (RECOMMENDED, simpler):**
- `sudo dnf install -y docker` installs Docker Engine, CLI, containerd
- Does NOT include docker-compose-plugin; must install Compose binary separately
- No `$releasever` workaround needed

**Approach B — Docker CE via CentOS repo (provides docker-compose-plugin as package):**
- Requires `sed -i 's/$releasever/9/g' /etc/yum.repos.d/docker-ce.repo` after adding the repo
- Alternatively: create repo file pointing directly to `https://download.docker.com/linux/rhel/9/$basearch/stable`
- The `$releasever` workaround was MEDIUM confidence as of last research; confirmed still required in 2026 for the CentOS-repo approach

**Recommendation:** Use Approach A to avoid external repo complexity. Docker Compose binary install from GitHub releases is the same result as the plugin package, and is the approach used in the AL2023 community gists (February 2026 verified).

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| AL2023 built-in `docker` + compose binary | Docker CE via centos repo | CE approach gives package-managed compose but requires releasever hack |
| AL2023 built-in `docker` | Amazon Linux 2 + `amazon-linux-extras` | AL2 is legacy, approaching EOL; AL2023 is current |
| Manual AWS CLI provisioning | Terraform/CDK | Terraform is overkill for single-instance POC; CLI is auditable and simpler |
| `t3.small` | `t3.micro` | micro has 1 GB RAM — insufficient for Synapse + Postgres + Nginx + Element concurrently |

---

## Architecture Patterns

### Provisioning Sequence

```
1. Create SSH key pair  (INFRA-05)
2. Create security group  (INFRA-02)
3. Add ingress rules: port 80/0.0.0.0/0, port 22/admin-ip  (INFRA-02)
4. Launch instance with:
     - SSM-resolved AL2023 AMI
     - t3.small
     - gp3 30 GB root volume  (INFRA-03)
     - user-data script installing Docker  (INFRA-04)
     - key pair + security group  (INFRA-01, INFRA-05)
5. Wait for instance-running state
6. Extract public DNS name
7. SSH in, verify: docker compose version, df -h (30 GB+)
```

### User-Data Script Pattern (AL2023 built-in Docker)

```bash
#!/bin/bash
set -euo pipefail

# Update system
dnf update -y

# Install Docker (AL2023 built-in; includes containerd and runc)
dnf install -y docker

# Configure Docker daemon
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF

# Enable and start Docker
systemctl enable --now docker

# Add ec2-user to docker group (no sudo needed for docker commands)
usermod -aG docker ec2-user

# Install Docker Compose v2 plugin (system-wide)
mkdir -p /usr/local/lib/docker/cli-plugins
curl -sSL \
  "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
```

### User-Data Script Pattern (Docker CE via CentOS repo — INFRA-04 alternative)

```bash
#!/bin/bash
set -euo pipefail

dnf update -y
dnf install -y dnf-plugins-core

# Add Docker's CentOS repo
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Workaround: AL2023 $releasever doesn't match Docker's repo structure
sed -i 's/$releasever/9/g' /etc/yum.repos.d/docker-ce.repo

# Install Docker CE with compose plugin
dnf install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
usermod -aG docker ec2-user
```

### Complete AWS CLI Provisioning Script

```bash
#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-1"
KEY_NAME="matrix-poc-key"
SG_NAME="matrix-poc-sg"
INSTANCE_NAME="matrix-poc"
ADMIN_IP="$(curl -s https://checkip.amazonaws.com)/32"

# INFRA-05: Create SSH key pair
aws ec2 create-key-pair \
  --region "$REGION" \
  --key-name "$KEY_NAME" \
  --key-type rsa \
  --key-format pem \
  --query "KeyMaterial" \
  --output text > "${KEY_NAME}.pem"
chmod 400 "${KEY_NAME}.pem"

# INFRA-02: Create security group
SG_ID=$(aws ec2 create-security-group \
  --region "$REGION" \
  --group-name "$SG_NAME" \
  --description "Matrix POC: port 80 public, port 22 admin only" \
  --query "GroupId" \
  --output text)

# INFRA-02: Ingress rules
aws ec2 authorize-security-group-ingress \
  --region "$REGION" \
  --group-id "$SG_ID" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --region "$REGION" \
  --group-id "$SG_ID" \
  --protocol tcp --port 22 --cidr "$ADMIN_IP"

# INFRA-01, INFRA-03, INFRA-04: Launch instance
INSTANCE_ID=$(aws ec2 run-instances \
  --region "$REGION" \
  --image-id "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --instance-type t3.small \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --block-device-mappings '[{
    "DeviceName": "/dev/xvda",
    "Ebs": {
      "VolumeSize": 30,
      "VolumeType": "gp3",
      "DeleteOnTermination": true
    }
  }]' \
  --user-data file://user-data.sh \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=${INSTANCE_NAME}-root}]" \
  --query "Instances[0].InstanceId" \
  --output text)

# Wait until running
aws ec2 wait instance-running \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID"

# Get public DNS
PUBLIC_DNS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].PublicDnsName" \
  --output text)

echo "Instance: $INSTANCE_ID"
echo "SSH: ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_DNS}"
```

### Anti-Patterns to Avoid

- **Opening port 8008 in security group:** Synapse listens on 8008 inside Docker's internal network only. Nginx proxies to it internally. Exposing 8008 externally bypasses the proxy and TLS.
- **Using `--count` > 1 without careful planning:** run-instances can launch multiple instances; explicit `--count 1` prevents accidents.
- **Hardcoding AMI IDs:** AMIs are deprecated after 90 days. Use SSM resolve pattern instead.
- **Not setting `chmod 400` on .pem file:** SSH will refuse to use a world-readable key.
- **Skipping `set -euo pipefail` in user-data:** Silent failures in user-data mean Docker may not be installed but instance appears healthy.
- **Not waiting for cloud-init to complete before SSHing:** user-data runs asynchronously after the instance enters "running" state. Docker may not be ready yet. Check `/var/log/cloud-init-output.log`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Finding current AL2023 AMI ID | Manual lookup + hardcode | `resolve:ssm:` in run-instances or `aws ssm get-parameter` | AMIs are deprecated 90 days after release; hardcoded IDs rot |
| Waiting for instance ready | Poll loop with sleep | `aws ec2 wait instance-running` | Built-in waiter handles retries and timeout correctly |
| Detecting admin IP | Ask user | `curl -s https://checkip.amazonaws.com` in script | Consistent, eliminates manual error |
| Docker Compose install check | Parse docker version string | `docker compose version` exit code | Exit 0 = v2 installed; exit nonzero = not installed or v1 standalone |

---

## Common Pitfalls

### Pitfall 1: user-data runs AFTER instance-running state
**What goes wrong:** Admin SSHs in immediately after `aws ec2 wait instance-running`, runs `docker compose version`, gets "command not found" because user-data is still executing.
**Why it happens:** EC2 "running" state means the instance is booted, not that user-data has completed. cloud-init can take 1-3 minutes on AL2023 with package installs.
**How to avoid:** After SSH, run `sudo cloud-init status --wait` or check `sudo tail -f /var/log/cloud-init-output.log` until it shows completion.
**Warning signs:** `docker: command not found` immediately after launch.

### Pitfall 2: $releasever issue with Docker CE CentOS repo
**What goes wrong:** `dnf install docker-ce` fails with 404 or "No match for argument" when using Docker's CentOS repo on AL2023.
**Why it happens:** AL2023's `$releasever` expands to the AL2023 version string, not "9" as Docker's repo expects.
**How to avoid:** Either use the AL2023 built-in `docker` package (avoids this entirely), or apply `sed -i 's/$releasever/9/g' /etc/yum.repos.d/docker-ce.repo` before the install.
**Warning signs:** DNF reports 404 errors for `download.docker.com/linux/centos/...` paths.
**2026 status:** Workaround is still required for the CentOS-repo approach. The fix in `system-release-2023.9.20251208` resolved the releasever issue for the AL2023 container image's microdnf, not for the EC2 instance's dnf with external repos.

### Pitfall 3: docker group membership requires new shell session
**What goes wrong:** user-data adds `ec2-user` to the `docker` group, but when admin SSHs in, `docker ps` returns "permission denied".
**Why it happens:** Group membership changes take effect on next login; the SSH session doesn't inherit the new group.
**How to avoid:** Log out and log back in, or run `newgrp docker` in the current session.
**Warning signs:** `permission denied while trying to connect to the Docker daemon socket`.

### Pitfall 4: EBS device name vs NVMe naming
**What goes wrong:** Block device mapping specifies `/dev/xvda` but `lsblk` shows `/dev/nvme0n1`.
**Why it happens:** Nitro-based instances (t3 family) expose EBS as NVMe. The OS name differs from the API name.
**How to avoid:** This is cosmetic — the volume is still mounted correctly as root. `df -h /` will show the correct 30 GB size. `lsblk` will show `/dev/nvme0n1` of 30 GB.
**Impact on verification:** Success criterion "EBS gp3 root volume 30 GB or more is attached" is verified with `df -h /` not device name lookup.

### Pitfall 5: IMDS hop limit for containerized AWS CLI (currently NOT an issue)
**What goes wrong:** If backup.sh or any script calling `aws` CLI were run INSIDE a Docker container on EC2, IAM credential lookup via IMDS would fail because the default hop limit of 1 is consumed by the Docker bridge NAT.
**Why it currently doesn't apply:** `backup.sh` in this repo runs directly on the EC2 host (calls `docker compose exec` from the host, not from inside a container). IAM credential access works with hop limit 1.
**How to avoid (if needed in future):** `aws ec2 modify-instance-metadata-options --instance-id <id> --http-put-response-hop-limit 2 --http-tokens optional`
**Warning signs:** `Unable to locate credentials` inside a container on an instance that has an IAM role.

### Pitfall 6: Admin IP changes between provisioning and SSH
**What goes wrong:** Security group created with admin IP `X.X.X.X/32`, but admin is on a dynamic IP that changes before they SSH in.
**Why it happens:** Dynamic home/office IPs rotate, or admin moves networks (VPN, coffee shop).
**How to avoid:** Capture IP at provisioning time with `curl -s https://checkip.amazonaws.com` and document it. If IP changes, use `aws ec2 authorize-security-group-ingress` to add new IP and optionally `revoke-security-group-ingress` to remove old one.

---

## Code Examples

Verified patterns from official sources:

### Create Key Pair and Save PEM
```bash
# Source: https://docs.aws.amazon.com/cli/latest/reference/ec2/create-key-pair.html
aws ec2 create-key-pair \
  --key-name matrix-poc-key \
  --key-type rsa \
  --key-format pem \
  --query "KeyMaterial" \
  --output text > matrix-poc-key.pem
chmod 400 matrix-poc-key.pem
```

### Create Security Group with Targeted Rules
```bash
# Source: https://docs.aws.amazon.com/cli/latest/reference/ec2/authorize-security-group-ingress.html
SG_ID=$(aws ec2 create-security-group \
  --group-name matrix-poc-sg \
  --description "Matrix POC security group" \
  --query "GroupId" --output text)

# Port 80: public
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0

# Port 22: admin only
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$(curl -s https://checkip.amazonaws.com)/32"
```

### Launch with gp3 Volume and user-data
```bash
# Source: https://docs.aws.amazon.com/cli/latest/reference/ec2/run-instances.html
# Source: https://docs.aws.amazon.com/linux/al2023/ug/ec2.html (SSM resolve pattern)
aws ec2 run-instances \
  --image-id "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --instance-type t3.small \
  --region us-east-1 \
  --key-name matrix-poc-key \
  --security-group-ids "$SG_ID" \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":30,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --user-data file://user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=matrix-poc}]' \
  --query "Instances[0].InstanceId" \
  --output text
```

### Wait and Retrieve Public DNS
```bash
# Source: https://docs.aws.amazon.com/cli/latest/reference/ec2/wait/instance-running.html
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

PUBLIC_DNS=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].PublicDnsName" \
  --output text)

ssh -i matrix-poc-key.pem ec2-user@"$PUBLIC_DNS"
```

### Verify Success Criteria on Instance
```bash
# Wait for cloud-init to finish
sudo cloud-init status --wait

# INFRA-04: Docker Compose v2
docker compose version
# Expected: Docker Compose version v2.x.x

# INFRA-03: EBS volume size
df -h /
# Expected: / mounted, Size column shows 30G or more

# INFRA-02: Port 8008 not externally reachable (run from admin machine)
# curl http://<EC2-PUBLIC-DNS>:8008    # Should time out (not in SG)
# curl http://<EC2-PUBLIC-DNS>         # Should connect (port 80 in SG)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Amazon Linux 2 + `amazon-linux-extras install docker` | Amazon Linux 2023 + `dnf install docker` | AL2023 GA March 2023 | AL2-specific extras mechanism gone; standard dnf |
| Standalone `docker-compose` v1 binary | Docker Compose plugin v2 (`docker compose`) | Compose v2 default 2022+ | Hyphenated `docker-compose` deprecated; use `docker compose` |
| Hardcoded AMI IDs | SSM parameter store resolve | AL2023 launch | AMIs deprecated 90 days after release |
| gp2 EBS volumes | gp3 EBS volumes | 2020 (gp3 launch) | gp3 is cheaper and faster baseline than gp2; use by default |

**Deprecated/outdated:**
- `amazon-linux-extras`: AL2-only mechanism; does not exist on AL2023
- `docker-compose` (standalone binary, hyphenated): replaced by `docker compose` plugin; still works but deprecated
- Hardcoded AMI IDs in provisioning scripts: AMIs are deprecated 90 days after release; use SSM parameters

---

## Open Questions

1. **Default VPC vs explicit subnet**
   - What we know: `run-instances` without `--subnet-id` uses the default VPC's default subnet, which exists in every AWS account by default.
   - What's unclear: If the admin's AWS account has deleted the default VPC (non-trivial but possible), the launch will fail.
   - Recommendation: Document that default VPC must exist. Add a pre-flight check: `aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text` should return a VPC ID, not "None".

2. **Whether to use IMDSv2-only at launch**
   - What we know: AWS recommends IMDSv2 (token-based) over IMDSv1. AL2023 AMIs with `ImdsSupport: v2.0` may default to IMDSv2 required. The backup.sh script runs on the host and uses rclone (not direct IMDS); standard AWS CLI on the host works with IMDSv2.
   - What's unclear: Whether `resolve:ssm:` AMI parameter results in an AMI that enforces IMDSv2.
   - Recommendation: Explicitly set `--metadata-options HttpTokens=optional` during launch to ensure compatibility, or test with the current AMI. This is low-risk for a POC.

3. **Security group and default VPC association**
   - What we know: `create-security-group` without `--vpc-id` creates the SG in the default VPC.
   - What's unclear: If admin specifies a non-default VPC, the SG and instance must be in the same VPC.
   - Recommendation: For POC, rely on default VPC behavior; document that both SG and instance must be in the same VPC if customized.

---

## Sources

### Primary (HIGH confidence)
- [AWS CLI EC2 run-instances reference](https://docs.aws.amazon.com/cli/latest/reference/ec2/run-instances.html) — block-device-mappings, user-data, tag-specifications parameters
- [AWS CLI ec2 wait instance-running](https://docs.aws.amazon.com/cli/latest/reference/ec2/wait/instance-running.html) — polling behavior, exit codes
- [AL2023 on EC2 documentation](https://docs.aws.amazon.com/linux/al2023/ug/ec2.html) — SSM parameter names for AMI resolution, supported instance types
- [AWS CLI authorize-security-group-ingress reference](https://docs.aws.amazon.com/cli/latest/reference/ec2/authorize-security-group-ingress.html) — ingress rule syntax
- [AWS CLI create-key-pair reference](https://docs.aws.amazon.com/cli/latest/reference/ec2/create-key-pair.html) — key format options, KeyMaterial query

### Secondary (MEDIUM confidence)
- [awsvpc/al2023-dev-guide setup-docker-al2023.md](https://github.com/awsvpc/al2023-dev-guide/blob/main/setup-docker-al2023.md) — AL2023 built-in docker package + compose binary install; verified against multiple community sources
- [oneuptime.com: How to Install Docker on Amazon Linux 2023 (Feb 2026)](https://oneuptime.com/blog/post/2026-02-08-how-to-install-docker-on-amazon-linux-2023/view) — confirms AL2023 built-in docker + separate compose binary approach
- [basaran gist: Setup Docker and docker-compose on Amazon Linux 2023](https://gist.github.com/basaran/c5d2829b05b8f0ca64e59f41104f488f) — user-data script pattern with AL2023 dnf docker package
- [Vantage instances.vantage.sh: t3.small pricing](https://instances.vantage.sh/aws/ec2/t3.small) — $0.0208/hr on-demand us-east-1, ~$15.18/mo

### Tertiary (LOW confidence)
- AWS re:Post and community discussions re: `$releasever/9` workaround — multiple sources agree on the fix; Docker CE CentOS repo path still requires it as of Feb 2026
- IMDS hop limit behavior with Docker — confirmed by AWS re:Post and AWS docs; current backup.sh is unaffected (runs on host)

---

## Metadata

**Confidence breakdown:**
- Standard stack (AWS CLI commands): HIGH — verified against official AWS CLI reference docs
- AMI resolution via SSM: HIGH — official AL2023 EC2 docs confirm pattern
- Docker installation on AL2023: MEDIUM — two approaches both verified via multiple Feb 2026 community sources; no single official AWS doc consolidates both steps
- Docker CE `$releasever=9` workaround: MEDIUM — widely confirmed in community; Docker has no official AL2023 install guide
- Pitfalls (cloud-init timing, NVMe naming, docker group): MEDIUM-HIGH — multiple independent sources confirm each

**Research date:** 2026-02-20
**Valid until:** 2026-05-20 (stable domain; AWS CLI syntax changes slowly; Docker-on-AL2023 patterns stable)
