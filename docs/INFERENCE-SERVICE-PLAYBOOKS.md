# Inference Service Playbooks

Audit timestamp: `2026-05-24T03:15:49Z`

## Scope

This document records operator-ready defaults for the shared inference service
automation lane. It is written for the existing Ansible root:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
```

The expected implementation shape is:

- shared role:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/inference_service`
- thin playbooks:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/ollama.yml`
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/vllm.yml`
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/sglang.yml`
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/open-webui.yml`
- test gate:
  `tests/shell/test_inference_service_playbooks.sh`

The forge3 playbook/test branch already uses these host groups and variables:

| Backend | Host group | Required shared variables |
| --- | --- | --- |
| Ollama | `ollama_servers` | `inference_service_backend: ollama`, `inference_service_name: ollama` |
| vLLM | `vllm_servers` | `inference_service_backend: vllm`, `inference_service_name: vllm` |
| SGLang | `sglang_servers` | `inference_service_backend: sglang`, `inference_service_name: sglang` |
| Open WebUI | `open_webui_servers` | `inference_service_backend: open-webui`, `inference_service_name: open-webui` |

## Common Defaults

Use one role surface for all backends:

| Setting | Default |
| --- | --- |
| container engine | `podman` |
| service manager | auto-detect `systemd` or `openrc` |
| accelerator profile | `auto`, with explicit `cpu`, `nvidia`, and `amd_rocm` overrides |
| env root | `/etc/inference-services` |
| runtime wrapper root | `/usr/local/libexec/inference-services` |
| state root | `/var/lib/inference` |
| log root | `/var/log/inference-services` |

Do not require SELinux. For RedHat-family hosts where SELinux is active, the
role may set compatible labels or use a documented opt-in, but the baseline must
work without making SELinux a prerequisite.

Use Podman by default. Allow a host-level container engine override for
transition hosts where the NVIDIA runtime is already Docker-only and Podman CDI
has not been validated.

## Accelerator Profiles

### `cpu`

Use no GPU device flags. This profile must be valid on Debian, RedHat-family,
and Gentoo/OpenRC targets.

### `nvidia`

For Podman/CDI-capable hosts, expose GPUs with:

```text
--device nvidia.com/gpu=all
```

Do not assume this is already valid on Jetson/L4T hosts. Thor AGX currently has
Docker and NVIDIA Container Toolkit active, but Podman is absent. Treat
Jetson/L4T as a host-prep exception until Podman plus NVIDIA CDI is validated or
a temporary Docker engine override is approved.

### `amd_rocm`

Expose ROCm devices without SELinux dependency:

```text
--device /dev/kfd
--device /dev/dri
```

Keep ROCm image, group, and permission handling overrideable. No live W7700
host was validated in this audit.

### `auto`

Detect the safest available profile from host facts. If more than one accelerator
path is visible, prefer explicit inventory variables over inference.

## Backend Defaults

| Backend | Initial port | State path | Notes |
| --- | ---: | --- | --- |
| Ollama | `11434` | `/var/lib/inference/ollama` | Best first engine for Thor once container-engine handling is resolved. |
| vLLM | `8000` | `/var/lib/inference/vllm` | OpenAI-compatible API. Require image and command overrides by architecture. |
| SGLang | `30000` | `/var/lib/inference/sglang` | OpenAI-compatible API. Require image and command overrides by architecture. |
| Open WebUI | `8080` | `/var/lib/inference/open-webui` | Keep frontend decoupled from model serving through endpoint variables. |

Recommended endpoint variables:

```yaml
inference_service_openai_base_url: ""
inference_service_ollama_base_url: ""
inference_service_model: ""
inference_service_extra_env: {}
inference_service_extra_container_args: []
```

The role should render backend env files from the same template and keep
backend-specific command/image selection in defaults or inventory variables, not
in the playbooks.

## Host Defaults

### Thor AGX

Use Thor as an Ubuntu/L4T exception host:

```yaml
inference_service_architecture: arm64
inference_service_accelerator_profile: nvidia
inference_service_container_engine: docker  # temporary until Podman/CDI is validated
inference_service_allow_docker_exception: true
```

This is not a recommendation to standardize on Docker. It records current live
state so automation can avoid breaking existing NVIDIA runtime assumptions.
Prefer an approved Podman/CDI prep step before making Podman mandatory on Thor.

Start with Ollama and Open WebUI. Defer vLLM and SGLang on Thor until their
arm64, Jetson/L4T, and CUDA 13 image path is validated.

## Acceptance Gates

Before merge:

```bash
bash tests/shell/test_inference_service_playbooks.sh
git diff --check
```

When the shared role exists:

```bash
for playbook in ollama vllm sglang open-webui; do
  ansible-playbook --syntax-check \
    -i /path/to/minimal-inventory.yml \
    "gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/${playbook}.yml"
done
```

Run the full shell suite only after clearing or fixing hardcoded `/tmp` test
artifact collisions. During this audit, `tests/shell/run-tests.sh` reached
pre-existing fixed-path `/tmp` ownership collisions before any forge4 edits.
