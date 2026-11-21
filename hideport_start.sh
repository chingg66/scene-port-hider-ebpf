#!/system/bin/sh

MODDIR=${0%/*}
CONF="$MODDIR/hideport.conf"
LOADER="$MODDIR/bin/hideport_loader"
LOG="$MODDIR/hideport.log"
PIDFILE="/dev/hideport_loader.pid"
LOCKDIR="/dev/hideport_loader.lock"

PKG="com.omarea.vtools"
PORTS="8788 8765"
ENABLE_EBPF=1
WAIT_FOR_PROCESS=0

[ -f "$CONF" ] && . "$CONF"
START_CONTEXT="${1:-manual}"

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" >> "$LOG"
}

is_running() {
    local pid
    if [ -f "$PIDFILE" ]; then
        pid="$(cat "$PIDFILE" 2>/dev/null)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    pidof hideport_loader >/dev/null 2>&1
}

if ! mkdir "$LOCKDIR" 2>/dev/null; then
    sleep 2
    if is_running; then
        log_msg "$START_CONTEXT" "hideport_loader is already running"
        exit 0
    fi
    # Stale lock left behind by a killed run: reclaim it instead of giving up.
    rmdir "$LOCKDIR" 2>/dev/null
    mkdir "$LOCKDIR" 2>/dev/null
fi

cleanup_lock() {
    # Keep the lock while a loader is alive so a second boot-stage start bails out.
    is_running || rmdir "$LOCKDIR" 2>/dev/null
}

trap cleanup_lock EXIT INT TERM

get_app_uid() {
    local uid

    uid="$(stat -c "%u" "/data/data/$PKG" 2>/dev/null)"
    if [ -n "$uid" ]; then
        echo "$uid"
        return 0
    fi

    uid="$(stat -c "%u" "/data/user/0/$PKG" 2>/dev/null)"
    if [ -n "$uid" ]; then
        echo "$uid"
        return 0
    fi

    uid="$(cmd package list packages -U --user 0 2>/dev/null | awk -v p="package:$PKG" '$0 ~ p {for(i=1;i<=NF;i++) if ($i ~ /^uid:/) {sub("uid:","",$i); print $i; exit}}')"
    if [ -n "$uid" ]; then
        echo "$uid"
        return 0
    fi

    uid="$(dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*userId=\([0-9][0-9]*\).*/\1/p' | head -n 1)"
    if [ -n "$uid" ]; then
        echo "$uid"
        return 0
    fi

    return 1
}

wait_for_uid() {
    local uid
    local i=0

    while [ "$i" -lt 180 ]; do
        uid="$(get_app_uid)"
        if [ -n "$uid" ]; then
            echo "$uid"
            return 0
        fi
        i=$((i + 1))
        sleep 1
    done

    return 1
}

wait_for_process_if_requested() {
    [ "$WAIT_FOR_PROCESS" = "1" ] || return 0

    while ! pidof "$PKG" >/dev/null 2>&1; do
        sleep 1
    done
    sleep 3
}

if [ "$ENABLE_EBPF" != "1" ]; then
    log_msg "$START_CONTEXT" "eBPF loader disabled by config"
    exit 0
fi

if is_running; then
    log_msg "$START_CONTEXT" "hideport_loader is already running"
    exit 0
fi

if [ ! -x "$LOADER" ]; then
    chmod 0755 "$LOADER" 2>/dev/null
fi

if [ ! -x "$LOADER" ]; then
    log_msg "$START_CONTEXT" "missing executable: $LOADER"
    exit 1
fi

APP_UID="$(wait_for_uid)"
if [ -z "$APP_UID" ]; then
    log_msg "$START_CONTEXT" "failed to resolve UID for package $PKG"
    exit 1
fi

wait_for_process_if_requested

ARGS=""
for port in $PORTS; do
    ARGS="$ARGS --port $port"
done
ARGS="$ARGS --uid $APP_UID"

log_msg "$START_CONTEXT" "starting hideport_loader for package $PKG uid $APP_UID ports $PORTS"
"$LOADER" $ARGS >> "$LOG" 2>&1 &
echo "$!" > "$PIDFILE"
