#!/system/bin/sh
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
sleep 2
MODDIR=${0%/*}
chmod 0755 "$MODDIR/monitor.sh"
chmod 0600 "$MODDIR/config/config.properties"

while true; do
  "$MODDIR/monitor.sh" >/dev/null 2>&1
  PERIOD=$(sed -n 's/^monitor_period_seconds=//p' "$MODDIR/config/config.properties" | tail -1 | tr -cd '0-9')
  [ -n "$PERIOD" ] || PERIOD=10
  [ "$PERIOD" -ge 2 ] 2>/dev/null || PERIOD=2
  sleep "$PERIOD"
done
