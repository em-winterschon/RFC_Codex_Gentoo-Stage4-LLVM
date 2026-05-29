# Git-Annex Artifact Plane Bootstrap

This runbook initializes the YukonSYS artifact-plane annex repo and its first
NASA/NFS directory special remote.

## Preconditions

- `git-annex` is installed on the host that runs the bootstrap.
- The host has access to `/mnt/nasa/forge/git-annex`.
- The selected GPG public key is available to `gpg`.
- The operator has verified the repo path and remote path are correct.

## Source-Workspace Boundary

Before bootstrapping the artifact repo, confirm every Forge account has the
standard source-workspace baseline:

```text
~/src/RFC_Codex_Gentoo-Stage4-LLVM
~/src/YukonSYS-Standard-Definitions
~/src/agentic-forge-control-plane
```

Do not use Git-Annex to synchronize normal source checkouts. Use normal git
fetch/checkout/worktree handling for source repos, and reserve Git-Annex for the
shared `YukonSYS-Artifact-Annex` artifact repo.

## Dry Run

```bash
scripts/bootstrap-yukonsys-artifact-annex.sh \
  --dry-run \
  --repo /opt/org-repos/yukon.systems/YukonSYS-Artifact-Annex \
  --remote-path /mnt/nasa/forge/git-annex/YukonSYS-Artifact-Annex \
  --gpg-key FINGERPRINT_OR_KEYID \
  --backend SHA256E \
  --remote-encryption hybrid \
  --remote-mac HMACSHA256 \
  --numcopies 2
```

Expected dry-run output includes:

```text
git annex init "forge-artifact-plane"
git config annex.backend SHA256E
git config annex.numcopies 2
git annex initremote nasa-nfs-artifact-annex type=directory ... encryption=hybrid ... mac=HMACSHA256
```

## Apply

```bash
scripts/bootstrap-yukonsys-artifact-annex.sh \
  --repo /opt/org-repos/yukon.systems/YukonSYS-Artifact-Annex \
  --remote-path /mnt/nasa/forge/git-annex/YukonSYS-Artifact-Annex \
  --gpg-key FINGERPRINT_OR_KEYID \
  --backend SHA256E \
  --remote-encryption hybrid \
  --remote-mac HMACSHA256 \
  --numcopies 2
```

## Validation

```bash
cd /opt/org-repos/yukon.systems/YukonSYS-Artifact-Annex
git config --get annex.backend
git config --get annex.numcopies
git annex info nasa-nfs-artifact-annex
git annex fsck
```

Expected:

```text
annex.backend == SHA256E
annex.numcopies == 2
remote type == directory
remote encryption == hybrid
fsck exits 0
```

## Backout

If no content has been copied to the remote yet:

```bash
cd /opt/org-repos/yukon.systems/YukonSYS-Artifact-Annex
git annex dead nasa-nfs-artifact-annex
git remote remove nasa-nfs-artifact-annex
rm -rf /mnt/nasa/forge/git-annex/YukonSYS-Artifact-Annex
```

If content has been copied, do not delete the remote path. First move or copy
the content elsewhere and verify `git annex fsck` from another trusted repo.
