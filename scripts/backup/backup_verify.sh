#!/usr/bin/env bash
#
# backup-verify.sh
#
# Read-only backup validation. Checks a backup directory for the presence
# of a recent file, verifies it's non-empty, and (optionally) validates
# archive integrity for common formats (tar, tar.gz, zip) without
# extracting or modifying anything.
# author blow_tech
# Usage:
#   ./backup-verify.sh -d /backups/sql -m 24
#   ./backup-verify.sh -d /backups/sql --pattern "*.tar.gz" -m 24 --verify-archive
#
# Options:
#   -d, --dir PATH            Backup directory to check (required)
#   -m, --max-age-hours N     Alert if newest matching file is older than N hours (default: 24)
#   --pattern GLOB            Filename glob to match (default: *)
#   --verify-archive          Test archive integrity (tar/tar.gz/zip) without extracting
#   -h, --help                 Show this help message
#
# Exit codes:
#   0  Backup found, within age threshold, and (if requested) integrity check passed
#   1  Backup missing, stale, empty, or failed integrity check
#   2  Invalid usage
#
# Requires: find, stat, tar (--list / -t for integrity), unzip (-t for integrity, optional).
# Read-only: uses tar -t / unzip -t which list/test contents without writing to disk.

set -euo pipefail

BACKUP_DIR=""
MAX_AGE_HOURS=24
PATTERN="*"
VERIFY_ARCHIVE=0

usage() {
    grep '^#' "$0" | sed -e 's/^#//' -e '1d'
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir) BACKUP_DIR="$2"; shift 2 ;;
        -m|--max-age-hours) MAX_AGE_HOURS="$2"; shift 2 ;;
        --pattern) PATTERN="$2"; shift 2 ;;
        --verify-archive) VERIFY_ARCHIVE=1; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

if [[ -z "$BACKUP_DIR" ]]; then
    echo "Error: -d/--dir is required" >&2
    usage
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Error: directory not found: $BACKUP_DIR" >&2
    exit 2
fi

echo "=== Backup Verification: ${BACKUP_DIR} — $(date '+%Y-%m-%d %H:%M:%S') ==="
echo "Pattern: ${PATTERN}  |  Max age: ${MAX_AGE_HOURS}h"

# Find the newest matching file (read-only)
NEWEST=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "$PATTERN" -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -n1 | cut -d' ' -f2- || true)

if [[ -z "$NEWEST" ]]; then
    echo "STATUS: FAIL — no files matching '${PATTERN}' found in ${BACKUP_DIR}"
    exit 1
fi

echo "Newest backup: ${NEWEST}"

FILE_SIZE=$(stat -c%s "$NEWEST")
FILE_AGE_SEC=$(( $(date +%s) - $(stat -c%Y "$NEWEST") ))
FILE_AGE_HOURS=$(( FILE_AGE_SEC / 3600 ))

echo "Size: ${FILE_SIZE} bytes"
echo "Age: ${FILE_AGE_HOURS} hour(s)"

EXIT_CODE=0

if [[ "$FILE_SIZE" -eq 0 ]]; then
    echo "STATUS: FAIL — backup file is empty"
    EXIT_CODE=1
fi

if [[ "$FILE_AGE_HOURS" -gt "$MAX_AGE_HOURS" ]]; then
    echo "STATUS: FAIL — backup is older than ${MAX_AGE_HOURS}h threshold"
    EXIT_CODE=1
fi

if [[ "$VERIFY_ARCHIVE" -eq 1 ]]; then
    echo "--- Archive integrity check (read-only) ---"
    case "$NEWEST" in
        *.tar.gz|*.tgz)
            if tar -tzf "$NEWEST" &>/dev/null; then
                echo "Archive integrity: OK (tar.gz)"
            else
                echo "Archive integrity: FAIL — corrupt or unreadable tar.gz"
                EXIT_CODE=1
            fi
            ;;
        *.tar)
            if tar -tf "$NEWEST" &>/dev/null; then
                echo "Archive integrity: OK (tar)"
            else
                echo "Archive integrity: FAIL — corrupt or unreadable tar"
                EXIT_CODE=1
            fi
            ;;
        *.zip)
            if command -v unzip &>/dev/null && unzip -t "$NEWEST" &>/dev/null; then
                echo "Archive integrity: OK (zip)"
            else
                echo "Archive integrity: FAIL — corrupt, unreadable zip, or unzip not installed"
                EXIT_CODE=1
            fi
            ;;
        *)
            echo "Archive integrity: SKIPPED — unrecognized extension for '${NEWEST}'"
            ;;
    esac
fi

echo
if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "Backup verification passed."
else
    echo "Backup verification FAILED. Review output above."
fi

exit "$EXIT_CODE"
