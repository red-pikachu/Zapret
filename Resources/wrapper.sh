#!/bin/bash
# Zapret2Mac wrapper — tpws transparent proxy via PF anchors
# Requires root (called with sudo from the app).

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TPWS="$DIR/tpws"
PIDFILE="/tmp/zapret_tpws.pid"
LOGFILE="/tmp/zapret2.log"
TPWS_PORT=988
PF_MAIN="/etc/pf.conf"
PF_ANCHOR_DIR="/etc/pf.anchors"

COMMAND=$1
shift
DESYNC_ARGS="$*"

# Patch /etc/pf.conf to reference our anchors (idempotent).
patch_pf_conf() {
    [ -f "$PF_MAIN" ] || return 1
    local patched=0

    if ! grep -q '^rdr-anchor "zapret"$' "$PF_MAIN"; then
        sed -i '' -e '/^rdr-anchor "com\.apple\/\*"$/i \
rdr-anchor "zapret"
' "$PF_MAIN" && patched=1
    fi

    if ! grep -q '^anchor "zapret"$' "$PF_MAIN"; then
        sed -i '' -e '/^anchor "com\.apple\/\*"$/i \
anchor "zapret"
' "$PF_MAIN" && patched=1
    fi

    if [ "$patched" = "1" ]; then
        echo "Patched $PF_MAIN, reloading root ruleset..." >> "$LOGFILE"
        pfctl -qf "$PF_MAIN" >> "$LOGFILE" 2>&1
    fi
}

# Write anchor files and load them into PF.
load_pf_anchors() {
    mkdir -p "$PF_ANCHOR_DIR"

    cat > "$PF_ANCHOR_DIR/zapret" << 'ANCHOR_EOF'
table <nozapret> persist
rdr-anchor "/zapret-v4" inet to !<nozapret>
anchor "/zapret-v4" inet to !<nozapret>
ANCHOR_EOF

    cat > "$PF_ANCHOR_DIR/zapret-v4" << RULES_EOF
rdr on lo0 inet proto tcp from !127.0.0.0/8 to any port {80,443} -> 127.0.0.1 port $TPWS_PORT
pass out route-to (lo0 127.0.0.1) inet proto tcp from !127.0.0.0/8 to any port {80,443} user { >root }
block drop out quick proto udp from any to any port 443
RULES_EOF

    pfctl -qa zapret    -f "$PF_ANCHOR_DIR/zapret"    >> "$LOGFILE" 2>&1
    pfctl -qa zapret-v4 -f "$PF_ANCHOR_DIR/zapret-v4" >> "$LOGFILE" 2>&1
}

# Remove our anchors from PF (traffic flows normally again).
clear_pf_anchors() {
    pfctl -qa zapret-v4 -F all >> "$LOGFILE" 2>&1
    pfctl -qa zapret    -F all >> "$LOGFILE" 2>&1
}

case "$COMMAND" in
    start)
        echo "$(date) - Starting Zapret2 (tpws). Strategy: $DESYNC_ARGS" > "$LOGFILE"

        # Stop previous instance if any (be aggressive).
        if [ -f "$PIDFILE" ]; then
            OLD_PID=$(cat "$PIDFILE")
            echo "Stopping old instance (PID $OLD_PID)..." >> "$LOGFILE"
            kill "$OLD_PID" 2>/dev/null
            for i in {1..10}; do
                kill -0 "$OLD_PID" 2>/dev/null || break
                sleep 0.2
            done
            kill -9 "$OLD_PID" 2>/dev/null
            rm -f "$PIDFILE"
        fi
        
        # Ensure no other tpws is on our port (just in case)
        # Note: We only kill the root one to not touch the SOCKS5 proxy
        lsof -ti tcp:$TPWS_PORT | xargs kill -9 2>/dev/null || true

        # Enable PF, patch pf.conf, load anchors.
        pfctl -qe >> "$LOGFILE" 2>&1
        patch_pf_conf
        clear_pf_anchors
        load_pf_anchors

        # Launch tpws as root (--user=root prevents privilege drop).
        echo "Launching: $TPWS --user=root --port=$TPWS_PORT --daemon $DESYNC_ARGS" >> "$LOGFILE"
        "$TPWS" --user=root --port=$TPWS_PORT --daemon --pidfile="$PIDFILE" \
            --bind-addr=127.0.0.1 \
            $DESYNC_ARGS >> "$LOGFILE" 2>&1

        sleep 0.5
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "tpws started (PID=$(cat "$PIDFILE"))." >> "$LOGFILE"
            echo "Started"
        else
            echo "ERROR: tpws failed to start." >> "$LOGFILE"
            clear_pf_anchors
            exit 1
        fi
        ;;

    status)
        if lsof -Pi :$TPWS_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
            echo "Running"
            exit 0
        else
            echo "Stopped"
            exit 1
        fi
        ;;

    stop)
        echo "$(date) - Stopping Zapret2 (tpws)..." >> "$LOGFILE"
        clear_pf_anchors

        # Kill by PID file first
        if [ -f "$PIDFILE" ]; then
            OLD_PID=$(cat "$PIDFILE")
            echo "Killing PID $OLD_PID..." >> "$LOGFILE"
            kill "$OLD_PID" 2>/dev/null
            sleep 0.5
            kill -9 "$OLD_PID" 2>/dev/null
            rm -f "$PIDFILE"
        fi
        
        # Kill anything still on the port (just in case)
        lsof -ti tcp:$TPWS_PORT | xargs kill -9 2>/dev/null || true
        
        echo "Zapret2 stopped." >> "$LOGFILE"
        echo "Stopped"
        ;;

    restart)
        "$0" stop
        sleep 1
        "$0" start "$DESYNC_ARGS"
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|status} [tpws strategy args]"
        exit 1
        ;;
esac
exit 0
