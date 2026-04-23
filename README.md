# RFC_Codex_Gentoo-Stage4-LLVM
An ephemeral repo for Codex use during Gentoo Stage4 builds

Additional host-side QEMU/VFIO helper files live under `gentoo-virt-qemu/`.

## Notifications

This repository now includes ntfy support in three places:

- Ansible controller notifications via:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/callback_plugins/ntfy.py`
- ad hoc Ansible task notifications via:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/action_plugins/ntfy.py`
- GitHub repository event notifications via:
  `.github/workflows/notify.yml`

Local Codex-side notifications can be sent with:

```bash
bash scripts/codex-ntfy.sh info "Codex started work"
bash scripts/codex-ntfy.sh action-required "Need operator input"
```

Shared environment keys are documented in:

- `ntfy.env.example`

The repository event workflow is designed to send notifications for:

- pushes and commits
- branch and tag create/delete events
- pull request open/edit/sync/merge/draft-state changes
- releases
- completion of the `Validate` workflow

Messages are formatted as RFC 5424-style syslog lines and mapped onto ntfy priorities.

## Validation

Local validation:
- `python -m pip install -r requirements-dev.txt`
- `pre-commit install`
- `pre-commit run --all-files`
- `bash tests/shell/run-tests.sh`

PR and release validation:
- `.github/workflows/validate.yml` runs the repo validation suite on pull requests and pushes to `main`
- `.github/workflows/notify.yml` sends repository event notifications to ntfy when configured
- the shell validation sequence currently covers shell syntax checks for committed `.sh` files, generator/output parity for the Ansible Python environment helper, and unit tests for `gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
- Python linting and formatting are enforced through `ruff` and `black`
