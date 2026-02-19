#!/usr/bin/env bash
# restore.sh — Restore a Matrix backup from an encrypted archive.
#
# Usage:
#   ./scripts/restore.sh /path/to/matrix-backup-YYYY-MM-DD_HHMMSS.tar.gz.gpg
#
# WARNING: This will REPLACE the current database and media store.
# The stack must be running (postgres must be up).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$REPO_ROOT/compose/.env"
COMPOSE_FILE="$REPO_ROOT/compose/docker-compose.yml"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <backup-file.tar.gz.gpg>"
    exit 1
fi

ARCHIVE="$1"
if [[ ! -f "$ARCHIVE" ]]; then
    echo "ERROR: File not found: $ARCHIVE"
    exit 1
fi

# Load env
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found."
    exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

for var in POSTGRES_DB POSTGRES_USER BACKUP_ENCRYPTION_PASSPHRASE; do
    if [[ -z "${!var:-}" ]] || [[ "${!var}" == __* ]]; then
        echo "ERROR: $var not set in .env"
        exit 1
    fi
done

RESTORE_DIR=$(mktemp -d)
trap 'rm -rf "$RESTORE_DIR"' EXIT

echo "=== Matrix Restore ==="
echo "Archive: $ARCHIVE"
echo ""

# Confirmation
read -rp "This will REPLACE the current database and media. Continue? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

# 1. Decrypt + extract
echo "[1/4] Decrypting and extracting..."
gpg --batch --yes --decrypt \
    --passphrase "$BACKUP_ENCRYPTION_PASSPHRASE" \
    "$ARCHIVE" | tar -xzf - -C "$RESTORE_DIR"

# Find the inner backup directory
INNER_DIR=$(find "$RESTORE_DIR" -maxdepth 1 -type d -name 'matrix-backup-*' | head -1)
if [[ -z "$INNER_DIR" ]]; then
    echo "ERROR: Could not find backup contents in archive."
    exit 1
fi

# 2. Stop synapse (keep postgres running)
echo "[2/4] Stopping Synapse..."
docker compose -f "$COMPOSE_FILE" stop synapse

# 3. Restore PostgreSQL
echo "[3/4] Restoring database..."
if [[ -f "$INNER_DIR/synapse.pgdump" ]]; then
    # Drop and recreate
    docker compose -f "$COMPOSE_FILE" exec -T postgres \
        dropdb -U "$POSTGRES_USER" --if-exists "$POSTGRES_DB"
    docker compose -f "$COMPOSE_FILE" exec -T postgres \
        createdb -U "$POSTGRES_USER" -O "$POSTGRES_USER" --encoding=UTF-8 --lc-collate=C --lc-ctype=C "$POSTGRES_DB"
    docker compose -f "$COMPOSE_FILE" exec -T postgres \
        pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges \
        < "$INNER_DIR/synapse.pgdump"
    echo "  Database restored."
else
    echo "  WARNING: No database dump found in backup."
fi

# 4. Restore media
echo "[4/4] Restoring media store..."
if [[ -f "$INNER_DIR/media.tar" ]]; then
    MEDIA_VOLUME=$(docker volume inspect compose_synapse_media --format '{{.Mountpoint}}' 2>/dev/null || echo "")
    if [[ -n "$MEDIA_VOLUME" ]]; then
        # Clear existing media and extract
        sudo rm -rf "${MEDIA_VOLUME:?}"/*
        sudo tar -xf "$INNER_DIR/media.tar" -C "$MEDIA_VOLUME"
        echo "  Media restored."
    else
        echo "  WARNING: Media volume not found. Extract media.tar manually."
    fi
else
    echo "  No media archive found in backup, skipping."
fi

# Restart
echo ""
echo "Starting Synapse..."
docker compose -f "$COMPOSE_FILE" up -d synapse

echo ""
echo "Restore complete. Verify by logging in at https://${ELEMENT_DOMAIN:-chat.example.com}"
echo ""
echo "Post-restore checklist:"
echo "  1. Log in as admin and verify rooms/messages"
echo "  2. Check Synapse logs: docker compose -f $COMPOSE_FILE logs -f synapse"
echo "  3. Verify media loads correctly in chat"
