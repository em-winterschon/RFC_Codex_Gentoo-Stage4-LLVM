# RFC_Codex_Gentoo-Stage4-LLVM
An ephemeral repo for Codex use during Gentoo Stage4 builds

Additional host-side QEMU/VFIO helper files live under `gentoo-virt-qemu/`.

## Documentation

- [docs/WORKFLOWS.md](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/WORKFLOWS.md)
  human-readable index for the machine-readable workflow manifests
- [docs/workflows/codex-approval-watcher-service.json](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/codex-approval-watcher-service.json)
  persistent ntfy approval-watcher install and validation flow
- [docs/workflows/stage4-vm-install-and-boot.json](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/stage4-vm-install-and-boot.json)
  Stage4 VM build, install, and target-disk boot validation flow

## Validation

Local validation:
- `python -m pip install -r requirements-dev.txt`
- `pre-commit install`
- `pre-commit run --all-files`
- `bash tests/shell/run-tests.sh`
- `bash tests/shell/test_workflow_manifests.sh`

PR and release validation:
- `.github/workflows/validate.yml` runs the repo validation suite on pull requests and pushes to `main`
- the shell validation sequence currently covers shell syntax checks for committed `.sh` files, generator/output parity for the Ansible Python environment helper, and unit tests for `gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
- Python linting and formatting are enforced through `ruff` and `black`

## Codex ntfy

- `scripts/codex_notify_with_env.sh` forwards Codex turn-complete notifications to ntfy using `~/.codex/ntfy-pub-subs.export.sh` or `/opt/codex/ntfy-pub-subs.export.sh`
- `scripts/codex_hook_with_env.sh` handles Codex hook-based remote approvals and reply prompts when the runtime emits supported hook events
- `scripts/codex_approval_watcher_with_env.sh` tails `~/.codex/log/codex-tui.log` and sends ntfy alerts for `exec_approval` and `patch_approval` dialogs raised by the sandbox approval layer
- the approval watcher notifies you to approve the action in the Codex UI; remote ntfy replies do not directly satisfy sandbox approval dialogs in this runtime
- `scripts/install_codex_approval_watcher_service.sh` installs the watcher as a persistent OpenRC service

Persistent setup on Gentoo/OpenRC:
```bash
bash scripts/install_codex_approval_watcher_service.sh
rc-service codex-approval-watcher status
```

Future-host workflow:
```bash
. /opt/codex/ntfy-pub-subs.export.sh
bash scripts/install_codex_approval_watcher_service.sh
```
