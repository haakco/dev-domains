#!/usr/bin/env bash
# cert_sanity.sh — byte-equality check for shared dev-domain module.
#
# Verifies that for every (app × BASE_DOMAIN × SITE_DOMAIN) combination,
# the CERT_DOMAINS produced by dev_domains::resolve matches the expected
# pattern: PRIMARY_DOMAIN first, then optional SITE primary, then each
# known host pair (with wildcard), with optional *.host.SITE_DOMAIN for
# dual-suffix apps.
#
# Run from any directory: bash ~/Dev/HaakCo/AiProjects/sharedLib/infra/tests/cert_sanity.sh

set -euo pipefail

MODULE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/dev-domains.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "${expected}" != "${actual}" ]]; then
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' \
            "${label}" "${expected}" "${actual}" >&2
        exit 1
    fi
}

assert_sorted_lines() {
    local label="$1" expected="$2" actual="$3"
    local e a
    e=$(printf '%s\n' "${expected}" | sort -u)
    a=$(printf '%s\n' "${actual}" | sort -u)
    assert_eq "${label}" "${e}" "${a}"
}

# -----------------------------------------------------------------------------
# Case 1: TrackLab — single suffix (BASE_DOMAIN only)
# -----------------------------------------------------------------------------
unset SITE_DOMAIN
export BASE_DOMAIN="haakdev.com"
source "${MODULE}"

# DNS_DOMAIN depends on hostname. Default to PRIMARY when not on a known host.
case "$(hostname -s 2>/dev/null || echo unknown)" in
    wdev|srvh01|srvh02|srvh03|dark)
        expected_dns="$(hostname -s).haakdev.com"
        ;;
    *)
        expected_dns="dev.haakdev.com"
        ;;
esac

dev_domains::resolve

assert_eq "TrackLab PRIMARY_DOMAIN" "dev.haakdev.com" "${PRIMARY_DOMAIN}"
assert_eq "TrackLab LOCAL_DOMAIN"  "dev.haakdev.com" "${LOCAL_DOMAIN}"
assert_eq "TrackLab TRAEFIK_DOMAIN" "traefik.${expected_dns}" "${TRAEFIK_DOMAIN}"
assert_eq "TrackLab API_APP_URL"   "https://${expected_dns}" "${API_APP_URL}"
assert_eq "TrackLab DNS_DOMAIN" "${expected_dns}" "${DNS_DOMAIN}"

# CERT_DOMAINS shape: PRIMARY_DOMAIN, *.PRIMARY_DOMAIN, then five (host, *.host) pairs.
expected_tracklab=$(printf '%s\n' \
    "dev.haakdev.com" \
    "*.dev.haakdev.com" \
    "wdev.haakdev.com" \
    "*.wdev.haakdev.com" \
    "srvh01.haakdev.com" \
    "*.srvh01.haakdev.com" \
    "srvh02.haakdev.com" \
    "*.srvh02.haakdev.com" \
    "srvh03.haakdev.com" \
    "*.srvh03.haakdev.com" \
    "dark.haakdev.com" \
    "*.dark.haakdev.com" \
    | sort -u)
actual_tracklab=$(printf '%s\n' "${CERT_DOMAINS[@]}" | sort -u)
assert_eq "TrackLab CERT_DOMAINS" "${expected_tracklab}" "${actual_tracklab}"

# First entry must be PRIMARY_DOMAIN so certbot writes to /live/${PRIMARY_DOMAIN}.
assert_eq "TrackLab CERT_DOMAINS[0]" "dev.haakdev.com" "${CERT_DOMAINS[0]}"

# -----------------------------------------------------------------------------
# Case 2: CouriB — dual suffix (BASE_DOMAIN + SITE_DOMAIN)
# -----------------------------------------------------------------------------
export BASE_DOMAIN="courib.com"
export SITE_DOMAIN="site.courib.com"
source "${MODULE}"
dev_domains::resolve

assert_eq "CouriB PRIMARY_DOMAIN" "dev.courib.com" "${PRIMARY_DOMAIN}"
assert_eq "CouriB SITE primary"   "dev.site.courib.com" "dev.${SITE_DOMAIN}"

expected_courib=$(printf '%s\n' \
    "dev.courib.com" \
    "*.dev.courib.com" \
    "dev.site.courib.com" \
    "*.dev.site.courib.com" \
    "wdev.courib.com" \
    "*.wdev.courib.com" \
    "*.wdev.site.courib.com" \
    "srvh01.courib.com" \
    "*.srvh01.courib.com" \
    "*.srvh01.site.courib.com" \
    "srvh02.courib.com" \
    "*.srvh02.courib.com" \
    "*.srvh02.site.courib.com" \
    "srvh03.courib.com" \
    "*.srvh03.courib.com" \
    "*.srvh03.site.courib.com" \
    "dark.courib.com" \
    "*.dark.courib.com" \
    "*.dark.site.courib.com" \
    | sort -u)
actual_courib=$(printf '%s\n' "${CERT_DOMAINS[@]}" | sort -u)
assert_eq "CouriB CERT_DOMAINS" "${expected_courib}" "${actual_courib}"

assert_eq "CouriB CERT_DOMAINS[0]" "dev.courib.com" "${CERT_DOMAINS[0]}"

# -----------------------------------------------------------------------------
# Case 3: dump-cert-domains exits 1 when BASE_DOMAIN is missing
# -----------------------------------------------------------------------------
output=$(unset BASE_DOMAIN SITE_DOMAIN; bash "${MODULE}" dump-cert-domains 2>&1 || true)
case "${output}" in
    *BASE_DOMAIN*required*) ;;
    *) fail "dump-cert-domains without BASE_DOMAIN should mention BASE_DOMAIN, got: ${output}" ;;
esac

# -----------------------------------------------------------------------------
# Case 4: dump-cert-domains produces the same set as dev_domains::resolve
# -----------------------------------------------------------------------------
export BASE_DOMAIN="haakdev.com"
unset SITE_DOMAIN
expected=$(dev_domains::resolve && printf '%s\n' "${CERT_DOMAINS[@]}" | sort -u)
actual=$(BASE_DOMAIN="haakdev.com" bash "${MODULE}" dump-cert-domains)
assert_eq "dump-cert-domains matches resolve CERT_DOMAINS" "${expected}" "${actual}"

# -----------------------------------------------------------------------------
# Case 6: hostname=unknown fallback (hostname -s failure)
# -----------------------------------------------------------------------------
# Run in a clean subshell with hostname stubbed to failure. The resolver
# should fall back to "unknown" via dev_domains::_shorthost, then
# default DNS_DOMAIN to PRIMARY_DOMAIN since "unknown" is not in
# KNOWN_SERVER_HOSTS.
actual=$(
    hostname() { return 1; }
    export -f hostname
    BASE_DOMAIN="haakdev.com" \
    SITE_DOMAIN="" \
    bash -c '
        source "'"${MODULE}"'"
        dev_domains::resolve
        printf "%s" "${DNS_DOMAIN}"
    '
)
assert_eq "Case6: DNS_DOMAIN falls back to PRIMARY_DOMAIN when hostname fails" \
    "dev.haakdev.com" "${actual}"

# -----------------------------------------------------------------------------
# Case 5: BASE_DOMAIN is required by dev_domains::resolve
# -----------------------------------------------------------------------------
unset BASE_DOMAIN SITE_DOMAIN
output=$(source "${MODULE}" && dev_domains::resolve 2>&1 || true)
case "${output}" in
    *BASE_DOMAIN*required*) ;;
    *) fail "dev_domains::resolve without BASE_DOMAIN should mention BASE_DOMAIN, got: ${output}" ;;
esac

printf 'cert_sanity.sh: all checks passed\n'