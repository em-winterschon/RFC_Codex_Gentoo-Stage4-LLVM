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
assert_file_contains "${SCRIPT}" 'nmcli connection add type bond ifname bond0'
assert_file_contains "${SCRIPT}" 'nmcli connection add type bond ifname bond1'
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
