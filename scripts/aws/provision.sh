#!/usr/bin/env bash
set -euo pipefail

# provision.sh — AWS CLI script to provision the Matrix POC EC2 infrastructure.
#
# Provisions:
#   - SSH key pair (RSA PEM)
#   - Security group with port 80 (public) and port 22 (admin IP only)
#   - EC2 t3.small instance on AL2023 with gp3 30 GB root volume
#   - Docker Engine + Compose v2 installed via user-data
#
# Outputs:
#   - ${KEY_NAME}.pem — SSH private key (chmod 400)
#   - instance-info.env — instance metadata for downstream scripts

# ─────────────────────────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────────────────────────

REGION="us-east-1"
KEY_NAME="matrix-poc-key"
SG_NAME="matrix-poc-sg"
INSTANCE_NAME="matrix-poc"

# ─────────────────────────────────────────────────────────────────────────────
# Setup: cd to script directory so relative file paths resolve correctly
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight checks
# ─────────────────────────────────────────────────────────────────────────────

echo "==> Pre-flight: checking AWS CLI access..."
aws sts get-caller-identity --query "Account" --output text > /dev/null

echo "==> Pre-flight: verifying default VPC exists in ${REGION}..."
VPC_ID=$(aws ec2 describe-vpcs \
  --region "$REGION" \
  --filters Name=isDefault,Values=true \
  --query "Vpcs[0].VpcId" \
  --output text)

if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  echo "ERROR: No default VPC found in ${REGION}."
  echo "       Run: aws ec2 create-default-vpc --region ${REGION}"
  exit 1
fi
echo "    Default VPC: ${VPC_ID}"

echo "==> Pre-flight: detecting admin IP..."
ADMIN_IP="$(curl -s https://checkip.amazonaws.com)/32"
echo "    Admin IP: ${ADMIN_IP}"

# ─────────────────────────────────────────────────────────────────────────────
# Step 1 — INFRA-05: Create SSH key pair
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "==> Step 1: Creating SSH key pair '${KEY_NAME}'..."

if aws ec2 describe-key-pairs --region "$REGION" --key-names "$KEY_NAME" --query "KeyPairs[0].KeyName" --output text 2>/dev/null | grep -q "$KEY_NAME"; then
  echo "ERROR: Key pair '${KEY_NAME}' already exists in ${REGION}."
  echo "       To delete it: aws ec2 delete-key-pair --region ${REGION} --key-name ${KEY_NAME}"
  echo "       Also remove the local PEM: rm -f ${SCRIPT_DIR}/${KEY_NAME}.pem"
  exit 1
fi

aws ec2 create-key-pair \
  --region "$REGION" \
  --key-name "$KEY_NAME" \
  --key-type rsa \
  --key-format pem \
  --query "KeyMaterial" \
  --output text > "${KEY_NAME}.pem"

chmod 400 "${KEY_NAME}.pem"
echo "    Key saved: ${SCRIPT_DIR}/${KEY_NAME}.pem (chmod 400)"

# ─────────────────────────────────────────────────────────────────────────────
# Step 2 — INFRA-02: Create security group + ingress rules
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "==> Step 2: Creating security group '${SG_NAME}'..."

# Fail clearly if security group already exists
if aws ec2 describe-security-groups \
    --region "$REGION" \
    --group-names "$SG_NAME" \
    --query "SecurityGroups[0].GroupId" \
    --output text 2>/dev/null | grep -q "sg-"; then
  echo "ERROR: Security group '${SG_NAME}' already exists in ${REGION}."
  echo "       To delete it: aws ec2 delete-security-group --region ${REGION} --group-name ${SG_NAME}"
  exit 1
fi

SG_ID=$(aws ec2 create-security-group \
  --region "$REGION" \
  --group-name "$SG_NAME" \
  --description "Matrix POC: port 80 public, port 22 admin only" \
  --query "GroupId" \
  --output text)
echo "    Security group created: ${SG_ID}"

# Port 80: public access for HTTP (Nginx / Element Web)
echo "    Adding ingress rule: TCP/80 from 0.0.0.0/0"
aws ec2 authorize-security-group-ingress \
  --region "$REGION" \
  --group-id "$SG_ID" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

# Port 22: admin SSH — restricted to detected admin IP only
echo "    Adding ingress rule: TCP/22 from ${ADMIN_IP}"
aws ec2 authorize-security-group-ingress \
  --region "$REGION" \
  --group-id "$SG_ID" \
  --protocol tcp --port 22 --cidr "$ADMIN_IP"

# NOTE: Port 8008 (Synapse) is intentionally NOT added.
# Synapse is Docker-network-internal; Nginx proxies to it internally.

# ─────────────────────────────────────────────────────────────────────────────
# Step 3 — INFRA-01, INFRA-03, INFRA-04: Launch EC2 instance
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "==> Step 3: Launching EC2 instance '${INSTANCE_NAME}'..."
echo "    AMI: AL2023 (resolved via SSM parameter store)"
echo "    Type: t3.small"
echo "    Volume: 30 GB gp3"
echo "    User-data: user-data.sh (installs Docker Engine + Compose v2)"

INSTANCE_ID=$(aws ec2 run-instances \
  --region "$REGION" \
  --image-id "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --instance-type t3.small \
  --count 1 \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":30,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --user-data file://user-data.sh \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=${INSTANCE_NAME}-root}]" \
  --query "Instances[0].InstanceId" \
  --output text)

echo "    Instance ID: ${INSTANCE_ID}"

# ─────────────────────────────────────────────────────────────────────────────
# Step 4 — Wait for running state and extract public DNS
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "==> Step 4: Waiting for instance to reach 'running' state (up to 10 min)..."
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
echo "    Instance is running."

PUBLIC_DNS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].PublicDnsName" \
  --output text)
echo "    Public DNS: ${PUBLIC_DNS}"

# ─────────────────────────────────────────────────────────────────────────────
# Step 5 — Output summary
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "============================================================"
echo "  Matrix POC — EC2 Instance Provisioned"
echo "============================================================"
echo "  Instance ID : ${INSTANCE_ID}"
echo "  Region      : ${REGION}"
echo "  Public DNS  : ${PUBLIC_DNS}"
echo "  Key file    : ${SCRIPT_DIR}/${KEY_NAME}.pem"
echo ""
echo "  SSH command:"
echo "    ssh -i ${SCRIPT_DIR}/${KEY_NAME}.pem ec2-user@${PUBLIC_DNS}"
echo ""
echo "  IMPORTANT: Wait 2-3 minutes for cloud-init to finish before SSHing in."
echo "             cloud-init installs Docker; the instance may appear 'running'"
echo "             before Docker is ready."
echo ""
echo "  To verify cloud-init completed:"
echo "    ssh -i ${SCRIPT_DIR}/${KEY_NAME}.pem ec2-user@${PUBLIC_DNS} 'sudo cloud-init status --wait'"
echo ""
echo "  Admin IP locked in security group: ${ADMIN_IP}"
echo "  If your IP changes, update the SG with:"
echo "    aws ec2 authorize-security-group-ingress --region ${REGION} --group-id ${SG_ID} --protocol tcp --port 22 --cidr <new-ip>/32"
echo "============================================================"

# ─────────────────────────────────────────────────────────────────────────────
# Step 6 — Save instance metadata for downstream scripts (Plan 02+)
# ─────────────────────────────────────────────────────────────────────────────

cat > "${SCRIPT_DIR}/instance-info.env" <<EOF
INSTANCE_ID=${INSTANCE_ID}
PUBLIC_DNS=${PUBLIC_DNS}
SG_ID=${SG_ID}
KEY_FILE=${SCRIPT_DIR}/${KEY_NAME}.pem
ADMIN_IP=${ADMIN_IP}
REGION=${REGION}
EOF

echo "  Metadata written: ${SCRIPT_DIR}/instance-info.env"
