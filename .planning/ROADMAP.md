# Roadmap: Matrix Element White-Label POC

## Overview

Three sequential phases deliver a working Matrix/Element deployment on AWS EC2. Phase 1 provisions the infrastructure substrate (nothing can run without it). Phase 2 adapts the existing TLS-built config for HTTP-only EC2 operation (the stack cannot be deployed unmodified). Phase 3 deploys incrementally and validates the POC from admin login through E2EE messaging. Each phase validates a layer before the next is added — shortcutting this order is the primary source of hard-to-debug failures.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: AWS Infrastructure** - Provision EC2 instance with Docker, security group, SSH access confirmed — DONE 2026-02-20
- [x] **Phase 2: Stack Configuration** - Adapt existing TLS-built configs for HTTP-only EC2 operation — DONE 2026-02-20
- [ ] **Phase 3: Deploy and Validate** - Deploy stack incrementally and verify E2EE messaging works end-to-end

## Phase Details

### Phase 1: AWS Infrastructure
**Goal**: A reachable EC2 instance with Docker installed is ready to receive the Compose stack
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04, INFRA-05
**Success Criteria** (what must be TRUE):
  1. EC2 instance is running and SSH access works from the admin machine using the created key pair
  2. `docker compose version` returns a v2 version string on the EC2 instance
  3. Security group allows port 80 from anywhere and port 22 from admin IP only — `curl http://<EC2-hostname>` gets a connection (even if no app is running) and port 8008 is not reachable externally
  4. EBS gp3 root volume of 30 GB or more is attached and mounted
**Plans**: 2 plans
- [x] 01-01-PLAN.md — Provision EC2 instance (key pair, security group, launch with Docker user-data) — DONE 2026-02-20
- [x] 01-02-PLAN.md — Verify SSH, Docker Compose, disk, and security group rules — DONE 2026-02-20

### Phase 2: Stack Configuration
**Goal**: The existing Docker Compose stack configs are adapted so the stack can be deployed and run correctly over HTTP on the EC2 public hostname
**Depends on**: Phase 1
**Requirements**: STACK-01, STACK-02, STACK-03, STACK-04, STACK-05
**Success Criteria** (what must be TRUE):
  1. Nginx config contains a single HTTP `:80` server block with no TLS directives, no `return 301 https://`, no HSTS header, and no trailing slash on the Synapse `proxy_pass`
  2. `homeserver.yaml` has `public_baseurl` and `server_name` set to the chosen EC2 hostname value, with `enable_registration: true` and `registration_requires_token: true` both present
  3. Element `config.json` has `base_url` set to the same `http://<EC2-hostname>` value
  4. All config changes are committed to the repo and ready to transfer to EC2 via SCP
**Plans**: 2 plans
- [x] 02-01-PLAN.md — Replace Nginx and Docker Compose with HTTP-only config, remove certbot — DONE 2026-02-20
- [x] 02-02-PLAN.md — Update Synapse, Element, and well-known configs for EC2 HTTP hostname — DONE 2026-02-20

### Phase 3: Deploy and Validate
**Goal**: The full Matrix/Element stack is running on EC2 and a human can register, log in, and exchange E2EE messages
**Depends on**: Phase 2
**Requirements**: STACK-06, VERIFY-01, VERIFY-02, VERIFY-03, VERIFY-04
**Success Criteria** (what must be TRUE):
  1. All Compose services (postgres, synapse, nginx, element) show healthy status in `docker compose ps`
  2. Admin user can log in at `http://<EC2-hostname>` using credentials from the bootstrap script
  3. Default Space and rooms are visible in the Element sidebar after admin login
  4. Two separate user accounts can exchange a message in a room and the E2EE lock icon is visible on messages
  5. Element Web loads with the custom brand name, logo, and theme colors applied
**Plans**: 3 plans
- [ ] 03-01-PLAN.md — Transfer repo to EC2, substitute placeholders, fill .env, generate signing key, start stack
- [ ] 03-02-PLAN.md — Bootstrap admin user, create default rooms, generate registration token, verify branding
- [ ] 03-03-PLAN.md — Human end-to-end verification (login, rooms, E2EE messaging, branding)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. AWS Infrastructure | 2/2 | Complete | 2026-02-20 |
| 2. Stack Configuration | 2/2 | Complete    | 2026-02-20 |
| 3. Deploy and Validate | 0/3 | Not started | - |
