#!/usr/bin/env bash
# Required: SRC_DIR, BACKUP_DIR (existing), EXPECTED_BACKUP_SOURCE.
# Versioned daily/weekly archives; retention is inventory-only.
set -euo pipefail
umask 077
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../core/alert_engine.sh"
source "$SCRIPT_DIR/../core/backup_engine.sh"
lock_script backup_rotation
backup_preflight "${SRC_DIR:?Set SRC_DIR}" "${BACKUP_DIR:?Set BACKUP_DIR}"
for dir in "$BACKUP_DIR/daily" "$BACKUP_DIR/weekly"; do
    [[ ! -L $dir ]] || { echo 'Refusing symlink backup subdirectory' >&2; exit 1; }
    mkdir -p -- "$dir"
done
JOB_ID=$(printf %s "$SOURCE_DIR" | sha256sum | cut -c1-16)
STAMP=$(date -u +%Y%m%dT%H%M%S)-$$
BACKUP_FILE="$BACKUP_DIR/daily/admin-daily-${JOB_ID}-${STAMP}.tar.gz"
create_verified_archive "$BACKUP_FILE"
if [[ $(date -u +%u) == 7 ]]; then
    WEEKLY_FILE="$BACKUP_DIR/weekly/admin-weekly-${JOB_ID}-$(date -u +%G-W%V)-${STAMP}.tar.gz"
    PARTIAL=$(mktemp "${WEEKLY_FILE}.partial.XXXXXX")
    cp -- "$BACKUP_FILE" "$PARTIAL"
    cmp -- "$BACKUP_FILE" "$PARTIAL"
    publish_verified_archive "$PARTIAL" "$WEEKLY_FILE"
fi
alert_info backup_rotation 'Backup verified' "$BACKUP_FILE"
preview_retention "$BACKUP_DIR/daily" "admin-daily-${JOB_ID}-*.tar.gz" "${DAILY_KEEP:-7}"
WEEKLY_KEEP=${WEEKLY_KEEP:-4}
[[ $WEEKLY_KEEP =~ ^[1-9][0-9]*$ ]] || exit 2
preview_retention "$BACKUP_DIR/weekly" "admin-weekly-${JOB_ID}-*.tar.gz" "$((7 * WEEKLY_KEEP))"
