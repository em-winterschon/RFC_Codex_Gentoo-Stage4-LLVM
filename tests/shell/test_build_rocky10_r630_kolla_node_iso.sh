#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/build-rocky10-r630-kolla-node-iso.sh"
RUN_TESTS="${REPO_ROOT}/tests/shell/run-tests.sh"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -F -q -- "${pattern}" "${file}"
}

test -f "${SCRIPT}"
bash -n "${SCRIPT}"

assert_file_contains "${SCRIPT}" 'Rocky Linux 10'
assert_file_contains "${SCRIPT}" 'ROCKY_BASEOS_URL'
assert_file_contains "${SCRIPT}" 'ROCKY_APPSTREAM_URL'
assert_file_contains "${SCRIPT}" 'BOOT_IP_DNS_ARGS'
assert_file_contains "${SCRIPT}" '${INSTALL_NET_DEVICE}:none:${BOOT_IP_DNS_ARGS}'
assert_file_contains "${SCRIPT}" 'IDSDM'
assert_file_contains "${SCRIPT}" 'SSDSCKKB240G8R'
assert_file_contains "${SCRIPT}" 'HUSMM3240ASS'
assert_file_contains "${SCRIPT}" 'INTEL SSDPED1D480GA'
assert_file_contains "${SCRIPT}" 'ignoredisk --only-use=\$sd_pri,\$os_pri,\$os_sec'
assert_file_contains "${SCRIPT}" 'clearpart --all --initlabel --drives=\$sd_pri,\$os_pri,\$os_sec'
assert_file_contains "${SCRIPT}" 'part /boot/efi'
assert_file_contains "${SCRIPT}" 'part /boot'
assert_file_contains "${SCRIPT}" 'raid /'
assert_file_contains "${SCRIPT}" 'raid swap'
swap_part_line="$(grep -n 'part raid.13' "${SCRIPT}" | head -n1 | cut -d: -f1)"
root_part_line="$(grep -n 'part raid.12' "${SCRIPT}" | head -n1 | cut -d: -f1)"
if (( swap_part_line >= root_part_line )); then
  printf 'FAIL: fixed swap mdmember must be declared before grow-root mdmember\n' >&2
  exit 1
fi
assert_file_contains "${SCRIPT}" 'MGMT_BOND_MEMBERS'
assert_file_contains "${SCRIPT}" 'FRONTEND_BOND_MEMBERS'
assert_file_contains "${SCRIPT}" 'MGMT_BOND_ENABLED'
assert_file_contains "${SCRIPT}" 'MGMT_BOND_ENABLED:-false'
assert_file_contains "${SCRIPT}" 'eno3np2,eno4np3'
assert_file_contains "${SCRIPT}" '/etc/NetworkManager/system-connections/bootnet.nmconnection'
assert_file_contains "${SCRIPT}" '/etc/NetworkManager/system-connections/bond0.nmconnection'
assert_file_contains "${SCRIPT}" '/etc/NetworkManager/system-connections/bond1.nmconnection'
assert_file_contains "${SCRIPT}" 'bond_options_to_nm_keyfile'
assert_file_contains "${SCRIPT}" 'lacp_rate=fast'
assert_file_contains "${SCRIPT}" 'xmit_hash_policy=layer3+4'
assert_file_contains "${SCRIPT}" 'master=bond0'
assert_file_contains "${SCRIPT}" 'master=bond1'
assert_file_contains "${SCRIPT}" 'if [[ "${MGMT_BOND_ENABLED}" == "true" ]]'
assert_file_contains "${SCRIPT}" 'R630 management LACP remains disabled by default'
if grep -F -q -- 'options=${MGMT_BOND_OPTIONS}' "${SCRIPT}" || grep -F -q -- 'options=${FRONTEND_BOND_OPTIONS}' "${SCRIPT}"; then
  printf 'FAIL: NetworkManager keyfiles must use native [bond] keys; options= imports as balance-rr on Rocky 10\n' >&2
  exit 1
fi
if grep -F -q -- 'nmcli connection add type bond' "${SCRIPT}"; then
  printf 'FAIL: installer must persist target NetworkManager keyfiles instead of mutating installer NetworkManager with nmcli\n' >&2
  exit 1
fi
assert_file_contains "${SCRIPT}" 'podman'
assert_file_contains "${SCRIPT}" 'kolla-ansible'
assert_file_contains "${SCRIPT}" 'PermitRootLogin prohibit-password'
assert_file_contains "${SCRIPT}" 'images/eltorito.img'
assert_file_contains "${SCRIPT}" 'if [[ -d "$WORKDIR/extract/isolinux" ]]'

if grep -q -- 'clearpart --all --initlabel$' "${SCRIPT}"; then
  printf 'FAIL: Rocky 10 Kolla node installer must scope clearpart to selected IDSDM and OS mirror devices\n' >&2
  exit 1
fi

assert_file_contains "${RUN_TESTS}" 'test_build_rocky10_r630_kolla_node_iso.sh'

printf 'PASS: %s\n' "$(basename "$0")"
