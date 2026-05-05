# Workflow Manifests

This repository keeps repeatable operational procedures in machine-readable JSON
under `docs/workflows/`.

Goals:
- make host and VM workflows reproducible
- keep stage ordering explicit
- capture command lines, required environment, expected exit codes, and major artifacts
- allow external tooling to consume the same workflow definitions that humans read

## Manifest format

Each workflow manifest uses:

- `apiVersion`
- `kind`
- `metadata`
- `variables`
- `stages`

Each stage may define:

- `id`
- `summary`
- `cwd`
- `env`
- `command`
- `expectedExitCodes`
- `artifacts`
- `notes`

Variable interpolation is shell-style documentation only. Values such as
`${repo_root}` or `${ssh_public_key_file}` are placeholders for the operator or
the calling automation layer.

## Included manifests

- [codex-approval-watcher-service.json](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/codex-approval-watcher-service.json)
  persistent ntfy approval-watcher installation and validation on a Gentoo/OpenRC host
- [stage4-netboot-path-b.json](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/stage4-netboot-path-b.json)
  Path B iPXE asset publication and operator handoff flow for bare-metal and VM fleets
- [stage4-routeros-pathb-deployment.json](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/stage4-routeros-pathb-deployment.json)
  RouterOS CHR render/apply workflow for the isolated Path B lab
- [stage4-vm-install-and-boot.json](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/stage4-vm-install-and-boot.json)
  Path A Stage4 VM build, launch, Ansible install, and target-disk boot validation flow
- [stage4-destination-install-sequences.json](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/stage4-destination-install-sequences.json)
  Path A staged Ansible execution plan for a destination test host, including the structured control-flow pipeline
- [ntfy-server-deployment.json](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/ntfy-server-deployment.json)
  deploy and validate a private ntfy server on a Gentoo/OpenRC host

## Validation

Workflow manifests are validated by:

```bash
bash tests/shell/test_workflow_manifests.sh
```

The repo-wide shell suite includes that check:

```bash
bash tests/shell/run-tests.sh
```
