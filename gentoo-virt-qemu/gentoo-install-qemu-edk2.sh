#!/usr/bin/env bash
set -euo pipefail

INSTALL_VIRT_VIEWER="${INSTALL_VIRT_VIEWER:-1}"
INSTALL_LIBVIRT="${INSTALL_LIBVIRT:-0}"
PACKAGE_USE_DIR="${PACKAGE_USE_DIR:-/etc/portage/package.use}"
PACKAGE_USE_FILE="${PACKAGE_USE_FILE:-${PACKAGE_USE_DIR}/codex-qemu}"
QEMU_USE_FLAGS="${QEMU_USE_FLAGS:-X gtk sdl slirp spice vnc}"
VIRT_VIEWER_USE_FLAGS="${VIRT_VIEWER_USE_FLAGS:-libvirt spice vnc}"

packages=(
  sys-firmware/edk2-bin
  app-emulation/qemu
  net-dialup/minicom
)

mkdir -p "${PACKAGE_USE_DIR}"

{
  printf 'app-emulation/qemu %s\n' "${QEMU_USE_FLAGS}"
  if [[ "${INSTALL_VIRT_VIEWER}" == '1' ]]; then
    printf 'app-emulation/virt-viewer %s\n' "${VIRT_VIEWER_USE_FLAGS}"
  fi
} >"${PACKAGE_USE_FILE}"

if [[ "${INSTALL_VIRT_VIEWER}" == '1' ]]; then
  packages+=( app-emulation/virt-viewer )
fi

if [[ "${INSTALL_LIBVIRT}" == '1' ]]; then
  packages+=( app-emulation/libvirt )
fi

emerge "${packages[@]}"
