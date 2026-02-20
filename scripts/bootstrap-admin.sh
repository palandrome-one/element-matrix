#!/usr/bin/env bash
# bootstrap-admin.sh — Create the first admin user on a fresh Synapse instance.
# Usage: ./scripts/bootstrap-admin.sh
# Reads ADMIN_USER, ADMIN_PASSWORD, SYNAPSE_REGISTRATION_SHARED_SECRET from compose/.env

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$REPO_ROOT/compose/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found. Copy .env.example to .env and fill in values."
    exit 1
fi

# Extract specific variables using grep/cut to avoid sourcing issues with
# multi-word values like POSTGRES_INITDB_ARGS=--encoding=UTF-8 --lc-collate=C
_get_env() { grep "^${1}=" "$ENV_FILE" | head -1 | cut -d= -f2-; }
ADMIN_USER="$(_get_env ADMIN_USER)"
ADMIN_PASSWORD="$(_get_env ADMIN_PASSWORD)"
SYNAPSE_REGISTRATION_SHARED_SECRET="$(_get_env SYNAPSE_REGISTRATION_SHARED_SECRET)"
SYNAPSE_SERVER_NAME="$(_get_env SYNAPSE_SERVER_NAME)"
ELEMENT_DOMAIN="$(_get_env ELEMENT_DOMAIN)"

# Validate required vars
for var in ADMIN_USER ADMIN_PASSWORD SYNAPSE_REGISTRATION_SHARED_SECRET; do
    if [[ -z "${!var:-}" ]] || [[ "${!var}" == __* ]]; then
        echo "ERROR: $var is not set or still has a placeholder value in .env"
        exit 1
    fi
done

echo "Creating admin user '@${ADMIN_USER}:${SYNAPSE_SERVER_NAME}'..."

docker compose -f "$REPO_ROOT/compose/docker-compose.yml" exec synapse \
    register_new_matrix_user \
    -u "$ADMIN_USER" \
    -p "$ADMIN_PASSWORD" \
    -a \
    -c /data/homeserver.yaml \
    "http://localhost:8008"

echo ""
echo "Admin user created successfully."
echo "Login at: https://${ELEMENT_DOMAIN:-chat.example.com}"
echo "Username: @${ADMIN_USER}:${SYNAPSE_SERVER_NAME}"
