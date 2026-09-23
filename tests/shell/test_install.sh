#!/bin/sh
# Tests for package/stock/install.sh: the file swap launch.sh does before the app starts.
# Run with tests/run_shell_tests.py (executes this inside the WSL1 distro).
set -u

INSTALL_SH=${1:?usage: test_install.sh <path to install.sh>}
fails=0
tests=0

check() { # check <description> <expected> <actual>
    tests=$((tests + 1))
    if [ "$2" = "$3" ]; then
        echo "  ok    $1"
    else
        fails=$((fails + 1))
        echo "  FAIL  $1: expected [$2], got [$3]"
    fi
}

setup() { # setup: a fake app dir with a staged update
    progdir=$(mktemp -d)
    USERDATA="$progdir/userdata"
    UPD="$USERDATA/update"
    mkdir -p "$UPD/staging/frontend" "$progdir/frontend" "$progdir/libs"
    echo "old reader" > "$progdir/reader.lua"
    echo "old luajit" > "$progdir/luajit"
    echo "old lib" > "$progdir/libs/lib.so"
    echo "my settings" > "$USERDATA/settings.reader.lua"
    echo "new reader" > "$UPD/staging/reader.lua"
    echo "new luajit" > "$UPD/staging/luajit"
    echo "brand new" > "$UPD/staging/frontend/new.lua"
    echo "0.2.0" > "$UPD/ready"
    # shellcheck source=/dev/null
    . "$INSTALL_SH"
}

cleanup() { rm -rf "$progdir"; }

# --- a normal install ---------------------------------------------------------
setup
ritder_install_staged
check "install succeeds" "0" "$?"
check "file replaced" "new reader" "$(cat "$progdir/reader.lua")"
check "file added" "brand new" "$(cat "$progdir/frontend/new.lua")"
check "untouched file kept" "old lib" "$(cat "$progdir/libs/lib.so")"
check "user settings kept" "my settings" "$(cat "$USERDATA/settings.reader.lua")"
check "old file backed up" "old reader" "$(cat "$UPD/backup/reader.lua")"
check "added file listed" "frontend/new.lua" "$(cat "$UPD/added.txt")"
check "pending written" "0.2.0" "$(cat "$UPD/pending")"
check "staging removed" "no" "$([ -d "$UPD/staging" ] && echo yes || echo no)"
check "ready removed" "no" "$([ -f "$UPD/ready" ] && echo yes || echo no)"
check "installing marker removed" "no" "$([ -f "$UPD/installing" ] && echo yes || echo no)"

# --- rolling back that install ------------------------------------------------
ritder_restore_backup
check "rollback restores the old file" "old reader" "$(cat "$progdir/reader.lua")"
check "rollback restores the old binary" "old luajit" "$(cat "$progdir/luajit")"
check "rollback removes an added file" "no" "$([ -f "$progdir/frontend/new.lua" ] && echo yes || echo no)"
check "rollback clears pending" "no" "$([ -f "$UPD/pending" ] && echo yes || echo no)"
check "rollback keeps user settings" "my settings" "$(cat "$USERDATA/settings.reader.lua")"
cleanup

# --- an install that fails half-way ------------------------------------------
setup
rm -rf "$progdir/frontend"
: > "$progdir/frontend" # a file where the update needs a directory: the move fails
ritder_install_staged
check "install reports failure" "1" "$?"
check "old file put back" "old reader" "$(cat "$progdir/reader.lua")"
check "old binary put back" "old luajit" "$(cat "$progdir/luajit")"
check "failure recorded" "0.2.0" "$(cat "$UPD/failed")"
check "no pending after failure" "no" "$([ -f "$UPD/pending" ] && echo yes || echo no)"
check "install.log written" "yes" "$([ -s "$USERDATA/update.log" ] && echo yes || echo no)"
cleanup

# --- an install cut short (power loss) then undone at the next start -----------
setup
echo "0.2.0" > "$UPD/installing"
mkdir -p "$UPD/backup"
echo "old reader" > "$UPD/backup/reader.lua"
echo "half new" > "$progdir/reader.lua"
echo "frontend/new.lua" > "$UPD/added.txt"
echo "half new" > "$progdir/frontend/new.lua"
ritder_restore_backup
check "interrupted install undone" "old reader" "$(cat "$progdir/reader.lua")"
check "interrupted install removed its new file" "no" "$([ -f "$progdir/frontend/new.lua" ] && echo yes || echo no)"
check "markers cleared" "no" "$([ -f "$UPD/installing" ] && echo yes || echo no)"
cleanup

# --- the run history (logging.sh) ----------------------------------------------
setup
LOGGING_SH=$(dirname "$INSTALL_SH")/logging.sh
mkdir -p "$progdir/frontend/ritder"
echo 'return { version = "0.1.4", }' > "$progdir/frontend/ritder/build_info.lua"
# shellcheck source=/dev/null
. "$LOGGING_SH"
echo "old run" > "$USERDATA/crash.log"
ritder_rotate_logs
check "previous run's log kept" "old run" "$(cat "$USERDATA/crash.log.1")"
ritder_session_start
check "start noted with the version" "yes" "$(grep -c "Ritder 0.1.4" "$USERDATA/ritder.log" > /dev/null && echo yes || echo no)"
echo "boom" > "$USERDATA/crash.log"
ritder_session_end 1
check "bad exit noted" "yes" "$(grep -q "thoát bất thường (mã 1)" "$USERDATA/ritder.log" && echo yes || echo no)"
check "crash marker written" "1" "$(cat "$USERDATA/crashed")"
check "crash output copied into the history" "yes" "$(grep -q "boom" "$USERDATA/ritder.log" && echo yes || echo no)"
ritder_session_end 42
check "restart for an update is not a crash" "no" "$([ -f "$USERDATA/crashed.42" ] && echo yes || echo no)"
i=0
while [ "$i" -lt 900 ]; do echo "line $i" >> "$USERDATA/ritder.log"; i=$((i + 1)); done
ritder_rotate_logs
check "history trimmed" "800" "$(wc -l < "$USERDATA/ritder.log" | tr -d ' ')"
cleanup

echo "$((tests - fails))/$tests passed"
[ "$fails" -eq 0 ]
