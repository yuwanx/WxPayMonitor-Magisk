#!/system/bin/sh
ui_print "- Installing pure Magisk WxPayMonitor"
ui_print "- No APK will be installed"
ui_print "- Config: /data/adb/modules/wxpay_monitor/config/config.properties"

OLD_CFG=/data/adb/modules/wxpay_monitor/config/config.properties
LEGACY_CFG=/sdcard/WxPayMonitor/config.properties
if [ -s "$OLD_CFG" ]; then
  cp -f "$OLD_CFG" "$MODPATH/config/config.properties"
elif [ -s "$LEGACY_CFG" ]; then
  cp -f "$LEGACY_CFG" "$MODPATH/config/config.properties"
fi

mkdir -p "$MODPATH/logs"
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/monitor.sh" 0 0 0755
set_perm "$MODPATH/config/config.properties" 0 0 0600
set_perm "$MODPATH/logs" 0 0 0755

if [ ! -x /system/bin/curl ] && ! command -v curl >/dev/null 2>&1; then
  ui_print "! curl not found. Enable your curl Magisk module before reboot."
fi
