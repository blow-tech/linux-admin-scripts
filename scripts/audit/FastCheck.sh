#!/usr/bin/env bash
# Scoped connectivity/TLS inspection. No DoS, exploit or vulnerability NSE categories.
set -euo pipefail
[[ $# == 2 && $2 == --scan ]] || { echo 'Usage: FastCheck.sh <DNS-name-or-IPv4> --scan (requires target-owner approval)' >&2; exit 2; }
host=$1
[[ ${#host} -le 253 && $host =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && $host != *..* ]] || exit 2
if [[ $host =~ ^[0-9.]+$ ]]; then
    [[ $host =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || exit 2
    IFS=. read -r -a octets <<< "$host"
    for octet in "${octets[@]}"; do (( 10#$octet <= 255 )) || exit 2; done
fi
PS3='Select check: '
select choice in 'HTTPS headers' 'TLS certificate' 'TCP port' 'Quit'; do
    case $choice in
        'HTTPS headers') curl --connect-timeout 5 --max-time 20 --head -- "https://$host" || exit $? ;;
        'TLS certificate') timeout 20 openssl s_client -connect "$host:443" -servername "$host" -verify_return_error -verify_hostname "$host" </dev/null || exit $? ;;
        'TCP port')
            read -r -p 'Port (1-65535): ' port
            [[ $port =~ ^[0-9]{1,5}$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 )) || { echo 'Invalid port' >&2; continue; }
            timeout 5 nc -vz -w 3 "$host" "$((10#$port))" || echo 'Connection failed; host availability unknown' >&2 ;;
        Quit) break ;;
        *) echo 'Invalid option' >&2 ;;
    esac
done
