# Fleet IPA And NFS Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make FreeIPA client readiness and NFS floating-home readiness a fleet baseline contract.

**Architecture:** Gentoo Stage5 base atoms carry the client-side SSSD/Kerberos/LDAP/NFS requirements. A repo-safe policy file defines distro package mappings, NFS protocol defaults, and floating-home prerequisites. A read-only Ansible audit validates live host readiness before enabling NFS-backed home directories.

**Tech Stack:** Gentoo package lists, FreeIPA/SSSD, NFSv4.1/NFSv4.2, Ansible, shell tests.

---

### Task 1: Baseline Contract Test

**Files:**
- Create: `tests/shell/test_fleet_ipa_nfs_readiness_contract.sh`

- [x] Write the failing shell test for baseline atoms, NFS protocol defaults, fstab safety options, audit playbook, wrapper script, and docs.
- [x] Run `bash tests/shell/test_fleet_ipa_nfs_readiness_contract.sh` and confirm it fails on missing `sys-auth/sssd` in the base package list.

### Task 2: Gentoo Baseline And NFS Defaults

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-package-lists/stage5-base-minimal-nox.packages`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/nfs-storage-client.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/nfs_storage_client/defaults/main.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/nfs_storage_client/tasks/main.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/nfs_storage_client/templates/fstab.j2`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/nfs_storage_client/templates/nfs.conf.j2`

- [x] Add SSSD, Kerberos, LDAP, CA, NFS, rpcbind, and keyutils atoms to the base package list.
- [x] Change normal NFS defaults to NFSv4.2 for LACP-capable hosts and NFSv4.1 for non-LACP hosts.
- [x] Add `nofail,soft` as mandatory fstab safety options.

### Task 3: Audit Workflow

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/fleet-readiness-definitions/ipa-nfs-baseline.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/fleet-ipa-nfs-readiness-audit.yml`
- Create: `scripts/audit-fleet-ipa-nfs-readiness.sh`
- Create: `docs/FLEET-IPA-NFS-READINESS.md`

- [x] Define cross-distro package/capability policy and Gentoo FreeIPA CLI limitation.
- [x] Add a read-only Ansible audit for SSSD/NSS/SSH-key/NFS mount readiness.
- [x] Add a wrapper script documenting the exact M70-to-IPA SSH probe syntax.
- [x] Document the operational policy and audit command.
