# Security Documentation

## Threat Model Summary

### Assets
1. **User messages** — E2EE protected in transit and at rest for encrypted rooms; unencrypted room messages are stored in Postgres in plaintext
2. **User metadata** — usernames, room memberships, timestamps, IP addresses
3. **Media files** — uploaded files/images stored in Synapse media store
4. **Server keys** — signing key, TLS certificates, database credentials
5. **Backup archives** — contain full database + media snapshots

### Threat Actors
| Actor | Motivation | Capability |
|-------|-----------|------------|
| Script kiddies | Disruption, defacement | Automated scanning, known exploits |
| Targeted attacker | Data exfiltration, surveillance | Social engineering, 0-days |
| Rogue admin | Insider abuse | Full server access |
| Law enforcement | Legal compliance | Subpoena, court order |
| Network observer | Metadata collection | Traffic analysis |

### Attack Surfaces
1. **Network**: Exposed ports (80, 443, 8448), DNS
2. **Application**: Synapse API (registration, federation, admin), Element XSS
3. **Infrastructure**: SSH, Docker daemon, host OS
4. **Supply chain**: Container images, dependencies
5. **Social**: Admin account compromise, invite link leakage

---

## Security Baseline Checklist

### Server Hardening
- [ ] SSH: key-only auth, disable root login, non-standard port
- [ ] Firewall (ufw/iptables): allow only 22/80/443/8448 inbound
- [ ] Automatic security updates: `unattended-upgrades`
- [ ] Docker: rootless mode or non-root containers where possible
- [ ] Fail2ban for SSH brute-force protection

### TLS
- [ ] TLS 1.2+ only (TLS 1.0/1.1 disabled)
- [ ] Strong cipher suites (see `proxy/snippets/tls-params.conf`)
- [ ] HSTS with `includeSubDomains` and `preload`
- [ ] OCSP stapling enabled
- [ ] Certificate auto-renewal via certbot
- [ ] Test with SSL Labs: target A+

### Synapse
- [ ] Registration disabled (invite-only via tokens)
- [ ] `registration_shared_secret` is strong and unique
- [ ] Federation disabled by default (`federation_domain_whitelist: []`)
- [ ] Rate limiting enabled for messages, registration, login
- [ ] URL preview disabled (prevents SSRF and privacy leaks)
- [ ] Trusted key servers: empty (no external trust)
- [ ] Admin API not exposed to internet (proxied only on internal network)

### Nginx
- [ ] Security headers set (HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy)
- [ ] Server version hidden (`server_tokens off`)
- [ ] Only proxy known paths (`/_matrix`, `/_synapse/client`)
- [ ] Client max body size limited (50M)
- [ ] WebSocket upgrade only for Synapse paths

### Secrets Management
- [ ] All secrets in `.env` file (not in version control)
- [ ] `.env` added to `.gitignore`
- [ ] Unique, random values for all secrets (minimum 32 characters)
- [ ] Backup encryption passphrase stored separately from backups
- [ ] Admin password is strong and unique

### Backups
- [ ] Automated daily backups
- [ ] AES-256 encrypted at rest
- [ ] Offsite copy via rclone
- [ ] Restore tested at least once
- [ ] Old backups pruned (7-day local retention)

---

## Federation Security (When Enabled)

Federation increases the attack surface significantly. Before enabling:

1. **Whitelist only trusted servers** instead of open federation
2. **Enable `allow_public_rooms_over_federation: false`** to prevent room directory scraping
3. **Monitor federation traffic** for abuse patterns
4. **Review incoming join requests** — consider requiring invite for sensitive rooms
5. **Understand metadata exposure**: federated servers see room membership and message metadata

To enable federation:
```yaml
# Remove or comment in homeserver.yaml:
# federation_domain_whitelist: []

# Or whitelist specific servers:
federation_domain_whitelist:
  - trusted-server.org
  - another-server.net
```

---

## Privacy Positioning

This deployment supports communities seeking privacy from corporate surveillance and forced KYC/age-verification systems. Key privacy properties:

1. **Self-hosted**: No third-party data access; you control the hardware
2. **E2EE by default**: Server cannot read encrypted room content
3. **No KYC**: Registration does not require government ID or phone number
4. **No telemetry**: `report_stats: no` — no data sent to Matrix.org
5. **No identity server**: Disabled by default; no phone/email directory lookup
6. **Federation off**: No metadata shared with external servers (until intentionally enabled)

### Legal Obligations
Self-hosting does not exempt you from local law. You must:
- Comply with lawful data requests (subpoenas, court orders)
- Implement a content moderation policy appropriate to your jurisdiction
- Consider GDPR/CCPA obligations if users are in EU/California
- Maintain an abuse reporting mechanism

### What the Server CAN See (Even with E2EE)
- Who is talking to whom (room membership)
- When messages are sent (timestamps)
- Message sizes and frequency
- User IP addresses (unless users use Tor/VPN)
- Unencrypted room names and topics
- Uploaded media metadata (filenames, sizes)

### What the Server CANNOT See (With E2EE)
- Message content in encrypted rooms
- Encrypted file contents
- Verification keys (stored on devices)

---

## Incident Classification

| Severity | Examples | Response Time |
|----------|----------|---------------|
| P1 Critical | Server compromise, data breach, signing key leak | Immediate |
| P2 High | Service outage > 30 min, TLS failure, backup failure | < 1 hour |
| P3 Medium | Spam/abuse, performance degradation, disk warning | < 4 hours |
| P4 Low | Non-critical feature issue, cosmetic bug | Next business day |

### P1 Response Procedure
1. **Contain**: Shut down the compromised service immediately
2. **Preserve**: Capture logs, do NOT destroy evidence
3. **Assess**: Determine scope of compromise
4. **Notify**: Inform affected users
5. **Recover**: Restore from last known-good backup
6. **Rotate**: All secrets, keys, passwords
7. **Review**: Post-incident analysis and prevention measures

---

## Day 1 Go-Live Checklist

- [ ] All `.env` placeholder values replaced with real secrets
- [ ] DNS A records propagated for all three domains
- [ ] TLS certificates obtained and loaded
- [ ] Synapse starts and reports healthy
- [ ] Element Web loads at `https://chat.example.com`
- [ ] `.well-known` endpoints return correct JSON
- [ ] Admin user created and can log in
- [ ] Default rooms created and accessible
- [ ] E2EE works in DMs (test with two sessions)
- [ ] Registration is invite-only (test that public reg is blocked)
- [ ] SMTP works (test password reset email)
- [ ] Firewall rules: only 22/80/443/8448 open
- [ ] `.env` is NOT committed to git
- [ ] First backup runs successfully

## Day 30 Hardening Checklist

- [ ] Restore test performed and documented
- [ ] Backup cron job verified (check last 7 days of backups)
- [ ] SSL Labs scan: A+ grade
- [ ] Synapse + Element updated to latest stable
- [ ] Fail2ban or equivalent active on SSH
- [ ] Unattended security updates enabled
- [ ] Log rotation configured
- [ ] Disk usage < 50% (or growth plan in place)
- [ ] Monitoring/uptime check active
- [ ] At least one non-admin moderator appointed
- [ ] Community code of conduct / rules posted
- [ ] Abuse reporting process documented
- [ ] Admin access audit: review who has SSH and Synapse admin
- [ ] Consider: coturn for voice/video reliability
- [ ] Consider: sliding sync proxy for faster client sync
- [ ] Consider: rate limit tuning based on actual usage patterns
