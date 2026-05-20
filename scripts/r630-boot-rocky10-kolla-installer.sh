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
REBOOT_AFTER_STAGE="${REBOOT_AFTER_STAGE:-0}"
BOOT_DIR="${BOOT_DIR:-/boot/rfc1918-rocky10-kolla}"
TITLE="${TITLE:-RFC1918 Rocky Linux 10 Kolla node installer}"

for cmd in curl grub2-reboot grubby; do
  command -v "$cmd" >/dev/null || {
    echo "missing required command: $cmd" >&2
    exit 1
  }
done

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

if grubby --info=ALL | grep -F "title=${TITLE}" >/dev/null 2>&1; then
  grubby --remove-kernel="$BOOT_DIR/vmlinuz-rocky10" || true
fi

grubby --add-kernel="$BOOT_DIR/vmlinuz-rocky10" \
  --initrd="$BOOT_DIR/initrd-rocky10.img" \
  --title="$TITLE" \
  --args="${args[*]}"

grub2-reboot "$TITLE"

printf 'staged one-shot installer: %s\n' "$TITLE"
printf 'kernel: %s\n' "$BOOT_DIR/vmlinuz-rocky10"
printf 'initrd: %s\n' "$BOOT_DIR/initrd-rocky10.img"
printf 'kickstart: %s\n' "$KICKSTART_URL"

if [[ "${REBOOT_AFTER_STAGE}" == "1" ]]; then
  systemctl reboot
fi
