#!/bin/sh
# Ritder's run history, kept across restarts so a problem can be reported afterwards.
# Sourced by launch.sh. Expects $progdir, $USERDATA and $UPD.
#
#   userdata/ritder.log    one line per start/exit, plus the tail of a crashed run (kept, trimmed)
#   userdata/crash.log     everything the app printed during the current run (overwritten)
#   userdata/crash.log.1   the same for the previous run
#   userdata/crashed       last run ended badly; the app says so and offers to collect the logs

RITDER_LOG_KEEP_LINES=800

ritder_note() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$USERDATA/ritder.log"
}

ritder_version() {
    sed -n 's/.*version = "\([^"]*\)".*/\1/p' "$progdir/frontend/ritder/build_info.lua" 2>/dev/null | head -1
}

# Keeps the previous run's output, and stops ritder.log from growing forever.
ritder_rotate_logs() {
    if [ -f "$USERDATA/crash.log" ]; then
        mv -f "$USERDATA/crash.log" "$USERDATA/crash.log.1"
    fi
    if [ -f "$USERDATA/ritder.log" ]; then
        lines=$(wc -l < "$USERDATA/ritder.log" 2>/dev/null || echo 0)
        if [ "$lines" -gt "$RITDER_LOG_KEEP_LINES" ]; then
            tail -n "$RITDER_LOG_KEEP_LINES" "$USERDATA/ritder.log" > "$USERDATA/ritder.log.tmp" &&
                mv -f "$USERDATA/ritder.log.tmp" "$USERDATA/ritder.log"
        fi
    fi
}

ritder_session_start() {
    ritder_note "mở app: Ritder $(ritder_version), kernel $(uname -r 2>/dev/null), $(free -m 2>/dev/null | sed -n '2s/.*/RAM &/p')"
}

# $1: the exit code of the app. 42 = update installed, 85 = KOReader restart, 0 = normal exit.
ritder_session_end() {
    case "$1" in
        0)  ritder_note "thoát bình thường" ;;
        42) ritder_note "thoát để cài bản cập nhật (mã 42)" ;;
        85) ritder_note "khởi động lại theo yêu cầu (mã 85)" ;;
        *)  ritder_note "thoát bất thường (mã $1)"
            echo "$1" > "$USERDATA/crashed"
            echo "--- 40 dòng cuối của crash.log ---" >> "$USERDATA/ritder.log"
            tail -n 40 "$USERDATA/crash.log" >> "$USERDATA/ritder.log" 2>/dev/null
            echo "--- hết ---" >> "$USERDATA/ritder.log"
            ;;
    esac
}
