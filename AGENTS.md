# dev-domains — Agent Guide

See root [`README.md`](README.md) for the variable contract and usage.
This file is the operating guide for agents working on this repo.

## Module contract

The module exposes:

- `KNOWN_SERVER_HOSTS` — bash array, owned by this repo. Currently
  `(wdev srvh01 srvh02 srvh03 dark)`.
- `dev_domains::resolve` — function. Reads `BASE_DOMAIN` (required),
  `SITE_DOMAIN` (optional), and `PRIMARY_SUBDOMAIN` (optional, defaults
  to `dev`) from the caller; sets every other variable (`PRIMARY_DOMAIN`,
  `LOCAL_DOMAIN`, `DNS_DOMAIN`, `EMAIL_DOMAIN`, `TRAEFIK_DOMAIN`,
  `API_APP_URL`, `API_FRONTEND_URL`, `CERT_DOMAINS`, `TRAEFIK_HOST_REGEXP`).
  Idempotent. Apps whose canonical dev hostname is not `dev.<base>` (e.g.
  TiaoTiao sets `PRIMARY_SUBDOMAIN=tiao`) get a per-app `PRIMARY_DOMAIN`
  without the rest of the module caring which subdomain the caller picked.
- `dev_domains::cors_hosts` — function. Prints the comma-separated host
  list for use in `API_CORS_FRONTEND_URLS` style variables.
- `dump-cert-domains` — when the file is executed (not sourced) with
  `dump-cert-domains` as the first argument, prints the sorted
  `CERT_DOMAINS` for byte-equality checks.

## Adding a new host

1. Edit `KNOWN_SERVER_HOSTS` in `dev-domains.sh`.
2. Bump the minor version (e.g. `v0.1.0` → `v0.2.0`).
3. Tag the release: `git tag -a v0.2.0 -m 'add srvh04'`.
4. Notify consumers (`haakco/tlm`, `haakco/cb`, `haakco/TiaoTiao`) so
   they regenerate dev certs and update their pinned version.

## Testing

```bash
bash tests/cert_sanity.sh
```

Six cases plus the `PRIMARY_SUBDOMAIN` override:

1. TrackLab (single suffix): `BASE_DOMAIN=haakdev.com`, no `SITE_DOMAIN`.
2. CouriB (dual suffix): `BASE_DOMAIN=courib.com`,
   `SITE_DOMAIN=site.courib.com`.
3. `dump-cert-domains` exits 1 when `BASE_DOMAIN` is missing.
4. `dump-cert-domains` produces the same set as `dev_domains::resolve`.
5. `dev_domains::resolve` exits 1 when `BASE_DOMAIN` is missing.
6. `hostname=unknown` fallback (stubbed `hostname` returning 1) →
   `DNS_DOMAIN=PRIMARY_DOMAIN`.
7. `PRIMARY_SUBDOMAIN=tiao` overrides default and produces the matching
   `tiao.haakdev.com` cert SAN list and Traefik regex.

## Versioning

Pre-1.0. Pin a specific tag. Breaking changes to the `dev_domains::resolve`
output keys require a minor bump; new optional keys are patch-level.

## Style

- Pure bash. No external dependencies beyond `hostname` (from
  coreutils) and `printf` / `grep`.
- No subshells in tight loops. `IFS='|'` joined array expansion is
  used for `TRAEFIK_HOST_REGEXP` only.
- All exported variables should be re-exported by callers — the module
  sets variables in the calling shell but does not `export` them, so
  consumer infra scripts must `export` the values they need visible to
  `docker compose`.

## Local checkout

Source: `github.com/haakco/dev-domains`.

Other developers on other PCs check this out alongside the HaakCo
sharedLib workspace:

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

Consumer infra scripts that reference the module. The recommended
pattern is `DEVDOMAINS_DIR` auto-detection (TrackLab's `env-compose.sh`
and `genDevCerts.sh` show the exact pattern), but an explicit path also
works:

```bash
# Recommended — auto-detect:
source "${DEVDOMAINS_DIR}/dev-domains.sh"

# Explicit (Linux):
source "${HOME}/Dev/HaakCo/AiProjects/sharedLib/infra/dev-domains/dev-domains.sh"

# Explicit (macOS with /Volumes/Dev mounted):
source "/Volumes/Dev/HaakCo/AiProjects/sharedLib/infra/dev-domains/dev-domains.sh"

# Or via a relative path inside the consumer repo, e.g.:
source "${REPO_ROOT}/shared/dev-domains.sh"
```

(Consumer repos that vendor the module into their own tree should
update the source path accordingly.)
