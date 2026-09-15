#!/usr/bin/env bash
#
# healthcheck.sh
#
# Read-only system health check for RHEL/CentOS (and most Linux) servers.
# Reports on CPU load, memory usage, disk usage, and swap — no changes made
# to the system. Exits non-zero if any metric crosses its threshold, so it
# can be wired into cron + alerting without extra glue code.
#
# author blow_tech
# Usage:
#   ./healthcheck.sh [--cpu-threshold N] [--mem-threshold N] [--disk-threshold N]
#
# Options:
#   --cpu-threshold N     Load average (1-min, normalized per core) alert threshold. Default: 0.85
#   --disk-threshold N    Disk usage percentage alert threshold. Default: 90
#   --mem-threshold N     Memory usage percentage alert threshold. Default: 90
#   -h, --help            Show this help message
#
# Exit codes:
#   0  All checks within thresholds
#   1  One or more checks exceeded thresholds
#   2  Invalid usage
#
# Requires: bash, coreutils (df, free, uptime, nproc) — all standard, no root required.

set -euo pipefail

CPU_THRESHOLD=0.85
DISK_THRESHOLD=90
MEM_THRESHOLD=90
ISSUES=0

usage() {
    grep '^#' "$0" | sed -e 's/^#//' -e '1d'
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpu-threshold) CPU_THRESHOLD="$2"; shift 2 ;;
        --disk-threshold) DISK_THRESHOLD="$2"; shift 2 ;;
        --mem-threshold) MEM_THRESHOLD="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

echo "=== Health Check: $(hostname) — $(date '+%Y-%m-%d %H:%M:%S') ==="

# --- CPU load ---
CORES=$(nproc)
LOAD_1M=$(cut -d' ' -f1 /proc/loadavg)
LOAD_NORMALIZED=$(awk -v l="$LOAD_1M" -v c="$CORES" 'BEGIN { printf "%.2f", l / c }')

echo "--- CPU ---"
echo "Cores: ${CORES}"
echo "Load average (1m): ${LOAD_1M} (normalized: ${LOAD_NORMALIZED})"
if awk -v n="$LOAD_NORMALIZED" -v t="$CPU_THRESHOLD" 'BEGIN { exit !(n > t) }'; then
    echo "STATUS: WARNING — normalized load ${LOAD_NORMALIZED} exceeds threshold ${CPU_THRESHOLD}"
    ISSUES=$((ISSUES + 1))
else
    echo "STATUS: OK"
fi

# --- Memory ---
echo "--- Memory ---"
read -r MEM_TOTAL MEM_USED <<< "$(free -m | awk '/^Mem:/ {print $2, $3}')"
MEM_PCT=$(awk -v u="$MEM_USED" -v t="$MEM_TOTAL" 'BEGIN { printf "%.0f", (u/t)*100 }')
echo "Used: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%)"
if [[ "$MEM_PCT" -ge "$MEM_THRESHOLD" ]]; then
    echo "STATUS: WARNING — memory usage ${MEM_PCT}% exceeds threshold ${MEM_THRESHOLD}%"
    ISSUES=$((ISSUES + 1))
else
    echo "STATUS: OK"
fi

# --- Swap ---
echo "--- Swap ---"
read -r SWAP_TOTAL SWAP_USED <<< "$(free -m | awk '/^Swap:/ {print $2, $3}')"
if [[ "$SWAP_TOTAL" -eq 0 ]]; then
    echo "No swap configured"
else
    SWAP_PCT=$(awk -v u="$SWAP_USED" -v t="$SWAP_TOTAL" 'BEGIN { printf "%.0f", (u/t)*100 }')
    echo "Used: ${SWAP_USED}MB / ${SWAP_TOTAL}MB (${SWAP_PCT}%)"
fi

# --- Disk ---
echo "--- Disk ---"
DISK_ISSUE=0
while read -r LINE; do
    USE_PCT=$(echo "$LINE" | awk '{print $5}' | tr -d '%')
    MOUNT=$(echo "$LINE" | awk '{print $6}')
    FS=$(echo "$LINE" | awk '{print $1}')
    echo "${MOUNT} (${FS}): ${USE_PCT}% used"
    if [[ "$USE_PCT" -ge "$DISK_THRESHOLD" ]]; then
        echo "  STATUS: WARNING — exceeds threshold ${DISK_THRESHOLD}%"
        DISK_ISSUE=1
    fi
done < <(df -hP -x tmpfs -x devtmpfs | tail -n +2)

if [[ "$DISK_ISSUE" -eq 1 ]]; then
    ISSUES=$((ISSUES + 1))
else
    echo "STATUS: OK (all filesystems)"
fi

echo "=== Summary ==="
if [[ "$ISSUES" -eq 0 ]]; then
    echo "All checks passed."
    exit 0
else
    echo "${ISSUES} check(s) exceeded threshold. Review output above."
    exit 1
fi
