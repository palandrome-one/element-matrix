---
phase: 02-stack-configuration
verified: 2026-02-20T04:30:00Z
status: passed
score: 4/4 success criteria verified
re_verification: false
human_verification:
  - test: "Start the stack after Phase 3 hostname substitution and confirm Nginx serves Element at http://<EC2-hostname>"
    expected: "Browser loads Element Web login page at the EC2 public hostname URL"
    why_human: "Cannot confirm Nginx config is syntactically valid without running nginx -t or starting the container; functional routing to Element and Synapse requires a live stack"
  - test: "Attempt to register a user without a token and confirm registration is rejected"
    expected: "Registration fails with a token-required error, not an open signup"
    why_human: "registration_requires_token: true is present in config but actual enforcement requires Synapse to be running and processing requests"
---

# Phase 2: Stack Configuration Verification Report

**Phase Goal:** The existing Docker Compose stack configs are adapted so the stack can be deployed and run correctly over HTTP on the EC2 public hostname
**Verified:** 2026-02-20T04:30:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Nginx config has a single HTTP :80 server block with no TLS directives | VERIFIED | `element.conf` has exactly 2 `listen.*80` directives; grep for `443\|8448\|ssl_certificate\|return 301 https\|Strict-Transport-Security\|tls-params` returns zero matches across both `element.conf` and `nginx.conf` |
| 2 | No `return 301 https://` redirect exists in any server block | VERIFIED | Zero matches for `return 301 https` or `return.*https` in `proxy/conf.d/element.conf` |
| 3 | No HSTS header is sent (security-headers.conf not included) | VERIFIED | Zero matches for `HSTS`, `Strict-Transport-Security`, or `security-headers` in `element.conf`; `nginx.conf` has no TLS params include |
| 4 | Synapse `proxy_pass` has no trailing slash (`http://synapse:8008;` exactly) | VERIFIED | Exact match: `proxy_pass http://synapse:8008;` present; the `/health` sub-location has an explicit path which is correct and distinct |
| 5 | Certbot service removed from docker-compose.yml | VERIFIED | `grep -c "certbot" compose/docker-compose.yml` returns 0 |
| 6 | Only port 80 exposed by nginx in docker-compose.yml | VERIFIED | `"80:80"` present; grep for `443\|8448` returns 0 |
| 7 | homeserver.yaml server_name set to placeholder value | VERIFIED | `server_name: "__EC2_HOSTNAME__"` confirmed |
| 8 | homeserver.yaml public_baseurl uses http:// protocol | VERIFIED | `public_baseurl: "http://__EC2_HOSTNAME__/"` confirmed |
| 9 | enable_registration: true present | VERIFIED | `enable_registration: true` on active (non-commented) line |
| 10 | registration_requires_token: true present | VERIFIED | `registration_requires_token: true` on active (non-commented) line |
| 11 | Email block disabled (commented out) | VERIFIED | `grep '^email:' homeserver.yaml` returns 0; block is preceded by `# email:` comment |
| 12 | Element config.json base_url uses http:// with placeholder | VERIFIED | `default_server_config.m.homeserver.base_url = "http://__EC2_HOSTNAME__"` confirmed via Python JSON parse |
| 13 | Element config.json server_name matches homeserver.yaml server_name | VERIFIED | Both set to `__EC2_HOSTNAME__` |
| 14 | well-known files reference POC hostname with http:// | VERIFIED | `well-known/matrix/client` base_url = `http://__EC2_HOSTNAME__`; `well-known/matrix/server` m.server = `__EC2_HOSTNAME__:80` |
| 15 | All changes committed to git | VERIFIED | `git diff HEAD` shows no uncommitted changes for any of the 7 modified files; 4 feat commits verified: `71ae249`, `63944d5`, `cb29d0b`, `0aad5f5` |

**Score:** 15/15 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `proxy/conf.d/element.conf` | Single HTTP :80 server block with path-based routing | VERIFIED | 43 lines; single server block; listen 80 (IPv4+IPv6); `server_name _`; locations for `/_matrix`, `/health`, `/.well-known/matrix/`, `/` |
| `proxy/nginx.conf` | Base Nginx config without TLS params include | VERIFIED | 37 lines; no `include.*tls-params`; `server_tokens off` preserved; all other base config intact |
| `compose/docker-compose.yml` | No certbot service, no 443/8448 ports, only port 80 | VERIFIED | 91 lines; 4 services (postgres, synapse, element, nginx); `"80:80"` only; no certbot anywhere; volumes: postgres_data, synapse_data, synapse_media only |
| `synapse/homeserver.yaml` | HTTP POC config with registration enabled | VERIFIED | `server_name: "__EC2_HOSTNAME__"`, `public_baseurl: "http://__EC2_HOSTNAME__/"`, `enable_registration: true`, `registration_requires_token: true`, email block commented out |
| `element/config.json` | Element Web config pointing to HTTP homeserver | VERIFIED | Valid JSON; `base_url: "http://__EC2_HOSTNAME__"`, `server_name: "__EC2_HOSTNAME__"`, `permalink_prefix: "http://__EC2_HOSTNAME__"`, `terms_and_conditions_links: []`, no `https://` anywhere |
| `well-known/matrix/client` | Matrix client discovery with HTTP base_url | VERIFIED | `m.homeserver.base_url: "http://__EC2_HOSTNAME__"` |
| `well-known/matrix/server` | Matrix server discovery with POC hostname | VERIFIED | `m.server: "__EC2_HOSTNAME__:80"` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `proxy/conf.d/element.conf` | `synapse:8008` | `proxy_pass` directive | VERIFIED | Exact match: `proxy_pass http://synapse:8008;` — no trailing slash |
| `proxy/conf.d/element.conf` | `element:80` | `proxy_pass` directive | VERIFIED | Exact match: `proxy_pass http://element:80;` in catch-all location |
| `compose/docker-compose.yml` | `proxy/conf.d/element.conf` | nginx volume mount | VERIFIED | `../proxy/conf.d:/etc/nginx/conf.d:ro` present |
| `element/config.json` | `synapse/homeserver.yaml` | `base_url` matches `public_baseurl` host | VERIFIED | Both use `__EC2_HOSTNAME__` as the hostname token |
| `element/config.json` | `synapse/homeserver.yaml` | `server_name` must match | VERIFIED | Both set to `"__EC2_HOSTNAME__"` exactly |
| `well-known/matrix/client` | `synapse/homeserver.yaml` | `base_url` matches `public_baseurl` | VERIFIED | Both use `http://__EC2_HOSTNAME__` |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| STACK-01 | 02-01-PLAN.md | Nginx config replaced with HTTP-only server block (no TLS, no HSTS, path-based routing) | SATISFIED | `element.conf` is a single HTTP :80 block; no TLS directives in any proxy file; docker-compose.yml has no certbot and only port 80 |
| STACK-02 | 02-02-PLAN.md | Synapse `public_baseurl` set to `http://<EC2-public-hostname>` | SATISFIED | `public_baseurl: "http://__EC2_HOSTNAME__/"` — placeholder to be substituted at Phase 3 deploy time per documented approach |
| STACK-03 | 02-02-PLAN.md | Synapse `server_name` set to a deliberate POC value (documented as non-migratable) | SATISFIED | `server_name: "__EC2_HOSTNAME__"` — placeholder for EC2 hostname; non-migratable nature documented in plan and summary |
| STACK-04 | 02-02-PLAN.md | Element `config.json` updated with HTTP base_url matching EC2 hostname | SATISFIED | `base_url: "http://__EC2_HOSTNAME__"` in `default_server_config.m.homeserver`; no `https://` remaining |
| STACK-05 | 02-02-PLAN.md | `enable_registration: true` with `registration_requires_token: true` (both required for invite flow) | SATISFIED | Both keys present as active (non-commented) YAML on separate lines |

**Orphaned requirements check:** STACK-06 maps to Phase 3 per REQUIREMENTS.md traceability table — correctly absent from Phase 2 plans.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | — | — | — | — |

No TODO/FIXME/PLACEHOLDER/stub patterns found in any modified file. No empty implementations. No orphaned artifacts.

**Note on `__EC2_HOSTNAME__` placeholder:** This is not an anti-pattern. The PLAN, SUMMARY, and ROADMAP all explicitly document this as the correct two-phase approach: configs use the placeholder in Phase 2, Phase 3 substitutes the actual EC2 hostname via `sed`/`envsubst` before `docker compose up`. The placeholder is consistent and correct across all 7 config files.

**Note on `https://` in homeserver.yaml header comment:** Line 2 contains `# Docs: https://element-hq.github.io/...` — this is a documentation URL in a comment, not a configuration value. It does not affect Synapse behavior.

### Human Verification Required

#### 1. Nginx Config Syntax

**Test:** On the EC2 instance after SCP transfer, run `docker compose run --rm nginx nginx -t`
**Expected:** `nginx: configuration file /etc/nginx/nginx.conf test is successful`
**Why human:** Nginx config syntax validation requires the nginx binary to parse the files; cannot be verified by grep alone

#### 2. Stack Starts HTTP-Only

**Test:** After Phase 3 hostname substitution, run `docker compose up -d` and check `curl -I http://<EC2-hostname>/`
**Expected:** HTTP 200 response serving Element Web; no redirect to HTTPS
**Why human:** Functional routing to Element and Synapse requires a live stack; container networking is not verifiable statically

#### 3. Invite-Only Registration Enforced

**Test:** Attempt to register via Element Web without a registration token
**Expected:** Registration fails with a token-required error; no open signup is possible
**Why human:** `registration_requires_token: true` enforcement requires Synapse to be running

### Success Criteria Assessment

| # | Success Criterion | Status | Evidence |
|---|-------------------|--------|----------|
| 1 | Nginx config: single HTTP :80 block, no TLS, no `return 301 https://`, no HSTS, no trailing slash on Synapse `proxy_pass` | PASSED | All 5 sub-conditions verified by grep; zero false positives |
| 2 | homeserver.yaml: `public_baseurl` and `server_name` set to EC2 hostname value, `enable_registration: true` and `registration_requires_token: true` both present | PASSED | All 4 values confirmed; placeholder `__EC2_HOSTNAME__` is the "chosen value" pending Phase 3 substitution |
| 3 | Element `config.json`: `base_url` set to same `http://<EC2-hostname>` value | PASSED | `http://__EC2_HOSTNAME__` matches homeserver.yaml `public_baseurl` host |
| 4 | All config changes committed to repo and ready to transfer to EC2 via SCP | PASSED | `git diff HEAD` shows zero uncommitted changes; 4 feat commits verified in git log |

**Final Score: 4/4 success criteria passed.**

### Gaps Summary

No gaps found. All success criteria are satisfied. All requirement IDs (STACK-01 through STACK-05) are covered by the two plans and verified in the codebase.

The phase goal — adapting the Docker Compose stack configs for HTTP-only EC2 deployment — is fully achieved. The `__EC2_HOSTNAME__` placeholder strategy is correct and intentional: the actual EC2 public hostname is not known at config-commit time and is injected at Phase 3 deploy time, which is the documented and planned approach.

---

_Verified: 2026-02-20T04:30:00Z_
_Verifier: Claude (gsd-verifier)_
