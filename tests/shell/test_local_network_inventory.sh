#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"

  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -Fq "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

inventory="${ANSIBLE_ROOT}/inventories/local-network/hosts.yml"
hasslehoff_vars="${ANSIBLE_ROOT}/inventories/local-network/host_vars/hasslehoff.yml"
network_fabric="${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/network_fabric.yml"
metrics_storage="${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/observability_metrics_storage.yml"
vault_file="${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/vault.yml"
obs_prometheus_vars="${ANSIBLE_ROOT}/inventories/local-network/host_vars/obs_sun99_prometheus_099064.yml"
obs_vmetrics_vars="${ANSIBLE_ROOT}/inventories/local-network/host_vars/obs_sun99_vmetrics_099065.yml"
obs_grafana_vars="${ANSIBLE_ROOT}/inventories/local-network/host_vars/obs_sun99_grafana_099066.yml"
obs_kibana_vars="${ANSIBLE_ROOT}/inventories/local-network/host_vars/obs_sun99_kibana_099067.yml"
playbook="${ANSIBLE_ROOT}/playbooks/local-network-inventory.yml"
proxmox_api_playbook="${ANSIBLE_ROOT}/playbooks/proxmox-api-validate.yml"
netbox_api_playbook="${ANSIBLE_ROOT}/playbooks/netbox-api-validate.yml"
swos_snapshot_playbook="${ANSIBLE_ROOT}/playbooks/swos-state-snapshot.yml"
routeros_snapshot_playbook="${ANSIBLE_ROOT}/playbooks/routeros-state-snapshot.yml"
routeros_spine_playbook="${ANSIBLE_ROOT}/playbooks/routeros-spine-distribution.yml"
routeros_spine_role="${ANSIBLE_ROOT}/roles/routeros_spine_distribution"
swos_snapshot_script="${REPO_ROOT}/scripts/collect-mikrotik-swos-state.py"
routeros_snapshot_script="${REPO_ROOT}/scripts/collect-mikrotik-routeros-state.py"

assert_file_contains "${inventory}" "hasslehoff:"
assert_file_contains "${inventory}" "svc_netbox_stage4:"
assert_file_contains "${inventory}" "parent_proxmox_vmid: 1062"
assert_file_contains "${inventory}" "netbox_api_url: http://172.16.99.62"
assert_file_contains "${inventory}" "identity_controllers:"
assert_file_contains "${inventory}" "svc_identity_ipa01:"
assert_file_contains "${inventory}" "parent_proxmox_vmid: 1063"
assert_file_contains "${inventory}" "freeipa_fqdn: ipa01.rfc1918.host"
assert_file_contains "${inventory}" "proxmox_api_token_secret: \"{{ vault_hasslehoff_proxmox_api_token_secret }}\""
assert_file_contains "${inventory}" "observability_prometheus:"
assert_file_contains "${inventory}" "obs_sun99_prometheus_099064:"
assert_file_contains "${inventory}" "ansible_host: 172.16.99.64"
assert_file_contains "${inventory}" "parent_proxmox_vmid: 1064"
assert_file_contains "${inventory}" "stage5_profile: vm-observability-prometheus"
assert_file_contains "${inventory}" "observability_victoriametrics:"
assert_file_contains "${inventory}" "obs_sun99_vmetrics_099065:"
assert_file_contains "${inventory}" "ansible_host: 172.16.99.65"
assert_file_contains "${inventory}" "parent_proxmox_vmid: 1065"
assert_file_contains "${inventory}" "stage5_profile: vm-observability-victoriametrics"
assert_file_contains "${inventory}" "observability_grafana:"
assert_file_contains "${inventory}" "obs_sun99_grafana_099066:"
assert_file_contains "${inventory}" "ansible_host: 172.16.99.66"
assert_file_contains "${inventory}" "parent_proxmox_vmid: 1066"
assert_file_contains "${inventory}" "stage5_profile: vm-observability-grafana"
assert_file_contains "${inventory}" "observability_kibana:"
assert_file_contains "${inventory}" "obs_sun99_kibana_099067:"
assert_file_contains "${inventory}" "ansible_host: 172.16.99.67"
assert_file_contains "${inventory}" "parent_proxmox_vmid: 1067"
assert_file_contains "${inventory}" "stage5_profile: vm-kibana-interface"
assert_file_contains "${inventory}" "sw_mgmt_mkcrs354:"
assert_file_contains "${inventory}" "routeros_serial_console: /dev/ttyUSB1"
assert_file_contains "${inventory}" "sw_spine_crs309_rfc99:"
assert_file_contains "${inventory}" "routeros_serial_console: /dev/ttyUSB0"
assert_file_contains "${inventory}" "routeros_state_snapshot_enabled: true"
assert_file_contains "${inventory}" "routeros_state_snapshot_enabled: false"
assert_file_contains "${inventory}" "rtr_mgmt_ccr2004:"
assert_file_contains "${inventory}" "gw_rfc99_mkccr2004_16g:"
assert_file_contains "${inventory}" "vault_rfc99_ccr2004_16g_admin_password"
assert_file_contains "${inventory}" "gmktek_nucbox_k10_stage5_candidate:"
assert_file_contains "${inventory}" "netboot_mac_address: \"84:47:09:5F:21:64\""
assert_file_contains "${inventory}" "netboot_static_address: 172.16.99.156"
assert_file_contains "${inventory}" "netboot_next_server: 172.16.99.108"
assert_file_contains "${inventory}" "netboot_bootfile_name: k10-ipxe.efi"
assert_file_contains "${inventory}" "netboot_tftp_root: /var/lib/netboot/path-b"
assert_file_contains "${inventory}" "netboot_firmware_policy: uefi-pxe-efi-only"
assert_file_contains "${inventory}" "sw_mgmt_css326:"
assert_file_contains "${inventory}" "swos_identity: sw-mgmt-mkcss326"
assert_file_contains "${inventory}" "swos_observed_version: 2.18.1751448030"
assert_file_contains "${inventory}" "swos_syslog_supported: false"
assert_file_contains "${inventory}" "rsyslog_vip: 172.16.99.93"
assert_file_contains "${inventory}" "rsyslog_hostname: log-sun99-rsyslog-099093.rfc1918.host"

assert_file_contains "${hasslehoff_vars}" "local_inventory_observed:"
assert_file_contains "${hasslehoff_vars}" "proxmox_observed_vms:"
assert_file_contains "${hasslehoff_vars}" "gw-rfc99-vyos-routeprime"
assert_file_contains "${hasslehoff_vars}" "svc-netbox-stage4"
assert_file_contains "${hasslehoff_vars}" "svc-identity-ipa01"
assert_file_contains "${hasslehoff_vars}" "Stage4 Gentoo replacement NetBox VM"
assert_file_contains "${hasslehoff_vars}" "Rocky 9 FreeIPA controller candidate"

assert_file_contains "${obs_prometheus_vars}" "vm-observability-prometheus.yml"
assert_file_contains "${obs_prometheus_vars}" "install_hostname: obs-sun99-prometheus-099064"
assert_file_contains "${obs_prometheus_vars}" "forward_hostname: log-sun99-rsyslog.rfc1918.host"
assert_file_contains "${obs_prometheus_vars}" "forward_port: 6514"
assert_file_contains "${obs_prometheus_vars}" "external_url: https://obs-sun99-prometheus.rfc1918.host/"
assert_file_contains "${obs_vmetrics_vars}" "vm-observability-victoriametrics.yml"
assert_file_contains "${obs_vmetrics_vars}" "install_hostname: obs-sun99-vmetrics-099065"
assert_file_contains "${obs_vmetrics_vars}" "forward_hostname: log-sun99-rsyslog.rfc1918.host"
assert_file_contains "${obs_vmetrics_vars}" "forward_port: 6514"
assert_file_contains "${obs_vmetrics_vars}" "src: hasslehoff.rfc1918.host:/srv/exports/metrics/victoriametrics"
assert_file_contains "${obs_vmetrics_vars}" "data_path: /srv/metrics/victoriametrics"
assert_file_contains "${obs_grafana_vars}" "vm-observability-grafana.yml"
assert_file_contains "${obs_grafana_vars}" "install_hostname: obs-sun99-grafana-099066"
assert_file_contains "${obs_grafana_vars}" "forward_hostname: log-sun99-rsyslog.rfc1918.host"
assert_file_contains "${obs_grafana_vars}" "forward_port: 6514"
assert_file_contains "${obs_grafana_vars}" "root_url: https://obs-sun99-grafana.rfc1918.host/"
assert_file_contains "${obs_kibana_vars}" "vm-kibana-interface.yml"
assert_file_contains "${obs_kibana_vars}" "install_hostname: obs-sun99-kibana-099067"
assert_file_contains "${obs_kibana_vars}" "forward_hostname: log-sun99-rsyslog.rfc1918.host"
assert_file_contains "${obs_kibana_vars}" "forward_port: 6514"
assert_file_contains "${obs_kibana_vars}" "server_name: obs-sun99-kibana.rfc1918.host"
assert_file_contains "${obs_kibana_vars}" "http://172.16.99.92:9200"

assert_file_contains "${network_fabric}" "hasslehoff-bond0"
assert_file_contains "${network_fabric}" "svc_netbox_stage4"
assert_file_contains "${network_fabric}" "proxmox_vmid: 1062"
assert_file_contains "${network_fabric}" "api_url: http://172.16.99.62"
assert_file_contains "${network_fabric}" "svc_identity_ipa01"
assert_file_contains "${network_fabric}" "proxmox_vmid: 1063"
assert_file_contains "${network_fabric}" "ipa01.rfc1918.host"
assert_file_contains "${network_fabric}" "obs_sun99_prometheus_099064"
assert_file_contains "${network_fabric}" "proxmox_vmid: 1064"
assert_file_contains "${network_fabric}" "obs-sun99-prometheus-099064.rfc1918.host"
assert_file_contains "${network_fabric}" "obs_sun99_vmetrics_099065"
assert_file_contains "${network_fabric}" "proxmox_vmid: 1065"
assert_file_contains "${network_fabric}" "obs-sun99-vmetrics-099065.rfc1918.host"
assert_file_contains "${network_fabric}" "obs_sun99_grafana_099066"
assert_file_contains "${network_fabric}" "proxmox_vmid: 1066"
assert_file_contains "${network_fabric}" "obs-sun99-grafana-099066.rfc1918.host"
assert_file_contains "${network_fabric}" "obs_sun99_kibana_099067"
assert_file_contains "${network_fabric}" "proxmox_vmid: 1067"
assert_file_contains "${network_fabric}" "obs-sun99-kibana-099067.rfc1918.host"
assert_file_contains "${network_fabric}" "llm-rag-service-control"
assert_file_contains "${network_fabric}" "llm-rag-inference-data"
assert_file_contains "${network_fabric}" "gw_rfc99_mkccr2004_16g"
assert_file_contains "${network_fabric}" "CCR2004-16G-2S+PC"
assert_file_contains "${network_fabric}" "network_fabric_media_defaults:"
assert_file_contains "${network_fabric}" "SFP-10GSR-85"
assert_file_contains "${network_fabric}" "AXS85-192-M3"
assert_file_contains "${network_fabric}" "sw_spine_crs309_rfc99"
assert_file_contains "${network_fabric}" "observed_routeros_version: 7.22.2"
assert_file_contains "${network_fabric}" "sw_mgmt_css326"
assert_file_contains "${network_fabric}" "observed_swos_version: 2.18.1751448030"
assert_file_contains "${network_fabric}" "syslog:"
assert_file_contains "${network_fabric}" "supported: false"
assert_file_contains "${network_fabric}" "qnap_archive_ts435xeu"
assert_file_contains "${network_fabric}" "crs309-crs354-lag"
assert_file_contains "${network_fabric}" "qnap-ts435xeu-bond0"
assert_file_contains "${metrics_storage}" "observability_metrics_storage:"
assert_file_contains "${metrics_storage}" "provider_host: hasslehoff"
assert_file_contains "${metrics_storage}" "provider_address: 172.16.99.9"
assert_file_contains "${metrics_storage}" "export_path: /srv/exports/metrics/victoriametrics"
assert_file_contains "${metrics_storage}" "client_mountpoint: /srv/metrics/victoriametrics"
assert_file_contains "${metrics_storage}" "nfsv4_tcp_rbac_uid_gid"
assert_file_contains "${metrics_storage}" "nfs_rdma"
assert_file_contains "${metrics_storage}" "nfs_multipath"
assert_file_contains "${swos_snapshot_script}" "HTTPDigestAuthHandler"
python3 -m py_compile "${swos_snapshot_script}"
assert_file_contains "${routeros_snapshot_script}" "sshpass"
assert_file_contains "${routeros_snapshot_script}" "timeout"
assert_file_contains "${routeros_snapshot_script}" "export hide-sensitive"
python3 -m py_compile "${routeros_snapshot_script}"
assert_file_contains "${swos_snapshot_playbook}" "Capture MikroTik SwOS state snapshots"
assert_file_contains "${swos_snapshot_playbook}" "SWOS_PASSWORD"
assert_file_contains "${swos_snapshot_playbook}" "no_log: true"
assert_file_contains "${routeros_snapshot_playbook}" "Capture MikroTik RouterOS state snapshots"
assert_file_contains "${routeros_snapshot_playbook}" "ROUTEROS_PASSWORD"
assert_file_contains "${routeros_snapshot_playbook}" "routeros_snapshot_enabled_effective"
assert_file_contains "${routeros_snapshot_playbook}" "allow-failures"
assert_file_contains "${routeros_spine_playbook}" "routeros_spine_distribution"
assert_file_contains "${routeros_spine_role}/defaults/main.yml" "routeros_spine_distribution_target_version: 7.22.2"
assert_file_contains "${routeros_spine_role}/defaults/main.yml" "bond-crs354"
assert_file_contains "${routeros_spine_role}/defaults/main.yml" "172.16.254.7/24"
assert_file_contains "${routeros_spine_role}/templates/routeros-spine-distribution-manifest.json.j2" "RouterOSSpineDistributionManifest"

head -n 1 "${vault_file}" | grep -q '^\$ANSIBLE_VAULT;' ||
  fail "local-network vault is not encrypted"

assert_file_contains "${playbook}" "Capture local network inventory snapshots"
assert_file_contains "${playbook}" "pvesh"
assert_file_contains "${playbook}" "local_network_snapshot_root"

assert_file_contains "${proxmox_api_playbook}" "Validate Proxmox API access"
assert_file_contains "${proxmox_api_playbook}" "PVEAPIToken={{ proxmox_api_token_id }}={{ proxmox_api_token_secret }}"
assert_file_contains "${proxmox_api_playbook}" "no_log: true"

assert_file_contains "${netbox_api_playbook}" "Validate NetBox API reachability"
assert_file_contains "${netbox_api_playbook}" "Authorization"
assert_file_contains "${netbox_api_playbook}" "netbox_api_token_file"
assert_file_contains "${netbox_api_playbook}" "netbox_api_auth_header"
assert_file_contains "${netbox_api_playbook}" "no_log: true"

if command -v ansible-playbook > /dev/null 2>&1; then
  tmp_inventory="$(mktemp --suffix=.yml)"
  trap 'rm -f "${tmp_inventory}"' EXIT
  cat > "${tmp_inventory}" << 'EOF'
---
all:
  children:
    proxmox_hypervisors:
      hosts:
        syntax_hasslehoff:
          ansible_connection: local
    netbox_services:
      hosts:
        syntax_netbox:
          ansible_connection: local
    mikrotik_swos:
      hosts:
        syntax_swos:
          ansible_connection: local
          ansible_host: 127.0.0.1
          swos_username: admin
          swos_password: syntax-only
    mikrotik_routeros:
      hosts:
        syntax_routeros:
          ansible_connection: local
          ansible_host: 127.0.0.1
          ansible_user: admin
          ansible_password: syntax-only
EOF
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${playbook}" > /dev/null
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${proxmox_api_playbook}" > /dev/null
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${netbox_api_playbook}" > /dev/null
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${swos_snapshot_playbook}" > /dev/null
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${routeros_snapshot_playbook}" > /dev/null
  ANSIBLE_ROLES_PATH="${ANSIBLE_ROOT}/roles" ansible-playbook --syntax-check -i "${tmp_inventory}" "${routeros_spine_playbook}" > /dev/null
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
