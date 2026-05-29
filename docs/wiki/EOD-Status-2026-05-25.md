# EOD Status 2026-05-25

## Historical Context

This closeout records the 2026-05-25 Thor inference lane. It is preserved for
operator traceability, but the temporary Docker transition assumptions in the
original handoff have been superseded by the later validated Podman plus NVIDIA
CDI state now recorded in `docs/THOR-AGX-INFERENCE-READINESS.md`.

## Completed

- PR #155 for inference service playbooks was merged into `main` before this
  EOD lane began.
- Thor AGX was modeled as `agx_rfc99_bunnydev_099034` for Ollama and Open WebUI
  first; vLLM and SGLang remain deferred until arm64/L4T/CUDA 13 images are
  validated.
- Added a Thor inventory regression test and wired it into the shell gate.
- Fixed the inference role check-mode path: service enable/start tasks are
  skipped during `ansible-playbook --check`, because planned unit files are not
  present on the target until a real apply.
- Preserved Docker/NVIDIA wrapper compatibility: explicit legacy Docker wrapper
  rendering uses `--gpus all`, while the active Thor service path remains
  Podman/CDI with `nvidia.com/gpu=all`.
- Ran Thor playbook validation and a bounded artifact deployment during the
  original 2026-05-25 lane; later validation promoted the current Podman/CDI
  state.

## Current Gates

- Docker is not the active Thor deployment path. Keep Docker masked/inactive
  unless a separate operator-approved maintenance window changes host policy.
- `openipmi.service` remains a known failed unit to track separately.
- vLLM and SGLang remain deferred on Thor. No arm64/L4T/CUDA 13 image path is
  accepted yet.

## Validation

- `bash tests/shell/test_thor_inference_inventory.sh`
- `bash tests/shell/test_inference_service_role_core.sh`
- `bash tests/shell/test_inference_service_playbooks.sh`
- `bash tests/shell/test_inference_service_docker_nvidia_wrapper.sh`
- Later full-suite validation is tracked on the branch/PR that reconciles this
  EOD note with the current Podman baseline.

## Recommendations

- Keep Thor inventory Podman-first with NVIDIA CDI.
- Use the Docker wrapper support only as a compatibility renderer for explicitly
  approved legacy exception artifacts.
- Start with Ollama before Open WebUI after any future runtime changes.
- Leave vLLM and SGLang out of Thor host groups until a known-good arm64/L4T
  image and launch command are committed.

## Backout Summary

- The historical 2026-05-25 apply was limited to service artifacts. Backout is
  to remove `/etc/inference-services/{ollama,open-webui}.env`,
  `/usr/local/libexec/inference-services/run-{ollama,open-webui}.sh`, and
  `/etc/systemd/system/inference-{ollama,open-webui}.service`, then run
  `systemctl daemon-reload`.
