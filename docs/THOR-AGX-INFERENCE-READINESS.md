# Thor AGX Inference Readiness

Audit timestamp: `2026-05-25T20:56:00-07:00`

Target:

```text
agx-rfc99-bunnydev.rfc1918.host
172.16.99.34/24
ssh alias: thor
```

## Summary

Thor is reachable and has a working NVIDIA Thor GPU stack. Podman is installed and validated on Thor.

The safest first workload sequence is:

1. preserve headless multi-user operation;
2. keep Docker inactive and masked;
3. deploy Ollama and Open WebUI first using Podman plus NVIDIA CDI;
4. defer vLLM and SGLang until arm64/L4T/CUDA 13 images are validated.

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
| container engine | Podman `4.9.3` with netavark backend |
| NVIDIA CDI | `/etc/cdi/nvidia.yaml`; `nvidia.com/gpu=0`, `nvidia.com/gpu=all` |
| legacy Docker state | Docker remains masked and inactive. |
| system default target | `multi-user.target` |
| display manager | `gdm3` inactive; `display-manager` not found |
| failed units | `openipmi.service` failed |
| inference units | `inference-ollama.service` and `inference-open-webui.service` enabled and running |

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

Legacy Docker-created networks may remain present until a later cleanup window:

```text
docker0 DOWN 172.17.0.1/16
br-8c52b4f58767 UP 172.18.0.1/16
```

## Readiness Decision

Thor is ready for Podman-first Ollama and Open WebUI deployment.

Recommended inventory stance:

```yaml
inference_service_architecture: arm64
inference_service_accelerator: nvidia
inference_service_container_engine: podman
inference_service_manager: systemd
inference_service_cdi_devices:
  - nvidia.com/gpu=all
```

Keep Ollama as the first model-serving backend and Open WebUI as the first
frontend. Use `nvidia.com/gpu=all` for the initial Thor service profile.

## Backend Defaults

| Backend | Thor default | Rationale |
| --- | --- | --- |
| Ollama | deployed | Lower integration risk for initial API service validation. |
| Open WebUI | deployed | Decouples UI from model-serving backend URLs. |
| vLLM | defer | Requires arm64/L4T/CUDA 13 image and command validation. |
| SGLang | defer | Same arm64/L4T/CUDA 13 validation risk as vLLM. |

## Deployment Validation

Live validation from M70 `forge1` on 2026-05-25:

| Check | Result |
| --- | --- |
| Ollama unit | `inference-ollama.service` active and enabled |
| Ollama API | `GET http://127.0.0.1:11434/api/version` returned `{"version":"0.24.0"}` |
| Ollama container | `inference-ollama` running under Podman |
| Ollama accelerator | journal reports CUDA `NVIDIA Thor`, compute `11.0`, driver `13.0` |
| Open WebUI unit | `inference-open-webui.service` active and enabled |
| Open WebUI HTTP | `HEAD http://127.0.0.1:8080/` returned `HTTP/1.1 200 OK` |
| Open WebUI container | `inference-open-webui` running under Podman |
| Legacy Docker state | `docker.service` and `docker.socket` inactive and masked |

## Blockers

- `nvcc` is not in `PATH`; CUDA developer tooling is not confirmed.
- FreeIPA/SSSD enrollment and central operator identity remain outside this
  audit.
- MGBE/QSFP interfaces are link-local and not bridged for inference traffic.

## Non-Mutation Rule

Earlier audits were read-only. The current approved mutation lane allows Podman
inference service deployment while preserving headless operation, current
management networking, and the inactive legacy Docker state.
