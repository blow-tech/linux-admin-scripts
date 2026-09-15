#!/usr/bin/env bash
#
# security-audit.sh
# author blow_tech
# Read-only security posture snapshot for a Linux host. Reports on listening
# ports, recent failed SSH logins, world-writable files in common paths,
# users with UID 0, and sudoers entries. Makes no changes — every command
# used is a query/read operation.
#
# Usage:
#   ./security-audit.sh
#   ./security-audit.sh --scan-path /var/www --failed-login-count 20
#
# Options:
#   --scan-path PATH           Additional path to scan for world-writable files (default: /tmp /var/tmp)
#   --failed-login-count N     Number of recent failed SSH attempts to show (default: 10)
#   -h, --help                 Show this help message
#
# Exit codes:
#   0  Completed (findings, if any, are informational — review output)
#   2  Invalid usage
#
# Requires: ss or netstat, find, awk, grep, journalctl or /var/log/secure access.
# Some sections (failed logins, sudoers) yield more detail when run as root,
# but the script runs and degrades gracefully without it — it never elevates
# privileges itself and never modifies any file, user, or service.

set -uo pipefail

SCAN_PATHS=("/tmp" "/var/tmp")
FAILED_LOGIN_COUNT=10

usage() {
    grep '^#' "$0" | sed -e 's/^#//' -e '1d'
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scan-path) SCAN_PATHS+=("$2"); shift 2 ;;
        --failed-login-count) FAILED_LOGIN_COUNT="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

echo "=== Security Audit: $(hostname) — $(date '+%Y-%m-%d %H:%M:%S') ==="
[[ "$EUID" -ne 0 ]] && echo "(Running as non-root — some sections may show limited detail)"
echo

echo "--- Listening network services ---"
if command -v ss &>/dev/null; then
    ss -tulnp 2>/dev/null || ss -tuln
else
    netstat -tulnp 2>/dev/null || netstat -tuln
fi
echo

echo "--- Users with UID 0 (should normally be root only) ---"
awk -F: '$3 == 0 { print $1 }' /etc/passwd
echo

echo "--- Sudoers entries (/etc/sudoers.d/*, read-only) ---"
if [[ -r /etc/sudoers ]]; then
    grep -Ev '^\s*#|^\s*$' /etc/sudoers 2>/dev/null || echo "(unable to read /etc/sudoers)"
else
    echo "(no read permission on /etc/sudoers — try running as root for this section)"
fi
if [[ -d /etc/sudoers.d ]]; then
    for f in /etc/sudoers.d/*; do
        [[ -f "$f" && -r "$f" ]] || continue
        echo "-- $f --"
        grep -Ev '^\s*#|^\s*$' "$f" 2>/dev/null
    done
fi
echo

echo "--- Recent failed SSH login attempts (last ${FAILED_LOGIN_COUNT}) ---"
if command -v journalctl &>/dev/null; then
    journalctl -u sshd --no-pager 2>/dev/null | grep -i "failed password" | tail -n "$FAILED_LOGIN_COUNT" \
        || echo "(no matching journal entries, or insufficient permissions)"
elif [[ -r /var/log/secure ]]; then
    grep -i "failed password" /var/log/secure | tail -n "$FAILED_LOGIN_COUNT"
elif [[ -r /var/log/auth.log ]]; then
    grep -i "failed password" /var/log/auth.log | tail -n "$FAILED_LOGIN_COUNT"
else
    echo "(no accessible auth log found — try running as root)"
fi
echo

echo "--- World-writable files in scanned paths ---"
for p in "${SCAN_PATHS[@]}"; do
    [[ -d "$p" ]] || continue
    echo "Scanning: $p"
    find "$p" -xdev -type f -perm -0002 2>/dev/null | head -n 50
done
echo

echo "=== Audit complete. This is a read-only informational report — no remediation was performed. ==="
