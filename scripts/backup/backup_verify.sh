#!/usr/bin/env bash
# Read-only backup validation; integrity checks do not prove restorability.
# Exit: 0 verified requested checks, 1 failed checks, 2 usage, 3 unavailable evidence.
set -euo pipefail
export LC_ALL=C
BACKUP_DIR='' MAX_AGE_HOURS=24 PATTERN='*' VERIFY_ARCHIVE=0
usage() { echo 'Usage: backup_verify.sh -d DIR [-m HOURS] [--pattern GLOB] [--verify-archive]'; }
unknown() { echo "STATUS: UNKNOWN — $*" >&2; exit 3; }
bad_usage() { echo "Error: $*" >&2; usage >&2; exit 2; }
while (( $# )); do
    case $1 in
        -d|--dir|-m|--max-age-hours|--pattern)
            (( $# >= 2 )) || bad_usage "Missing value for $1"
            case $1 in
                -d|--dir) BACKUP_DIR=$2 ;;
                -m|--max-age-hours) MAX_AGE_HOURS=$2 ;;
                --pattern) PATTERN=$2 ;;
            esac
            shift 2 ;;
        --verify-archive) VERIFY_ARCHIVE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) bad_usage "Unknown option: $1" ;;
    esac
done
[[ -n $BACKUP_DIR && -d $BACKUP_DIR ]] || bad_usage 'An existing backup directory is required'
[[ $MAX_AGE_HOURS =~ ^[0-9]{1,6}$ ]] || bad_usage 'Hours must be a nonnegative integer of at most six digits'
MAX_AGE_HOURS=$((10#$MAX_AGE_HOURS))
BACKUP_DIR=$(realpath -e -- "$BACKUP_DIR") || unknown 'Cannot resolve backup directory'
umask 077
WORK=$(mktemp -d) || unknown 'Cannot allocate private temporary directory'
trap 'rm -rf -- "$WORK"' EXIT
# NUL records preserve spaces/newlines. Check find AND sort status without head/SIGPIPE.
if ! find "$BACKUP_DIR" -maxdepth 1 -type f -name "$PATTERN" -printf '%T@ %p\0' | sort -z -nr > "$WORK/files"; then
    unknown 'Backup enumeration failed'
fi
RECORD=''
if ! IFS= read -r -d '' RECORD < "$WORK/files"; then
    echo 'STATUS: FAIL — no matching backup files'; exit 1
fi
NEWEST=${RECORD#* }
META=$(stat -c '%s %Y' -- "$NEWEST") || unknown 'Cannot stat newest backup'
read -r FILE_SIZE MTIME <<< "$META"
NOW=$(date +%s) || unknown 'Cannot read current time'
[[ $FILE_SIZE =~ ^[0-9]+$ && $MTIME =~ ^-?[0-9]+$ && $NOW =~ ^[0-9]+$ ]] || unknown 'Malformed file metadata'
FILE_AGE_SEC=$((NOW-MTIME))
printf 'Newest backup: %q\nSize: %s bytes\nAge: %s seconds\n' "$NEWEST" "$FILE_SIZE" "$FILE_AGE_SEC"
(( FILE_AGE_SEC >= 0 )) || unknown 'Backup timestamp is in the future; check clock consistency'
EXIT_CODE=0
if (( FILE_SIZE == 0 )); then echo 'STATUS: FAIL — backup is empty'; EXIT_CODE=1; fi
if (( FILE_AGE_SEC > MAX_AGE_HOURS * 3600 )); then
    echo "STATUS: FAIL — backup is older than ${MAX_AGE_HOURS}h"; EXIT_CODE=1
fi
if (( VERIFY_ARCHIVE )); then
    case $NEWEST in
        *.tar.gz|*.tgz)
            if ! gzip -t -- "$NEWEST" || ! tar -tzf "$NEWEST" >/dev/null; then EXIT_CODE=1; fi ;;
        *.tar) if ! tar -tf "$NEWEST" >/dev/null; then EXIT_CODE=1; fi ;;
        *.zip)
            command -v unzip >/dev/null || unknown 'unzip is required for ZIP integrity verification'
            if ! unzip -t "$NEWEST" >/dev/null; then EXIT_CODE=1; fi ;;
        *) unknown 'Requested integrity check is unsupported for this file extension' ;;
    esac
fi
if (( EXIT_CODE == 0 )); then
    echo 'Backup verification passed (requested checks only; restore test still required).'
else
    echo 'Backup verification FAILED.'
fi
exit "$EXIT_CODE"
