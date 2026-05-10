#!/usr/bin/env bash
set -euo pipefail

SUN99_CIDR="${SUN99_CIDR:-172.16.99.0/24}"
PATHB_CIDR="${PATHB_CIDR:-10.9.8.0/24}"
PATHB_IFACE="${PATHB_IFACE:-br-pathb}"

if [[ "$(id -u)" != 0 ]]; then
  printf 'apply-x12again-pathb-sun99-nat: must run as root\n' >&2
  exit 2
fi

sysctl -w net.ipv4.ip_forward=1 >/dev/null

if ! iptables -t nat -C POSTROUTING -s "${SUN99_CIDR}" -d "${PATHB_CIDR}" -o "${PATHB_IFACE}" -j MASQUERADE 2>/dev/null; then
  iptables -t nat -A POSTROUTING -s "${SUN99_CIDR}" -d "${PATHB_CIDR}" -o "${PATHB_IFACE}" -j MASQUERADE
fi

iptables -t nat -S POSTROUTING
