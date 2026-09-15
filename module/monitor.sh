#!/system/bin/sh
# Pure Magisk notification poller. Parsing strategy adapted from
# yuwanx/Message_Forwarding (MIT); no APK or NotificationListenerService.

MODDIR=${0%/*}
CFG="$MODDIR/config/config.properties"
LOGDIR="$MODDIR/logs"
LOG="$LOGDIR/monitor.log"
STATE=/data/adb/wxpay_monitor_state
QUEUE="$STATE/queue"
PREV="$STATE/pushed"
NEXT="$STATE/pushed.next"
INITIALIZED="$STATE/initialized"
CA_BUNDLE="$STATE/android-ca-bundle.pem"

mkdir -p "$LOGDIR" "$QUEUE"
touch "$LOG" "$PREV"

log() {
  echo "$(date '+%F %T') $*" >> "$LOG"
}

cfg() {
  sed -n "s/^$1=//p" "$CFG" 2>/dev/null | tail -1 | tr -d '\r'
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g;s/"/\\"/g;s/\t/\\t/g;s/\r/\\r/g' | tr '\n' ' '
}

matches_csv() {
  TEXT=$1
  CSV=$2
  [ -z "$CSV" ] && return 1
  OLDIFS=$IFS
  IFS=,
  for ITEM in $CSV; do
    IFS=$OLDIFS
    ITEM=$(printf '%s' "$ITEM" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$ITEM" ] && printf '%s' "$TEXT" | grep -F -q "$ITEM"; then
      IFS=$OLDIFS
      return 0
    fi
    IFS=,
  done
  IFS=$OLDIFS
  return 1
}

find_curl() {
  C=$(cfg curl_path)
  if [ -n "$C" ] && [ -x "$C" ]; then
    echo "$C"
  elif [ -x "$MODDIR/curl" ]; then
    echo "$MODDIR/curl"
  else
    command -v curl 2>/dev/null
  fi
}

make_id() {
  SRC=$1
  if command -v md5sum >/dev/null 2>&1; then
    printf '%s' "$SRC" | md5sum | cut -d' ' -f1
  elif toybox md5sum /dev/null >/dev/null 2>&1; then
    printf '%s' "$SRC" | toybox md5sum | cut -d' ' -f1
  else
    printf '%s' "$SRC" | busybox md5sum | cut -d' ' -f1
  fi
}

queue_report() {
  ID=$1
  TITLE=$2
  MESSAGE=$3
  PKG=$4
  NOW_SEC=$(date +%s)
  NOW_MS="${NOW_SEC}000"
  RECEIVE_TIME="$(date '+%Y-%m-%d %H:%M:%S').000000"
  MAKER=$(getprop ro.product.manufacturer)
  MODEL=$(getprop ro.product.model)
  DEVICE=$(printf '%s %s' "$MAKER" "$MODEL" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  ETITLE=$(json_escape "$TITLE")
  EMSG=$(json_escape "$MESSAGE")
  EPKG=$(json_escape "$PKG")
  ETIME=$(json_escape "$RECEIVE_TIME")
  EDEVICE=$(json_escape "$DEVICE")
  CONTENT="{\"title\":\"$ETITLE\",\"msg\":\"$EMSG\",\"package_name\":\"$EPKG\",\"receive_time\":\"$ETIME\",\"device_name\":\"$EDEVICE\"}"
  ECONTENT=$(json_escape "$CONTENT")
  printf '%s' "{\"from\":\"android\",\"content\":\"$ECONTENT\",\"timestamp\":$NOW_MS,\"sign\":\"\"}" > "$QUEUE/$ID.json"
  log "QUEUED id=$ID package=$PKG title=$TITLE"
}

process_queue() {
  CURL=$(find_curl)
  if [ -z "$CURL" ]; then
    log "ERROR curl not found"
    return
  fi

  BASE=$(cfg platform_address); BASE=${BASE%/}
  API=$(cfg report_api_path); case "$API" in /*) ;; *) API="/$API";; esac
  PID_VALUE=$(cfg merchant_id)
  TOKEN=$(cfg merchant_key)
  if [ -z "$BASE" ] || [ -z "$PID_VALUE" ] || [ -z "$TOKEN" ]; then
    log "ERROR incomplete platform_address/merchant_id/merchant_key"
    return
  fi
  URL="$BASE$API?pid=$PID_VALUE&token=$TOKEN"

  if [ ! -s "$CA_BUNDLE" ]; then
    cat /system/etc/security/cacerts/* > "$CA_BUNDLE" 2>/dev/null
    chmod 0600 "$CA_BUNDLE" 2>/dev/null
  fi

  for FILE in "$QUEUE"/*.json; do
    [ -f "$FILE" ] || continue
    RESPONSE="$FILE.response"
    CODE=$("$CURL" -sS --cacert "$CA_BUNDLE" --connect-timeout 12 --max-time 25 \
      -o "$RESPONSE" -w '%{http_code}' \
      -H 'Content-Type: application/json; charset=utf-8' \
      -H 'Accept: application/json' \
      --data-binary "@$FILE" "$URL" 2>>"$LOG")
    BODY=$(cat "$RESPONSE" 2>/dev/null | tr '\r\n' ' ' | cut -c1-240)
    if [ "$CODE" = "200" ] && printf '%s' "$BODY" | grep -Eq '"code"[[:space:]]*:[[:space:]]*0'; then
      log "SENT file=$(basename "$FILE") HTTP=$CODE body=$BODY"
      rm -f "$FILE" "$RESPONSE"
    else
      log "RETRY file=$(basename "$FILE") HTTP=$CODE body=$BODY"
      rm -f "$RESPONSE"
    fi
  done
}

ENABLED=$(cfg enabled)
if [ "$ENABLED" != "true" ] && [ "$ENABLED" != "1" ]; then
  exit 0
fi

APP_LIST=$(cfg packages | sed 's/,/|/g;s/ //g')
TITLE_KEYWORDS=$(cfg title_keywords)
MESSAGE_KEYWORDS=$(cfg message_keywords)
if [ -z "$APP_LIST" ]; then
  log "ERROR packages is empty"
  process_queue
  exit 0
fi

# Message_Forwarding's proven approach: flatten each NotificationRecord into one
# line, then extract package/title/text/ticker from the current notification set.
RAW=$(dumpsys notification --noredact 2>/dev/null | sed -n 's/\\//g;p')
if [ -z "$RAW" ]; then
  RAW=$(dumpsys notification 2>/dev/null | sed -n 's/\\//g;p')
fi
if [ -z "$RAW" ]; then
  log "ERROR unable to read notification service"
  process_queue
  exit 0
fi

RECORDS=$(echo -e $RAW | sed -n 's/NotificationRecord(/\nNotificationRecord(/g;p' \
  | sed -n 's/mAdjustments=\[.*//g;s/stats=SingleNotificationStats{.*//g;p' \
  | grep 'NotificationRecord(' | grep -E "$APP_LIST")

: > "$NEXT"
COUNT=$(printf '%s\n' "$RECORDS" | sed '/^[[:space:]]*$/d' | wc -l)
OLD=$(cat "$PREV" 2>/dev/null)

while [ "$COUNT" -gt 0 ] 2>/dev/null; do
  RECORD=$(printf '%s\n' "$RECORDS" | sed -n "${COUNT}p")
  PKG=$(printf '%s' "$RECORD" | sed -n 's/.* pkg=//g;s/ .*//g;$p')
  TITLE=$(printf '%s' "$RECORD" | grep 'android\.title=' | sed -n 's/.*android\.title=//g;s/) android\..*//g;s/) isVideoCall=.*//g;s/.*String (//g;$p')
  MESSAGE=$(printf '%s' "$RECORD" | grep 'android\.text=' | sed -n 's/.*android\.text=//g;s/) android\..*//g;s/.*String (//g;$p')
  if [ -z "$MESSAGE" ] || [ "$MESSAGE" = "null" ]; then
    MESSAGE=$(printf '%s' "$RECORD" | grep 'tickerText=' | sed -n 's/.*tickerText=//g;s/ contentView=.*//g;$p')
  fi

  if [ -n "$PKG" ] && printf '%s\n' "$PKG" | grep -E -q "^($APP_LIST)$" \
    && { matches_csv "$TITLE" "$TITLE_KEYWORDS" || matches_csv "$MESSAGE" "$MESSAGE_KEYWORDS"; }; then
    NORMALIZED=$(printf '%s: %s' "$TITLE" "$MESSAGE" | tr '\r\n' ' ' | sed 's/[[:space:]]\+/ /g;s/^ //;s/ $//' | cut -c1-300)
    ID=$(make_id "${PKG}__${NORMALIZED}")
    echo "$ID" >> "$NEXT"
    if [ -e "$INITIALIZED" ] && ! printf '%s\n' "$OLD" | grep -Fx -q "$ID"; then
      queue_report "$ID" "$TITLE" "$MESSAGE" "$PKG"
    fi
  fi
  COUNT=$((COUNT - 1))
done

mv -f "$NEXT" "$PREV"
if [ ! -e "$INITIALIZED" ]; then
  touch "$INITIALIZED"
  log "BASELINE complete; existing notifications were not resent"
fi

process_queue
