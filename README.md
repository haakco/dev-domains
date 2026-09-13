# dev-domains

Centralized hostname-aware DNS domain resolver for HaakCo dev stacks.

> **Status:** v0.1.4 — pin a specific version in your consumer repo.

## What it does

`dev-domains` is the single source of truth for the office/dev-server host
list and the hostname-aware DNS domain derivation that every HaakCo app
uses (TrackLab, CouriB, TiaoTiao, future apps).

Each app declares only its `BASE_DOMAIN` (and optional `SITE_DOMAIN`),
sources this module, and calls `dev_domains::resolve`. The resolver then
auto-detects the current shell hostname and sets every domain-derived
variable (`DNS_DOMAIN`, `TRAEFIK_DOMAIN`, `EMAIL_DOMAIN`, `API_APP_URL`,
`API_FRONTEND_URL`, `PRIMARY_DOMAIN`, `LOCAL_DOMAIN`, `CERT_DOMAINS`,
`TRAEFIK_HOST_REGEXP`).

### Variables

| Variable | Owner | Example (TrackLab) | Example (CouriB) |
|---|---|---|---|
| `BASE_DOMAIN` | per-app caller | `haakdev.com` | `courib.com` |
| `SITE_DOMAIN` | per-app, optional | unset | `site.courib.com` |
| `PRIMARY_SUBDOMAIN` | per-app, optional (defaults to `dev`) | unset | unset |
| `PRIMARY_DOMAIN` | this module, derived | `${PRIMARY_SUBDOMAIN:-dev}.${BASE_DOMAIN}` → `dev.haakdev.com` | `${PRIMARY_SUBDOMAIN:-dev}.${BASE_DOMAIN}` → `dev.courib.com` |
| `LOCAL_DOMAIN` | this module, derived | `dev.haakdev.com` | `dev.courib.com` |
| `DNS_DOMAIN` | this module, hostname-aware | `srvh01.haakdev.com` on `srvh01`; `dev.haakdev.com` elsewhere | `srvh01.courib.com` on `srvh01`; `dev.courib.com` elsewhere |
| `EMAIL_DOMAIN` | this module, derived | equals `DNS_DOMAIN` | equals `DNS_DOMAIN` |
| `TRAEFIK_DOMAIN` | this module, derived | `traefik.srvh01.haakdev.com` | `traefik.srvh01.courib.com` |
| `API_APP_URL` / `API_FRONTEND_URL` | this module, derived | `https://srvh01.haakdev.com` | `https://srvh01.courib.com` |
| `CERT_DOMAINS` | this module, derived | `${PRIMARY_DOMAIN}`, `*.${PRIMARY_DOMAIN}`, each `${KNOWN_SERVER_HOSTS[i]}.${BASE_DOMAIN}` and its wildcard | adds `*.${KNOWN_SERVER_HOSTS[i]}.${SITE_DOMAIN}` when `SITE_DOMAIN` is set |
| `TRAEFIK_HOST_REGEXP` | this module, derived | `^(dev\|wdev\|srvh01\|...\|dark)\.haakdev\.com$` | includes `site.courib.com` variants when `SITE_DOMAIN` is set |

`KNOWN_SERVER_HOSTS` is owned by this module — currently
`(dev wdev srvh01 srvh02 dark mini)`.

## Usage

```bash
# In your app's infra/<env script>:
export BASE_DOMAIN="${BASE_DOMAIN:-<your-app-base-domain>}"
# Optional: SITE_DOMAIN="${SITE_DOMAIN:-<your-app-site-domain>}"  # apps with a separate site
source /path/to/dev-domains.sh
dev_domains::resolve
# All variables above are now set in the calling shell. Export the ones
# your docker-compose / Traefik config consume.
export DNS_DOMAIN EMAIL_DOMAIN TRAEFIK_DOMAIN API_APP_URL API_FRONTEND_URL \
       PRIMARY_DOMAIN LOCAL_DOMAIN CERT_DOMAINS
```

The hostname detection rule:

```bash
SHORTHOST=$(hostname -s 2>/dev/null || echo unknown)
if printf '%s\n' "${KNOWN_SERVER_HOSTS[@]}" | grep -qx -- "${SHORTHOST}"; then
    DNS_DOMAIN="${SHORTHOST}.${BASE_DOMAIN}"
else
    DNS_DOMAIN="dev.${BASE_DOMAIN}"
fi
```

When `SITE_DOMAIN` is set, the generated Traefik `HostRegexp` and CORS
allowlist include both `<host>.${BASE_DOMAIN}` and `<host>.${SITE_DOMAIN}`
variants.

## Test helper

`BASE_DOMAIN=... bash dev-domains.sh dump-cert-domains` prints the sorted
`CERT_DOMAINS` list, one per line. Use this for byte-equality checks
against the regenerated dev cert SAN list.

## Consumer upgrade contract

`v0.1.4` adds `PRIMARY_SUBDOMAIN` (optional, defaults to `dev`) and `dev`
to `KNOWN_SERVER_HOSTS` so apps with a non-`dev` primary (e.g. TiaoTiao's
`tiao.haakdev.com`) keep routing `dev.haakdev.com` requests. Consumers
that don't use these features see no behavior change from `v0.1.0`.
that don't set it see no behavior change from `v0.1.0`. Consumers (TrackLab,
CouriB, TiaoTiao) should pin a specific tag. Breaking changes to
`dev_domains::resolve` output keys require a minor bump; new optional keys
are patch-level.

## Checkout (developer machine)

```bash
# Linux (or macOS where Dev lives under $HOME):
mkdir -p ~/Dev/HaakCo/AiProjects/sharedLib
cd ~/Dev/HaakCo/AiProjects/sharedLib
git clone git@github.com:haakco/dev-domains.git infra/dev-domains
cd infra/dev-domains && git checkout v0.1.0

# macOS with /Volumes/Dev mounted:
mkdir -p /Volumes/Dev/HaakCo/AiProjects/sharedLib
cd /Volumes/Dev/HaakCo/AiProjects/sharedLib
git clone git@github.com:haakco/dev-domains.git infra/dev-domains
cd infra/dev-domains && git checkout v0.1.0
```

Consumer scripts auto-detect either path; set `DEVDOMAINS_DIR` to
override.

To upgrade: bump the pin in each consumer's `infra/env-compose.sh` (and
any other source that references the version), checkout a newer tag in
the shared clone, and regenerate dev certs in each consumer.

## Consumers

| Repo | Status |
|---|---|
| `haakco/tlm` (TrackLab) | Wired (commit `30773b98`, `5cb29a9b`) |
| `haakco/cb` (CouriB) | Plan written (`2026-07-24_centralized_hostname_aware_dns_domain_design_plan.md`); implementation pending |
| `haakco/TiaoTiao` | Remediation plan written (`2026-07-24_centralized_dns_domain_remediation_plan.md`); implementation pending |

## Adding a new dev server

1. Add the hostname to `KNOWN_SERVER_HOSTS` in `dev-domains.sh`.
2. Regenerate dev certs in each consumer repo (`infra/dev-certs-gen/<cert script>`).
3. Add the new `<host>.<app-base-domain>` and wildcard DNS records
   pointing at the server's IP.

The cert SAN list update is automatic — every consumer reads
`CERT_DOMAINS` from the resolver.

## License

HaakCo internal. See `LICENSE`.