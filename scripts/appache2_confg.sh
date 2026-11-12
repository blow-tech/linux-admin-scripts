#!/usr/bin/env bash
# Default is a plan. Installation can start Apache via package maintainer scripts.
# Firewall activation is deliberately a separate, reviewed infrastructure change.
set -euo pipefail
[[ -r /etc/os-release ]] || exit 1
source /etc/os-release
case ${ID:-} in ubuntu|debian) ;; *) echo 'Only Ubuntu/Debian supported' >&2; exit 2 ;; esac
[[ $# -le 1 && ${1:---plan} =~ ^--(plan|install)$ ]] || exit 2
printf '%s\n' 'Plan: install apache2. Package installation may start the service.' \
 'Firewall prerequisite: review existing UFW policy, actual SSH port/source and out-of-band access.' \
 'This script does not install, activate or modify the firewall.'
if [[ ${1:---plan} == --install ]]; then
    (( EUID == 0 )) || { echo '--install requires root' >&2; exit 1; }
    apt-get install --yes apache2
    apache2ctl configtest
    systemctl is-active --quiet apache2
    echo 'Apache installed; configuration valid and service active.'
fi
