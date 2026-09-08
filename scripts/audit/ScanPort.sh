#!/usr/bin/env bash
# Authorized, single-host TCP connectivity checks only; never infer host-down from ICMP.
set -euo pipefail
[[ $# == 2 && $2 == --scan ]] || { echo 'Usage: ScanPort.sh <IPv4> --scan (requires target-owner approval)' >&2; exit 2; }
ip=$1
[[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || exit 2
IFS=. read -r -a octets <<< "$ip"
for octet in "${octets[@]}"; do (( 10#$octet <= 255 )) || exit 2; done
command -v nc >/dev/null
command -v timeout >/dev/null
ports=(20 21 22 23 25 53 80 110 123 135 139 143 443 445 993 995 1433 1521 3306 3389 5432 5900 8080 8443)
printf 'Checking %s TCP ports on %s\n' "${#ports[@]}" "$ip"
for port in "${ports[@]}"; do
    if timeout 4 nc -z -w 2 -n "$ip" "$port"; then
        printf '%s OPEN\n' "$port"
    else
        status=$?
        case $status in
            1|124) printf '%s CLOSED/FILTERED/TIMED OUT\n' "$port" ;;
            *) echo "Probe tool failed (exit $status)" >&2; exit "$status" ;;
        esac
    fi
done
