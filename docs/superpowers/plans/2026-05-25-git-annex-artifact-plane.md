# Git-Annex Artifact Plane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a cryptographically secure, cross-architecture-compatible Git-Annex artifact-plane policy and expand M70 Forge workers to `forge5` and `forge6`.

**Architecture:** Normal git remains the source-control plane. Git-Annex becomes the artifact data plane with `SHA256E` integrity keys, encrypted directory special remotes, and worker-role preferred content. M70 local worker users use sequential UID/GID values and must be mirrored into FreeIPA before workers are spawned on additional hosts.

**Tech Stack:** git, git-annex, GPG, NFS/NASA directory special remote, shell validation, FreeIPA desired-state tracking.

---

### Task 1: Artifact-Plane Policy

**Files:**
- Create: `artifact-plane/git-annex-policy.yml`
- Create: `docs/GIT-ANNEX-ARTIFACT-PLANE.md`
- Create: `docs/runbooks/git-annex-artifact-plane-bootstrap.md`
- Create: `scripts/bootstrap-yukonsys-artifact-annex.sh`
- Test: `tests/shell/test_git_annex_artifact_plane.sh`

- [x] Write the shell test requiring `SHA256E`, `hybrid`, `HMACSHA256`, `numcopies=2`, forbidden insecure backends, and a dry-run bootstrap.
- [x] Run `bash tests/shell/test_git_annex_artifact_plane.sh` and confirm it fails on missing policy files.
- [x] Add the policy, documentation, runbook, and bootstrap script.
- [x] Run `bash tests/shell/test_git_annex_artifact_plane.sh` and confirm it passes.
- [x] Run `git diff --check`.
- [ ] Commit with `docs: add git-annex artifact plane policy`.

### Task 2: M70 Forge Worker Expansion

**Live Hosts:**
- M70: `admin-sun99-forge-099070`

- [x] Inspect `forge1` through `forge4` UID/GID/group state.
- [x] Create `forge5` with UID `1004`, primary GID `1005`, home `/home/forge5`, shell `/bin/bash`, and groups `wheel`, `forge-superusers`, `nfsnasa`.
- [x] Create `forge6` with UID `1005`, primary GID `1006`, home `/home/forge6`, shell `/bin/bash`, and groups `wheel`, `forge-superusers`, `nfsnasa`.
- [x] Seed `/home/forge5` and `/home/forge6` from the Forge home bootstrap baseline used for existing workers, preserving ownership and avoiding shared writable state.
- [x] Verify `id forge5`, `id forge6`, home ownership, SSH material parity, sudo, and source-workspace baseline.
- [x] Record FreeIPA desired-state if the current host cannot run `ipa user-show` or `ipa user-add`.

### Task 3: FreeIPA Tracking

**Expected Identity State:**
- `forge5`: UID `1004`, primary GID `1005`
- `forge6`: UID `1005`, primary GID `1006`
- Supplemental groups: `wheel`, `forge-superusers`, `nfsnasa`

- [x] Check whether `ipa` CLI exists on the host.
- [ ] If available, run `ipa user-show forge5` and `ipa user-show forge6`; create or update records if absent.
- [x] If unavailable, write an FCP/Forge memory event with desired state and next action for the IPA admin host.
- [x] Do not claim FreeIPA completion unless `ipa user-show` validates the records.

**Current FreeIPA status:** blocked from M70. The `ipa` CLI is absent and SSH
to `ipa01.rfc1918.host` as `verwalterin` or `root` was denied from M70. FCP
event `c06ed582-3305-4a19-be6b-de3b29ded28a` records the desired state and
next action.
