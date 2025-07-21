#!/bin/bash

# 定义 system.img 路径
SYSTEM_IMG="/data/android.avd/system.img"

# 检查文件是否存在
if [ ! -f "$SYSTEM_IMG" ]; then
  echo "Error: system.img not found at $SYSTEM_IMG"
  exit 1
fi

# 检查是否首次启动
if [ -f /data/.first-boot-done ]; then
  RAMDISK="-ramdisk /data/android.avd/ramdisk.img"
fi

# 启动命令
/opt/android-sdk/emulator/emulator \
  -avd android \
  -nojni \
  -netfast \
  -writable-system \
  -no-boot-anim \
  -skip-adb-auth \
  -gpu swiftshader_indirect \
  -no-snapshot \
  -no-metrics \
  $RAMDISK \
  -qemu -m ${RAM_SIZE:-4096} \
  -drive file="$SYSTEM_IMG",if=none,id=system,format=raw,readonly=off \
  -device virtio-blk-pci,drive=system