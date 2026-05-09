#!/bin/bash
# ===========================================================
# Script Name : backup_rotation.sh
# Purpose     : Daily + weekly backup with rotation and alerts
# Usage       : ./backup_rotation.sh
#               Recommended cron: 0 2 * * *  (2AM daily)
# Author      : blow_tech
# Version     : 2.0
# ===========================================================
set -euo pipefail

SCRIPT_NAME="backup_rotation"
LOG_FILE="/var/log/admin-scripts/${SCRIPT_NAME}.log"

# =================== CONFIGURATION =========================
SRC_DIR="/var/www/html"     # Directory to back up
BACKUP_DIR="/backups"        # Backup destination root
DAILY_KEEP=7                 # Keep last N daily backups
WEEKLY_KEEP=4                # Keep last N weekly backups
MIN_FREE_MB=500              # Abort if less than this MB free on backup disk
# ===========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/alert_engine.sh"

lock_script "$SCRIPT_NAME"

mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$BACKUP_DIR/daily"
mkdir -p "$BACKUP_DIR/weekly"

rotate_log "$LOG_FILE" 10240

HOST=$(hostname)
DATE=$(date +"%Y-%m-%d")
WEEK_NUM=$(date +%V)
DAY_OF_WEEK=$(date +%u)   # 1=Monday … 7=Sunday
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

log() { echo "[$TIMESTAMP] $*" | tee -a "$LOG_FILE"; }

log "=== Backup rotation started on $HOST ==="

# ----------------------------------------------------------
# Pre-flight: check source exists
# ----------------------------------------------------------
if [ ! -d "$SRC_DIR" ]; then
    MSG="Source directory $SRC_DIR does not exist on $HOST!"
    log "❌ ABORT: $MSG"
    alert_critical "$SCRIPT_NAME" "Backup Aborted — Missing Source" "$MSG"
    exit 1
fi

# ----------------------------------------------------------
# Pre-flight: check free disk space on backup destination
# ----------------------------------------------------------
FREE_MB=$(df -BM "$BACKUP_DIR" | awk 'NR==2 {gsub(/M/,"",$4); print $4}')
if [ "$FREE_MB" -lt "$MIN_FREE_MB" ]; then
    MSG="Only ${FREE_MB}MB free on $BACKUP_DIR (minimum: ${MIN_FREE_MB}MB). Backup aborted on $HOST."
    log "❌ ABORT: $MSG"
    alert_critical "$SCRIPT_NAME" "Backup Aborted — Disk Space Low" "$MSG"
    exit 1
fi

# ----------------------------------------------------------
# Daily backup
# ----------------------------------------------------------
BACKUP_FILE="$BACKUP_DIR/daily/backup-$DATE.tar.gz"

if [ -f "$BACKUP_FILE" ]; then
    log "⏭️  Daily backup for $DATE already exists — skipping creation."
else
    log "📦 Creating daily backup: $BACKUP_FILE ..."
    if tar -czf "$BACKUP_FILE" "$SRC_DIR" 2>>"$LOG_FILE"; then
        SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
        log "✅ Daily backup created: $BACKUP_FILE ($SIZE)"
        alert_info "$SCRIPT_NAME" "Backup Success — $HOST" \
            "Daily backup created: $BACKUP_FILE ($SIZE)"
    else
        MSG="tar failed for $SRC_DIR → $BACKUP_FILE on $HOST"
        log "❌ FAILED: $MSG"
        alert_critical "$SCRIPT_NAME" "Backup FAILED — $HOST" "$MSG"
        exit 1
    fi
fi

# ----------------------------------------------------------
# Rotate old daily backups
# ----------------------------------------------------------
DELETED=$(find "$BACKUP_DIR/daily" -type f -mtime +"$DAILY_KEEP" -name "*.tar.gz" \
          -print -delete 2>>"$LOG_FILE" | wc -l)
log "🧹 Daily rotation: removed $DELETED old backup(s) older than $DAILY_KEEP days."

# ----------------------------------------------------------
# Weekly backup (every Sunday)
# ----------------------------------------------------------
if [ "$DAY_OF_WEEK" -eq 7 ]; then
    WEEKLY_FILE="$BACKUP_DIR/weekly/backup-week-$WEEK_NUM.tar.gz"

    if [ -f "$WEEKLY_FILE" ]; then
        log "⏭️  Weekly backup for week $WEEK_NUM already exists — skipping."
    else
        log "📦 Creating weekly backup: $WEEKLY_FILE ..."
        cp "$BACKUP_FILE" "$WEEKLY_FILE"
        SIZE=$(du -sh "$WEEKLY_FILE" | cut -f1)
        log "✅ Weekly backup created: $WEEKLY_FILE ($SIZE)"
        alert_info "$SCRIPT_NAME" "Weekly Backup Success — $HOST" \
            "Weekly backup (week $WEEK_NUM) created: $WEEKLY_FILE ($SIZE)"
    fi

    # Rotate old weekly backups (older than WEEKLY_KEEP * 7 days)
    WDELETED=$(find "$BACKUP_DIR/weekly" -type f -mtime +"$((7 * WEEKLY_KEEP))" -name "*.tar.gz" \
               -print -delete 2>>"$LOG_FILE" | wc -l)
    log "🧹 Weekly rotation: removed $WDELETED old weekly backup(s)."
fi

log "=== Backup rotation completed successfully ==="
