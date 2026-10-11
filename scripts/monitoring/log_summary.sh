#!/usr/bin/env bash
# Read-only log analysis. Input errors never become successful empty reports.
# Exit: 0 complete (including no matches), 2 usage, 3 incomplete/error/timeout.
set -euo pipefail
export LC_ALL=C
PATTERN='error|warn|fail|critical|denied' TOP_N=15 INCLUDE_ROTATED=0 LOGFILE='' SCAN_TIMEOUT=60
usage() { echo 'Usage: log_summary.sh -f FILE [-p REGEX] [-n TOP] [--include-rotated] [--timeout SECONDS]'; }
bad_usage() { echo "Error: $*" >&2; usage >&2; exit 2; }
unknown() { echo "STATUS: UNKNOWN — $*" >&2; exit 3; }
while (( $# )); do
    case $1 in
        -f|--file|-p|--pattern|-n|--top|--timeout)
            (( $# >= 2 )) || bad_usage "Missing value for $1"
            case $1 in
                -f|--file) LOGFILE=$2 ;;
                -p|--pattern) PATTERN=$2 ;;
                -n|--top) TOP_N=$2 ;;
                --timeout) SCAN_TIMEOUT=$2 ;;
            esac
            shift 2 ;;
        --include-rotated) INCLUDE_ROTATED=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) bad_usage "Unknown option: $1" ;;
    esac
done
[[ $TOP_N =~ ^[1-9][0-9]{0,3}$ ]] || bad_usage 'TOP must be 1–9999'
[[ $SCAN_TIMEOUT =~ ^[1-9][0-9]{0,4}$ ]] || bad_usage 'Timeout must be 1–99999 seconds per file'
[[ -n $LOGFILE && -f $LOGFILE && -r $LOGFILE ]] || bad_usage 'A readable regular log file is required'
rc=0; grep -Ei -- "$PATTERN" /dev/null >/dev/null || rc=$?
(( rc <= 1 )) || bad_usage 'Invalid extended regular expression'
umask 077
WORK=$(mktemp -d) || unknown 'Cannot allocate private temporary directory'
trap 'rm -rf -- "$WORK"' EXIT
MATCHES=$WORK/matches
: > "$MATCHES"
scan_file() {
    local file=$1 rc=0
    local -a statuses
    [[ -f $file && -r $file ]] || unknown "Cannot read regular file: $file"
    case $file in
        *.gz)
            # zgrep may silently read non-gzip input as plaintext. Require a
            # successful decompressor as well as grep's success/no-match status.
            if timeout --kill-after=5 "$SCAN_TIMEOUT" gzip -cd -- "$file" |
                timeout --kill-after=5 "$SCAN_TIMEOUT" grep -Ei -- "$PATTERN" >> "$MATCHES"; then
                statuses=("${PIPESTATUS[@]}")
            else
                statuses=("${PIPESTATUS[@]}")
            fi
            (( statuses[0] == 0 && statuses[1] <= 1 )) || unknown "Compressed scan failed for $file (exits ${statuses[*]}); report is incomplete"
            ;;
        *) timeout --kill-after=5 "$SCAN_TIMEOUT" grep -Ei -- "$PATTERN" "$file" >> "$MATCHES" || rc=$? ;;
    esac
    (( rc <= 1 )) || unknown "Scan failed for $file (exit $rc); report is incomplete"
}
scan_file "$LOGFILE"
if (( INCLUDE_ROTATED )); then
    for file in "$LOGFILE".*; do
        suffix=${file#"$LOGFILE".}
        [[ $suffix =~ ^[0-9]+(\.gz)?$ ]] || continue
        [[ -e $file || -L $file ]] || continue
        scan_file "$file"
    done
fi
TOTAL_MATCHES=$(wc -l < "$MATCHES")
echo "Total matching lines: $TOTAL_MATCHES"
if (( TOTAL_MATCHES == 0 )); then echo 'No matches found for the given pattern.'; exit 0; fi
echo "--- Top $TOP_N most frequent matching lines (heuristic normalization) ---"
# Consume sorted input fully; head can cause a spurious SIGPIPE under pipefail.
awk '{ $1=""; $2=""; $3=""; print }' "$MATCHES" | sed -E 's/[0-9]+/#/g' | sort | uniq -c | sort -rn | sed -n "1,${TOP_N}p"
echo '--- Matches per severity keyword ---'
for keyword in error warn fail critical denied; do
    rc=0; count=$(grep -ci -- "$keyword" "$MATCHES") || rc=$?
    (( rc <= 1 )) || unknown 'Cannot read collected matches'
    printf '%-10s %s\n' "$keyword" "$count"
done
