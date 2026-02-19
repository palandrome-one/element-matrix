# Ops Runbook

## Table of Contents
1. [Stack Management](#stack-management)
2. [Backup & Restore](#backup--restore)
3. [Upgrades](#upgrades)
4. [User & Room Administration](#user--room-administration)
5. [Incident Response](#incident-response)
6. [Monitoring & Alerting](#monitoring--alerting)
7. [Scaling Triggers](#scaling-triggers)
8. [Certificate Management](#certificate-management)

---

## Stack Management

### Start / Stop / Restart
```bash
cd compose
docker compose up -d          # Start all services
docker compose down            # Stop all services
docker compose restart synapse # Restart single service
```

### View Logs
```bash
docker compose logs -f synapse     # Follow Synapse logs
docker compose logs -f nginx       # Follow proxy logs
docker compose logs --tail=100 postgres  # Last 100 lines from Postgres
```

---

## Backup & Restore

### Automated Backup
Add to cron (daily at 3 AM):
```bash
crontab -e
# Add:
0 3 * * * /path/to/element-matrix/scripts/backup.sh >> /var/log/matrix-backup.log 2>&1
```

### Manual Backup
```bash
./scripts/backup.sh              # Full backup + offsite upload
./scripts/backup.sh --local-only # Skip offsite upload
```

Backups include:
- PostgreSQL database dump (custom format)
- Synapse media store archive
- All configuration files + .env

Backups are AES-256 encrypted with the passphrase in `.env`.

### Restore
```bash
./scripts/restore.sh /path/to/matrix-backup-YYYY-MM-DD_HHMMSS.tar.gz.gpg
```

**Post-restore checklist:**
1. Log in as admin, verify rooms and message history
2. Verify media loads (avatars, uploaded files)
3. Check Synapse logs for errors
4. Run a test message send/receive

### Restore Test (monthly)
1. Spin up a test VM or local Docker environment
2. Copy latest backup to test environment
3. Run restore script
4. Verify login, rooms, and media load correctly
5. Document result and date in this section

Last restore test: `__NOT_YET_PERFORMED__`

---

## Upgrades

### Update All Container Images
```bash
cd compose
docker compose pull          # Pull latest images
docker compose up -d         # Recreate containers with new images
docker compose logs -f       # Watch for startup errors
```

### Pre-Upgrade Checklist
1. **Backup first**: `./scripts/backup.sh`
2. Check Synapse release notes for breaking changes: https://github.com/element-hq/synapse/releases
3. Check Element Web release notes: https://github.com/element-hq/element-web/releases
4. If a database migration is needed, Synapse runs it automatically on startup

### Rollback
If an upgrade breaks something:
```bash
cd compose
docker compose down
# Pin to the previous working version in docker-compose.yml, e.g.:
#   image: matrixdotorg/synapse:v1.XX.0
docker compose up -d
```

For database-level rollback, restore from the pre-upgrade backup.

---

## User & Room Administration

### Create Invite Token (for invite-only registration)
```bash
# Generate a single-use registration token valid for 7 days
docker compose -f compose/docker-compose.yml exec synapse \
  curl -s -X POST http://localhost:8008/_synapse/admin/v1/registration_tokens/new \
  -H "Authorization: Bearer $(cat /tmp/admin_token)" \
  -H "Content-Type: application/json" \
  -d '{"uses_allowed": 1, "expiry_time": '$(( $(date +%s) + 604800 ))' }'
```

Or use the Synapse Admin API directly. First, get an admin access token by logging in.

### Deactivate a User
```bash
curl -X POST "https://matrix.example.com/_synapse/admin/v2/deactivate/@baduser:example.com" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"erase": false}'
```

### List Rooms
```bash
curl -s "https://matrix.example.com/_synapse/admin/v1/rooms?limit=50" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq '.rooms[] | {room_id, name, joined_members}'
```

### Purge Room History (if retention is needed)
```bash
curl -X POST "https://matrix.example.com/_synapse/admin/v1/purge_history/$ROOM_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"purge_up_to_ts": '$(( $(date +%s) * 1000 - 86400000 * 90 ))'}'
```

---

## Incident Response

### Synapse Won't Start
1. Check logs: `docker compose logs synapse`
2. Common causes:
   - Database connection failed → check Postgres is healthy: `docker compose ps`
   - Config syntax error → validate YAML: `python3 -c "import yaml; yaml.safe_load(open('synapse/homeserver.yaml'))"`
   - Port conflict → check `ss -tlnp | grep 8008`

### Database Issues
1. Check Postgres health: `docker compose exec postgres pg_isready`
2. Check disk space: `df -h` (Postgres data lives in a Docker volume)
3. Connection pool exhaustion → restart Synapse, check `cp_max` setting

### Certificate Expired
```bash
# Manually renew
docker compose run --rm certbot certonly --webroot -w /var/www/certbot \
  -d chat.example.com -d matrix.example.com -d example.com

# Reload nginx
docker compose exec nginx nginx -s reload
```

### High Memory Usage (Synapse)
Synapse can be memory-hungry with many users:
1. Check: `docker stats synapse`
2. Consider enabling Synapse cache factor: add `caches.global_factor: 0.5` to homeserver.yaml
3. Long-term: evaluate Synapse workers (Phase 2)

### Suspected Abuse / Spam
1. Identify the user from logs or reports
2. Quarantine: set user's power level to -1 in affected rooms
3. Deactivate account (see above)
4. If federated: block the remote server via `federation_domain_whitelist`

---

## Monitoring & Alerting (Phase 2)

### Basic Health Checks
Add to monitoring (UptimeRobot, Uptime Kuma, or cron):
```bash
# Synapse health
curl -sf https://matrix.example.com/health || echo "ALERT: Synapse down"

# Element loads
curl -sf https://chat.example.com/ | grep -q "Element" || echo "ALERT: Element down"

# TLS valid
echo | openssl s_client -connect chat.example.com:443 -servername chat.example.com 2>/dev/null | openssl x509 -noout -dates
```

### Disk Space Alert
```bash
# Add to cron — alert if /var/lib/docker usage > 80%
USAGE=$(df /var/lib/docker --output=pcent | tail -1 | tr -dc '0-9')
if [ "$USAGE" -gt 80 ]; then
  echo "ALERT: Docker disk usage at ${USAGE}%"
fi
```

### Prometheus (Optional, Phase 2)
Uncomment `enable_metrics: true` in homeserver.yaml, then scrape `http://synapse:8008/_synapse/metrics`.

---

## Scaling Triggers

| Signal | Threshold | Action |
|--------|-----------|--------|
| Synapse RAM | > 2 GB sustained | Tune caches, evaluate workers |
| Postgres CPU | > 70% sustained | Tune `shared_buffers`, `work_mem` |
| Disk usage | > 80% | Expand volume or add S3 media backend |
| Federation lag | > 30s | Consider Synapse workers for federation |
| Concurrent users | > 500 | Evaluate Synapse worker mode |
| Response time (sync) | > 5s p95 | Enable sliding sync proxy |

---

## Certificate Management

Certbot runs as a sidecar container and auto-renews. To force a renewal:
```bash
docker compose run --rm certbot renew --force-renewal
docker compose exec nginx nginx -s reload
```

Check expiration:
```bash
echo | openssl s_client -connect chat.example.com:443 2>/dev/null | openssl x509 -noout -enddate
```
