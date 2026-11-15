#!/bin/sh
# Read-only host check for OneiOS porting (run on the phone as root beside One UI).
# Exits 0 when the model matches a supported Snapdragon Ultra host; prints GPU/CPU sysfs hints.

set -eu

MODEL=$(getprop ro.product.model 2>/dev/null || true)
DEVICE=$(getprop ro.product.device 2>/dev/null || true)
SOC=$(getprop ro.soc.model 2>/dev/null || true)
BOARD=$(getprop ro.board.platform 2>/dev/null || true)

echo "host: model=$MODEL device=$DEVICE soc=$SOC board=$BOARD"

case "$MODEL" in
  SM-S928*) HOST=s24-ultra ;;
  SM-S938*) HOST=s25-ultra ;;
  *) echo "verify-host: unsupported model (need SM-S928 or SM-S938)" >&2; exit 2 ;;
esac

case "$SOC" in
  SM8650)
    [ "$DEVICE" = e3q ] || { echo "verify-host: SM8650 but device=$DEVICE (expected e3q)" >&2; exit 2; }
  ;;
  SM8750)
    [ "$DEVICE" = pa3q ] || { echo "verify-host: SM8750 but device=$DEVICE (expected pa3q)" >&2; exit 2; }
  ;;
  *)
    echo "verify-host: soc=$SOC (need SM8650 or SM8750)" >&2
    exit 2
  ;;
esac

echo "verify-host: profile ok ($HOST)"

if [ -r /sys/class/kgsl/kgsl-3d0/device/chipid ]; then
  echo -n "kgsl chipid: "
  cat /sys/class/kgsl/kgsl-3d0/device/chipid 2>/dev/null || true
fi
if [ -r /sys/module/udmabuf/parameters/size_limit_mb ]; then
  echo -n "udmabuf size_limit_mb: "
  cat /sys/module/udmabuf/parameters/size_limit_mb
  echo -n "udmabuf list_limit: "
  cat /sys/module/udmabuf/parameters/list_limit
fi

ncpu=$(ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null | wc -l | tr -d ' ')
echo "cpus: $ncpu"

exit 0
