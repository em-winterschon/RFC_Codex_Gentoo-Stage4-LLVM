#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export INSTANCE_NAME="${INSTANCE_NAME:-vm-workstation-nscde}"
export QEMU_DISPLAY_MODE="${QEMU_DISPLAY_MODE:-spice}"
export QEMU_VIDEO_DEVICE="${QEMU_VIDEO_DEVICE:-qxl-vga}"
export QEMU_SPICE_PORT="${QEMU_SPICE_PORT:-5931}"
export QEMU_SPICE_ADDRESS="${QEMU_SPICE_ADDRESS:-127.0.0.1}"
export QEMU_SPICE_AGENT="${QEMU_SPICE_AGENT:-1}"
export QEMU_SMP="${QEMU_SMP:-16}"
export QEMU_MEMORY_MIB="${QEMU_MEMORY_MIB:-32768}"
export SSH_READY_PORT="${SSH_READY_PORT:-2231}"
export QEMU_NETDEV_BACKEND="${QEMU_NETDEV_BACKEND:-user,hostfwd=tcp:127.0.0.1:${SSH_READY_PORT}-:22}"
export QEMU_SERIAL_TCP="${QEMU_SERIAL_TCP:-127.0.0.1:4561,server=on,wait=off,telnet=on}"
export QEMU_SERIAL_FILE="${QEMU_SERIAL_FILE:-${STAGE3_IMAGE_DIR:-/opt/gentoo-virt-qemu/stage3}/state/${INSTANCE_NAME}.serial.log}"

exec "${SCRIPT_DIR}/qemu-launch-stage3-vm.sh" "$@"
