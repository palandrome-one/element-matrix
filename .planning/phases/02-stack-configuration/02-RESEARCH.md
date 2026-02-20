# Phase 2: Stack Configuration - Research

**Researched:** 2026-02-20
**Domain:** Nginx HTTP-only reverse proxy, Synapse homeserver.yaml, Element Web config.json, Docker Compose service graph
**Confidence:** HIGH

---

## Summary

Phase 2 is a config-editing phase, not a software-installation phase. The EC2 instance (from Phase 1) is running and has Docker Compose v2. The goal is to edit three config files in the existing repo so the stack works over plain HTTP on a single EC2 public hostname, then commit those edits so they can be transferred to the EC2 instance via SCP.

The existing repo is built for a TLS/subdomain production deployment (chat.example.com, matrix.example.com, certbot, HSTS, 443/8448 listeners). Every single one of those production assumptions must be stripped away for the POC. The changes are surgical but must be complete: a single missed `https://` reference or a `return 301 https://` or an HSTS header will cause silent or confusing failures.

The most consequential decision in this phase is `server_name`. It is baked permanently into every Matrix user ID (`@user:server_name`) and cannot be changed without dropping the database and starting over. The EC2 public hostname (e.g., `ec2-1-2-3-4.compute-1.amazonaws.com`) is a valid but non-migratable choice for a POC — acceptable because Phase 2 is explicitly a throwaway POC that will be superseded by a production deployment with a custom domain. This must be documented so future operators know the constraint.

**Primary recommendation:** Make the four targeted config edits (Nginx, homeserver.yaml, config.json, docker-compose.yml), strip all TLS/HSTS/certbot references, commit, and verify the commit is clean before SCP transfer to EC2.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| STACK-01 | Nginx config replaced with HTTP-only server block (no TLS, no HSTS, path-based routing) | Synapse reverse_proxy.md confirms the exact location regex and no-trailing-slash rule; HTTP port 80 server block is standard Nginx |
| STACK-02 | Synapse `public_baseurl` set to `http://<EC2-public-hostname>` | Synapse config docs confirm `public_baseurl` format; HTTP is technically valid; `x_forwarded: true` listener already set |
| STACK-03 | Synapse `server_name` set to a deliberate POC value (documented as non-migratable) | Official docs explicitly warn this cannot change post-first-run; EC2 hostname is valid syntax |
| STACK-04 | Element `config.json` updated with HTTP base_url matching EC2 hostname | Element Web docs confirm `default_server_config.m.homeserver.base_url` is the correct field; HTTP URL works when page is also served over HTTP (no mixed content) |
| STACK-05 | `enable_registration: true` with `registration_requires_token: true` (both required for invite flow) | Both flags documented in Synapse config; registration tokens introduced in Synapse 1.42.0 (stable since Matrix v1.2); existing homeserver.yaml already has `registration_requires_token: true` but `enable_registration: false` |
</phase_requirements>

---

## Current State of the Repo (Audit)

This section documents exactly what exists and what must change. The planner needs this to write precise tasks.

### proxy/nginx.conf

- Includes `proxy/snippets/tls-params.conf` globally — this file sets `ssl_protocols`, `ssl_ciphers`, OCSP stapling, and resolver. **Must remove the `include` line** since there are no TLS listeners in the POC.
- Otherwise fine: gzip, logging, mime types, `server_tokens off` can all stay.

### proxy/snippets/tls-params.conf

- Contains `ssl_protocols`, `ssl_ciphers`, `ssl_session_*`, OCSP config. Safe to leave the file on disk but the `include` in nginx.conf must be removed (Nginx will fail to start if ssl directives are present in `http {}` without any SSL listener context on some versions; removing the include is the safe path).

### proxy/snippets/security-headers.conf

- Contains `Strict-Transport-Security` (HSTS). **Must not be included in the HTTP-only server block.** Either remove the include or remove the HSTS line. Safest: do not include this file at all in the POC server block. Other headers (`X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`) are harmless over HTTP and can be kept if desired, but HSTS must go.

### proxy/conf.d/element.conf

- Current config has: HTTP→HTTPS redirect block, Element HTTPS block (443), Synapse HTTPS block (443), Federation HTTPS block (8448), well-known HTTPS block (443). **Entire file must be replaced** with a single HTTP `:80` server block.
- Existing Synapse `proxy_pass` is `http://synapse:8008;` with no trailing slash — **this is correct per official Synapse docs** ("do not add a path, even a single /, after the port in proxy_pass, otherwise nginx will canonicalise the URI and cause signature verification errors").
- The Element `proxy_pass` is `http://element:80;` — this has no trailing slash, also correct.

### compose/docker-compose.yml

- Nginx ports: currently `"80:80"`, `"443:443"`, `"8448:8448"`. For POC: only `"80:80"` needed. Remove 443 and 8448.
- Certbot service: entire service block should be removed (or commented). It runs `certbot renew` in a loop — pointless and noisy with no certs.
- Certbot volumes: `certbot_conf` and `certbot_webroot` are mounted into nginx. Once certbot service is removed and element.conf no longer references `/etc/letsencrypt`, these volume mounts in the nginx service can be removed too.
- Everything else (postgres, synapse, element, internal/external networks) stays unchanged.

### synapse/homeserver.yaml

- `server_name: "example.com"` → must be set to the actual EC2 hostname (e.g., `ec2-1-2-3-4.compute-1.amazonaws.com`)
- `public_baseurl: "https://matrix.example.com/"` → must become `http://<EC2-hostname>/` (no trailing path segments required, trailing slash is conventional)
- `web_client_location: "https://chat.example.com/"` → must become `http://<EC2-hostname>/` or can be removed (it's optional; sets the "Web client" link in Synapse's fallback page)
- `enable_registration: false` → must become `enable_registration: true`
- `registration_requires_token: true` → already correct, no change needed
- Email section (`smtp_host`, `smtp_user`, etc.) has `__PLACEHOLDER__` values — Synapse will fail to start if it tries to send email and these are unset, but since email notifications are `enable_notifs: true` by default, this could cause startup errors. **Must either disable email or set dummy values.** Safest for POC: set `enable_notifs: false` or comment out the entire email block.
- The `__POSTGRES_PASSWORD__`, `__REGISTRATION_SHARED_SECRET__`, `__MACAROON_SECRET_KEY__`, `__FORM_SECRET__` placeholders still need to be replaced. These are not part of Phase 2's scope per requirements, but the planner must note that `homeserver.yaml` cannot be used as-is without them. Phase 2 requirement scope says only the four named fields; placeholder substitution may be a separate plan or a dependency to note.

### element/config.json

- `default_server_config.m.homeserver.base_url: "https://matrix.example.com"` → must become `"http://<EC2-hostname>"`
- `default_server_config.m.homeserver.server_name: "example.com"` → must become the POC `server_name` value
- `permalink_prefix: "https://chat.example.com"` → must become `"http://<EC2-hostname>"`
- `terms_and_conditions_links` and `embedded_pages` reference `https://example.com/...` — these point to nonexistent pages; safest to empty them out for POC to avoid broken links in UI
- `disable_custom_urls: true` is fine to keep (forces users to use the configured homeserver)

### well-known/matrix/client and server

- These are served via Nginx in production. In the POC, because both Element Web and Synapse live at the same hostname, `.well-known` discovery is not strictly necessary for operation (Element is configured directly via config.json). However, if they remain they should reference the EC2 hostname with `http://`. Not a blocking requirement for Phase 2 but worth noting.

---

## Architecture Patterns

### Pattern 1: Single-Host HTTP Nginx — Path-Based Routing

**What:** One `server { listen 80; }` block routes all traffic by path prefix. Root and non-Matrix paths go to Element Web container; `/_matrix` and `/_synapse/client` go to Synapse container.

**Official source:** Synapse reverse_proxy.md confirms the location regex pattern and the no-trailing-slash rule on `proxy_pass`.

**Key rule:** `proxy_pass http://synapse:8008;` — no trailing slash, no path. If you write `proxy_pass http://synapse:8008/;`, Nginx will rewrite/canonicalize the URI and break Matrix signature verification.

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name <EC2-hostname>;

    # Matrix API — route to Synapse (no trailing slash on proxy_pass!)
    location ~ ^(/_matrix|/_synapse/client) {
        proxy_pass http://synapse:8008;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        client_max_body_size 50m;
    }

    # Health check
    location /health {
        proxy_pass http://synapse:8008/health;
    }

    # .well-known for Matrix discovery (optional but good practice)
    location /.well-known/matrix/ {
        alias /var/www/well-known/matrix/;
        default_type application/json;
        add_header Access-Control-Allow-Origin "*" always;
    }

    # Element Web — catch-all
    location / {
        proxy_pass http://element:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Note:** `X-Forwarded-Proto: http` will be set correctly for all requests. Synapse's `x_forwarded: true` listener config causes Synapse to trust this header and use it in generated URLs (including the `public_baseurl`). This pairing is required.

### Pattern 2: Synapse Listener Configuration (Already Correct)

The existing `homeserver.yaml` listener is already correct for behind-proxy use:

```yaml
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ["0.0.0.0"]
    resources:
      - names: [client, federation]
        compress: false
```

`tls: false` — Synapse itself does not terminate TLS (Nginx does).
`x_forwarded: true` — Synapse trusts `X-Forwarded-For` and `X-Forwarded-Proto` headers from the proxy.
This block does not need to change.

### Pattern 3: Registration Token Flow (No Change to Flow Logic)

`enable_registration: true` — opens the registration endpoint.
`registration_requires_token: true` — registration endpoint requires a valid token.

Without a token, the registration API returns an error. This is the correct invite-only flow: admin creates tokens via admin API, shares them with invited users.

Token management API: `POST /_synapse/admin/v1/registration_tokens/new` (requires admin access token).

This configuration is: users cannot self-register without a token, but the endpoint is open and ready. This is the correct POC state.

### Pattern 4: Mixed Content — Why HTTP-to-HTTP Works

The "mixed content" browser restriction applies when an HTTPS page attempts to load HTTP resources. When both Element Web and Synapse are served over HTTP (as in this POC), there is no mixed content — all requests are HTTP-to-HTTP. This is a deliberate, documented POC constraint, not a misconfiguration.

**Consequence:** The POC is accessible only over HTTP on EC2 hostname. If someone attempts to access via HTTPS, it will fail (no 443 listener). This is expected and acceptable for the POC.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Registration token management | Custom auth wrapper | Synapse built-in `registration_requires_token` + admin API | Token CRUD, expiry, use limits are all built into Synapse 1.42+ |
| TLS stripping at proxy | Custom script to remove SSL | Edit nginx.conf and element.conf directly | Config is declarative; no stripping logic needed |
| Domain substitution | Bash `sed` pipeline across all files | Manual targeted edits per file | Only 4 specific values need changing; `sed` across files risks hitting the wrong substitution |

---

## Common Pitfalls

### Pitfall 1: Trailing Slash on Synapse proxy_pass

**What goes wrong:** `proxy_pass http://synapse:8008/;` causes Nginx to canonicalize the URI. Requests to `/_matrix/client/v3/login` get rewritten, breaking Matrix signature verification. Auth flows fail with cryptic 401 or 403 errors.

**Why it happens:** Nginx treats `proxy_pass` with a trailing path component as a URI rewrite instruction.

**How to avoid:** Always write `proxy_pass http://synapse:8008;` — no trailing slash, no path.

**Source:** Explicitly documented in official Synapse `reverse_proxy.md`: "do not add a path (even a single /) after the port in proxy_pass."

### Pitfall 2: HSTS Header Over HTTP

**What goes wrong:** If `security-headers.conf` is included in the HTTP server block, the `Strict-Transport-Security` header is sent over HTTP. Browsers that receive HSTS over HTTP ignore it per spec, but the header is noise. More dangerously, if a browser ever hits the host over HTTPS (even once), HSTS will cause it to refuse HTTP connections permanently until the max-age expires.

**How to avoid:** Do not include `security-headers.conf` in the HTTP-only POC server block. Either delete the include or remove the HSTS line specifically.

### Pitfall 3: TLS Directives in http{} Context Without SSL Listener

**What goes wrong:** `nginx.conf` currently includes `snippets/tls-params.conf` at the `http {}` level. This sets `ssl_protocols`, `ssl_session_cache`, OCSP stapling, and a resolver. On some Nginx versions, these directives in the global `http {}` context with no `ssl` listener present cause Nginx to emit warnings or fail to start.

**How to avoid:** Remove the `include /etc/nginx/snippets/tls-params.conf;` line from `nginx.conf` for the POC.

### Pitfall 4: server_name Finalized on First `docker compose up`

**What goes wrong:** Synapse writes `server_name` into the SQLite/Postgres database on first startup. If a placeholder `example.com` is accidentally left in `homeserver.yaml` when the stack first starts on EC2, all user IDs become `@user:example.com`. Changing `server_name` later requires dropping and recreating the database.

**How to avoid:** Verify `server_name` in `homeserver.yaml` is correct **before** the first `docker compose up` on EC2. This is a one-shot setting.

**Warning sign:** If `synapse generate` was previously run with a wrong `server_name`, the generated signing key file contains the old name. The key and the config must match. Use `docker compose run --rm synapse generate` fresh on EC2 with the correct name in the config.

### Pitfall 5: Certbot Volumes Still Mounted in Nginx

**What goes wrong:** If the nginx service still mounts `certbot_conf:/etc/letsencrypt:ro`, Docker will create an empty volume for it. If `element.conf` contains SSL certificate path references, Nginx will fail to start because the cert files do not exist.

**How to avoid:** Remove certbot volume mounts from the nginx service AND remove all `ssl_certificate`/`ssl_certificate_key` directives from the new element.conf. Also remove or comment the certbot service itself.

### Pitfall 6: Synapse Email Placeholders Causing Startup Failure

**What goes wrong:** `homeserver.yaml` has `enable_notifs: true` under the email block, but `smtp_host: "__SMTP_HOST__"`. If Synapse tries to resolve the SMTP host at startup or on first email trigger, it will log errors or crash.

**How to avoid:** For the POC, either disable the email section entirely (`email:` block commented out, or `enable_notifs: false`) or set dummy but syntactically valid SMTP values. The simplest fix: comment out the entire `email:` block. Email notifications are not required for POC validation.

### Pitfall 7: public_baseurl Trailing Slash

**What goes wrong:** Synapse documentation shows `public_baseurl: https://example.com/` with a trailing slash. While Synapse may handle both forms, the trailing slash is the documented convention and used in Synapse's internal URL construction.

**How to avoid:** Always set `public_baseurl: "http://<EC2-hostname>/"` with trailing slash.

### Pitfall 8: EC2 Public Hostname May Change on Reboot

**What goes wrong:** EC2 public hostnames (e.g., `ec2-1-2-3-4.compute-1.amazonaws.com`) change if the instance is stopped and started (not just rebooted). `server_name` is permanent in the database; if the hostname changes, `public_baseurl` can be updated but `server_name` cannot.

**How to avoid:** For the POC, this is an acceptable risk — the instance will not be stopped between provisioning and validation. Document this constraint clearly. Use the EC2 public hostname as-is for the POC `server_name`. In production, a custom domain (with Elastic IP or Route 53) must be used.

---

## Code Examples

### Synapse homeserver.yaml — Minimum Required Changes

```yaml
# Change from:
server_name: "example.com"
public_baseurl: "https://matrix.example.com/"
web_client_location: "https://chat.example.com/"
enable_registration: false

# Change to:
server_name: "ec2-1-2-3-4.compute-1.amazonaws.com"   # actual EC2 hostname
public_baseurl: "http://ec2-1-2-3-4.compute-1.amazonaws.com/"
web_client_location: "http://ec2-1-2-3-4.compute-1.amazonaws.com/"
enable_registration: true
# registration_requires_token: true  — already present, no change needed
```

And disable/comment the email block:
```yaml
# email:          # commented out for POC — no SMTP configured
#   smtp_host: ...
```

### Element config.json — Minimum Required Changes

```json
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "http://ec2-1-2-3-4.compute-1.amazonaws.com",
            "server_name": "ec2-1-2-3-4.compute-1.amazonaws.com"
        }
    },
    "permalink_prefix": "http://ec2-1-2-3-4.compute-1.amazonaws.com"
}
```

### docker-compose.yml — nginx service changes

```yaml
# Remove or comment:
#   - "443:443"
#   - "8448:8448"
# Keep:
ports:
  - "80:80"

# Remove certbot volume mounts from nginx service:
volumes:
  - ../proxy/nginx.conf:/etc/nginx/nginx.conf:ro
  - ../proxy/conf.d:/etc/nginx/conf.d:ro
  - ../proxy/snippets:/etc/nginx/snippets:ro
  - ../well-known:/var/www/well-known:ro
  # certbot_conf and certbot_webroot volumes removed

# Remove entire certbot service block
# Remove certbot_conf and certbot_webroot from volumes: section
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Separate domains per service (chat., matrix., etc.) | Single-host path-based routing for POC | N/A — both valid | Simplifies EC2 POC (no DNS records needed) |
| Registration tokens via plugin (matrix-registration) | Built-in `registration_requires_token` | Synapse 1.42.0 (2021), stable Matrix v1.2 | No extra service needed |
| Certbot HTTP-01 challenge via well-known path | Not applicable for POC (EC2 hostname) | N/A | EC2 public hostnames cannot receive Let's Encrypt certs |

**Deprecated/outdated:**
- `SYNAPSE_SERVER_NAME` env var as the primary way to set server_name: Still works for `synapse generate`, but `homeserver.yaml` `server_name:` is the authoritative runtime config. Do not rely on env var alone.

---

## Open Questions

1. **What is the actual EC2 hostname?**
   - What we know: Phase 1 is complete; SSH access confirmed; instance is running
   - What's unclear: The exact hostname value (e.g., `ec2-1-2-3-4.compute-1.amazonaws.com`) is stored in `scripts/aws/instance-info.env` which is gitignored
   - Recommendation: The planner should structure the plan so the operator retrieves the hostname from the EC2 instance (via `curl -s http://169.254.169.254/latest/meta-data/public-hostname` or from `instance-info.env` locally) and substitutes it into the three config files. The plan must treat the hostname as an operator-supplied value, not a hardcoded value.

2. **Should `server_name` be the full EC2 hostname or a shorter alias?**
   - What we know: `server_name` must be valid hostname syntax; underscores are rejected by Synapse; EC2 public hostnames are valid
   - What's unclear: State.md notes an unresolved concern: "EC2 public hostname is impermanent without Elastic IP; options: public IP with EIP, short placeholder like `poc.internal`"
   - Recommendation: For this POC (acknowledged non-migratable), use the actual EC2 public hostname. It's the most debuggable choice (URLs in Matrix rooms will be recognizable). A placeholder like `poc.internal` creates a different problem: `public_baseurl` must match `server_name`'s implied domain for client discovery. Using the actual hostname avoids that mismatch. Document the non-migratability.

3. **Do the `__POSTGRES_PASSWORD__` and other secret placeholders in homeserver.yaml need to be resolved in Phase 2?**
   - What we know: Phase 2 requirements only name STACK-01 through STACK-05; secret substitution is not listed
   - What's unclear: Whether the plan should include a task for secrets substitution as a prerequisite, or defer it to Phase 3 (STACK-06: `docker compose up -d` starts healthy)
   - Recommendation: Include secret substitution as a task in Phase 2 (or at minimum call it out as a dependency note). The config file cannot be used without it. The planner should include it — it's a natural part of "adapt configs so the stack can deploy."

4. **Should `well-known` files be updated in Phase 2?**
   - What we know: `well-known/matrix/client` and `well-known/matrix/server` still reference `https://matrix.example.com`
   - What's unclear: Whether `.well-known` discovery is exercised in Phase 2 validation (the success criteria don't mention it)
   - Recommendation: Update them in Phase 2 alongside the other config changes (they reference the same hostname and protocol). Costs one minute; avoids leaving stale references that might confuse debugging.

---

## Sources

### Primary (HIGH confidence)
- [Synapse reverse_proxy.md](https://github.com/matrix-org/synapse/blob/develop/docs/reverse_proxy.md) — Nginx config examples, proxy_pass no-trailing-slash warning, required headers
- [Synapse config_documentation.md](https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html) — `server_name`, `public_baseurl`, `enable_registration`, `registration_requires_token` definitions and warnings
- [Element Web config.md](https://github.com/element-hq/element-web/blob/develop/docs/config.md) — `default_server_config`, `base_url` format

### Secondary (MEDIUM confidence)
- [Synapse reverse_proxy.html (element-hq)](https://element-hq.github.io/synapse/latest/reverse_proxy.html) — Verified Nginx example block, no-trailing-slash rule confirmed
- [Registration Tokens — Synapse admin API](https://matrix-org.github.io/synapse/latest/usage/administration/admin_api/registration_tokens.html) — Token management API confirmed

### Tertiary (LOW confidence)
- Community Nginx + Synapse gists — general patterns consistent with official docs; not authoritative

---

## Metadata

**Confidence breakdown:**
- Standard stack (Nginx HTTP-only, Synapse, Element): HIGH — official docs consulted, existing working configs inspected
- Architecture (path-based routing, proxy_pass no-slash): HIGH — official Synapse docs explicitly document the rule
- Pitfalls (server_name permanence, trailing slash, HSTS over HTTP): HIGH — server_name permanence is official doc warning; others are Nginx/browser-spec facts
- Secret substitution dependency: MEDIUM — logical necessity, not explicitly in Phase 2 requirements list

**Research date:** 2026-02-20
**Valid until:** 2026-05-20 (stable tech; Nginx and Synapse config APIs are not fast-moving)
