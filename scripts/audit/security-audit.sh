#!/usr/bin/env bash
# Informational local audit. 0 collected, 2 usage, 3 incomplete. No clearance claim.
set -uo pipefail
export LC_ALL=C
paths=(); count=10; status=0
usage() { echo 'security-audit.sh [--scan-path ABSOLUTE_PATH] [--failed-login-count 1..1000]'; }
while (($#)); do
 case $1 in
  --scan-path) (($#>=2)) || { usage; exit 2; }; [[ $2 == /* && -d $2 ]] || exit 2; paths+=("$2"); shift 2;;
  --failed-login-count) (($#>=2)) || { usage; exit 2; }; [[ $2 =~ ^[1-9][0-9]{0,3}$ ]] && ((10#$2<=1000)) || exit 2; count=$2; shift 2;;
  -h|--help) usage; exit 0;;
  *) usage; exit 2;;
 esac
done
collect() { timeout -k 5 30 "$@" || { echo "UNKNOWN: $1 collection failed" >&2; return 3; }; }
echo '--- Listening ports ---'
collect ss -tulnp || status=3
echo '--- UID zero accounts ---'
collect awk -F: '$3==0{print $1}' /etc/passwd || status=3
echo '--- Sudoers (review output; includes may require separate review) ---'
for f in /etc/sudoers /etc/sudoers.d/*; do
 [[ -f $f ]] || continue
 if ! collect awk '!/^[[:space:]]*(#|$)/' "$f"; then status=3; fi
done
[[ -r /etc/sudoers ]] || { echo 'UNKNOWN: sudoers unavailable'; status=3; }
echo '--- Failed SSH observations in retained last-day journal ---'
if journal=$(collect journalctl -u sshd -u ssh --since '-1 day' --no-pager); then
 awk 'tolower($0) ~ /failed password/' <<< "$journal" | tail -n "$count"
else status=3; fi
if ((${#paths[@]}==0)); then echo 'NOT REQUESTED: filesystem permission walk'; fi
for p in "${paths[@]}"; do
 echo "--- World writable files under $p (one filesystem) ---"
 collect find "$p" -xdev -type f -perm -0002 -print || status=3
done
echo 'Informational observations only; not a complete security assessment.'
exit "$status"
