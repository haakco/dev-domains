#!/usr/bin/env bash
# HaakCo dev-domain resolver.
#
# Single source of truth for the office/dev-server host list and the
# hostname-aware DNS domain derivation that every HaakCo app uses. Each
# app's `infra/<env script>` declares BASE_DOMAIN (and optional SITE_DOMAIN),
# sources this file, and calls `dev_domains::resolve`.
#
# Conventions:
#   BASE_DOMAIN   — required. e.g. "haakdev.com", "courib.com".
#   SITE_DOMAIN   — optional. e.g. "site.courib.com" for apps with a separate
#                   site alongside the API. Unset for TrackLab/TiaoTiao.
#   PRIMARY_DOMAIN — always "dev.${BASE_DOMAIN}". Always first in CERT_DOMAINS
#                    so certbot writes to /live/${PRIMARY_DOMAIN}.
#   LOCAL_DOMAIN  — equal to PRIMARY_DOMAIN.
#   DNS_DOMAIN    — "${SHORTHOST}.${BASE_DOMAIN}" when current hostname is
#                   in KNOWN_SERVER_HOSTS, else PRIMARY_DOMAIN.
#
# Test helper:
#   BASE_DOMAIN=... SITE_DOMAIN=... bash dev-domains.sh dump-cert-domains
# prints the sorted CERT_DOMAINS list, one per line.

# Single source of truth for the office/dev server list. Add a new host
# here only; cert regeneration in each app picks it up automatically.
KNOWN_SERVER_HOSTS=(wdev srvh01 srvh02 srvh03 dark)

# Resolve current shell hostname. "unknown" if hostname is unavailable.
dev_domains::_shorthost() {
    local host
    host=$(hostname -s 2>/dev/null || true)
    [[ -z "${host}" ]] && host=unknown
    printf '%s\n' "${host}"
}

# dev_domains::resolve
#
# Reads BASE_DOMAIN (required) and SITE_DOMAIN (optional) from the calling
# shell, then sets DNS_DOMAIN, PRIMARY_DOMAIN, LOCAL_DOMAIN, EMAIL_DOMAIN,
# TRAEFIK_DOMAIN, API_APP_URL, API_FRONTEND_URL, CERT_DOMAINS, and
# TRAEFIK_HOST_REGEX. Idempotent — safe to call multiple times.
dev_domains::resolve() {
    if [[ -z "${BASE_DOMAIN:-}" ]]; then
        printf 'dev_domains::resolve: BASE_DOMAIN is required\n' >&2
        return 1
    fi

    PRIMARY_DOMAIN="dev.${BASE_DOMAIN}"
    LOCAL_DOMAIN="${PRIMARY_DOMAIN}"

    local shorthost
    shorthost=$(dev_domains::_shorthost)
    local on_known=0
    local h
    for h in "${KNOWN_SERVER_HOSTS[@]}"; do
        if [[ "${h}" == "${shorthost}" ]]; then
            on_known=1
            break
        fi
    done
    if [[ "${on_known}" -eq 1 ]]; then
        DNS_DOMAIN="${shorthost}.${BASE_DOMAIN}"
    else
        DNS_DOMAIN="${PRIMARY_DOMAIN}"
    fi

    EMAIL_DOMAIN="${DNS_DOMAIN}"
    TRAEFIK_DOMAIN="traefik.${DNS_DOMAIN}"
    API_APP_URL="https://${DNS_DOMAIN}"
    API_FRONTEND_URL="https://${DNS_DOMAIN}"

    # CERT_DOMAINS: PRIMARY first, optional SITE primary, then each known
    # host pair. Wildcards preserve the original ordering (per-pair, not
    # sorted) so certbot's /live/${PRIMARY_DOMAIN} stays at index 0.
    CERT_DOMAINS=(
        "${PRIMARY_DOMAIN}"
        "*.${PRIMARY_DOMAIN}"
    )
    if [[ -n "${SITE_DOMAIN:-}" ]]; then
        CERT_DOMAINS+=(
            "dev.${SITE_DOMAIN}"
            "*.dev.${SITE_DOMAIN}"
        )
    fi
    for h in "${KNOWN_SERVER_HOSTS[@]}"; do
        CERT_DOMAINS+=(
            "${h}.${BASE_DOMAIN}"
            "*.${h}.${BASE_DOMAIN}"
        )
        if [[ -n "${SITE_DOMAIN:-}" ]]; then
            CERT_DOMAINS+=(
                "*.${h}.${SITE_DOMAIN}"
            )
        fi
    done

    # Traefik HostRegexp over the bare (non-wildcard) cert domains. TrackLab
    # uses just BASE_DOMAIN; CouriB also includes *.site.courib.com variants.
    local -a regex_parts=("${PRIMARY_DOMAIN}")
    if [[ -n "${SITE_DOMAIN:-}" ]]; then
        regex_parts+=("dev.${SITE_DOMAIN}")
    fi
    for h in "${KNOWN_SERVER_HOSTS[@]}"; do
        regex_parts+=("${h}.${BASE_DOMAIN}")
        if [[ -n "${SITE_DOMAIN:-}" ]]; then
            regex_parts+=("${h}.${SITE_DOMAIN}")
        fi
    done
    # Build an alternation: ^(a|b|c|...)$
    local IFS='|'
    TRAEFIK_HOST_REGEXP="^( ${regex_parts[*]} )\$"
    # Trim the literal spaces introduced by IFS='|'. They are required for
    # readability in the source but the regex must not contain them.
    TRAEFIK_HOST_REGEXP="${TRAEFIK_HOST_REGEXP// /}"
}

# dev_domains::cors_hosts
#
# Prints the comma-separated host list suitable for an `API_CORS_FRONTEND_URLS`
# style variable. Includes the resolved DNS_DOMAIN plus the primary dev host
# plus each known office/dev server.
dev_domains::cors_hosts() {
    local parts=("${DNS_DOMAIN}")
    if [[ "${DNS_DOMAIN}" != "${PRIMARY_DOMAIN}" ]]; then
        parts+=("${PRIMARY_DOMAIN}")
    fi
    local h
    for h in "${KNOWN_SERVER_HOSTS[@]}"; do
        parts+=("${h}.${BASE_DOMAIN}")
        if [[ -n "${SITE_DOMAIN:-}" ]]; then
            parts+=("${h}.${SITE_DOMAIN}")
        fi
    done
    local IFS=','
    printf '%s\n' "${parts[*]}"
}

# Test helper: print CERT_DOMAINS sorted, one per line. Used by the
# byte-equality cert SAN check in validation.md.
dump-cert-domains() {
    if [[ -z "${BASE_DOMAIN:-}" ]]; then
        printf 'dump-cert-domains: BASE_DOMAIN is required\n' >&2
        return 1
    fi
    dev_domains::resolve
    printf '%s\n' "${CERT_DOMAINS[@]}" | sort -u
}

# When executed (not sourced), expose dump-cert-domains for the test
# harness. Usage: BASE_DOMAIN=... bash dev-domains.sh dump-cert-domains
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] && [[ $# -ge 1 ]]; then
    case "$1" in
        dump-cert-domains)
            shift
            dump-cert-domains "$@"
            ;;
        *)
            printf 'unknown subcommand: %s\n' "$1" >&2
            exit 2
            ;;
    esac
fi