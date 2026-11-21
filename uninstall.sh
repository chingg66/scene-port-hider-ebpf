#!/system/bin/sh

PIDFILE="/data/adb/hideport_loader.pid"

if [ -f "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE" 2>/dev/null)"
    [ -n "$PID" ] && kill "$PID" 2>/dev/null
    rm -f "$PIDFILE"
fi

if command -v pidof >/dev/null 2>&1; then
    for p in $(pidof hideport_loader 2>/dev/null); do
        kill "$p" 2>/dev/null
    done
fi

rm -rf /data/adb/hideport_loader.lock /dev/hideport_loader.pid /dev/hideport_loader.lock
