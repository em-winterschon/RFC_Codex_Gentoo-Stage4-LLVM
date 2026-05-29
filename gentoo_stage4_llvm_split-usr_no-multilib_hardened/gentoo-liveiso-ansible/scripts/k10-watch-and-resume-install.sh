#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_ROOT}/../.." && pwd)"
K10_HOST="${K10_HOST:-172.16.99.156}"
K10_TARGET="${K10_TARGET:-gmktek_nucbox_k10_stage5_candidate}"
LOG_FILE="${K10_RESUME_LOG:-/root/k10-watch-and-resume-install.$(date +%Y%m%d-%H%M%S).log}"
NTFY_URL="${K10_NTFY_URL:-http://172.16.99.96/forge-change}"
NTFY_HOST="${K10_NTFY_HOST:-msg-sun99-ntfysys.rfc1918.host}"
SLEEP_SECONDS="${K10_WATCH_SLEEP_SECONDS:-60}"

notify() {
  local body="$1"
  command -v curl > /dev/null 2>&1 || return 0
  curl -fsS --max-time 5 \
    -H "Host: ${NTFY_HOST}" \
    -H "Title: K10 Ansible resume" \
    -d "${body}" \
    "${NTFY_URL}" > /dev/null 2>&1 || true
}

ssh_k10() {
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8 "root@${K10_HOST}" "$@"
}

mount_target() {
  ssh_k10 'set -e
zpool import -f -R /mnt/gentoo rpool >/dev/null 2>&1 || true
zfs mount rpool/ROOT/gentoo >/dev/null 2>&1 || true
zfs mount -a >/dev/null 2>&1 || true
mkdir -p /mnt/gentoo/efi
mountpoint -q /mnt/gentoo/efi || mount /dev/disk/by-partlabel/EFI_SYSTEM_1 /mnt/gentoo/efi >/dev/null 2>&1 || mount /dev/disk/by-partlabel/EFI_SYSTEM_2 /mnt/gentoo/efi >/dev/null 2>&1 || true
test -d /mnt/gentoo/etc/portage
'
}

resume_ansible() {
  cd "${ANSIBLE_ROOT}"
  ANSIBLE_STDOUT_CALLBACK=default "${REPO_ROOT}/scripts/with-ansible-vault-env.sh" ansible-playbook \
    -i inventories/local-network/hosts.yml playbooks/install.yml \
    -l "${K10_TARGET}" \
    -e '{"selected_roles":["preflight","liveiso_prepare","profile","portage","chroot_base","boot","network","rsyslog_base","telemetry_node_exporter","rfc1918_ca_trust","ipa_client","workstation_session_stack","platform_profile","identity","service_readiness"],"portage_emerge_default_opts_extra":["--noreplace"]}' \
    -e install_debug_checkpoints=true
}

main() {
  mkdir -p "$(dirname "${LOG_FILE}")"
  notify "K10 watcher started; waiting for local system package marker on ${K10_HOST}"
  {
    printf 'START %s host=%s target=%s\n' "$(date -Is)" "${K10_HOST}" "${K10_TARGET}"
    while true; do
      if ! ssh_k10 'hostname >/dev/null'; then
        printf '%s ssh-unreachable; waiting\n' "$(date -Is)"
        sleep "${SLEEP_SECONDS}"
        continue
      fi

      if ! mount_target; then
        printf '%s target-root-not-ready; waiting\n' "$(date -Is)"
        sleep "${SLEEP_SECONDS}"
        continue
      fi

      if ssh_k10 'test -f /mnt/gentoo/root/k10-resume-markers/system-packages.rc'; then
        rc="$(ssh_k10 'cat /mnt/gentoo/root/k10-resume-markers/system-packages.rc')"
        printf '%s system-packages-rc=%s\n' "$(date -Is)" "${rc}"
        if [[ "${rc}" != "0" ]]; then
          notify "K10 local package merge failed rc=${rc}; Ansible resume not started"
          return "${rc}"
        fi
        notify "K10 local package merge succeeded; resuming remaining Ansible install roles"
        set +e
        resume_ansible
        ansible_rc=$?
        set -e
        printf '%s ansible-rc=%s\n' "$(date -Is)" "${ansible_rc}"
        if [[ "${ansible_rc}" -eq 0 ]]; then
          notify "K10 remaining Ansible install roles completed successfully"
        else
          notify "K10 remaining Ansible install roles failed rc=${ansible_rc}"
        fi
        return "${ansible_rc}"
      fi

      printf '%s package-pass-running; waiting\n' "$(date -Is)"
      sleep "${SLEEP_SECONDS}"
    done
  } >> "${LOG_FILE}" 2>&1
}

main "$@"
