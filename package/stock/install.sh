#!/bin/sh
# Applies a staged Ritder update, and puts the previous files back when asked.
# Sourced by launch.sh before the app starts, so no file being replaced is open,
# mapped or running: on the SD card's FAT/exFAT, replacing a file that the app is
# executing can block forever (this is what hung 0.1.2 on the device).
#
# Expects: $progdir (the app directory) and $UPD ($progdir/userdata/update).
# Files it works with, all inside $UPD:
#   ready       version of an unpacked update waiting to be applied (written by the app)
#   staging/    the unpacked new version
#   installing  set while files are being swapped (a leftover means it was cut short)
#   backup/     the files this update replaced
#   added.txt   the files this update created
#   pending     version waiting to be confirmed by a successful start
#   failed      the swap failed; the app reports it and the old version keeps running

ritder_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$USERDATA/update.log"
}

# Puts back the files replaced by the last update and deletes the ones it added.
ritder_restore_backup() {
    if [ -f "$UPD/added.txt" ]; then
        while IFS= read -r f; do
            case "$f" in
                ""|/*|*..*) ;;
                *) rm -f "$progdir/$f" ;;
            esac
        done < "$UPD/added.txt"
    fi
    if [ -d "$UPD/backup" ]; then
        find "$UPD/backup" -type f | sed "s|^$UPD/backup/||" > "$UPD/restore.txt"
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            mkdir -p "$progdir/$(dirname "$f")"
            rm -f "$progdir/$f"
            mv -f "$UPD/backup/$f" "$progdir/$f"
        done < "$UPD/restore.txt"
    fi
    rm -rf "$UPD/backup" "$UPD/staging"
    rm -f "$UPD/added.txt" "$UPD/pending" "$UPD/installing" "$UPD/ready" "$UPD/restore.txt"
}

# Moves the unpacked update into the app directory, keeping what it replaces.
ritder_install_staged() {
    version=$(cat "$UPD/ready" 2>/dev/null)
    [ -n "$version" ] || version="?"
    ritder_log "installing update $version"
    rm -rf "$UPD/backup"
    mkdir -p "$UPD/backup"
    : > "$UPD/added.txt"
    echo "$version" > "$UPD/installing"
    find "$UPD/staging" -type f | sed "s|^$UPD/staging/||" > "$UPD/files.txt"

    ritder_ok=1
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in /*|*..*) continue ;; esac
        dst="$progdir/$f"
        if [ -e "$dst" ]; then
            mkdir -p "$UPD/backup/$(dirname "$f")"
            mv -f "$dst" "$UPD/backup/$f" || { ritder_ok=0; break; }
        else
            echo "$f" >> "$UPD/added.txt"
        fi
        mkdir -p "$(dirname "$dst")"
        mv -f "$UPD/staging/$f" "$dst" || { ritder_ok=0; break; }
    done < "$UPD/files.txt"

    rm -f "$UPD/files.txt"
    if [ "$ritder_ok" -ne 1 ]; then
        ritder_log "update $version failed while replacing files, putting the old ones back"
        ritder_restore_backup
        echo "$version" > "$UPD/failed"
        return 1
    fi
    echo "$version" > "$UPD/pending"
    rm -rf "$UPD/staging"
    rm -f "$UPD/ready" "$UPD/installing" "$UPD/package.tar.gz"
    ritder_log "update $version installed, waiting for a successful start"
    return 0
}
