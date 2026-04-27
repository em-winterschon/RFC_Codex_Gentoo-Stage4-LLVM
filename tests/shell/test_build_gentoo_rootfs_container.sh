#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_SCRIPT="${REPO_ROOT}/scripts/build-gentoo-rootfs-container.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected '${needle}' in '${haystack}'"
}

test_dry_run() {
  local temp_dir output package_list
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"

  cat >"${package_list}" <<'EOF'
# comment
app-shells/bash
net-misc/curl
EOF

  output="$(
    bash "${BUILD_SCRIPT}" \
      --root "${temp_dir}/rootfs" \
      --package-list "${package_list}" \
      --engine none \
      --tarball "${temp_dir}/rootfs.tar.zst" \
      --dry-run
  )"

  assert_contains "${output}" "root=${temp_dir}/rootfs"
  assert_contains "${output}" "package-count=2"
  assert_contains "${output}" 'engine=none'
  assert_contains "${output}" "tarball=${temp_dir}/rootfs.tar.zst"
}

test_auto_engine_prefers_buildah() {
  local temp_dir bin_dir package_list output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  bin_dir="${temp_dir}/bin"
  mkdir -p "${bin_dir}"
  package_list="${temp_dir}/packages.txt"

  cat >"${package_list}" <<'EOF'
app-shells/bash
EOF

  cat >"${bin_dir}/buildah" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${bin_dir}/buildah"

  output="$(
    PATH="${bin_dir}:${PATH}" \
      bash "${BUILD_SCRIPT}" \
        --root "${temp_dir}/rootfs" \
        --package-list "${package_list}" \
        --image-ref localhost/test:latest \
        --dry-run
  )"

  assert_contains "${output}" 'engine=buildah'
  assert_contains "${output}" 'image-ref=localhost/test:latest'
}

test_dry_run_sanitizes_features() {
  local temp_dir package_list output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"

  cat >"${package_list}" <<'EOF'
app-shells/bash
EOF

  output="$(
    FEATURES='network-sandbox distcc ccache userpriv' \
      bash "${BUILD_SCRIPT}" \
        --root "${temp_dir}/rootfs" \
        --package-list "${package_list}" \
        --engine none \
        --dry-run
  )"

  assert_contains "${output}" 'sanitized-features=network-sandbox userpriv'
}

test_dry_run
test_auto_engine_prefers_buildah
test_dry_run_sanitizes_features

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
