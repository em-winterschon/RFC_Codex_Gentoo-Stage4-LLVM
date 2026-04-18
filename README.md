# RFC_Codex_Gentoo-Stage4-LLVM
An ephemeral repo for Codex use during Gentoo Stage4 builds

Additional host-side QEMU/VFIO helper files live under `gentoo-virt-qemu/`.

## Validation

Local validation:
- `python -m pip install -r requirements-dev.txt`
- `pre-commit install`
- `pre-commit run --all-files`
- `bash tests/shell/run-tests.sh`

PR and release validation:
- `.github/workflows/validate.yml` runs the repo validation suite on pull requests and pushes to `main`
- the shell validation sequence currently covers shell syntax checks for committed `.sh` files, generator/output parity for the Ansible Python environment helper, and unit tests for `gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
- Python linting and formatting are enforced through `ruff` and `black`
