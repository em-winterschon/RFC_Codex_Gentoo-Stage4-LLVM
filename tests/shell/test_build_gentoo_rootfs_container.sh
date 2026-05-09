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

  cat > "${package_list}" << 'EOF'
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
  assert_contains "${output}" 'binpkg-sync-root=/srv/stage5-binpkgs'
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

  cat > "${package_list}" << 'EOF'
app-shells/bash
EOF

  cat > "${bin_dir}/buildah" << 'EOF'
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

  cat > "${package_list}" << 'EOF'
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

  cat > "${package_list}" << 'EOF'
app-shells/bash
EOF

  cat > "${use_file}" << 'EOF'
# merged-usr container rootfs override
-split-usr
EOF

  cat > "${package_use_file}" << 'EOF'
app-alternatives/awk -split-usr
EOF

  cat > "${host_package_use_file}" << 'EOF'
sys-apps/coreutils -split-usr
EOF

  cat > "${rootfs_links_file}" << 'EOF'
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

  cat > "${package_list}" << 'EOF'
app-shells/bash
EOF

  mkdir -p "${overlay_dir}/profiles" "${overlay_dir}/metadata"
  printf 'test-overlay\n' > "${overlay_dir}/profiles/repo_name"
  cat > "${overlay_dir}/metadata/layout.conf" << 'EOF'
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

  cat > "${package_list}" << 'EOF'
app-shells/bash
EOF

  cat > "${mask_file}" << 'EOF'
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

test_dry_run_bootstrap_runtime_seed() {
  local temp_dir package_list output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"

  cat > "${package_list}" << 'EOF'
app-shells/bash
EOF

  output="$(
    bash "${BUILD_SCRIPT}" \
      --root "${temp_dir}/rootfs" \
      --package-list "${package_list}" \
      --bootstrap-runtime-seed auto \
      --engine none \
      --dry-run
  )"

  assert_contains "${output}" 'bootstrap-runtime-seed=auto'
}

test_package_use_file_requires_explicit_config_root() {
  local temp_dir package_list package_use_file output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"
  package_use_file="${temp_dir}/package.use"

  cat > "${package_list}" << 'EOF'
app-shells/bash
EOF

  cat > "${package_use_file}" << 'EOF'
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

  cat > "${package_list}" << 'EOF'
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

  cat > "${package_list}" << 'EOF'
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

test_dry_run_binpkg_sync() {
  local temp_dir package_list output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"

  cat > "${package_list}" << 'EOF'
app-shells/bash
EOF

  output="$(
    bash "${BUILD_SCRIPT}" \
      --root "${temp_dir}/rootfs" \
      --package-list "${package_list}" \
      --pkgdir "${temp_dir}/binpkgs" \
      --binpkg-repo-id stage4-test__stage5-test__amd64__x86_64_v2 \
      --binpkg-sync-remote root@example.invalid \
      --binpkg-sync-root /srv/stage5-binpkgs \
      --engine none \
      --dry-run
  )"

  assert_contains "${output}" 'binpkg-repo-id=stage4-test__stage5-test__amd64__x86_64_v2'
  assert_contains "${output}" 'binpkg-sync-remote=root@example.invalid'
  assert_contains "${output}" 'binpkg-sync-root=/srv/stage5-binpkgs'
}

test_dry_run_stage3_target_plan() {
  local temp_dir package_list output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"

  cat > "${package_list}" << 'EOF'
app-shells/bash
EOF

  output="$(
    bash "${BUILD_SCRIPT}" \
      --root "${temp_dir}/rootfs" \
      --package-list "${package_list}" \
      --stage3-target amd64-llvm-openrc \
      --stage3-cache-dir "${temp_dir}/stage3-cache" \
      --reset-rootfs \
      --engine none \
      --dry-run
  )"

  assert_contains "${output}" 'stage3-target=amd64-llvm-openrc'
  assert_contains "${output}" 'stage3-release-arch=amd64'
  assert_contains "${output}" 'stage3-current-dir=current-stage3-amd64-llvm-openrc'
  assert_contains "${output}" 'stage3-latest-url=https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-llvm-openrc/latest-stage3-amd64-llvm-openrc.txt'
  assert_contains "${output}" "stage3-cache-dir=${temp_dir}/stage3-cache"
  assert_contains "${output}" 'main-emptytree=false'
  assert_contains "${output}" 'reset-rootfs=true'
}

test_dry_run_stage3_tarball_plan() {
  local temp_dir package_list stage3_tarball output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"
  stage3_tarball="${temp_dir}/stage3-amd64-llvm-openrc-test.tar.xz"

  cat > "${package_list}" << 'EOF'
app-shells/bash
EOF
  : > "${stage3_tarball}"

  output="$(
    bash "${BUILD_SCRIPT}" \
      --root "${temp_dir}/rootfs" \
      --package-list "${package_list}" \
      --stage3-tarball "${stage3_tarball}" \
      --engine none \
      --dry-run
  )"

  assert_contains "${output}" "stage3-tarball=${stage3_tarball}"
  assert_contains "${output}" 'main-emptytree=false'
}

test_stage3_tarball_extracts_before_rootfs_skeleton() {
  local temp_dir package_list stage3_dir stage3_tarball emerge_log
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"
  stage3_dir="${temp_dir}/stage3"
  stage3_tarball="${temp_dir}/stage3-amd64-llvm-openrc-test.tar.xz"
  emerge_log="${temp_dir}/emerge.log"

  cat > "${package_list}" << 'EOF'
app-shells/bash
EOF

  mkdir -p "${stage3_dir}/etc" "${temp_dir}/bin"
  printf 'Gentoo Base System release test\n' > "${stage3_dir}/etc/gentoo-release"
  tar -C "${stage3_dir}" -cJf "${stage3_tarball}" .

  cat > "${temp_dir}/bin/emerge" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${emerge_log}"
exit 0
EOF
  chmod +x "${temp_dir}/bin/emerge"

  PATH="${temp_dir}/bin:${PATH}" \
    bash "${BUILD_SCRIPT}" \
    --root "${temp_dir}/rootfs" \
    --package-list "${package_list}" \
    --stage3-tarball "${stage3_tarball}" \
    --engine none

  [[ -f "${temp_dir}/rootfs/etc/gentoo-release" ]] || fail "stage3 gentoo-release was not extracted"
  [[ -f "${emerge_log}" ]] || fail "stub emerge was not called"
  if grep -q -- '--emptytree' "${emerge_log}"; then
    fail "stage3-backed package layering should not use --emptytree"
  fi
}

test_stage3_config_root_disables_inherited_binrepos() {
  local temp_dir package_list stage3_dir stage3_tarball emerge_log stage5_conf disabled_conf
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  package_list="${temp_dir}/packages.txt"
  stage3_dir="${temp_dir}/stage3"
  stage3_tarball="${temp_dir}/stage3-amd64-llvm-openrc-test.tar.xz"
  emerge_log="${temp_dir}/emerge.log"
  stage5_conf="${temp_dir}/rootfs/etc/portage/binrepos.conf/stage5-container.conf"
  disabled_conf="${temp_dir}/rootfs/etc/portage/binrepos.conf.disabled-by-stage5-builder/gentoobinhost.conf"

  cat > "${package_list}" << 'EOF'
app-shells/bash
EOF

  mkdir -p "${stage3_dir}/etc/portage/binrepos.conf" "${temp_dir}/bin"
  printf 'Gentoo Base System release test\n' > "${stage3_dir}/etc/gentoo-release"
  cat > "${stage3_dir}/etc/portage/binrepos.conf/gentoobinhost.conf" << 'EOF'
[gentoobinhost]
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64
verify-signature = true
EOF
  tar -C "${stage3_dir}" -cJf "${stage3_tarball}" .

  cat > "${temp_dir}/bin/emerge" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${emerge_log}"
exit 0
EOF
  chmod +x "${temp_dir}/bin/emerge"

  PATH="${temp_dir}/bin:${PATH}" \
    PORTAGE_BINHOST='http://binhost.example.invalid/stage3-test' \
    bash "${BUILD_SCRIPT}" \
    --root "${temp_dir}/rootfs" \
    --config-root "${temp_dir}/rootfs" \
    --sysroot "${temp_dir}/rootfs" \
    --package-list "${package_list}" \
    --stage3-tarball "${stage3_tarball}" \
    --binpkg-repo-id stage3-test \
    --engine none

  [[ -f "${stage5_conf}" ]] || fail "stage5 binrepo config was not written"
  assert_contains "$(< "${stage5_conf}")" 'sync-uri = http://binhost.example.invalid/stage3-test'
  assert_contains "$(< "${stage5_conf}")" 'verify-signature = false'
  [[ -f "${disabled_conf}" ]] || fail "inherited stage3 binrepo config was not disabled"
}

test_dry_run
test_auto_engine_prefers_buildah
test_dry_run_sanitizes_features
test_dry_run_use_file
test_dry_run_overlay_dir
test_dry_run_host_package_mask_file
test_dry_run_bootstrap_runtime_seed
test_package_use_file_requires_explicit_config_root
test_dry_run_sysroot
test_dry_run_explicit_pkgdir
test_dry_run_binpkg_sync
test_dry_run_stage3_target_plan
test_dry_run_stage3_tarball_plan
test_stage3_tarball_extracts_before_rootfs_skeleton
test_stage3_config_root_disables_inherited_binrepos

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
