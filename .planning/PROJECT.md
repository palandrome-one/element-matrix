# Matrix Element White-Label POC

## What This Is

A proof-of-concept deployment of a white-labeled Matrix/Element communication platform on AWS, provisioned entirely via AWS CLI. Targets privacy-conscious communities migrating from Discord. The POC demonstrates branded chat with E2EE on a single EC2 instance, with architecture designed to scale to 50K+ users in future phases.

## Core Value

Users can access a branded, self-hosted chat platform where registration, messaging, and E2E encryption work end-to-end — proving the white-label Matrix stack is viable for large-scale community deployment.

## Requirements

### Validated

<!-- Inferred from existing codebase -->

- ✓ Docker Compose stack defined (Synapse + Postgres + Nginx + Element + Certbot) — existing
- ✓ Synapse homeserver config with invite-only registration, rate limiting, federation off — existing
- ✓ Element Web white-label config (custom brand, theme, default homeserver) — existing
- ✓ Nginx reverse proxy config with security headers and virtual hosts — existing
- ✓ .well-known Matrix discovery files — existing
- ✓ Admin bootstrap script — existing
- ✓ Default room/space creation script (Python/matrix-nio) — existing
- ✓ Encrypted backup/restore scripts — existing
- ✓ Ops runbook, security docs, migration guide — existing

### Active

<!-- Current scope: deploy to AWS and prove it works -->

- [ ] AWS EC2 instance provisioned via AWS CLI
- [ ] Security group configured (SSH, HTTP, HTTPS, federation port)
- [ ] Docker + Compose installed on EC2 instance
- [ ] Compose stack deployed and running on EC2
- [ ] Element Web accessible via EC2 public hostname (no TLS for POC)
- [ ] Synapse API accessible via EC2 public hostname
- [ ] Admin user created and can log in
- [ ] Default rooms/spaces created and joinable
- [ ] Two users can exchange messages with E2EE
- [ ] Nginx config adapted for no-TLS / EC2 hostname operation
- [ ] Automated backup to S3 configured

### Out of Scope

- Custom domain + TLS — deferred to production phase (domain will be mapped later)
- Federation — off for POC; decision documented below for project owner
- VoIP/coturn — not needed for chat-only POC
- Discord bridge — ToS risk; roadmap item only
- SSO/OIDC — future phase
- Synapse workers / horizontal scaling — future phase for 50K users
- Mobile app customization — Element mobile works as-is with server URL

## Context

**Background:** Discord's "teen-by-default" age verification policy triggered community migration toward privacy-respecting, self-hosted platforms. Matrix/Element is the primary beneficiary. This POC validates the technical stack before committing to full production deployment.

**Existing codebase:** Complete Docker Compose stack with configs, scripts, and documentation already exists in this repo. The work is adapting it for AWS deployment via CLI and running without TLS/custom domain for the POC.

**Scale trajectory:** POC starts on a single t3.medium EC2 instance. Production target is 50K+ users, which will require Synapse workers, RDS or dedicated Postgres, S3 media backend, and likely an ALB.

**AWS CLI:** Already installed on the development machine. All AWS provisioning should use CLI commands, not the console.

## Constraints

- **Platform**: AWS (us-east-1), provisioned via AWS CLI only
- **No TLS**: EC2 public hostname for POC; no custom domain yet
- **Budget**: Minimal — single t3.medium instance (~$30/month)
- **Timeline**: POC, not production — speed over perfection
- **Existing code**: Must adapt existing configs, not rewrite from scratch

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| AWS over bare metal VPS | Client requirement; scales better long-term for 50K users | — Pending |
| EC2 public hostname (no custom domain) | POC speed; custom domain mapped later | — Pending |
| No TLS for POC | Let's Encrypt can't issue certs for amazonaws.com; self-signed adds complexity | — Pending |
| Federation OFF | Reduces attack surface, simpler moderation, suits private community model. **Pros of ON:** users can chat across Matrix servers, join public rooms, wider network. **Cons of ON:** increased abuse surface, metadata exposure to federated servers, moderation complexity. Recommendation: enable later with whitelist once moderation tools are in place. | — Pending |
| t3.medium instance | 2 vCPU / 4GB RAM sufficient for POC; reserved instance available at ~$18/mo for production | — Pending |
| Invite-only registration | Abuse prevention; matches private community model | — Pending |
| E2EE enabled by default | Core privacy value proposition; server cannot read messages | — Pending |

---
*Last updated: 2026-02-20 after initialization*
