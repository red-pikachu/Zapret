#!/bin/bash
# Zapret2 macOS Wrapper
# This script requires root privileges to run pfctl and dvtws2.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DVTWS2="$DIR/dvtws2"
PIDFILE="/tmp/zapret_dvtws2.pid"
LOGFILE="/tmp/zapret2.log"
DIVERT_PORT=12500

COMMAND=$1
shift
DESYNC_ARGS="$@"

case "$COMMAND" in
    start)
        echo "$(date) - Starting Zapret2 daemon with strategy args: $DESYNC_ARGS" > "$LOGFILE"
        
        # Stop existing instance if any
        if [ -f "$PIDFILE" ]; then
            kill $(cat "$PIDFILE") 2>/dev/null
            rm -f "$PIDFILE"
        fi
        
        # Enable pf
        pfctl -e >> "$LOGFILE" 2>&1
        
        # Add divert rules for HTTP/HTTPS, Discord, Telegram to anchor 'zapret'
        (
        echo "pass out on en0 inet proto tcp to port {80, 443, 2053, 2083, 2087, 2096, 8443, 5222, 5228} divert-packet port $DIVERT_PORT"
        echo "pass out on en0 inet proto udp to port {443, 50000:50100, 19294:19344} divert-packet port $DIVERT_PORT"
        ) | pfctl -a zapret -f - >> "$LOGFILE" 2>&1
        
        # Check for custom configs
        HOSTLIST_ARG=""
        if [ -f "$HOME/.zapret2/hostlist.txt" ]; then
            HOSTLIST_ARG="--hostlist=$HOME/.zapret2/hostlist.txt"
        fi
        
        # Start dvtws2
        echo "Running: $DVTWS2 --port=$DIVERT_PORT --daemon --pidfile=$PIDFILE --lua-init=@$DIR/lua/zapret-antidpi.lua --out-range=1-3 $DESYNC_ARGS $HOSTLIST_ARG" >> "$LOGFILE"
        
        "$DVTWS2" --port=$DIVERT_PORT --daemon --pidfile="$PIDFILE" \
            --lua-init="@$DIR/lua/zapret-antidpi.lua" \
            --out-range="1-3" \
            $DESYNC_ARGS \
            $HOSTLIST_ARG >> "$LOGFILE" 2>&1
            
        echo "Zapret2 started." >> "$LOGFILE"
        echo "Started"
        ;;
    stop)
        echo "$(date) - Stopping Zapret2 daemon..." >> "$LOGFILE"
        
        # Remove divert rules from anchor
        pfctl -a zapret -F all >> "$LOGFILE" 2>&1
        
        # Kill the daemon
        if [ -f "$PIDFILE" ]; then
            kill $(cat "$PIDFILE") 2>/dev/null
            rm -f "$PIDFILE"
        fi
        
        # We can also explicitly killall just in case
        killall dvtws2 >> "$LOGFILE" 2>&1
        
        echo "Zapret2 stopped." >> "$LOGFILE"
        echo "Stopped"
        ;;
    *)
        echo "Usage: $0 {start|stop} [strategy]"
        exit 1
        ;;
esac
exit 0
