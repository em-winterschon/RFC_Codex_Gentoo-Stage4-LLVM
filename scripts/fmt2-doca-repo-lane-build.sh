#!/usr/bin/env bash
set -euo pipefail

DOCA_LANE="${DOCA_LANE:-doca-3.3.0-bf2-cx5-rocky10.1}"
NASA_REPO_ROOT="${NASA_REPO_ROOT:-/opt/storage/nfs/nasa/nasa-yum-repo-doca-host}"
LOCAL_STAGE_ROOT="${LOCAL_STAGE_ROOT:-/srv/stage/doca-host-builds}"

case "${DOCA_LANE}" in
doca-2.9.4-cx4-rocky9.6)
  DOCA_VERSION="${DOCA_VERSION:-2.9.4}"
  TARGET_EL="${TARGET_EL:-el9}"
  TARGET_KERNEL="${TARGET_KERNEL:-5.14.0-570.12.1.el9_6.x86_64}"
  TARGET_DEVICES="${TARGET_DEVICES:-ConnectX-4}"
  REPO_SUBDIR="${REPO_SUBDIR:-doca-2.9.4/el9/x86_64}"
  ;;
doca-3.3.0-bf2-cx5-rocky10.1)
  DOCA_VERSION="${DOCA_VERSION:-3.3.0}"
  TARGET_EL="${TARGET_EL:-el10}"
  TARGET_KERNEL="${TARGET_KERNEL:-6.12.0-124.8.1.el10_1.x86_64}"
  TARGET_DEVICES="${TARGET_DEVICES:-BlueField-2,ConnectX-5}"
  REPO_SUBDIR="${REPO_SUBDIR:-doca-3.3.0/el10/x86_64}"
  ;;
*)
  printf 'ERROR: unsupported DOCA_LANE=%s\n' "${DOCA_LANE}" >&2
  exit 64
  ;;
esac

LOCAL_STAGE="${LOCAL_STAGE:-${LOCAL_STAGE_ROOT}/${DOCA_LANE}/${TARGET_KERNEL}}"
PUBLISH_REPO="${PUBLISH_REPO:-${NASA_REPO_ROOT}/${REPO_SUBDIR}}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

plan() {
  cat << PLAN
doca_lane=${DOCA_LANE}
doca_version=${DOCA_VERSION}
target_el=${TARGET_EL}
target_kernel=${TARGET_KERNEL}
target_devices=${TARGET_DEVICES}
local_stage=${LOCAL_STAGE}
nasa_repo_root=${NASA_REPO_ROOT}
publish_repo=${PUBLISH_REPO}
PLAN
}

prepare_local_stage() {
  if [[ "${APPLY_STAGE:-0}" != "1" ]]; then
    die "refusing to prepare local stage without APPLY_STAGE=1"
  fi
  mkdir -p \
    "${LOCAL_STAGE}/incoming" \
    "${LOCAL_STAGE}/kernel-rpms" \
    "${LOCAL_STAGE}/doca-rpms" \
    "${LOCAL_STAGE}/ofed-rpms" \
    "${LOCAL_STAGE}/dkms-logs" \
    "${LOCAL_STAGE}/firmware" \
    "${LOCAL_STAGE}/evidence"
  plan > "${LOCAL_STAGE}/lane.env"
}

sync_to_nasa_repo() {
  if [[ "${APPLY_REPO_SYNC:-0}" != "1" ]]; then
    die "refusing to sync to NASA repo without APPLY_REPO_SYNC=1"
  fi
  test -d "${LOCAL_STAGE}" || die "missing local stage: ${LOCAL_STAGE}"
  mkdir -p "${PUBLISH_REPO}/RPMS" "${PUBLISH_REPO}/SRPMS" "${PUBLISH_REPO}/logs" "${PUBLISH_REPO}/firmware" "${PUBLISH_REPO}/evidence"
  find "${LOCAL_STAGE}" -type f -name '*.rpm' -print -exec cp -a '{}' "${PUBLISH_REPO}/RPMS/" ';'
  find "${LOCAL_STAGE}/dkms-logs" "${LOCAL_STAGE}/evidence" -type f -print -exec cp -a '{}' "${PUBLISH_REPO}/logs/" ';' 2> /dev/null || true
  find "${LOCAL_STAGE}/firmware" -type f -print -exec cp -a '{}' "${PUBLISH_REPO}/firmware/" ';' 2> /dev/null || true
  plan > "${PUBLISH_REPO}/lane.env"
  find "${PUBLISH_REPO}" -type f -print0 | sort -z | xargs -0 sha256sum > "${PUBLISH_REPO}/SHA256SUMS"
}

refresh_repo() {
  if [[ "${APPLY_REPO_REFRESH:-0}" != "1" ]]; then
    die "refusing to refresh NASA repo without APPLY_REPO_REFRESH=1"
  fi
  command -v createrepo_c > /dev/null 2>&1 || die "createrepo_c is required"
  test -d "${PUBLISH_REPO}" || die "missing publish repo: ${PUBLISH_REPO}"
  createrepo_c --update "${PUBLISH_REPO}"
}

case "${1:-plan}" in
plan) plan ;;
prepare-local-stage) prepare_local_stage ;;
sync-to-nasa-repo) sync_to_nasa_repo ;;
refresh-repo) refresh_repo ;;
*)
  cat >&2 << USAGE
Usage: $0 [plan|prepare-local-stage|sync-to-nasa-repo|refresh-repo]

Lanes:
  DOCA_LANE=doca-2.9.4-cx4-rocky9.6
  DOCA_LANE=doca-3.3.0-bf2-cx5-rocky10.1

Safety gates:
  APPLY_STAGE=1          create local build staging directories
  APPLY_REPO_SYNC=1      copy RPMs/evidence from local stage into NASA repo
  APPLY_REPO_REFRESH=1   run createrepo_c --update on the NASA repo
USAGE
  exit 64
  ;;
esac
