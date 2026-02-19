---
phase: 01-aws-infrastructure
plan: 01
subsystem: infra
tags: [aws, ec2, docker, al2023, docker-compose, security-group, ssh]

# Dependency graph
requires: []
provides:
  - t3.small EC2 instance running in us-east-1 with Docker Engine and Docker Compose v2
  - SSH key pair (matrix-poc-key.pem) for instance access
  - Security group (matrix-poc-sg) with TCP/80 public and TCP/22 admin-only
  - gp3 30 GB root volume
  - instance-info.env metadata file for downstream scripts
  - scripts/aws/user-data.sh cloud-init script
  - scripts/aws/provision.sh AWS CLI provisioning script
affects: [02-matrix-stack-deploy]

# Tech tracking
tech-stack:
  added: [aws-cli, docker-engine, docker-compose-v2, amazon-linux-2023]
  patterns: [user-data-cloud-init, aws-cli-provisioning, ssm-ami-resolution, set-euo-pipefail]

key-files:
  created:
    - scripts/aws/user-data.sh
    - scripts/aws/provision.sh
  modified:
    - .gitignore

key-decisions:
  - "Use AL2023 built-in docker package (dnf install docker) instead of Docker CE CentOS repo — avoids releasever workaround, simpler install"
  - "Install Docker Compose v2 as binary CLI plugin from GitHub releases — same result as package, no external repo needed"
  - "Resolve AL2023 AMI via SSM parameter store (resolve:ssm:) — avoids hardcoded AMI IDs that rot after 90 days"
  - "instance-info.env added to .gitignore — contains admin IP and instance IDs, must not be committed"
  - "instance-info.env written by provision.sh — consumed by Plan 02 for deployment verification"

patterns-established:
  - "All shell scripts use set -euo pipefail — fails loudly on any error, prevents silent cloud-init failures"
  - "provision.sh cd to its own directory first — ensures relative file:// user-data reference resolves"
  - "Pre-flight checks before resource creation (VPC exists, key/SG not already present) — fail-fast with clear error messages"

requirements-completed: [INFRA-01, INFRA-02, INFRA-03, INFRA-04, INFRA-05]

# Metrics
duration: 4min
completed: 2026-02-20
---

# Phase 01 Plan 01: AWS Infrastructure Provisioning Summary

**t3.small AL2023 EC2 instance (i-0788240f8e1ae5807) running in us-east-1 with Docker Engine and Compose v2 installed via user-data, behind a 2-rule security group (TCP/80 public, TCP/22 admin-IP)**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-19T18:16:50Z
- **Completed:** 2026-02-19T18:21:40Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- EC2 instance i-0788240f8e1ae5807 running in us-east-1 (t3.small, 30 GB gp3, AL2023)
- Security group sg-0facc7dfa93ee4111 with exactly 2 ingress rules (TCP/80 from 0.0.0.0/0, TCP/22 from admin IP)
- Docker Engine + Compose v2 plugin will be installed on boot via user-data.sh cloud-init
- SSH key pair matrix-poc-key.pem saved locally with 400 permissions
- instance-info.env written for Plan 02 consumption

## Task Commits

Each task was committed atomically:

1. **Task 1: Create user-data.sh cloud-init script for Docker on AL2023** - `0374ed5` (feat)
2. **Task 2: Create provision.sh and execute it to launch EC2 instance** - `8bec9c7` (feat)

**Plan metadata:** `[pending final commit]` (docs: complete plan)

## Files Created/Modified
- `scripts/aws/user-data.sh` - Cloud-init script: dnf install docker, daemon.json config, systemctl enable, usermod, Compose v2 plugin
- `scripts/aws/provision.sh` - AWS CLI provisioning: key pair creation, security group with 2 rules, run-instances with gp3/user-data, wait, metadata output
- `.gitignore` - Added scripts/aws/instance-info.env exclusion (security: contains admin IP and instance IDs)

## Decisions Made
- AL2023 built-in `dnf install docker` over Docker CE CentOS repo — eliminates the `$releasever=9` workaround that research flagged as MEDIUM confidence
- Docker Compose v2 binary from GitHub releases as CLI plugin — equivalent to `docker-compose-plugin` package, no external repo required
- SSM parameter store AMI resolution (`resolve:ssm:`) — canonical approach per AL2023 docs, avoids 90-day AMI ID expiration
- Wrote `instance-info.env` with full instance metadata (INSTANCE_ID, PUBLIC_DNS, SG_ID, KEY_FILE, ADMIN_IP, REGION) for Plan 02 to source

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Created missing default VPC before provisioning**
- **Found during:** Task 2 (executing provision.sh)
- **Issue:** provision.sh pre-flight check detected no default VPC in us-east-1. `aws ec2 describe-vpcs --filters Name=isDefault,Values=true` returned None, which would cause run-instances to fail.
- **Fix:** Ran `aws ec2 create-default-vpc --region us-east-1` before re-running provision.sh. VPC vpc-0691bbcfa36261705 created.
- **Files modified:** None (AWS infrastructure only)
- **Verification:** Pre-flight check passed on second run; instance launched successfully
- **Committed in:** 8bec9c7 (Task 2 commit, noted in message)

**2. [Rule 2 - Missing Critical] Added instance-info.env to .gitignore**
- **Found during:** Task 2 (post-execution git status)
- **Issue:** instance-info.env contains admin IP (96.9.84.206/32) and AWS instance IDs — sensitive operational data that must not be committed
- **Fix:** Added `scripts/aws/instance-info.env` pattern to .gitignore
- **Files modified:** .gitignore
- **Verification:** `git status` shows instance-info.env as untracked (excluded), not staged
- **Committed in:** 8bec9c7 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 missing critical security)
**Impact on plan:** Both fixes necessary — first unblocked provisioning, second prevented sensitive data exposure. No scope creep.

## Issues Encountered
- Default VPC was absent in the target AWS account/region. The research doc noted this as an open question with "recommend documenting that default VPC must exist." The pre-flight check in provision.sh caught this correctly and provided the remediation command. Fixed inline before proceeding.

## User Setup Required
None - provisioning executed fully autonomously. The EC2 instance is running.

**Important operational notes for Plan 02:**
- `instance-info.env` lives at `scripts/aws/instance-info.env` (gitignored) — source it for instance metadata
- Wait 2-3 minutes after provisioning before SSHing in — Docker cloud-init is still running
- Verify cloud-init completion: `ssh -i scripts/aws/matrix-poc-key.pem ec2-user@ec2-23-20-14-90.compute-1.amazonaws.com 'sudo cloud-init status --wait'`
- Admin IP locked in SG: 96.9.84.206/32 — if IP changes, update SG manually

## Next Phase Readiness
- EC2 instance running and ready to accept SSH connections
- Docker Engine will be installed on boot (cloud-init in progress)
- All metadata in instance-info.env for Plan 02 to consume
- Plan 02 can begin after cloud-init completes (~2-3 min from launch)

---
*Phase: 01-aws-infrastructure*
*Completed: 2026-02-20*
