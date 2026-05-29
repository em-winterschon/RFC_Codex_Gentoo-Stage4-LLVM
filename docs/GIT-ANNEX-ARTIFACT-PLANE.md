# Git-Annex Artifact Plane

Git-Annex is the artifact data plane for Forge workers. It does not replace
normal git branches, PRs, NetBox source-of-truth data, FCP coordination, or
GitHub review. It tracks large content and copy location while normal git keeps
source files, playbooks, templates, manifests, and review history.

## Backend Policy

Default backend: `SHA256E`.

`SHA256E` is the baseline because it is cryptographically secure, widely
implemented, preserves filename extensions in annex keys, and aligns with
portable SHA-256 acceleration better than BLAKE2, SHA3, or SHA512 across the
current mix of ARM64-v8 crypto-extension systems, older x86_64 Xeons, and newer
Ice Lake class Xeons.

Do not use `SHA1`, `SHA1E`, `MD5`, `MD5E`, `WORM`, or `URL` as YukonSYS
artifact-plane backends. Those backends either do not provide cryptographic
content verification or do not provide the artifact identity behavior we need
for multi-worker reproducibility.

Git-Annex backend selection is integrity keying, not transport encryption.
Remote encryption is configured separately on special remotes.

## Remote Policy

NFS/NASA primary special remote:

```text
name: nasa-nfs-artifact-annex
type: directory
path: /mnt/nasa/forge/git-annex/YukonSYS-Artifact-Annex
encryption: hybrid
mac: HMACSHA256
minimum copies: 2
```

Use `hybrid` encryption for special remotes that are shared artifact stores,
because it allows additional GPG recipients to be added later. Use
`HMACSHA256` for encrypted remote filename MACs when creating a new remote.

## Content Layout

The first artifact repo is `YukonSYS-Artifact-Annex`:

```text
artifacts/netboot/
artifacts/kernels/
artifacts/doca/
artifacts/binpkgs/
artifacts/vm-images/
artifacts/inference-models/
artifacts/validation-runs/
manifests/
provenance/
```

Normal source repos should reference annexed artifacts by manifest, content key,
version, and provenance path. They should not embed large binaries.

## Source Workspace Parity

Git-Annex should not be used as the source repo parity mechanism. Source parity
is a manifest and bootstrap concern:

```text
~/src/RFC_Codex_Gentoo-Stage4-LLVM
~/src/YukonSYS-Standard-Definitions
~/src/agentic-forge-control-plane
```

All Forge worker users should have those source repos. Worker-specific feature
worktrees are intentionally local to the worker that owns the task and should
not be copied across every Forge account unless the task is reassigned.

The annex-backed shared artifact repo is separate:

```text
~/src/YukonSYS-Artifact-Annex
```

That repo can be present for every Forge worker once `git-annex` is installed,
but it stores generated artifacts, large binaries, model caches, package
outputs, VM images, kernel/DOCA payloads, and provenance data rather than normal
source files.

## Worker Preferred Content

Use preferred content to keep worker caches bounded:

```text
forge-control-plane:
  not binpkgs, VM images, or inference models

forge-builder:
  binpkgs, kernels, DOCA, netboot artifacts

forge-inference:
  inference models and validation runs

forge-archive:
  all content
```

These expressions live in `artifact-plane/git-annex-policy.yml` so worker
automation can render them consistently.

## Drop And Fsck Guardrails

No Forge worker should run `git annex drop` without a passing `git annex fsck`
for the relevant content and confirmation that `annex.numcopies` is still
satisfied.

Do not run broad `git annex unused` or `git annex dropunused` cleanup from
worker automation unless an operator reviewed the corresponding `git-annex`
branch state and the cleanup scope is explicitly bounded.

## Bootstrap

Use:

```bash
scripts/bootstrap-yukonsys-artifact-annex.sh \
  --repo /opt/org-repos/yukon.systems/YukonSYS-Artifact-Annex \
  --remote-path /mnt/nasa/forge/git-annex/YukonSYS-Artifact-Annex \
  --gpg-key FINGERPRINT_OR_KEYID
```

Use `--dry-run` first on every new host. The script prints the commands it
would run and does not require `git-annex` to be installed in dry-run mode.
