#!/usr/bin/env bash
# Fail-closed file backups. Live databases require application-specific backups.
backup_preflight() {
    local source=$1 destination=$2 actual needed available tool
    for tool in realpath findmnt tar gzip df du sha256sum mktemp flock; do
        command -v "$tool" >/dev/null || { echo "Missing dependency: $tool" >&2; return 1; }
    done
    SOURCE_DIR=$(realpath -e -- "$source") || return 1
    BACKUP_DIR=$(realpath -e -- "$destination") || return 1
    [[ -d $SOURCE_DIR && -d $BACKUP_DIR && $SOURCE_DIR != / && $BACKUP_DIR != / ]] || return 1
    [[ $BACKUP_DIR != "$SOURCE_DIR" && $BACKUP_DIR != "$SOURCE_DIR/"* ]] || {
        echo 'Backup destination must be outside the source tree' >&2; return 1;
    }
    : "${EXPECTED_BACKUP_SOURCE:?Set EXPECTED_BACKUP_SOURCE to the reviewed findmnt SOURCE for this destination}"
    actual=$(findmnt -n -o SOURCE -T "$BACKUP_DIR") || return 1
    [[ $actual == "$EXPECTED_BACKUP_SOURCE" ]] || { echo 'Backup mount identity mismatch' >&2; return 1; }
    [[ ! -L $destination ]] || { echo 'Symlink backup destinations are not supported' >&2; return 1; }
    needed=$(du -sb -- "$SOURCE_DIR" | cut -f1) || return 1
    available=$(df -B1 --output=avail -- "$BACKUP_DIR" | awk 'NR==2 {print $1}') || return 1
    [[ $needed =~ ^[0-9]+$ && $available =~ ^[0-9]+$ ]] || return 1
    (( available > needed + needed / 10 + 524288000 )) || { echo 'Insufficient backup headroom' >&2; return 1; }
}
publish_verified_archive() {
    local partial=$1 target=$2 checksum
    [[ ! -e $target && ! -L $target && ! -e ${target}.sha256 && ! -L ${target}.sha256 ]] || {
        echo 'Refusing existing archive or checksum' >&2; return 1;
    }
    gzip -t -- "$partial" && tar -tzf "$partial" >/dev/null || return 1
    checksum=$(mktemp "${target}.sha256.partial.XXXXXX") || return 1
    # Hash through the final pathname only after no-clobber archive publication.
    ln -T -- "$partial" "$target" || return 1
    sha256sum -- "$target" > "$checksum" || return 1
    ln -T -- "$checksum" "${target}.sha256" || return 1
    rm -- "$partial" "$checksum" || return 1
}
create_verified_archive() {
    local target=$1 partial
    [[ ! -e $target && ! -L $target && ! -e ${target}.sha256 && ! -L ${target}.sha256 ]] || {
        echo 'Refusing existing archive or checksum' >&2; return 1;
    }
    partial=$(mktemp "${target}.partial.XXXXXX") || return 1
    if ! tar -czf "$partial" -C "$(dirname -- "$SOURCE_DIR")" -- "$(basename -- "$SOURCE_DIR")"; then
        echo "Backup failed; incomplete artifact retained: $partial" >&2; return 1
    fi
    publish_verified_archive "$partial" "$target" || return 1
    printf 'Verified archive: %s (restore test still required)\n' "$target"
}
preview_retention() {
    local dir=$1 pattern=$2 days=$3
    [[ $days =~ ^[1-9][0-9]*$ ]] || return 1
    printf 'Retention candidates only; review before any separate deletion:\n'
    find "$dir" -maxdepth 1 -type f -name "$pattern" -mtime "+$days" -print
}
