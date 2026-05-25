# Thor AGX Inference Readiness

Audit timestamp: `2026-05-24T03:15:49Z`

Target:

```text
agx-rfc99-bunnydev.rfc1918.host
172.16.99.34/24
ssh alias: thor
```

## Summary

Thor is reachable and has a working NVIDIA Thor GPU stack, but it is not yet
ready for the shared Podman-first inference role without either a Podman/CDI prep
step or an explicitly approved temporary Docker exception.

The safest first workload sequence is:

1. preserve headless multi-user operation;
2. resolve the current failed `openipmi.service` state;
3. validate or install Podman with NVIDIA CDI, or approve a Docker exception;
4. deploy Ollama and Open WebUI first;
5. defer vLLM and SGLang until arm64/L4T/CUDA 13 images are validated.

## 2026-05-25 Update

Operator approval authorized Thor inference playbook testing and deployment
work. Forge3 completed the repeatable non-runtime deployment lane:

- inventory host `agx_rfc99_bunnydev_099034` now targets Thor at
  `172.16.99.34`;
- Thor is a member of `ollama_servers` and `open_webui_servers` only;
- `vllm_servers` and `sglang_servers` intentionally do not include Thor;
- Ansible ping succeeds through the M70 root automation SSH path;
- Ollama and Open WebUI syntax checks and check-mode runs pass;
- stopped/disabled artifacts were applied for both services.

Live verification after apply:

```text
inference-ollama.service: disabled, inactive
inference-open-webui.service: disabled, inactive
docker.service: masked, inactive
docker.socket: masked, inactive
podman: missing
```

The rendered Docker wrappers use the NVIDIA Docker runtime flag:

```text
docker run --gpus all
```

No inference containers were started and no images were pulled. Runtime startup
is blocked until Docker is deliberately unmasked/started for the temporary
Jetson exception or Podman plus NVIDIA CDI is validated.

## Live Evidence

| Check | Result |
| --- | --- |
| SSH | reachable as `eva` through alias `thor` |
| OS | Ubuntu 24.04.4 LTS |
| kernel | `6.8.12-tegra` |
| architecture | `aarch64` |
| device model | NVIDIA Jetson AGX Thor Developer Kit |
| L4T | R38 revision 4.0 |
| primary management interface | `enP2p1s0`, `172.16.99.34/24` |
| default route | `172.16.99.1` via `enP2p1s0` |
| GPU | `NVIDIA Thor`, driver `580.00`, CUDA runtime `13.0` from `nvidia-smi` |
| GPU utilization | `0%`, no GPU processes reported by `nvidia-smi` |
| CUDA compiler | `nvcc` missing from `PATH` |
| NVIDIA container tooling | `nvidia-ctk` and `nvidia-container-runtime` version `1.18.1` present |
| container engine | Docker active, Podman missing |
| Docker socket access as `eva` | denied |
| passwordless sudo as `eva` | unavailable |
| root automation SSH from M70 | reachable on 2026-05-25 |
| system default target | `multi-user.target` |
| display manager | `gdm3` inactive; `display-manager` not found |
| failed units | `openipmi.service` failed |
| inference units | `ollama`, `open-webui`, `vllm`, and `sglang` not installed |

## Network State

Management is up:

```text
enP2p1s0 UP 172.16.99.34/24
```

The MGBE/QSFP-facing interfaces are not ready for inference data-plane use:

```text
mgbe0_0 UP 169.254.251.154/16
mgbe1_0 UP 169.254.106.149/16
mgbe2_0 UP 169.254.1.123/16
mgbe3_0 UP 169.254.175.105/16
```

They still need CRS354 `qsfpplus2` physical/link validation and an approved
bridge or OVS design before VM or container data-plane automation uses them.

Docker-created networks are present:

```text
docker0 DOWN 172.17.0.1/16
br-8c52b4f58767 UP 172.18.0.1/16
```

## Readiness Decision

Thor is ready for documentation and inventory modeling. It is not ready for an
unconditional Podman-first inference apply because the live host has Docker but
no Podman.

Recommended inventory stance:

```yaml
inference_service_architecture: arm64
inference_service_accelerator_profile: nvidia
inference_service_container_engine: docker
inference_service_allow_docker_exception: true
inference_service_service_manager: systemd
```

Use the Docker exception only to preserve the existing Jetson/L4T NVIDIA runtime
state. The preferred end state remains Podman with NVIDIA CDI after a separate
host-prep validation.

## Backend Defaults

| Backend | Thor default | Rationale |
| --- | --- | --- |
| Ollama | first engine | Lower integration risk for initial API service validation. |
| Open WebUI | first frontend | Decouples UI from model-serving backend URLs. |
| vLLM | defer | Requires arm64/L4T/CUDA 13 image and command validation. |
| SGLang | defer | Same arm64/L4T/CUDA 13 validation risk as vLLM. |

## Blockers

- `openipmi.service` is failed in the live audit, while the earlier
  stabilization handoff recorded zero failed units after cleanup.
- Podman is missing.
- Docker access is not available to the SSH user used for this audit.
- `nvcc` is not in `PATH`; CUDA developer tooling is not confirmed.
- FreeIPA/SSSD enrollment and central operator identity remain outside this
  audit.
- MGBE/QSFP interfaces are link-local and not bridged for inference traffic.

## Non-Mutation Rule

The original audit performed read-only checks. On 2026-05-25, the operator
approved inference playbook testing and deployment. The live apply was limited
to stopped/disabled Ollama and Open WebUI artifacts. Do not unmask/start Docker,
switch Thor to Podman/CDI, pull images, or start inference services without a
separate host-prep decision.
