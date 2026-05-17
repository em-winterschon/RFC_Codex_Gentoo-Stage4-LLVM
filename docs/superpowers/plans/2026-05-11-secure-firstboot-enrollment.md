# Secure First-Boot Enrollment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repo-safe first-boot enrollment scaffold that can remove the K10 keytab embedding blocker by delivering a short-lived encrypted FreeIPA OTP bundle.

**Architecture:** The first implementation uses `age` for encrypted bundle transport and keeps Clevis/Tang as an optional future NBDE layer. A small validator/renderer pair defines the bundle contract, while an Ansible role installs an OpenRC first-boot service scaffold for installed hosts.

**Tech Stack:** Gentoo OpenRC, FreeIPA OTP enrollment, SSSD, `app-crypt/age`, Python JSON validation, Ansible roles, shell regression tests.

---

### Task 1: First-Boot Bundle Contract

**Files:**
- Create: `scripts/validate_secure_firstboot_bundle.py`
- Create: `scripts/render_secure_firstboot_bundle.py`
- Test: `tests/shell/test_secure_firstboot_enrollment.sh`

- [ ] **Step 1: Write the failing shell test**

Create `tests/shell/test_secure_firstboot_enrollment.sh` with checks that assert the validator and renderer exist, reject missing OTP, accept a valid future-expiring bundle, and reject an expired bundle.

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/shell/test_secure_firstboot_enrollment.sh`

Expected: fail because the validator and renderer do not exist yet.

- [ ] **Step 3: Implement validator and renderer**

Implement `scripts/validate_secure_firstboot_bundle.py` to validate method `freeipa-otp`, FQDN, realm, domain, IPA server, expiry, and OTP presence. Implement `scripts/render_secure_firstboot_bundle.py` to read OTP from an environment variable and print JSON without accepting OTP on the command line.

- [ ] **Step 4: Run the test to verify it passes**

Run: `tests/shell/test_secure_firstboot_enrollment.sh`

Expected: pass.

### Task 2: Profile And Package Layer

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-package-lists/stage5-secure-firstboot-enrollment.packages`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/secure-firstboot-enrollment.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/secure-firstboot-enrollment.metadata.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-service-atoms/stage5-role-service-atoms.yml`
- Test: `tests/shell/test_secure_firstboot_enrollment.sh`

- [ ] **Step 1: Extend the failing test**

Add assertions that the package list contains `app-crypt/age`, `net-misc/curl`, and `app-misc/jq`, and that metadata documents Clevis/Tang as optional Guru-gated future work.

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/shell/test_secure_firstboot_enrollment.sh`

Expected: fail because profile files do not exist yet.

- [ ] **Step 3: Add profile files**

Create the package list, profile definition, metadata, and service atom entry for `secure-firstboot-enrollment`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `tests/shell/test_secure_firstboot_enrollment.sh`

Expected: pass.

### Task 3: OpenRC First-Boot Role Scaffold

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/secure_firstboot_enrollment/defaults/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/secure_firstboot_enrollment/tasks/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/secure_firstboot_enrollment/templates/stage5-firstboot-enroll.confd.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/secure_firstboot_enrollment/templates/stage5-firstboot-enroll.initd.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/secure_firstboot_enrollment/templates/stage5-firstboot-enroll.sh.j2`
- Test: `tests/shell/test_secure_firstboot_enrollment.sh`

- [ ] **Step 1: Extend the failing test**

Add assertions that the role exists, templates reference `age --decrypt`, the service is OpenRC-compatible, and enrollment is opt-in.

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/shell/test_secure_firstboot_enrollment.sh`

Expected: fail because the role does not exist yet.

- [ ] **Step 3: Add the role scaffold**

Implement defaults, tasks, and templates. The script must fail closed when disabled, missing bundle URL, missing age identity, expired bundle, or FQDN mismatch. The live enrollment command remains explicitly configurable because Gentoo FreeIPA client packaging is profile-dependent.

- [ ] **Step 4: Run the test to verify it passes**

Run: `tests/shell/test_secure_firstboot_enrollment.sh`

Expected: pass.

### Task 4: Documentation And E2ET Gate Update

**Files:**
- Modify: `docs/IDENTITY-AAA.md`
- Modify: `docs/GMKTEK-K10-STAGE5-VALIDATION.md`
- Modify: `docs/ROADMAP-AND-TODO.md`
- Modify: `docs/wiki/Identity-AAA.md`
- Modify: `docs/wiki/GMKtek-K10-Stage5-Validation.md`
- Modify: `docs/wiki/Roadmap-and-TODO.md`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/host-e2et-definitions/k10-stage5-aaa-reboot.yml`
- Test: `tests/shell/test_live_ipa_client_enrollment.sh`
- Test: `tests/shell/test_secure_firstboot_enrollment.sh`

- [ ] **Step 1: Update docs and E2ET wording**

Document that the blocker is now secure first-boot bundle apply, not keytab embedding. Keep K10 hard-gated until a disk-installed host or secure first-boot apply proves reboot-durable enrollment.

- [ ] **Step 2: Run verification**

Run:

```bash
tests/shell/test_secure_firstboot_enrollment.sh
tests/shell/test_live_ipa_client_enrollment.sh
python3 scripts/host_e2et_conformance.py --manifest gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/host-e2et-definitions/k10-stage5-aaa-reboot.yml --json-output /tmp/k10-stage5-aaa-e2et.json --markdown-output /tmp/k10-stage5-aaa-e2et.md --junit-output /tmp/k10-stage5-aaa-e2et.junit.xml
```

Expected: shell tests pass. E2ET remains non-zero until live secure first-boot enrollment is applied and validated.

### Task 5: Commit

**Files:**
- All files above.

- [ ] **Step 1: Review status and diff**

Run:

```bash
git status --short
git diff --stat
```

- [ ] **Step 2: Commit**

Run:

```bash
git add docs gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible scripts tests/shell/test_secure_firstboot_enrollment.sh
git commit -m "Scaffold secure first-boot IPA enrollment"
```
