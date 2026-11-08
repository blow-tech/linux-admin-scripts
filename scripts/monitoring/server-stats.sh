#!/usr/bin/env bash
# Bounded local statistics snapshot. No ANSI terminal dependency or implicit writes.
set -uo pipefail
export LC_ALL=C
status=0
collect() { printf '\n--- %s ---\n' "$*"; timeout -k 5 15 "$@" || { echo "UNKNOWN: $1 failed" >&2; status=3; }; }
collect uname -a
collect uptime
collect free -m
collect df -hP
collect ps -eo pid,ppid,user,pcpu,pmem,comm --sort=-pcpu
exit "$status"
