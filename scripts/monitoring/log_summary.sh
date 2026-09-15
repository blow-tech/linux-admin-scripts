#!/usr/bin/env bash
#
# log-summary.sh
#
# Read-only log analysis tool. Scans a log file (including rotated .gz
# archives) for error/warning/critical patterns and prints a frequency
# summary. Makes no changes to any file — safe to run against live logs.
#
# author blow_tech
# Usage:
#   ./log-summary.sh -f /var/log/messages [-p "error|fail|critical"] [-n 10]
#   ./log-summary.sh -f /var/log/messages --include-rotated
#
# Options:
#   -f, --file PATH         Log file to analyze (required)
#   -p, --pattern REGEX     Extended regex pattern to match (default: error|warn|fail|critical|denied)
#   -n, --top N             Show top N most frequent matching lines (default: 15)
#   --include-rotated       Also scan rotated logs matching PATH.1, PATH.2.gz, etc.
#   -h, --help              Show this help message
#
# Exit codes:
#   0  Completed (matches may or may not have been found)
#   2  Invalid usage or file not found/readable
#
# Requires: bash, grep, zgrep, awk, sort. Read access to the target log
# file(s) — no write or execute permissions needed on the logs themselves.

set -euo pipefail

PATTERN='error|warn|fail|critical|denied'
TOP_N=15
INCLUDE_ROTATED=0
LOGFILE=""

usage() {
    grep '^#' "$0" | sed -e 's/^#//' -e '1d'
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file) LOGFILE="$2"; shift 2 ;;
        -p|--pattern) PATTERN="$2"; shift 2 ;;
        -n|--top) TOP_N="$2"; shift 2 ;;
        --include-rotated) INCLUDE_ROTATED=1; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

if [[ -z "$LOGFILE" ]]; then
    echo "Error: -f/--file is required" >&2
    usage
fi

if [[ ! -r "$LOGFILE" ]]; then
    echo "Error: cannot read '$LOGFILE' (check path and permissions)" >&2
    exit 2
fi

echo "=== Log Summary: ${LOGFILE} — $(date '+%Y-%m-%d %H:%M:%S') ==="
echo "Pattern: ${PATTERN}"
echo

TMP_MATCHES=$(mktemp)
trap 'rm -f "$TMP_MATCHES"' EXIT

# Current log
grep -Ei "$PATTERN" "$LOGFILE" >> "$TMP_MATCHES" || true

# Rotated logs (plain and gzip), read-only
if [[ "$INCLUDE_ROTATED" -eq 1 ]]; then
    for f in "${LOGFILE}".*; do
        [[ -e "$f" ]] || continue
        case "$f" in
            *.gz) zgrep -Ei "$PATTERN" "$f" >> "$TMP_MATCHES" || true ;;
            *)    grep -Ei "$PATTERN" "$f"  >> "$TMP_MATCHES" || true ;;
        esac
    done
fi

TOTAL_MATCHES=$(wc -l < "$TMP_MATCHES" | tr -d ' ')
echo "Total matching lines: ${TOTAL_MATCHES}"
echo

if [[ "$TOTAL_MATCHES" -eq 0 ]]; then
    echo "No matches found for the given pattern."
    exit 0
fi

echo "--- Top ${TOP_N} most frequent matching lines (normalized) ---"
# Strip leading timestamps/PIDs heuristically so similar events group together,
# then rank by frequency. This is a best-effort normalization, not exact parsing.
awk '{ $1=""; $2=""; $3=""; print }' "$TMP_MATCHES" \
    | sed -E 's/[0-9]+/#/g' \
    | sort \
    | uniq -c \
    | sort -rn \
    | head -n "$TOP_N"

echo
echo "--- Matches per severity keyword ---"
for kw in error warn fail critical denied; do
    COUNT=$(grep -ci "$kw" "$TMP_MATCHES" || true)
    printf "%-10s %s\n" "$kw" "$COUNT"
done
