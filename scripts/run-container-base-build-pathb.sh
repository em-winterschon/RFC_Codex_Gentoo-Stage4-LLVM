#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f /root/RFC_Codex_Gentoo-Stage4-LLVM/scripts/build-gentoo-rootfs-container.sh ]]; then
  SCRIPT_DIR=/root/RFC_Codex_Gentoo-Stage4-LLVM/scripts
fi
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

REPO_ID="${STAGE5_BINPKG_REPO_ID:-stage3-llvm_clang_openrc__stage5-service_container-base__amd64__x86_64_v2_generic}"
REPO_URL="${STAGE5_BINPKG_REPO_URL:-http://10.9.8.90:8088/${REPO_ID}}"
ROOTFS_DIR="${CONTAINER_ROOTFS_DIR:-/var/lib/container-services-ephemeral/images/gentoo-stage3-llvm-clang-openrc-rootfs}"
PKGDIR="${CONTAINER_PKGDIR:-/var/lib/container-services-ephemeral/images/gentoo-stage3-llvm-clang-openrc-binpkgs}"
STAGE3_TARGET="${CONTAINER_STAGE3_TARGET:-amd64-llvm-openrc}"
STAGE3_CACHE_DIR="${CONTAINER_STAGE3_CACHE_DIR:-/var/lib/container-services-ephemeral/stage3-cache}"
BINPKG_SYNC_REMOTE="${BINPKG_SYNC_REMOTE:-root@10.9.8.90}"
BINPKG_SYNC_ROOT="${BINPKG_SYNC_ROOT:-/srv/stage5-binpkgs}"
TARBALL="${CONTAINER_TARBALL:-/var/lib/container-services-ephemeral/images/gentoo-stage3-llvm-clang-openrc.tar.zst}"
IMAGE_REF="${CONTAINER_IMAGE_REF:-localhost/gentoo-stage3-llvm-clang-openrc:latest}"
EMERGE_JOBS="${EMERGE_JOBS:-20}"
EMERGE_LOAD_AVERAGE="${EMERGE_LOAD_AVERAGE:-60}"

cd "${REPO_ROOT}"

export MAKEOPTS="${MAKEOPTS:--j64}"
export BINHOST="${BINHOST:-${REPO_URL}}"
export PORTAGE_BINHOST="${PORTAGE_BINHOST:-${REPO_URL}}"
export EMERGE_DEFAULT_OPTS="${EMERGE_DEFAULT_OPTS:---jobs=${EMERGE_JOBS} --load-average=${EMERGE_LOAD_AVERAGE} --getbinpkg=y --buildpkg=y --usepkg=y --binpkg-changed-deps=n --with-bdeps=y --complete-graph=y --autounmask=y --autounmask-backtrack=y --autounmask-continue=y --autounmask-unrestricted-atoms=y --autounmask-use=y --autounmask-write=y --binpkg-respect-use=y}"
export FEATURES="${FEATURES:-buildpkg parallel-install merge-sync -distcc -ccache}"
export PORTAGE_BINPKG_FORMAT="${PORTAGE_BINPKG_FORMAT:-tar}"
export BINPKG_COMPRESS="${BINPKG_COMPRESS:-zstd}"
export BINPKG_COMPRESS_FLAGS="${BINPKG_COMPRESS_FLAGS:--2}"
export RES_OPTIONS="${RES_OPTIONS:-attempts:2 timeout:2}"

install -d -m 0700 /etc/portage/gnupg
if command -v getuto >/dev/null 2>&1 && [[ ! -f /etc/portage/gnupg/pubring.kbx ]]; then
  getuto
fi
install -d -m 0755 /etc/portage/binrepos.conf
install -d -m 0755 /etc/portage/binrepos.conf.disabled-by-stage5-builder
for binrepo_conf in /etc/portage/binrepos.conf/*; do
  [[ -e "${binrepo_conf}" ]] || continue
  [[ "$(basename "${binrepo_conf}")" == "stage5-container.conf" ]] && continue
  mv "${binrepo_conf}" "/etc/portage/binrepos.conf.disabled-by-stage5-builder/$(basename "${binrepo_conf}")"
done
cat > /etc/portage/binrepos.conf/stage5-container.conf <<EOF
[stage5-container]
priority = 50
sync-uri = ${REPO_URL}
location = /var/cache/binhost/stage5-container
verify-signature = false
EOF

exec bash "${SCRIPT_DIR}/build-gentoo-rootfs-container.sh" \
  --root "${ROOTFS_DIR}" \
  --pkgdir "${PKGDIR}" \
  --binpkg-repo-id "${REPO_ID}" \
  --binpkg-sync-remote "${BINPKG_SYNC_REMOTE}" \
  --binpkg-sync-root "${BINPKG_SYNC_ROOT}" \
  --stage3-target "${STAGE3_TARGET}" \
  --stage3-cache-dir "${STAGE3_CACHE_DIR}" \
  --reset-rootfs \
  --package-list container-image-definitions/gentoo-stage3-llvm-clang-openrc.packages \
  --use-file container-image-definitions/gentoo-stage3-llvm-clang-openrc.use \
  --package-use-file container-image-definitions/gentoo-stage3-llvm-clang-openrc.package.use \
  --config-root "${ROOTFS_DIR}" \
  --sysroot "${ROOTFS_DIR}" \
  --image-ref "${IMAGE_REF}" \
  --tarball "${TARBALL}" \
  --source-url https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM \
  --description "Gentoo Stage3 LLVM/Clang OpenRC base container"
