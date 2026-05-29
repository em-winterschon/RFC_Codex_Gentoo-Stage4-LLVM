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
  local file=$1
  local pattern=$2
  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -q -- "${pattern}" "${file}" || fail "expected ${pattern} in ${file}"
}

profile="${ANSIBLE_ROOT}/profile-definitions/vm-mcp-control-plane.yml"
metadata="${ANSIBLE_ROOT}/profile-definitions/vm-mcp-control-plane.metadata.yml"
inventory="${ANSIBLE_ROOT}/inventories/local-network/hosts.yml"
intake="${ANSIBLE_ROOT}/inventory-intake/sites/local-rfc1918-lab.yml"
nginx_ui_role="${ANSIBLE_ROOT}/roles/container_app_nginx_ui"
mcp_generic_role="${ANSIBLE_ROOT}/roles/container_app_mcp_generic"
haproxy_template="${ANSIBLE_ROOT}/roles/container_app_haproxy/templates/haproxy.cfg.j2"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"

assert_file_contains "${profile}" '^gentoo_profile_definition:'
assert_file_contains "${profile}" 'vm-mcp-control-plane'
assert_file_contains "${profile}" 'nginx_ui:'
assert_file_contains "${profile}" 'uozi/nginx-ui:latest'
assert_file_contains "${profile}" 'NGINX_UI_NODE_SECRET'
assert_file_contains "${profile}" 'vault_nginx_ui_node_secret'
assert_file_contains "${profile}" 'NGINX_UI_OPENAI_BASE_URL'
assert_file_contains "${profile}" 'NGINX_UI_OPENAI_TOKEN'
assert_file_contains "${profile}" 'vault_nginx_ui_openai_token'
assert_file_contains "${profile}" 'mcp_generic:'
assert_file_contains "${profile}" 'mcp-control-plane.rfc1918.host'
assert_file_contains "${profile}" 'mcp-generic.rfc1918.host'
assert_file_contains "${profile}" 'log_requests: false'
assert_file_contains "${metadata}" 'vm-mcp-control-plane'
assert_file_contains "${inventory}" 'mcp_control_plane_hosts:'
assert_file_contains "${inventory}" 'vm_mcp_control_plane:'
assert_file_contains "${inventory}" 'ansible_host: 172.16.99.68'
assert_file_contains "${inventory}" 'service_tls_id: mcp_control_plane'
assert_file_contains "${inventory}" 'vault_nginx_ui_secrets_present'
assert_file_contains "${inventory}" 'haproxy_query_string_logging_disabled'
assert_file_contains "${inventory}" 'docker_socket_disabled'
assert_file_contains "${intake}" 'vm_mcp_control_plane'
assert_file_contains "${intake}" 'management_ip: 172.16.99.68'
assert_file_contains "${intake}" 'mcp-control-plane.rfc1918.host'
assert_file_contains "${intake}" 'nginx-ui.rfc1918.host'
assert_file_contains "${intake}" 'mcp-generic.rfc1918.host'
assert_file_contains "${intake}" 'service_tls_id: mcp_control_plane'

for role_dir in "${nginx_ui_role}" "${mcp_generic_role}"; do
  test -d "${role_dir}" || fail "missing role ${role_dir}"
  test -f "${role_dir}/defaults/main.yml" || fail "missing role defaults ${role_dir}"
  test -f "${role_dir}/tasks/main.yml" || fail "missing role tasks ${role_dir}"
done

assert_file_contains "${nginx_ui_role}/tasks/main.yml" 'container_nginx_ui_profile'
assert_file_contains "${nginx_ui_role}/tasks/main.yml" 'container_runtime_applications'
assert_file_contains "${nginx_ui_role}/tasks/main.yml" '/etc/nginx-ui'
assert_file_contains "${nginx_ui_role}/tasks/main.yml" '/etc/nginx'
assert_file_contains "${nginx_ui_role}/tasks/main.yml" 'docker_socket_enabled'
assert_file_contains "${mcp_generic_role}/tasks/main.yml" 'container_mcp_generic_profile'
assert_file_contains "${mcp_generic_role}/tasks/main.yml" 'MCP_SERVER_TRANSPORT'
assert_file_contains "${mcp_generic_role}/tasks/main.yml" 'container_runtime_applications'

assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'container_app_nginx_ui'
assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'container_app_mcp_generic'
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'container_app_nginx_ui'
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'container_app_mcp_generic'

assert_file_contains "${haproxy_template}" 'nginx_ui'
assert_file_contains "${haproxy_template}" 'mcp_generic'
assert_file_contains "${haproxy_template}" 'path_beg /mcp'
assert_file_contains "${haproxy_template}" 'option dontlog-normal'

assert_file_contains "${REPO_ROOT}/docs/MCP-CONTROL-PLANE.md" 'Nginx-UI'
assert_file_contains "${REPO_ROOT}/docs/MCP-CONTROL-PLANE.md" 'node_secret'
assert_file_contains "${REPO_ROOT}/docs/MCP-CONTROL-PLANE.md" 'Live Readiness Gates'
assert_file_contains "${REPO_ROOT}/docs/MCP-CONTROL-PLANE.md" '172.16.99.68'
assert_file_contains "${REPO_ROOT}/docs/wiki/MCP-Control-Plane.md" 'Nginx-UI'
assert_file_contains "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md" 'MCP-001'
assert_file_contains "${REPO_ROOT}/docs/wiki/Roadmap-and-TODO.md" 'MCP-001'
assert_file_contains "${run_tests}" 'test_mcp_control_plane_services.sh'

ANSIBLE_ROOT="${ANSIBLE_ROOT}" python3 - << 'PY'
import os
import shlex
from pathlib import Path

import yaml
from jinja2 import Environment, StrictUndefined

ansible_root = Path(os.environ["ANSIBLE_ROOT"])
profile = yaml.safe_load((ansible_root / "profile-definitions/vm-mcp-control-plane.yml").read_text(encoding="utf-8"))
apps = profile["gentoo_profile_definition"]["container_app_profiles"]
inventory = yaml.safe_load((ansible_root / "inventories/local-network/hosts.yml").read_text(encoding="utf-8"))
intake = yaml.safe_load((ansible_root / "inventory-intake/sites/local-rfc1918-lab.yml").read_text(encoding="utf-8"))

nginx_ui = apps["nginx_ui"]
if nginx_ui["docker_socket_enabled"] is not False:
    raise SystemExit("Nginx-UI Docker socket must default disabled")
if nginx_ui["env"]["NGINX_UI_NODE_SECRET"] != "{{ vault_nginx_ui_node_secret }}":
    raise SystemExit("Nginx-UI node secret must be vault-backed")
if nginx_ui["env"]["NGINX_UI_OPENAI_TOKEN"] != "{{ vault_nginx_ui_openai_token }}":
    raise SystemExit("Nginx-UI OpenAI token must be vault-backed")

haproxy = apps["haproxy"]
service_names = {item["name"] for item in haproxy["mcp_routes"]}
if {"nginx-ui-mcp", "generic-mcp"} - service_names:
    raise SystemExit("HAProxy MCP routes missing expected services")

mcp_host = inventory["all"]["children"]["mcp_control_plane_hosts"]["hosts"]["vm_mcp_control_plane"]
if mcp_host["ansible_host"] != "172.16.99.68":
    raise SystemExit("MCP control-plane inventory host must use 172.16.99.68")
if mcp_host["stage5_profile"] != "vm-mcp-control-plane":
    raise SystemExit("MCP control-plane inventory host must use vm-mcp-control-plane profile")
if mcp_host["service_tls_id"] != "mcp_control_plane":
    raise SystemExit("MCP control-plane inventory host must link to mcp_control_plane TLS service")
required_gates = {
    "vault_nginx_ui_secrets_present",
    "rfc1918_tls_material_present",
    "dns_records_present",
    "haproxy_query_string_logging_disabled",
    "docker_socket_disabled",
}
if required_gates - set(mcp_host.get("mcp_control_plane_readiness_gates", [])):
    raise SystemExit("MCP control-plane readiness gates are incomplete")

devices = {item["name"]: item for item in intake.get("devices", [])}
service_vips = {item["name"]: item for item in intake.get("service_vips", [])}
if devices["vm_mcp_control_plane"]["management_ip"] != "172.16.99.68":
    raise SystemExit("MCP control-plane NetBox intake device must use 172.16.99.68")
if devices["vm_mcp_control_plane"]["stage5_profile"] != "vm-mcp-control-plane":
    raise SystemExit("MCP control-plane NetBox intake device must track stage5 profile")
if service_vips["mcp-control-plane"]["address"] != "172.16.99.68":
    raise SystemExit("MCP control-plane service VIP must use 172.16.99.68")
if "nginx-ui.rfc1918.host" not in service_vips["mcp-control-plane"].get("aliases", []):
    raise SystemExit("MCP control-plane service VIP missing nginx-ui alias")

env = Environment(undefined=StrictUndefined, trim_blocks=False, lstrip_blocks=False)
env.filters["bool"] = bool
env.filters["quote"] = shlex.quote
template = env.from_string((ansible_root / "roles/container_app_haproxy/templates/haproxy.cfg.j2").read_text(encoding="utf-8"))
rendered = template.render(
    resolved_haproxy_service_types_local=[],
    container_haproxy_profile=haproxy,
    container_runtime_applications=[
        {
            "name": "nginx-ui",
            "ip_address": "10.77.1.60",
            "backend_port": 80,
            "hostnames": ["mcp-control-plane.rfc1918.host"],
        },
        {
            "name": "mcp-generic",
            "ip_address": "10.77.1.61",
            "backend_port": 3000,
            "hostnames": ["mcp-generic.rfc1918.host"],
        },
    ],
)
for expected in (
    "acl host_nginx_ui",
    "acl path_nginx_ui_mcp path_beg /mcp",
    "use_backend be_nginx_ui_mcp if host_nginx_ui path_nginx_ui_mcp",
    "backend be_nginx_ui_mcp",
    "option dontlog-normal",
    "server nginx-ui 10.77.1.60:80 check",
    "server mcp-generic 10.77.1.61:3000 check",
):
    if expected not in rendered:
        raise SystemExit(f"missing rendered MCP HAProxy detail: {expected}")
PY

printf 'PASS: %s\n' "$(basename "$0")"
