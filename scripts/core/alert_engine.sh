#!/usr/bin/env bash
# Local alerts only: no mail/webhook destination is assumed or contacted.
# Sourcing this file performs no work.
alert_emit() { printf '%s [%s] %s: %s -- %s\n' "$(date -Is)" "$1" "$2" "$3" "$4" >&2; }
alert_info() { alert_emit INFO "$@"; }
alert_warning() { alert_emit WARNING "$@"; }
alert_critical() { alert_emit CRITICAL "$@"; }
lock_script() {
    local name=$1 dir=${ADMIN_SCRIPTS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/admin-scripts}
    [[ $name =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
    command -v flock >/dev/null || { echo 'flock is required' >&2; return 1; }
    (umask 077; mkdir -p -- "$dir") || return 1
    [[ ! -L $dir && -O $dir && $(stat -c %a -- "$dir") == 700 ]] || {
        echo 'State directory must be owned by this user, mode 700, and not a symlink' >&2; return 1;
    }
    [[ ! -L $dir/$name.lock ]] || return 1
    exec {ADMIN_SCRIPTS_LOCK_FD}>"$dir/$name.lock" || return 1
    flock -n "$ADMIN_SCRIPTS_LOCK_FD" || { echo "Another $name run holds the lock" >&2; return 1; }
}
rotate_log() {
    local path=$1 limit_kib=$2 archive
    [[ ! -L $path && $limit_kib =~ ^[0-9]+$ ]] || return 1
    if [[ -f $path ]] && (( $(stat -c %s -- "$path") > limit_kib * 1024 )); then
        archive=$(mktemp "${path}.$(date +%Y%m%dT%H%M%S).XXXXXX") || return 1
        mv -- "$path" "$archive" || return 1
        # Retain evidence for a separately configured retention policy.
    fi
}
