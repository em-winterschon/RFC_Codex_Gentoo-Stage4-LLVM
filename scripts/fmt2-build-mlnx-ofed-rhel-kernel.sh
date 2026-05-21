#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-preflight}"

OFED_VERSION="${OFED_VERSION:-24.10-4.1.4.0}"
OFED_SRC_NAME="MLNX_OFED_SRC-${OFED_VERSION}"
OFED_SRC_TGZ="${OFED_SRC_TGZ:-/var/tmp/${OFED_SRC_NAME}.tgz}"
OFED_SRC_DIR="${OFED_SRC_DIR:-/var/tmp/${OFED_SRC_NAME}}"
OFED_SHA256="${OFED_SHA256:-6401c0e49f12da0bceb1b03037e39eed2b11e3624dcba139485d2e1631ce5682}"
OFED_EXTRA_ARGS="${OFED_EXTRA_ARGS:-}"

KERNEL_VERSION="${KERNEL_VERSION:-$(uname -r)}"
KERNEL_SOURCES="${KERNEL_SOURCES:-/lib/modules/${KERNEL_VERSION}/build}"
OFED_DISTRO="${OFED_DISTRO:-rhel8.9}"

BUILDROOT="${BUILDROOT:-/srv/stage/mlnx-ofed-buildroot}"
OUTPUT_DIR="${OUTPUT_DIR:-/srv/stage/mlnx-ofed-builds/${OFED_VERSION}/${KERNEL_VERSION}}"

BUILDROOT_PACKAGES=(
  rpm-build
  libdb-devel
  libselinux-devel
  systemd-devel
  glib2-devel
  bison
  python3-docutils
  elfutils-devel
  python3-Cython
  libmnl-devel
  cmake
  python36-devel
  kernel-rpm-macros
  libtool
  perl-generators
  autoconf
  gdb-headless
  valgrind-devel
  numactl-devel
  flex
  iptables-devel
  libnl3-devel
  lsof
  automake
  gcc
  make
  perl
  findutils
  tar
  gzip
  xz
  cpio
  diffutils
  patch
  which
  redhat-rpm-config
)

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_rhel_like() {
  test -r /etc/os-release || die "/etc/os-release is missing"
  # shellcheck disable=SC1091
  . /etc/os-release
  case " ${ID:-} ${ID_LIKE:-} " in
  *" rhel "* | *" centos "* | *" rocky "* | *" fedora "*) ;;
  *) die "expected a RHEL-like build host, got ID=${ID:-unknown} ID_LIKE=${ID_LIKE:-unknown}" ;;
  esac
}

require_source() {
  test -f "${OFED_SRC_TGZ}" || die "missing ${OFED_SRC_TGZ}"
  printf '%s  %s\n' "${OFED_SHA256}" "${OFED_SRC_TGZ}" | sha256sum -c -
  test -d "${OFED_SRC_DIR}" || tar -C /var/tmp -xzf "${OFED_SRC_TGZ}"
  test -x "${OFED_SRC_DIR}/install.pl" || die "missing executable ${OFED_SRC_DIR}/install.pl"
}

require_kernel_tree() {
  test -d "${KERNEL_SOURCES}" || die "missing kernel sources: ${KERNEL_SOURCES}"
  test -e "/lib/modules/${KERNEL_VERSION}" || die "missing /lib/modules/${KERNEL_VERSION}"
}

preflight() {
  require_rhel_like
  require_source
  require_kernel_tree
  sudo "${OFED_SRC_DIR}/install.pl" \
    --kernel-only \
    --check-deps-only \
    -k "${KERNEL_VERSION}" \
    -s "${KERNEL_SOURCES}" \
    --distro "${OFED_DISTRO}" \
    ${OFED_EXTRA_ARGS} || true

  printf 'kernel=%s\n' "${KERNEL_VERSION}"
  printf 'kernel_sources=%s\n' "${KERNEL_SOURCES}"
  printf 'buildroot=%s\n' "${BUILDROOT}"
  printf 'output_dir=%s\n' "${OUTPUT_DIR}"
  printf 'ofed_extra_args=%s\n' "${OFED_EXTRA_ARGS:-<none>}"
}

create_buildroot() {
  require_rhel_like
  if [[ "${APPLY_CREATE_BUILDROOT:-0}" != "1" ]]; then
    die "refusing to create buildroot without APPLY_CREATE_BUILDROOT=1"
  fi

  sudo mkdir -p "${BUILDROOT}/etc/pki/rpm-gpg"
  sudo cp -a /etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial "${BUILDROOT}/etc/pki/rpm-gpg/" 2> /dev/null || true
  sudo dnf \
    --installroot="${BUILDROOT}" \
    --releasever=8 \
    --disablerepo='*' \
    --enablerepo=baseos \
    --enablerepo=appstream \
    --enablerepo=extras \
    --enablerepo=powertools \
    --setopt=install_weak_deps=False \
    -y install "${BUILDROOT_PACKAGES[@]}"

  sudo rpm --root "${BUILDROOT}" -qa | sort > "${BUILDROOT}/var/tmp/ofed-buildroot-rpms.txt"
  sudo du -sh "${BUILDROOT}"
}

build_kernel_rpms() {
  require_rhel_like
  require_source
  require_kernel_tree

  if [[ "${APPLY_BUILD:-0}" != "1" ]]; then
    die "refusing to build OFED RPMs without APPLY_BUILD=1"
  fi
  test -x /usr/bin/systemd-nspawn || die "systemd-nspawn is required on the build host"
  test -x "${BUILDROOT}/usr/bin/rpmbuild" || die "buildroot is missing rpmbuild; run create-buildroot first"

  sudo mkdir -p "${OUTPUT_DIR}/rpms" "${OUTPUT_DIR}/logs"
  sudo systemd-nspawn -q -D "${BUILDROOT}" \
    --bind-ro="${OFED_SRC_DIR}:/mnt/mlnx-src" \
    --bind-ro="/usr/src/kernels:/usr/src/kernels" \
    --bind-ro="/lib/modules/${KERNEL_VERSION}:/lib/modules/${KERNEL_VERSION}" \
    --bind="${OUTPUT_DIR}:/mnt/mlnx-output" \
    /bin/bash -lc "set -euo pipefail
      rm -rf /tmp/mlnx-work
      mkdir -p /tmp/mlnx-work /mnt/mlnx-output/rpms /mnt/mlnx-output/logs
      cp -a /mnt/mlnx-src/. /tmp/mlnx-work/
      cd /tmp/mlnx-work
      ./install.pl --kernel-only --build-only ${OFED_EXTRA_ARGS} -k '${KERNEL_VERSION}' -s '${KERNEL_SOURCES}' --distro '${OFED_DISTRO}' --builddir /mnt/mlnx-output/build 2>&1 | tee /mnt/mlnx-output/logs/install-kernel-only-build.log
      find /tmp/mlnx-work /mnt/mlnx-output/build -type f -name '*.rpm' -print -exec cp -a '{}' /mnt/mlnx-output/rpms/ ';'
      find /mnt/mlnx-output/rpms -maxdepth 1 -type f -name '*.rpm' -print | sort"

  find "${OUTPUT_DIR}/rpms" -maxdepth 1 -type f -name '*.rpm' -print | sort
}

case "${ACTION}" in
preflight) preflight ;;
create-buildroot) create_buildroot ;;
build-kernel-rpms) build_kernel_rpms ;;
*)
  cat >&2 << USAGE
Usage: $0 [preflight|create-buildroot|build-kernel-rpms]

Safety gates:
  APPLY_CREATE_BUILDROOT=1  allow isolated buildroot creation
  APPLY_BUILD=1             allow kernel RPM build inside systemd-nspawn
USAGE
  exit 64
  ;;
esac
