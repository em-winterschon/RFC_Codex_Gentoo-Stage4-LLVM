#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_ROOT="${TARGET_ROOT:-/mnt/gentoo}"
MARKER_DIR="${K10_MARKER_DIR:-${TARGET_ROOT}/root/k10-resume-markers}"
PACKAGE_LIST="${K10_PACKAGE_LIST:-${TARGET_ROOT}/root/k10-system-packages.list}"
LOG_FILE="${K10_LOG_FILE:-/root/k10-local-emerge-resume.$(date +%Y%m%d-%H%M%S).log}"
NTFY_URL="${K10_NTFY_URL:-http://172.16.99.96/forge-change}"
NTFY_HOST="${K10_NTFY_HOST:-msg-sun99-ntfysys.rfc1918.host}"
REBOOT_ON_SUCCESS="${K10_REBOOT_ON_SUCCESS:-1}"
HEARTBEAT_PID=""

notify() {
  local body="$1"
  command -v curl >/dev/null 2>&1 || return 0
  curl -fsS --max-time 5 \
    -H "Host: ${NTFY_HOST}" \
    -H "Title: K10 local emerge" \
    -d "${body}" \
    "${NTFY_URL}" >/dev/null 2>&1 || true
}

write_default_package_list() {
  [[ -s "${PACKAGE_LIST}" ]] && return 0
  mkdir -p "$(dirname "${PACKAGE_LIST}")"
  cat >"${PACKAGE_LIST}" <<'PKGS'
app-admin/logrotate
app-admin/rsyslog
app-admin/sudo
app-crypt/age
app-crypt/mit-krb5
app-metrics/node_exporter
app-misc/ca-certificates
app-misc/jq
app-misc/tmux
app-portage/eix
app-portage/gentoolkit
app-editors/vim
media-fonts/dejavu
net-misc/chrony
net-misc/curl
net-misc/openssh
net-misc/wget
net-nds/openldap
sys-apps/dbus
sys-apps/ethtool
sys-apps/iproute2
sys-apps/lm-sensors
sys-apps/net-tools
sys-apps/pciutils
sys-apps/smartmontools
sys-apps/usbutils
sys-auth/sssd
sys-boot/efibootmgr
sys-firmware/intel-microcode
sys-firmware/sof-firmware
sys-fs/dosfstools
sys-fs/zfs
sys-fs/zfs-kmod
sys-kernel/dracut
sys-kernel/gentoo-kernel-bin
sys-kernel/installkernel
sys-kernel/linux-firmware
sys-process/btop
sys-process/daemontools
sys-process/htop
sys-process/iotop-c
sys-process/lsof
sys-process/numactl
sys-process/numad
sys-process/parallel
sys-process/psmisc
sys-process/time
sys-process/wait_on_pid
sys-process/watchpid
x11-apps/xauth
x11-apps/xinit
x11-apps/xrandr
x11-base/xorg-server
x11-drivers/xf86-input-libinput
x11-misc/slim
x11-terms/xterm
PKGS
}

apply_cpu_caps() {
  printf 1 >/sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || true
  printf 15 >/sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null || true
  for cpufreq_dir in /sys/devices/system/cpu/cpu*/cpufreq; do
    [[ -w "${cpufreq_dir}/scaling_max_freq" ]] || continue
    printf 1200000 >"${cpufreq_dir}/scaling_max_freq" 2>/dev/null || true
  done
}

mount_target_fs() {
  mkdir -p "${TARGET_ROOT}"/{dev,proc,run,sys}
  mountpoint -q "${TARGET_ROOT}/proc" || mount -t proc proc "${TARGET_ROOT}/proc"
  if ! mountpoint -q "${TARGET_ROOT}/sys"; then
    mount --rbind /sys "${TARGET_ROOT}/sys"
    mount --make-rslave "${TARGET_ROOT}/sys" || true
  fi
  if ! mountpoint -q "${TARGET_ROOT}/dev"; then
    mount --rbind /dev "${TARGET_ROOT}/dev"
    mount --make-rslave "${TARGET_ROOT}/dev" || true
  fi
  if ! mountpoint -q "${TARGET_ROOT}/run"; then
    mount --rbind /run "${TARGET_ROOT}/run"
    mount --make-rslave "${TARGET_ROOT}/run" || true
  fi
  cp -L /etc/resolv.conf "${TARGET_ROOT}/etc/resolv.conf" 2>/dev/null || true
}

start_heartbeat() {
  (
    while true; do
      {
        printf '=== %s ===\n' "$(date -Is)"
        uptime || true
        awk '{printf "loadavg %s %s %s running=%s threads=%s\n",$1,$2,$3,$4,$5}' /proc/loadavg || true
        for zone in /sys/class/thermal/thermal_zone*/temp; do
          [[ -r "${zone}" ]] && printf '%s=%s\n' "${zone}" "$(cat "${zone}")"
        done
        tail -8 "${TARGET_ROOT}/var/log/emerge.log" 2>/dev/null || true
      } >>"${MARKER_DIR}/heartbeat.log" 2>&1
      sleep 30
    done
  ) &
  HEARTBEAT_PID="$!"
  echo "${HEARTBEAT_PID}" >"${MARKER_DIR}/heartbeat.pid"
}

cleanup() {
  if [[ -n "${HEARTBEAT_PID}" ]]; then
    kill "${HEARTBEAT_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

main() {
  mkdir -p "${MARKER_DIR}" "$(dirname "${LOG_FILE}")"
  write_default_package_list
  apply_cpu_caps
  mount_target_fs
  start_heartbeat
  notify "K10 local package merge started on $(hostname); target=${TARGET_ROOT}"

  set +e
  {
    printf 'START %s\n' "$(date -Is)"
    printf 'target=%s\npackage_list=%s\n' "${TARGET_ROOT}" "${PACKAGE_LIST}"
    chroot "${TARGET_ROOT}" /bin/bash -lc '
set -Eeo pipefail
env-update >/dev/null
source /etc/profile
mapfile -t packages < <(sed -e "/^[[:space:]]*#/d" -e "/^[[:space:]]*$/d" /root/k10-system-packages.list)
FEATURES="-distcc -ccache buildpkg parallel-install merge-sync -fail-clean" \
CCACHE_DISABLE=1 \
CCACHE_PREFIX= \
emerge --noreplace --verbose --oneshot "${packages[@]}"
'
  } >>"${LOG_FILE}" 2>&1
  local rc=$?
  set -e

  echo "${rc}" >"${MARKER_DIR}/system-packages.rc"
  printf 'END rc=%s %s\n' "${rc}" "$(date -Is)" >>"${LOG_FILE}"
  sync

  if [[ "${rc}" -eq 0 ]]; then
    touch "${MARKER_DIR}/system-packages.success"
    notify "K10 local package merge completed successfully; reboot_on_success=${REBOOT_ON_SUCCESS}"
    if [[ "${REBOOT_ON_SUCCESS}" == "1" ]]; then
      sleep 15
      reboot -f
    fi
  else
    touch "${MARKER_DIR}/system-packages.failed"
    notify "K10 local package merge failed rc=${rc}; leaving host online for inspection"
  fi

  return "${rc}"
}

main "$@"
