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
  assert_contains "${output}" "pkgdir=${temp_dir}/binpkgs"
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

test_dry_run_use_file() {
  local temp_dir package_list use_file package_use_file host_package_use_file rootfs_links_file output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"
  use_file="${temp_dir}/use.txt"
  package_use_file="${temp_dir}/package.use"
  host_package_use_file="${temp_dir}/host.package.use"
  rootfs_links_file="${temp_dir}/rootfs.links"

  cat >"${package_list}" <<'EOF'
app-shells/bash
EOF

  cat >"${use_file}" <<'EOF'
# merged-usr container rootfs override
-split-usr
EOF

  cat >"${package_use_file}" <<'EOF'
app-alternatives/awk -split-usr
EOF

  cat >"${host_package_use_file}" <<'EOF'
sys-apps/coreutils -split-usr
EOF

  cat >"${rootfs_links_file}" <<'EOF'
/bin usr/bin
/sbin usr/sbin
EOF

  output="$(
    bash "${BUILD_SCRIPT}" \
      --root "${temp_dir}/rootfs" \
      --package-list "${package_list}" \
      --use-file "${use_file}" \
      --package-use-file "${package_use_file}" \
      --host-package-use-file "${host_package_use_file}" \
      --rootfs-links-file "${rootfs_links_file}" \
      --config-root "${temp_dir}/rootfs" \
      --engine none \
      --dry-run
  )"

  assert_contains "${output}" "use-file=${use_file}"
  assert_contains "${output}" "package-use-file=${package_use_file}"
  assert_contains "${output}" "host-package-use-file=${host_package_use_file}"
  assert_contains "${output}" "rootfs-links-file=${rootfs_links_file}"
  assert_contains "${output}" 'use-overrides=-split-usr'
}

test_dry_run_overlay_dir() {
  local temp_dir package_list overlay_dir output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"
  overlay_dir="${temp_dir}/overlay"

  cat >"${package_list}" <<'EOF'
app-shells/bash
EOF

  mkdir -p "${overlay_dir}/profiles" "${overlay_dir}/metadata"
  printf 'test-overlay\n' > "${overlay_dir}/profiles/repo_name"
  cat >"${overlay_dir}/metadata/layout.conf" <<'EOF'
masters = gentoo
repo-name = test-overlay
EOF

  output="$(
    bash "${BUILD_SCRIPT}" \
      --root "${temp_dir}/rootfs" \
      --package-list "${package_list}" \
      --overlay-dir "${overlay_dir}" \
      --config-root "${temp_dir}/rootfs" \
      --engine none \
      --dry-run
  )"

  assert_contains "${output}" "overlay-dir=${overlay_dir}"
  assert_contains "${output}" 'overlay-repo-name=test-overlay'
}

test_dry_run_host_package_mask_file() {
  local temp_dir package_list mask_file output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"
  mask_file="${temp_dir}/package.mask"

  cat >"${package_list}" <<'EOF'
app-shells/bash
EOF

  cat >"${mask_file}" <<'EOF'
=app-alternatives/awk-4::gentoo
EOF

  output="$(
    bash "${BUILD_SCRIPT}" \
      --root "${temp_dir}/rootfs" \
      --package-list "${package_list}" \
      --host-package-mask-file "${mask_file}" \
      --engine none \
      --dry-run
  )"

  assert_contains "${output}" "host-package-mask-file=${mask_file}"
}

test_package_use_file_requires_explicit_config_root() {
  local temp_dir package_list package_use_file output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"
  package_use_file="${temp_dir}/package.use"

  cat >"${package_list}" <<'EOF'
app-shells/bash
EOF

  cat >"${package_use_file}" <<'EOF'
app-alternatives/awk -split-usr
EOF

  if output="$(
    bash "${BUILD_SCRIPT}" \
      --root "${temp_dir}/rootfs" \
      --package-list "${package_list}" \
      --package-use-file "${package_use_file}" \
      --engine none \
      --dry-run 2>&1
  )"; then
    fail "expected package-use-file without config-root to fail"
  fi

  assert_contains "${output}" '--package-use-file requires an explicit non-/ --config-root'
}

test_dry_run_sysroot() {
  local temp_dir package_list output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"

  cat >"${package_list}" <<'EOF'
app-shells/bash
EOF

  output="$(
    bash "${BUILD_SCRIPT}" \
      --root "${temp_dir}/rootfs" \
      --config-root "${temp_dir}/rootfs" \
      --sysroot "${temp_dir}/rootfs" \
      --package-list "${package_list}" \
      --engine none \
      --dry-run
  )"

  assert_contains "${output}" "config-root=${temp_dir}/rootfs"
  assert_contains "${output}" "sysroot=${temp_dir}/rootfs"
}

test_dry_run_explicit_pkgdir() {
  local temp_dir package_list output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"

  cat >"${package_list}" <<'EOF'
app-shells/bash
EOF

  output="$(
    bash "${BUILD_SCRIPT}" \
      --root "${temp_dir}/rootfs" \
      --package-list "${package_list}" \
      --pkgdir "${temp_dir}/custom-binpkgs" \
      --engine none \
      --dry-run
  )"

  assert_contains "${output}" "pkgdir=${temp_dir}/custom-binpkgs"
}

test_dry_run
test_auto_engine_prefers_buildah
test_dry_run_sanitizes_features
test_dry_run_use_file
test_dry_run_overlay_dir
test_dry_run_host_package_mask_file
test_package_use_file_requires_explicit_config_root
test_dry_run_sysroot
test_dry_run_explicit_pkgdir

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
