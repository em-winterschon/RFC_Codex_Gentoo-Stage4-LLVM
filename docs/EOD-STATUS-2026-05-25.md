# EOD Status 2026-05-25

## Completed

- Fast-forwarded the local RFC checkout to `origin/main` at `96bf3ed`, which
  includes the merged inference service playbook lane from PR
  [#155](https://github.com/yukon-systems/RFC_Codex_Gentoo-Stage4-LLVM/pull/155).
  PR #155 merged on `2026-05-24T14:59:50Z` with successful Notify and Validate
  checks.
- Created `codex/forge3-eod-2026-05-25` for the EOD, Thor inventory, and
  inference role follow-up work.
- Added Thor AGX to the local-network inventory as
  `agx_rfc99_bunnydev_099034` and placed it only in `ollama_servers` and
  `open_webui_servers`. `vllm_servers` and `sglang_servers` remain empty for
  Thor until arm64/L4T/CUDA 13 images are validated.
- Added Thor host variables for the documented temporary Docker/NVIDIA
  exception: `arm64`, `nvidia`, `docker`, `systemd`, and
  `inference_service_allow_docker_exception: true`.
- Added `tests/shell/test_thor_inference_inventory.sh` and wired it into
  `tests/shell/run-tests.sh`.
- Fixed the inference role check-mode path: service enable/start tasks are
  skipped during `ansible-playbook --check`, because planned unit files are not
  present on the target until a real apply.
- Fixed the Docker/NVIDIA wrapper path for Thor. Docker-based NVIDIA services now
  render `--gpus all`; Podman keeps the CDI-style device behavior.
- Cleaned a stale paused-validation laptop fixture reference in the Hetzner DNS
  shell test so the repository-wide paused laptop guard and full shell suite stay
  consistent.
- Ran Thor playbook validation and a safe deployment:
  - `ansible -m ping` succeeds for `agx_rfc99_bunnydev_099034`.
  - `playbooks/ollama.yml` and `playbooks/open-webui.yml` syntax checks pass.
  - check mode passes for both playbooks with `--limit agx_rfc99_bunnydev_099034`.
  - stopped/disabled artifact apply completed for Ollama and Open WebUI.
- Verified on Thor that `/etc/inference-services/*.env`,
  `/usr/local/libexec/inference-services/run-*.sh`, and
  `inference-{ollama,open-webui}.service` exist; both services are disabled and
  inactive, and both wrappers use `docker run --gpus all`.

## Current Gates

- Runtime start is intentionally not complete. Thor has Docker installed, but
  `docker.service` and `docker.socket` are currently masked and inactive.
  Podman is still missing. Starting inference containers should wait for an
  explicit Docker unmask/start decision or a Podman/CDI host-prep step.
- `openipmi.service` remains failed on Thor.
- The `forge3` user SSH key is rejected for the `eva` account on Thor. The
  root automation SSH path works from M70 and is now reflected in inventory for
  Ansible execution.
- vLLM and SGLang remain deferred on Thor. No arm64/L4T/CUDA 13 image path was
  validated today.
- The Ansible YAML callback still emits a deprecation warning and a check-mode
  diff callback warning from `community.general.yaml`; these warnings did not
  block playbook execution.

## Validation

- `bash tests/shell/test_thor_inference_inventory.sh`
- `bash tests/shell/test_inference_service_role_core.sh`
- `bash tests/shell/test_inference_service_playbooks.sh`
- from the Ansible root,
  `sudo -n ../../scripts/with-ansible-vault-env.sh ansible -i inventories/local-network/hosts.yml agx_rfc99_bunnydev_099034 -m ping`
- from the Ansible root,
  `sudo -n ../../scripts/with-ansible-vault-env.sh ansible-playbook --syntax-check -i inventories/local-network/hosts.yml playbooks/ollama.yml`
- from the Ansible root,
  `sudo -n ../../scripts/with-ansible-vault-env.sh ansible-playbook --syntax-check -i inventories/local-network/hosts.yml playbooks/open-webui.yml`
- from the Ansible root,
  `sudo -n ../../scripts/with-ansible-vault-env.sh ansible-playbook --check --diff --limit agx_rfc99_bunnydev_099034 -i inventories/local-network/hosts.yml playbooks/ollama.yml`
- from the Ansible root,
  `sudo -n ../../scripts/with-ansible-vault-env.sh ansible-playbook --check --diff --limit agx_rfc99_bunnydev_099034 -i inventories/local-network/hosts.yml playbooks/open-webui.yml`
- stopped/disabled apply for both playbooks with
  `-e inference_service_state=stopped -e inference_service_enable_on_boot=false`
- live Thor verification through root SSH confirmed disabled/inactive services
  and Docker wrappers with `--gpus all`.

## Recommendations

- Treat the next Thor action as a host-prep change, not a playbook syntax issue:
  either unmask and start Docker for the temporary Jetson exception or validate
  Podman plus NVIDIA CDI and switch the inventory back to the default Podman
  path.
- Start Ollama first after the container engine gate is resolved. Validate
  `http://127.0.0.1:11434/api/tags` locally on Thor before starting Open WebUI.
- Keep Open WebUI disabled until Ollama is confirmed healthy.
- Leave vLLM and SGLang out of Thor host groups until a known-good arm64/L4T
  image and launch command are committed.

## Backout Summary

- The live Thor apply was limited to stopped/disabled service artifacts. Backout
  is to remove `/etc/inference-services/{ollama,open-webui}.env`,
  `/usr/local/libexec/inference-services/run-{ollama,open-webui}.sh`, and
  `/etc/systemd/system/inference-{ollama,open-webui}.service`, then run
  `systemctl daemon-reload`.
- Repo changes are isolated on `codex/forge3-eod-2026-05-25`.
