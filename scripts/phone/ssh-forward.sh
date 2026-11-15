#!/bin/sh
# ADB port forward to the guest's dropbear (port 2222) during an open iOS session.
#
# With wifi=tap (xnuhost.conf), the guest is 192.168.77.2 on oneios0; this script listens on the
# phone (127.0.0.1:PHONE_PORT) and relays to the guest. On the Mac:
#
#   adb forward tcp:2222 tcp:7222
#   ssh -i ~/.ssh/id_rsa -p 2222 -o StrictHostKeyChecking=no root@127.0.0.1
#
#   scripts/phone/ssh-forward.sh start    # relay on phone + adb forward (default ports)
#   scripts/phone/ssh-forward.sh stop
#   scripts/phone/ssh-forward.sh status
#
# Override: GUEST_IP, GUEST_PORT=2222, PHONE_PORT=7222, LOCAL_PORT=2222, ADB_SERIAL.
set -eu
STAGE=/data/local/tmp/oneios
PIDFILE=$STAGE/control/ssh-forward.pid
LOG=$STAGE/logs/ssh-forward.log
GUEST_IP=${GUEST_IP:-192.168.77.2}
GUEST_PORT=${GUEST_PORT:-2222}
PHONE_PORT=${PHONE_PORT:-7222}
LOCAL_PORT=${LOCAL_PORT:-2222}
ADB=${ADB:-adb}
[ -n "${ADB_SERIAL:-}" ] && ADB="$ADB -s $ADB_SERIAL"

die() { echo "ssh-forward.sh: $*" >&2; exit 1; }

session_open() {
  $ADB shell "su -c 'p=\$(cat $STAGE/session/xnuhost.pid 2>/dev/null); [ -n \"\$p\" ] && kill -0 \$p 2>/dev/null && echo open'" | tr -d '\r' | grep -q open
}

find_busybox() {
  $ADB shell "su -c 'for c in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do [ -x \"\$c\" ] && echo \$c && exit 0; done; exit 1'" | tr -d '\r'
}

start() {
  session_open || die "no open iOS session (return to One UI or switch first)"
  BB=$(find_busybox) || die "no root busybox"
  $ADB forward --remove "tcp:$LOCAL_PORT" 2>/dev/null || true
  $ADB shell "su -c 'mkdir -p $STAGE/logs; [ -f $PIDFILE ] && kill \$(cat $PIDFILE) 2>/dev/null; rm -f $PIDFILE
    nohup $BB nc -lk -p $PHONE_PORT -e $BB nc $GUEST_IP $GUEST_PORT \
      </dev/null >>$LOG 2>&1 & echo \$! > $PIDFILE'" || die "could not start relay on phone"
  sleep 0.5
  $ADB forward "tcp:$LOCAL_PORT" "tcp:$PHONE_PORT" || die "adb forward failed"
  echo "ssh-forward: adb localhost:$LOCAL_PORT -> phone:$PHONE_PORT -> guest $GUEST_IP:$GUEST_PORT"
  echo "  ssh -i ~/.ssh/id_rsa -p $LOCAL_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@127.0.0.1"
}

stop() {
  $ADB forward --remove "tcp:$LOCAL_PORT" 2>/dev/null || true
  $ADB shell "su -c '[ -f $PIDFILE ] && kill \$(cat $PIDFILE) 2>/dev/null; rm -f $PIDFILE'" 2>/dev/null || true
  echo "ssh-forward: stopped"
}

status() {
  $ADB forward --list 2>/dev/null | grep "tcp:$LOCAL_PORT" || echo "no adb forward on tcp:$LOCAL_PORT"
  $ADB shell "su -c 'if [ -f $PIDFILE ] && kill -0 \$(cat $PIDFILE) 2>/dev/null; then echo relay pid=\$(cat $PIDFILE); else echo relay off; fi; tail -3 $LOG 2>/dev/null'" | tr -d '\r'
}

case "${1:-start}" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  *) die "usage: $0 start|stop|status";;
esac