#!/usr/bin/env bash
set -euo pipefail

INSTALL_VIRT_VIEWER="${INSTALL_VIRT_VIEWER:-1}"
INSTALL_LIBVIRT="${INSTALL_LIBVIRT:-0}"

packages=(
  sys-firmware/edk2-bin
  app-emulation/qemu
  net-dialup/minicom
)

if [[ "${INSTALL_VIRT_VIEWER}" == '1' ]]; then
  packages+=( app-emulation/virt-viewer )
fi

if [[ "${INSTALL_LIBVIRT}" == '1' ]]; then
  packages+=( app-emulation/libvirt )
fi

emerge "${packages[@]}"
