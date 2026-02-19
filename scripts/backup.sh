#!/usr/bin/env bash
# backup.sh — Automated backup of PostgreSQL + Synapse media + configs.
# Produces an encrypted, timestamped archive and optionally uploads to an rclone remote.
#
# Usage:
#   ./scripts/backup.sh              # Full backup + upload
#   ./scripts/backup.sh --local-only # Skip rclone upload

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$REPO_ROOT/compose/.env"
COMPOSE_FILE="$REPO_ROOT/compose/docker-compose.yml"
BACKUP_DIR="$REPO_ROOT/backups"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
BACKUP_NAME="matrix-backup-${TIMESTAMP}"
WORK_DIR="$BACKUP_DIR/$BACKUP_NAME"

LOCAL_ONLY=false
if [[ "${1:-}" == "--local-only" ]]; then
    LOCAL_ONLY=true
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

mkdir -p "$WORK_DIR"

echo "=== Matrix Backup: $TIMESTAMP ==="

# 1. PostgreSQL dump
echo "[1/4] Dumping PostgreSQL..."
docker compose -f "$COMPOSE_FILE" exec -T postgres \
    pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom \
    > "$WORK_DIR/synapse.pgdump"
echo "  Database dump: $(du -sh "$WORK_DIR/synapse.pgdump" | cut -f1)"

# 2. Synapse media store
echo "[2/4] Backing up media store..."
MEDIA_VOLUME=$(docker volume inspect compose_synapse_media --format '{{.Mountpoint}}' 2>/dev/null || echo "")
if [[ -n "$MEDIA_VOLUME" && -d "$MEDIA_VOLUME" ]]; then
    tar -cf "$WORK_DIR/media.tar" -C "$MEDIA_VOLUME" .
    echo "  Media archive: $(du -sh "$WORK_DIR/media.tar" | cut -f1)"
else
    echo "  WARNING: Media volume not found, skipping. Check volume name if unexpected."
fi

# 3. Config files
echo "[3/4] Backing up configs..."
tar -cf "$WORK_DIR/configs.tar" \
    -C "$REPO_ROOT" \
    synapse/homeserver.yaml \
    synapse/log.config \
    element/config.json \
    compose/.env \
    proxy/

echo "  Configs archived."

# 4. Compress + encrypt
echo "[4/4] Compressing and encrypting..."
ARCHIVE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz.gpg"
tar -czf - -C "$BACKUP_DIR" "$BACKUP_NAME" | \
    gpg --batch --yes --symmetric --cipher-algo AES256 \
    --passphrase "$BACKUP_ENCRYPTION_PASSPHRASE" \
    -o "$ARCHIVE"
rm -rf "$WORK_DIR"

ARCHIVE_SIZE=$(du -sh "$ARCHIVE" | cut -f1)
echo ""
echo "Backup complete: $ARCHIVE ($ARCHIVE_SIZE)"

# 5. Upload offsite
if [[ "$LOCAL_ONLY" == false ]] && command -v rclone &>/dev/null; then
    REMOTE="${BACKUP_RCLONE_REMOTE:-}"
    if [[ -n "$REMOTE" && "$REMOTE" != __* ]]; then
        echo ""
        echo "Uploading to $REMOTE..."
        rclone copy "$ARCHIVE" "$REMOTE/" --progress
        echo "Upload complete."
    else
        echo "BACKUP_RCLONE_REMOTE not configured, skipping upload."
    fi
else
    if [[ "$LOCAL_ONLY" == false ]]; then
        echo "rclone not installed, skipping offsite upload."
    fi
fi

# 6. Cleanup old local backups (keep last 7)
echo ""
echo "Cleaning up old local backups (keeping last 7)..."
ls -1t "$BACKUP_DIR"/*.tar.gz.gpg 2>/dev/null | tail -n +8 | xargs -r rm -f
echo "Done."
