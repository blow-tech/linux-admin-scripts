#!/usr/bin/env bash
# Read-only health checks. Usage: healthcare_check.sh [--cpu-threshold N] [--mem-threshold N] [--disk-threshold N]
# Exit: 0 healthy, 1 threshold exceeded, 2 invalid usage, 3 incomplete collection.
set -euo pipefail
export LC_ALL=C
CPU_THRESHOLD=0.85 DISK_THRESHOLD=90 MEM_THRESHOLD=90 ISSUES=0
usage() { echo 'Usage: healthcare_check.sh [--cpu-threshold N] [--mem-threshold N] [--disk-threshold N]'; }
unknown() { echo "STATUS: UNKNOWN — $*" >&2; exit 3; }
bad_usage() { echo "Error: $*" >&2; usage >&2; exit 2; }
while (( $# )); do
    case $1 in
        --cpu-threshold|--disk-threshold|--mem-threshold)
            (( $# >= 2 )) || bad_usage "Missing value for $1"
            case $1 in
                --cpu-threshold) CPU_THRESHOLD=$2 ;;
                --disk-threshold) DISK_THRESHOLD=$2 ;;
                --mem-threshold) MEM_THRESHOLD=$2 ;;
            esac
            shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) bad_usage "Unknown option: $1" ;;
    esac
done
[[ $CPU_THRESHOLD =~ ^[0-9]{1,6}(\.[0-9]{1,6})?$ ]] || bad_usage 'Invalid CPU threshold'
for n in "$MEM_THRESHOLD" "$DISK_THRESHOLD"; do
    [[ $n =~ ^[0-9]{1,3}$ ]] && (( 10#$n >= 1 && 10#$n <= 100 )) || bad_usage 'Percentage thresholds must be 1–100'
done
MEM_THRESHOLD=$((10#$MEM_THRESHOLD)); DISK_THRESHOLD=$((10#$DISK_THRESHOLD))
CORES=$(timeout 30 nproc) || unknown 'CPU core collection failed'
LOAD_1M=$(cut -d' ' -f1 /proc/loadavg) || unknown 'Load collection failed'
[[ $CORES =~ ^[1-9][0-9]*$ && $LOAD_1M =~ ^[0-9]+(\.[0-9]+)?$ ]] || unknown 'Malformed CPU data'
echo "CPU: load=$LOAD_1M cores=$CORES threshold=$CPU_THRESHOLD per core"
if awk -v l="$LOAD_1M" -v c="$CORES" -v t="$CPU_THRESHOLD" 'BEGIN {exit !(l/c > t)}'; then
    echo 'STATUS: WARNING — CPU load exceeded threshold'; ISSUES=$((ISSUES+1))
fi
# Collect memory and swap once; never turn missing rows into zero usage.
MEMORY=$(timeout 30 free -m) || unknown 'Memory collection failed'
read -r MEM_TOTAL MEM_USED <<< "$(awk '/^Mem:/ {print $2, $3}' <<< "$MEMORY")"
read -r SWAP_TOTAL SWAP_USED <<< "$(awk '/^Swap:/ {print $2, $3}' <<< "$MEMORY")"
for n in "$MEM_TOTAL" "$MEM_USED" "$SWAP_TOTAL" "$SWAP_USED"; do
    [[ $n =~ ^(0|[1-9][0-9]*)$ ]] || unknown 'Missing or malformed memory/swap row'
done
(( MEM_TOTAL > 0 && MEM_USED <= MEM_TOTAL && SWAP_USED <= SWAP_TOTAL )) || unknown 'Inconsistent memory/swap totals'
echo "Memory: $MEM_USED/$MEM_TOTAL MiB; swap: $SWAP_USED/$SWAP_TOTAL MiB"
if awk -v u="$MEM_USED" -v t="$MEM_TOTAL" -v limit="$MEM_THRESHOLD" 'BEGIN {exit !(100*u/t >= limit)}'; then
    echo 'STATUS: WARNING — memory usage exceeded threshold'; ISSUES=$((ISSUES+1))
fi
DISKS=$(timeout 30 df -hP -x tmpfs -x devtmpfs) || unknown 'Filesystem collection failed'
CHECKED=0
while read -r fs size used avail percent mount; do
    [[ $fs == Filesystem ]] && continue
    percent=${percent%%%}
    [[ $percent =~ ^(0|[1-9][0-9]*)$ && -n $mount ]] || unknown 'Missing or malformed filesystem row'
    CHECKED=$((CHECKED+1))
    printf '%s (%s): %s%% used\n' "$mount" "$fs" "$percent"
    if (( percent >= DISK_THRESHOLD )); then
        echo 'STATUS: WARNING — disk usage exceeded threshold'; ISSUES=$((ISSUES+1))
    fi
done <<< "$DISKS"
(( CHECKED > 0 )) || unknown 'No eligible filesystems were checked'
if (( ISSUES )); then echo "$ISSUES threshold(s) exceeded."; exit 1; fi
echo 'All checks passed.'
