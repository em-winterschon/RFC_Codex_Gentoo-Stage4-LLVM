#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s <path-b-build-root>\n' "$(basename "$0")" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

build_root="$1"

if [[ -z "${build_root}" || "${build_root}" == '/' ]]; then
  printf 'Refusing unsafe build root: %s\n' "${build_root}" >&2
  exit 2
fi

if [[ ! -d "${build_root}" ]]; then
  mkdir -p "${build_root}"
  exit 0
fi

unmount_target() {
  local target="$1"

  if mountpoint -q "${target}"; then
    umount "${target}" 2> /dev/null || umount -l "${target}" 2> /dev/null || true
  fi
}

mount_list="$(mktemp)"
grep -F " ${build_root}" /proc/self/mountinfo | awk '{ print $5 }' | sort -r > "${mount_list}" || true
while IFS= read -r mounted_target; do
  unmount_target "${mounted_target}"
done < "${mount_list}"
rm -f "${mount_list}"

for pseudo_mount in \
  "${build_root}/dev/mqueue" \
  "${build_root}/dev/shm" \
  "${build_root}/dev/pts" \
  "${build_root}/dev" \
  "${build_root}/proc" \
  "${build_root}/sys"; do
  unmount_target "${pseudo_mount}"
done

if grep -F " ${build_root}" /proc/self/mountinfo > /dev/null; then
  printf 'Build root still has active mountpoints:\n' >&2
  grep -F " ${build_root}" /proc/self/mountinfo >&2
  exit 1
fi

find "${build_root}" -mindepth 1 -maxdepth 1 -xdev -exec rm -rf --one-file-system {} +
mkdir -p "${build_root}"
