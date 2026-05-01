#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

for role_dir in \
  container_host \
  container_app_ntfy \
  container_app_nginx \
  container_app_haproxy \
  container_net_policy \
  container_service_segments
do
  test -d "${ANSIBLE_ROOT}/roles/${role_dir}"
  test -f "${ANSIBLE_ROOT}/roles/${role_dir}/tasks/main.yml"
done

assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'container_host'
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'container_service_segments'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-service-base-image.yml" '^gentoo_profile_definition:'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-service-base-image.yml" 'ghcr.io/em-winterschon/gentoo-stage3-llvm-clang-openrc:latest'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-service-base-image.yml" 'ghcr.io/em-winterschon/gentoo-stage3-llvm-clang-openrc:git-e5bf45f'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-service-base-image.yml" 'sha256:4c0cc158b9ab55f7b126dcd80deb8327959a0fd8cd132af7fa09a438df4e85b6'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/vm-container-services.yml" '^gentoo_profile_definition:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-container-services.yml" '^profile_definition_files:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-container-services.yml" 'container-service-base-image.yml'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-container-services.yml" 'container-rsyslog-collector.yml'
assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml" 'resolved_profile_container_base_image'
assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml" 'container_base_image'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_host/tasks/main.yml" 'base-image.yml'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_host/templates/base-image.yml.j2" 'resolved_profile_container_base_image'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/vm-container-services.yml" 'ghcr.io/em-winterschon/gentoo-stage5-nginx:latest'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/vm-container-services.yml" 'ghcr.io/em-winterschon/gentoo-stage5-haproxy:latest'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/vm-container-services.yml" 'gcc-compat.conf'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-rsyslog-collector.yml" 'ghcr.io/em-winterschon/gentoo-stage5-rsyslog-collector:latest'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-rsyslog-collector.yml" 'sha256:2acfd8f06d7aa3a9524a95bade090793543c228bd62b6bf38e76302324195287'
assert_file_contains "${ANSIBLE_ROOT}/inventories/pathb-container-services/hosts.yml" '10.9.8.89'
assert_file_contains "${ANSIBLE_ROOT}/inventories/pathb-container-services/group_vars/install_targets.yml" '52:54:00:12:34:78'
assert_file_contains "${ANSIBLE_ROOT}/inventories/pathb-container-services/group_vars/install_targets.yml" 'portage_seed_gentoo_repo_from_liveiso: true'
assert_file_contains "${ANSIBLE_ROOT}/inventories/pathb-container-services/group_vars/install_targets.yml" 'portage_initialize_binpkg_trust: true'
assert_file_contains "${ANSIBLE_ROOT}/inventories/pathb-container-services/host_vars/vm_container_services.yml" 'container-haproxy-elasticsearch-test-vip.yml'
assert_file_contains "${ANSIBLE_ROOT}/inventories/pathb-container-services/host_vars/vm_container_services.yml" 'elasticsearch-test-vip-http'
assert_file_contains "${ANSIBLE_ROOT}/roles/chroot_base/tasks/main.yml" 'Seed Gentoo repository from LiveISO'
assert_file_contains "${ANSIBLE_ROOT}/roles/chroot_base/tasks/main.yml" 'Initialize Portage binary package trust in target'
assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" '-name vmlinuz'
assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" '-xtype f'
assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" 'usepkg-exclude sys-fs/zfs-kmod'
assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" 'Assert selected target kernel has a ZFS module'
assert_file_contains "${ANSIBLE_ROOT}/roles/storage/tasks/layout_zfs_native.yml" 'Preserve provisioning hostid for target root-on-ZFS imports'
assert_file_contains "${ANSIBLE_ROOT}/roles/storage/tasks/layout_mdadm.yml" 'Preserve provisioning hostid for target root-on-ZFS imports'
assert_file_contains "${ANSIBLE_ROOT}/roles/storage/tasks/layout_zfs_native.yml" 'Mount target child ZFS datasets after root dataset'
assert_file_contains "${ANSIBLE_ROOT}/roles/storage/tasks/layout_mdadm.yml" 'Mount target child ZFS datasets after root dataset'
assert_file_contains "${ANSIBLE_ROOT}/roles/chroot_base/tasks/main.yml" 'Ensure target ZFS child datasets are mounted before chroot writes'
assert_file_contains "${ANSIBLE_ROOT}/roles/memory_storage/tasks/main.yml" 'zfs mount -a'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_net_policy/templates/nftables.conf.j2" 'port_map.*-2'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_net_policy/templates/nftables.conf.j2" 'oifname "podman\*" accept'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_service_segments/templates/podman-app-run.sh.j2" '--tmpfs'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_service_segments/templates/podman-app-run.sh.j2" '--pull'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_nginx/tasks/main.yml" '/usr/sbin/nginx'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_nginx/tasks/main.yml" 'pull_policy'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_nginx/tasks/main.yml" '/dev/stderr'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_nginx/templates/nginx.conf.j2" 'mime.types.nginx'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_nginx/templates/nginx.conf.j2" 'types_hash_max_size 4096'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_haproxy/tasks/main.yml" '/usr/sbin/haproxy'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_haproxy/tasks/main.yml" 'pull_policy'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_haproxy/tasks/main.yml" '/etc/haproxy/haproxy.cfg'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_haproxy/templates/haproxy.cfg.j2" 'user haproxy'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_haproxy/templates/haproxy.cfg.j2" 'group haproxy'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_rsyslog_collector/tasks/main.yml" '/usr/sbin/rsyslogd'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_rsyslog_collector/tasks/main.yml" 'pull_policy'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_rsyslog_collector/tasks/main.yml" '/var/spool/rsyslog'
assert_file_contains "${ANSIBLE_ROOT}/inventories/pathb-container-services/host_vars/vm_container_services.yml" 'pull_policy: never'

ANSIBLE_ROOT="${ANSIBLE_ROOT}" python3 - <<'PY'
import os
import shlex
from pathlib import Path

import yaml
from jinja2 import Environment, StrictUndefined

ansible_root = Path(os.environ["ANSIBLE_ROOT"])
vm_profile = yaml.safe_load((ansible_root / "profile-definitions/vm-container-services.yml").read_text(encoding="utf-8"))
haproxy_caps = set(
    vm_profile["gentoo_profile_definition"]["container_app_profiles"]["haproxy"]["cap_add"]
)
for expected_cap in ("NET_BIND_SERVICE", "SETGID", "SETUID"):
    if expected_cap not in haproxy_caps:
        raise SystemExit(f"missing HAProxy capability: {expected_cap}")

template_path = ansible_root / "roles/container_app_haproxy/templates/haproxy.cfg.j2"
env = Environment(undefined=StrictUndefined, trim_blocks=False, lstrip_blocks=False)
env.filters["bool"] = bool
env.filters["quote"] = shlex.quote
template = env.from_string(
    template_path.read_text(encoding="utf-8")
)
rendered = template.render(
    resolved_haproxy_service_types_local=[
        {
            "name": "syslog-tcp",
            "mode": "tcp",
            "bind": "*:6514",
            "backend_name": "be_syslog_tcp",
            "servers": [{"name": "rsyslog-collector", "address": "10.77.0.40", "port": 514}],
        }
    ],
    container_runtime_applications=[
        {"name": "nginx", "ip_address": "10.77.1.30"},
        {"name": "ntfy", "ip_address": "10.77.1.20"},
    ],
)

for expected in ("frontend fe_syslog_tcp", "frontend fe_http", "backend be_nginx", "backend be_ntfy"):
    if expected not in rendered:
        raise SystemExit(f"missing rendered HAProxy section: {expected}")

nft_template_path = ansible_root / "roles/container_net_policy/templates/nftables.conf.j2"
nft_template = env.from_string(
    nft_template_path.read_text(encoding="utf-8")
)
nft_rendered = nft_template.render(
    resolved_site_security_profile_local={
        "firewall": {
            "default_policy_input": "drop",
            "default_policy_forward": "drop",
            "default_policy_output": "accept",
            "allowed_management_cidrs": ["10.9.8.0/24"],
            "enable_container_nat": True,
        }
    },
    container_runtime_applications=[
        {
            "name": "haproxy",
            "published_ports": [
                "80:80/tcp",
                "443:443/tcp",
                "10.9.8.92:9200:9200/tcp",
            ],
        }
    ],
)

if "tcp dport 9200 accept" not in nft_rendered:
    raise SystemExit("nftables render did not expose the VIP host port")
if "dport 10.9.8.92" in nft_rendered:
    raise SystemExit("nftables render used the VIP address as a port")

podman_template_path = ansible_root / "roles/container_service_segments/templates/podman-app-run.sh.j2"
podman_template = env.from_string(
    podman_template_path.read_text(encoding="utf-8")
)
podman_rendered = podman_template.render(
    container_runtime_app={
        "name": "ntfy",
        "image": "docker.io/binwiederhier/ntfy:v2.14.0",
        "pull_policy": "never",
        "network": "apps",
        "published_ports": [],
        "volumes": [],
        "tmpfs": [],
        "environment": {},
        "command": ["serve"],
    },
    resolved_profile_site_security_profile={
        "isolation": {
            "read_only_rootfs": True,
            "drop_capabilities": True,
            "userns": "host",
        }
    },
)

if "--pull never" not in podman_rendered:
    raise SystemExit("podman wrapper render did not include pull policy")
PY

printf 'PASS: %s\n' "$(basename "$0")"
