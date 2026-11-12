#!/usr/bin/env bash
# Usage: Nginx_create.sh <dns-name> <reviewed-template> <owner> [--apply] [--reload]
# Default: print proposed configuration only. --apply installs after baseline validation.
set -euo pipefail
[[ $# -ge 3 ]] || { echo 'Supply DNS name, template and existing service owner' >&2; exit 2; }
vhost=$1 template=$2 owner=$3; shift 3
apply=false reload=false
for arg in "$@"; do
    case $arg in --apply) apply=true ;; --reload) reload=true ;; *) echo "Unknown option: $arg" >&2; exit 2 ;; esac
done
[[ ${#vhost} -le 253 && $vhost == *.* && $vhost =~ ^[a-zA-Z0-9.-]+$ ]] || exit 2
IFS=. read -r -a labels <<< "$vhost"
[[ $vhost != *. ]] || exit 2
for label in "${labels[@]}"; do
    [[ ${#label} -le 63 && $label =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] || exit 2
done
[[ $owner =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ && -f $template && ! -L $template ]] || exit 2
id "$owner" >/dev/null
config=$(sed "s/{{DOMAIN}}/$vhost/g" "$template")
[[ $config != *'{{'* ]] || { echo 'Unresolved template placeholder' >&2; exit 2; }
if ! $apply; then
    printf '%s\n' "$config"
    echo 'PREVIEW only. Review template, certificate paths and change window before --apply.' >&2
    exit 0
fi
(( EUID == 0 )) || { echo '--apply requires root' >&2; exit 1; }
for parent in /var /var/www /etc /etc/nginx /etc/nginx/sites-available /etc/nginx/sites-enabled; do
    [[ -d $parent && ! -L $parent ]] || { echo "Missing or symlink parent: $parent" >&2; exit 1; }
done
available=/etc/nginx/sites-available/$vhost
enabled=/etc/nginx/sites-enabled/$vhost
webroot=/var/www/$vhost
for path in "$available" "$enabled" "$webroot"; do
    [[ ! -e $path && ! -L $path ]] || { echo "Refusing existing target: $path" >&2; exit 1; }
done
nginx -t
stage=$(mktemp /etc/nginx/sites-available/.stage.XXXXXX)
made_available=false made_enabled=false made_root=false committed=false reload_attempted=false
rollback() {
    local status=$?
    if ! $committed; then
        $made_enabled && rm -- "$enabled"
        $made_available && rm -- "$available"
        $made_root && rmdir -- "$webroot"
        if $reload_attempted; then
            nginx -t && systemctl reload nginx || echo 'CRITICAL: rollback reload failed; operator action required' >&2
        fi
    fi
    rm -f -- "$stage"
    return "$status"
}
trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '%s\n' "$config" > "$stage"
chmod 644 "$stage"
mkdir -- "$webroot"; made_root=true
chown -- "$owner:$(id -gn "$owner")" "$webroot"
ln -- "$stage" "$available"; made_available=true
ln -s -- "$available" "$enabled"; made_enabled=true
nginx -t
if $reload; then
    reload_attempted=true
    systemctl reload nginx
fi
committed=true
printf 'Configuration validated and installed: %s; reload requested=%s\n' "$vhost" "$reload"
