#!/usr/bin/env bash
# Explicit local audit categories replace the unbounded interactive menu.
# No package repository requests, scans, secrets, notifications or service changes.
set -uo pipefail
export LC_ALL=C
usage() { echo 'LinuxAudit.sh system|users|disk|network|services|ssh|security|packages|cron|logs [more categories...]'; }
(($#)) || { usage; exit 2; }
status=0
run() { printf '\n--- %s ---\n' "$*"; timeout -k 5 30 "$@" || { echo "UNKNOWN: $1 failed" >&2; status=3; }; }
for category in "$@"; do
 case $category in
  system) run uname -a; run uptime; run last -n 10 reboot;;
  users) run getent passwd; run getent group; run who;;
  disk) run df -hP; run lsblk -f; run free -m;;
  network) run ip address show; run ip route show; run ss -tulnp;;
  services) run systemctl list-units --type=service --no-pager; run systemctl --failed --no-pager;;
  ssh) run sshd -T;;
  security) bash "$(dirname "$0")/security-audit.sh" || status=3;;
  packages)
   if command -v rpm >/dev/null; then run rpm -qa;
   elif command -v dpkg-query >/dev/null; then run dpkg-query -W;
   else echo 'UNKNOWN: no supported local package database'; status=3; fi;;
  cron) run systemctl list-timers --all --no-pager; run crontab -l;;
  logs) run journalctl --since '-1 day' -n 100 --no-pager;;
  -h|--help) usage; exit 0;;
  *) usage; exit 2;;
 esac
done
exit "$status"
