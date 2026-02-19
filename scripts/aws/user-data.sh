#!/bin/bash
set -euo pipefail

# user-data.sh — Cloud-init script for Amazon Linux 2023
# Installs Docker Engine and Docker Compose v2 plugin on first boot.
# Uses AL2023 built-in docker package (avoids Docker CE $releasever hack).

# 1. System update
dnf update -y

# 2. Install Docker Engine, CLI, and containerd from AL2023 built-in repo
dnf install -y docker

# 3. Configure Docker daemon
#    - native cgroup driver (required for systemd cgroup management)
#    - json-file logging with rotation (prevents log disk exhaustion)
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

# 4. Enable and start Docker on boot
systemctl enable --now docker

# 5. Allow ec2-user to run docker without sudo
usermod -aG docker ec2-user

# 6. Install Docker Compose v2 as a system-wide CLI plugin
mkdir -p /usr/local/lib/docker/cli-plugins
curl -sSL \
  "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
