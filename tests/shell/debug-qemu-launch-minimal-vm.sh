#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if ! command -v bashdb > /dev/null 2>&1; then
  printf 'bashdb is required to debug qemu-launch-minimal-vm.sh\n' >&2
  exit 1
fi

export QEMU_LAUNCH_DRY_RUN="${QEMU_LAUNCH_DRY_RUN:-1}"
exec bashdb -q "${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-minimal-vm.sh" "$@"
