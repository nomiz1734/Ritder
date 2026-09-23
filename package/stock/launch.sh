#!/bin/sh
# Ritder launcher for the TrimUI stock OS (Apps/Ritder).
#
# The KOReader binaries need glibc >= 2.35, newer than the firmware's, so they run through
# the glibc shipped in sys/ (explicit loader + --library-path; nothing is exported through
# LD_LIBRARY_PATH, so the firmware tools KOReader calls keep using the system glibc).
#
# Exit codes: 42 = an OTA update was installed (re-run the new launch.sh),
#             85 = KOReader's own "restart" (run again).
# A non-zero exit while userdata/update/pending exists means the fresh update does not start:
# the files it replaced are put back from userdata/update/backup (see docs/OTA-co-che-cap-nhat.md).

progdir=$(cd "$(dirname "$0")" && pwd)
cd "$progdir" || exit 1

USERDATA="$progdir/userdata"
UPD="$USERDATA/update"
mkdir -p "$USERDATA"

export RITDER_DIR="$progdir"
export RITDER_DEVICE=trimui-brick-pro
export KO_HOME="$USERDATA"
export RITDER_HOME_DIR="${RITDER_HOME_DIR:-/mnt/SDCARD/Books}"
export LC_ALL=C.UTF-8
mkdir -p "$RITDER_HOME_DIR" 2>/dev/null

LOADER="$progdir/sys/ld-linux-aarch64.so.1"
LIBPATH="$progdir/sys:$progdir/libs"
CPU=/sys/devices/system/cpu/cpu0/cpufreq

# ritder_log, ritder_install_staged and ritder_restore_backup.
. "$progdir/install.sh"
# ritder_note, ritder_rotate_logs, ritder_session_start and ritder_session_end.
. "$progdir/logging.sh"

# First start (not a re-run after an update or a rollback).
if [ -z "${RITDER_RESTARTED:-}" ]; then
    # Render pages at full speed when needed, idle low otherwise.
    RITDER_OLD_GOV=$(cat "$CPU/scaling_governor" 2>/dev/null)
    export RITDER_OLD_GOV
    if grep -q schedutil "$CPU/scaling_available_governors" 2>/dev/null; then
        echo schedutil > "$CPU/scaling_governor" 2>/dev/null
    elif grep -q ondemand "$CPU/scaling_available_governors" 2>/dev/null; then
        echo ondemand > "$CPU/scaling_governor" 2>/dev/null
    fi
    # First run: seed the reader settings (Vietnamese UI, D-pad left/right turn pages...).
    if [ ! -f "$USERDATA/settings.reader.lua" ] && [ -f "$progdir/defaults/settings.reader.lua" ]; then
        sed "s#@HOME_DIR@#$RITDER_HOME_DIR#g" "$progdir/defaults/settings.reader.lua" > "$USERDATA/settings.reader.lua"
    fi
fi

# An install that was cut short (power loss, crash) leaves a half-updated app: undo it.
if [ -f "$UPD/installing" ]; then
    ritder_log "update $(cat "$UPD/installing") was interrupted, restoring the previous files"
    ritder_restore_backup
fi

# The app unpacked an update and asked for a restart: swap the files in now, while
# nothing is running out of them.
if [ -f "$UPD/ready" ] && [ -d "$UPD/staging" ]; then
    ritder_install_staged
fi

chmod +x "$LOADER" "$progdir/luajit" "$progdir/sdcv" "$progdir/sdcv.bin" 2>/dev/null
if ! "$LOADER" --version > /dev/null 2>&1; then
    echo "$(date) cannot execute $LOADER (SD card mounted noexec?)" >> "$USERDATA/launch.log"
    exit 1
fi

while true; do
    ritder_rotate_logs
    ritder_session_start
    "$LOADER" --library-path "$LIBPATH" "$progdir/luajit" reader.lua > "$USERDATA/crash.log" 2>&1
    code=$?
    ritder_session_end "$code"
    if [ "$code" -eq 42 ]; then
        # An update was installed: start over with the new launcher and binaries.
        export RITDER_RESTARTED=1
        exec /bin/sh "$progdir/launch.sh"
    fi
    if [ "$code" -eq 85 ]; then
        continue
    fi
    if [ "$code" -ne 0 ] && [ -f "$UPD/pending" ] && [ -d "$UPD/backup" ]; then
        # The new version failed before confirming it works: go back to the previous one.
        version=$(cat "$UPD/pending")
        ritder_log "update $version failed (exit $code), rolled back"
        tail -n 40 "$USERDATA/crash.log" >> "$USERDATA/update.log" 2>/dev/null
        ritder_restore_backup
        echo "$version" > "$UPD/rolled_back"
        export RITDER_RESTARTED=1
        exec /bin/sh "$progdir/launch.sh"
    fi
    if [ "$code" -ne 0 ]; then
        cp -f "$USERDATA/crash.log" "$USERDATA/launch.log" 2>/dev/null
    fi
    break
done

if [ -n "${RITDER_OLD_GOV:-}" ]; then
    echo "$RITDER_OLD_GOV" > "$CPU/scaling_governor" 2>/dev/null
fi
