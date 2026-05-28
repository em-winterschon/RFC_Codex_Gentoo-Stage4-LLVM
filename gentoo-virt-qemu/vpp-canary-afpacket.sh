#!/usr/bin/env bash
set -euo pipefail

target_mac="${VPP_CANARY_AF_PACKET_MAC:-52:54:00:70:ca:01}"
state_dir="${VPP_CANARY_STATE_DIR:-/var/lib/vpp-canary}"
attempts="${VPP_CANARY_ATTEMPTS:-30}"
sleep_seconds="${VPP_CANARY_SLEEP_SECONDS:-1}"

find_interface_by_mac() {
  local address_path iface mac

  for address_path in /sys/class/net/*/address; do
    [[ -r "${address_path}" ]] || continue
    iface="$(basename "$(dirname "${address_path}")")"
    mac="$(tr '[:upper:]' '[:lower:]' < "${address_path}")"
    if [[ "${mac}" == "${target_mac,,}" ]]; then
      printf '%s' "${iface}"
      return 0
    fi
  done

  return 1
}

wait_for_vpp() {
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if vppctl show version >/dev/null 2>&1; then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  printf 'VPP CLI did not become ready after %s attempts\n' "${attempts}" >&2
  return 1
}

main() {
  local iface vpp_iface

  iface="$(find_interface_by_mac)" || {
    printf 'No Linux interface found with MAC %s\n' "${target_mac}" >&2
    return 1
  }
  vpp_iface="host-${iface}"

  wait_for_vpp
  if ! vppctl show interface | awk '{ print $1 }' | grep -Fxq "${vpp_iface}"; then
    vppctl create host-interface name "${iface}" >/dev/null
  fi
  vppctl set interface state "${vpp_iface}" up

  install -d -m 0755 "${state_dir}"
  printf '%s\n' "${vpp_iface}" > "${state_dir}/afpacket-interface"
  vppctl show interface "${vpp_iface}" > "${state_dir}/afpacket-interface.vppctl"
}

main "$@"
