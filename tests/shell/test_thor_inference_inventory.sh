#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

inventory="${ANSIBLE_ROOT}/inventories/local-network/hosts.yml"
thor_vars="${ANSIBLE_ROOT}/inventories/local-network/host_vars/agx_rfc99_bunnydev_099034.yml"

[[ -f "${inventory}" ]] || fail "missing local-network inventory"
[[ -f "${thor_vars}" ]] || fail "missing Thor host_vars"

ANSIBLE_ROOT="${ANSIBLE_ROOT}" python3 - << 'PYTHON'
import os
from pathlib import Path

import yaml

ansible_root = Path(os.environ["ANSIBLE_ROOT"])
inventory = yaml.safe_load(
    (ansible_root / "inventories/local-network/hosts.yml").read_text(encoding="utf-8")
)
host_vars = yaml.safe_load(
    (
        ansible_root
        / "inventories/local-network/host_vars/agx_rfc99_bunnydev_099034.yml"
    ).read_text(encoding="utf-8")
)

children = inventory["all"]["children"]
gpu_compute = children["gpu_compute"]["hosts"]
ollama_servers = children["ollama_servers"]["hosts"]
open_webui_servers = children["open_webui_servers"]["hosts"]
vllm_servers = children["vllm_servers"]["hosts"]
sglang_servers = children["sglang_servers"]["hosts"]

host = gpu_compute.get("agx_rfc99_bunnydev_099034")
if not isinstance(host, dict):
    raise SystemExit("Thor must be modeled as gpu_compute host agx_rfc99_bunnydev_099034")

expected_host_fields = {
    "ansible_host": "172.16.99.34",
    "ansible_user": "root",
    "local_network_role": "inference-gpu-host",
    "fqdn": "agx-rfc99-bunnydev.rfc1918.host",
    "observed_service_ip": "172.16.99.34",
    "inference_service_container_engine": "podman",
    "inference_service_accelerator": "nvidia",
    "inference_service_manager": "systemd",
}
for key, expected in expected_host_fields.items():
    if host.get(key) != expected:
        raise SystemExit(f"Thor inventory {key} must be {expected!r}")

if "agx_rfc99_bunnydev_099034" not in ollama_servers:
    raise SystemExit("Thor must be in ollama_servers for first engine validation")
if "agx_rfc99_bunnydev_099034" not in open_webui_servers:
    raise SystemExit("Thor must be in open_webui_servers for first frontend validation")
if "agx_rfc99_bunnydev_099034" in vllm_servers:
    raise SystemExit("Thor vLLM must stay deferred until arm64/L4T/CUDA image validation")
if "agx_rfc99_bunnydev_099034" in sglang_servers:
    raise SystemExit("Thor SGLang must stay deferred until arm64/L4T/CUDA image validation")

expected_vars = {
    "inference_service_architecture": "arm64",
    "inference_service_accelerator": "nvidia",
    "inference_service_container_engine": "podman",
    "inference_service_manager": "systemd",
}
for key, expected in expected_vars.items():
    if host_vars.get(key) != expected:
        raise SystemExit(f"Thor host_vars {key} must be {expected!r}")

if host_vars.get("inference_service_allow_docker_exception") is not None:
    raise SystemExit("Thor host_vars must not enable Docker exception deployment")

if host_vars.get("inference_service_cdi_devices") != ["nvidia.com/gpu=all"]:
    raise SystemExit("Thor host_vars must pin NVIDIA CDI device nvidia.com/gpu=all")

blocked = set(host_vars.get("inference_service_deferred_backends", []))
if blocked != {"vllm", "sglang"}:
    raise SystemExit("Thor deferred backend list must be exactly vllm and sglang")

live_audit = host_vars.get("inference_service_live_audit", {})
if live_audit.get("podman_present") is not True:
    raise SystemExit("Thor live audit must record Podman present")
if live_audit.get("docker_active") is not False:
    raise SystemExit("Thor live audit must record Docker inactive")
if "nvidia.com/gpu=all" not in live_audit.get("nvidia_cdi", {}).get("devices", []):
    raise SystemExit("Thor live audit must record NVIDIA CDI devices")
PYTHON

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
