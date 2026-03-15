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

        # Stop previous instance if any.
        if [ -f "$PIDFILE" ]; then
            kill "$(cat "$PIDFILE")" 2>/dev/null
            rm -f "$PIDFILE"
        fi

        # Enable PF, patch pf.conf, load anchors.
        pfctl -qe >> "$LOGFILE" 2>&1
        patch_pf_conf
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

    stop)
        echo "$(date) - Stopping Zapret2 (tpws)..." >> "$LOGFILE"

        clear_pf_anchors

        if [ -f "$PIDFILE" ]; then
            kill "$(cat "$PIDFILE")" 2>/dev/null
            sleep 0.3
            rm -f "$PIDFILE"
        fi
        killall tpws >> "$LOGFILE" 2>&1 || true

        echo "Zapret2 stopped." >> "$LOGFILE"
        echo "Stopped"
        ;;

    *)
        echo "Usage: $0 {start|stop} [tpws strategy args]"
        exit 1
        ;;
esac
exit 0
