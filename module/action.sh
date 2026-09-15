#!/system/bin/sh
MODDIR=${0%/*}
echo "== WxPayMonitor pure Magisk =="
echo "Config: $MODDIR/config/config.properties"
echo "Log: $MODDIR/logs/monitor.log"
"$MODDIR/monitor.sh"
echo "--- latest log ---"
tail -n 30 "$MODDIR/logs/monitor.log" 2>/dev/null
