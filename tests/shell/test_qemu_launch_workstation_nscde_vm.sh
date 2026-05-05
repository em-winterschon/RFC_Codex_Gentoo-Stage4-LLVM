#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LAUNCH_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-workstation-nscde-vm.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected to find '${needle}' in output"
}

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

qemu_bin="${temp_dir}/qemu-system-x86_64"
cat > "${qemu_bin}" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"-netdev help"*)
    printf 'user\n'
    ;;
  *"-device help"*)
    printf 'name "std"\nname "virtio-vga"\nname "qxl-vga"\n'
    ;;
  *"-help"*)
    printf -- '-spice options\n'
    ;;
  *)
    printf 'fake qemu should only be used for help paths\n' >&2
    exit 1
    ;;
esac
EOF
chmod +x "${qemu_bin}"

stage3_dir="${temp_dir}/stage3"
mkdir -p "${stage3_dir}/images" "${stage3_dir}/state"
touch \
  "${stage3_dir}/images/vm-workstation-nscde.qcow2" \
  "${stage3_dir}/OVMF_CODE.fd" \
  "${stage3_dir}/OVMF_VARS.fd" \
  "${stage3_dir}/bpool0.img" \
  "${stage3_dir}/bpool1.img" \
  "${stage3_dir}/rpool0.img" \
  "${stage3_dir}/rpool1.img"

output="$(
  QEMU_LAUNCH_DRY_RUN=1 \
  WAIT_FOR_SSH=0 \
  LAUNCHER_LOG_ENABLE=0 \
  QEMU_BIN="${qemu_bin}" \
  STAGE3_IMAGE_DIR="${stage3_dir}" \
  EFI_FIRM="${stage3_dir}/OVMF_CODE.fd" \
  EFI_VARS_TEMPLATE="${stage3_dir}/OVMF_VARS.fd" \
  BPOOL_DISK0="${stage3_dir}/bpool0.img" \
  BPOOL_DISK1="${stage3_dir}/bpool1.img" \
  RPOOL_DISK0="${stage3_dir}/rpool0.img" \
  RPOOL_DISK1="${stage3_dir}/rpool1.img" \
  bash "${LAUNCH_SCRIPT}" 2>&1
)"

assert_contains "${output}" 'Display mode: spice (video: qxl-vga)'
assert_contains "${output}" '-spice'
assert_contains "${output}" 'port=5931'
assert_contains "${output}" 'addr=127.0.0.1'
assert_contains "${output}" 'disable-ticketing=on'
assert_contains "${output}" '-device qxl-vga'
assert_contains "${output}" 'hostfwd=tcp:127.0.0.1:2231-:22'
assert_contains "${output}" 'vm-workstation-nscde'

printf 'PASS: %s\n' "$(basename "$0")"
