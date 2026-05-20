#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Stage a one-shot Rocky Linux 10 Kolla-node netinstall boot entry on an R630.

This script runs on the target R630. It does not reboot unless
REBOOT_AFTER_STAGE=1 is explicitly set.

Required environment:
  NODE_HOSTNAME     Installed host FQDN.
  STATIC_IP         Static management IP for the installer and installed host.
  KICKSTART_URL     HTTP URL for the host-specific kickstart.
  KERNEL_URL        HTTP URL for Rocky 10 pxeboot/vmlinuz.
  INITRD_URL        HTTP URL for Rocky 10 pxeboot/initrd.img.

Optional environment:
  ROCKY_REPO_URL       Rocky 10 BaseOS install source.
  NETMASK              Installer netmask.
  GATEWAY              Installer gateway.
  DNS                  Installer DNS server.
  INSTALL_NET_DEVICE   Installer device selector, default: link.
  INSTALL_NET_MAC      Optional MAC binding for installer network device.
  REBOOT_AFTER_STAGE    Set to 1 to reboot after staging.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

: "${NODE_HOSTNAME:?NODE_HOSTNAME is required}"
: "${STATIC_IP:?STATIC_IP is required}"
: "${KICKSTART_URL:?KICKSTART_URL is required}"
: "${KERNEL_URL:?KERNEL_URL is required}"
: "${INITRD_URL:?INITRD_URL is required}"

ROCKY_REPO_URL="${ROCKY_REPO_URL:-https://dl.rockylinux.org/pub/rocky/10/BaseOS/x86_64/os/}"
NETMASK="${NETMASK:-255.255.255.0}"
GATEWAY="${GATEWAY:-10.200.99.1}"
DNS="${DNS:-10.200.99.1}"
INSTALL_NET_DEVICE="${INSTALL_NET_DEVICE:-link}"
INSTALL_NET_MAC="${INSTALL_NET_MAC:-}"
REBOOT_AFTER_STAGE="${REBOOT_AFTER_STAGE:-0}"
BOOT_DIR="${BOOT_DIR:-/boot/rfc1918-rocky10-kolla}"
TITLE="${TITLE:-RFC1918 Rocky Linux 10 Kolla node installer}"

for cmd in curl grub2-mkconfig grub2-reboot grubby; do
  command -v "$cmd" >/dev/null || {
    echo "missing required command: $cmd" >&2
    exit 1
  }
done

grub_path_for_boot_file() {
  local path=$1

  if [[ "$path" == /boot/* ]]; then
    printf '/%s\n' "${path#/boot/}"
    return
  fi

  printf '%s\n' "$path"
}

find_grub_cfg() {
  local cfg

  for cfg in \
    /etc/grub2-efi.cfg \
    /etc/grub2.cfg \
    /boot/efi/EFI/rocky/grub.cfg \
    /boot/grub2/grub.cfg; do
    if [[ -e "$cfg" ]]; then
      readlink -f "$cfg"
      return
    fi
  done

  printf '/boot/grub2/grub.cfg\n'
}

write_custom_grub_entry() {
  local custom_file=/etc/grub.d/40_custom
  local begin="# BEGIN RFC1918 Rocky Linux 10 Kolla node installer"
  local end="# END RFC1918 Rocky Linux 10 Kolla node installer"
  local kernel_path
  local initrd_path
  local linux_cmd=linux
  local initrd_cmd=initrd
  local tmp

  kernel_path="$(grub_path_for_boot_file "$BOOT_DIR/vmlinuz-rocky10")"
  initrd_path="$(grub_path_for_boot_file "$BOOT_DIR/initrd-rocky10.img")"

  if [[ -d /sys/firmware/efi ]]; then
    linux_cmd=linuxefi
    initrd_cmd=initrdefi
  fi

  tmp="$(mktemp)"

  if [[ -f "$custom_file" ]]; then
    awk -v begin="$begin" -v end="$end" '
      $0 == begin { skip = 1; next }
      $0 == end { skip = 0; next }
      !skip { print }
    ' "$custom_file" >"$tmp"
  else
    {
      printf '#!/bin/sh\n'
      printf 'exec tail -n +3 "$0"\n'
    } >"$tmp"
  fi

  {
    printf '\n%s\n' "$begin"
    printf "menuentry '%s' --id rfc1918-rocky10-kolla-installer {\n" "$TITLE"
    printf '  %s %s %s\n' "$linux_cmd" "$kernel_path" "${args[*]}"
    printf '  %s %s\n' "$initrd_cmd" "$initrd_path"
    printf '}\n'
    printf '%s\n' "$end"
  } >>"$tmp"

  install -m 0755 "$tmp" "$custom_file"
  rm -f "$tmp"

  grub2-mkconfig -o "$(find_grub_cfg)"
}

mkdir -p "$BOOT_DIR"
curl -fL -o "$BOOT_DIR/vmlinuz-rocky10" "$KERNEL_URL"
curl -fL -o "$BOOT_DIR/initrd-rocky10.img" "$INITRD_URL"

args=(
  "inst.ks=${KICKSTART_URL}"
  "inst.repo=${ROCKY_REPO_URL}"
  "ip=${STATIC_IP}::${GATEWAY}:${NETMASK}:${NODE_HOSTNAME}:${INSTALL_NET_DEVICE}:none"
  "nameserver=${DNS}"
  "rd.neednet=1"
  "inst.text"
  "console=tty0"
  "console=ttyS0,115200n8"
)

if [[ -n "$INSTALL_NET_MAC" ]]; then
  args+=("ifname=${INSTALL_NET_DEVICE}:${INSTALL_NET_MAC}")
fi

if grubby --info=ALL | grep -F "title=${TITLE}" >/dev/null 2>&1; then
  grubby --remove-kernel="$BOOT_DIR/vmlinuz-rocky10" || true
fi

if ! grubby --add-kernel="$BOOT_DIR/vmlinuz-rocky10" \
  --initrd="$BOOT_DIR/initrd-rocky10.img" \
  --title="$TITLE" \
  --args="${args[*]}"; then
  echo "grubby could not add the installer kernel; falling back to /etc/grub.d/40_custom" >&2
  write_custom_grub_entry
fi

grub2-reboot "$TITLE"

printf 'staged one-shot installer: %s\n' "$TITLE"
printf 'kernel: %s\n' "$BOOT_DIR/vmlinuz-rocky10"
printf 'initrd: %s\n' "$BOOT_DIR/initrd-rocky10.img"
printf 'kickstart: %s\n' "$KICKSTART_URL"

if [[ "${REBOOT_AFTER_STAGE}" == "1" ]]; then
  systemctl reboot
fi
