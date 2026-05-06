#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  generate-workstation-package-review.sh X12_CAPTURE MICROBOX_CAPTURE OUTPUT_DIR

Creates sorted workstation package review files:
  shared-primary-candidates.atoms
  x12again-only-primary-candidates.atoms
  microbox-only-primary-candidates.atoms
  union-primary-candidates.atoms
  wayland-plasma-rejects.atoms
  stage5-workstation-review-candidates.atoms
  README.md
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 3 ]]; then
  usage >&2
  exit 2
fi

x12_capture=$1
microbox_capture=$2
output_dir=$3

for required in \
  "${x12_capture}/primary-candidates.atoms" \
  "${microbox_capture}/primary-candidates.atoms"; do
  if [[ ! -f "${required}" ]]; then
    printf 'missing required capture file: %s\n' "${required}" >&2
    exit 1
  fi
done

mkdir -p "${output_dir}"
tmpdir=$(mktemp -d)
trap 'rm -rf "${tmpdir}"' EXIT

sort -u "${x12_capture}/primary-candidates.atoms" > "${tmpdir}/x12.atoms"
sort -u "${microbox_capture}/primary-candidates.atoms" > "${tmpdir}/microbox.atoms"

comm -12 "${tmpdir}/x12.atoms" "${tmpdir}/microbox.atoms" > "${output_dir}/shared-primary-candidates.atoms"
comm -23 "${tmpdir}/x12.atoms" "${tmpdir}/microbox.atoms" > "${output_dir}/x12again-only-primary-candidates.atoms"
comm -13 "${tmpdir}/x12.atoms" "${tmpdir}/microbox.atoms" > "${output_dir}/microbox-only-primary-candidates.atoms"
sort -u "${tmpdir}/x12.atoms" "${tmpdir}/microbox.atoms" > "${output_dir}/union-primary-candidates.atoms"

grep -E \
  '^(dev-libs/(wayland|wayland-protocols|plasma-wayland-protocols)|dev-qt/qtwayland|dev-util/wayland-scanner|gui-apps/xwaylandvideobridge|gui-libs/wlroots|kde-plasma/.+|sys-apps/xdg-desktop-portal|x11-base/xwayland|x11-misc/sddm)$' \
  "${output_dir}/union-primary-candidates.atoms" \
  > "${output_dir}/wayland-plasma-rejects.atoms" || true

comm -23 \
  "${output_dir}/union-primary-candidates.atoms" \
  <(sort -u "${output_dir}/wayland-plasma-rejects.atoms") \
  > "${output_dir}/stage5-workstation-review-candidates.atoms"

{
  printf '# Stage4 LOX Workstation Package Review\n\n'
  printf 'Generated from:\n\n'
  printf '%s\n' "- \`${x12_capture}\`"
  printf '%s\n\n' "- \`${microbox_capture}\`"
  printf 'Canonical target ID:\n\n'
  printf '```text\n'
  printf 'stage4-lox__stage5-workstation-nscde__amd64__gpu-universal-xorg\n'
  printf '```\n\n'
  printf 'Counts:\n\n'
  printf '| File | Count |\n'
  printf '| --- | ---: |\n'
  for file in \
    shared-primary-candidates.atoms \
    x12again-only-primary-candidates.atoms \
    microbox-only-primary-candidates.atoms \
    union-primary-candidates.atoms \
    wayland-plasma-rejects.atoms \
    stage5-workstation-review-candidates.atoms; do
    printf '| `%s` | %s |\n' "${file}" "$(wc -l < "${output_dir}/${file}")"
  done
  printf '\n`stage5-workstation-review-candidates.atoms` is a review input, not an active emerge target.\n'
} > "${output_dir}/README.md"
