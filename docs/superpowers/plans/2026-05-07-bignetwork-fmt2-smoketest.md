# BigNetwork FMT2 Smoke-Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a disposable Devuan VM path for validating BigNetwork SDN transport to FMT2/SFO200 before porting the service into a permanent Gentoo Stage4 role.

**Architecture:** The first pass uses a temporary Devuan VM because the vendor artifact is a Debian package and the immediate success criterion is network reachability. The repo still gets a native Ansible boundary: one role renders Devuan iPXE/preseed artifacts, and one role installs/manages the extracted BigNetwork binary with explicit OpenRC/sysvinit service support. Gentoo integration remains gated until the Devuan smoke-test proves FMT2 reachability.

**Tech Stack:** Ansible, iPXE, Devuan netboot installer, BigNetwork `bn` 1.12.2, OpenRC/sysvinit service templates, shell regression tests.

---

### Task 1: Regression Coverage

**Files:**
- Create: `tests/shell/test_bignetwork_smoketest_roles.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
  grep -Fq "${needle}" "${path}" || fail "expected '${needle}' in ${path}"
}

assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/defaults/main.yml" "bignetwork_edge_default_extracted_root:"
assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/tasks/main.yml" "Install BigNetwork edge binary"
assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/templates/bn.openrc.j2" "command=\"/usr/sbin/bn\""
assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/templates/bn.sysvinit.j2" "BigNetwork virtualization service"
assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/templates/bignetwork-smoketest.sh.j2" "bn -q"

assert_file_contains "${ANSIBLE_ROOT}/roles/devuan_netboot_assets/defaults/main.yml" "devuan_netboot_default_release:"
assert_file_contains "${ANSIBLE_ROOT}/roles/devuan_netboot_assets/tasks/main.yml" "Render Devuan BigNetwork smoke-test iPXE script"
assert_file_contains "${ANSIBLE_ROOT}/roles/devuan_netboot_assets/templates/devuan-bignetwork-smoketest.ipxe.j2" "debian-installer/amd64/linux"
assert_file_contains "${ANSIBLE_ROOT}/roles/devuan_netboot_assets/templates/devuan-bignetwork-smoketest.preseed.j2" "pkgsel/include"
assert_file_contains "${ANSIBLE_ROOT}/playbooks/devuan-bignetwork-smoketest-netboot.yml" "hosts: netboot_publishers"
assert_file_contains "${REPO_ROOT}/docs/BIGNETWORK-FMT2-SMOKETEST.md" "Devuan smoke-test first"

(
  cd "${ANSIBLE_ROOT}"
  ansible-playbook -i inventories/examples/hosts.yml playbooks/devuan-bignetwork-smoketest-netboot.yml --syntax-check > /dev/null
)

printf 'PASS: %s\n' "$(basename "$0")"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/shell/test_bignetwork_smoketest_roles.sh`
Expected: fails on missing `roles/bignetwork_edge/defaults/main.yml`.

### Task 2: BigNetwork Edge Role

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/bignetwork_edge/defaults/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/bignetwork_edge/tasks/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/bignetwork_edge/templates/bn.openrc.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/bignetwork_edge/templates/bn.sysvinit.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/bignetwork_edge/templates/bignetwork-smoketest.sh.j2`

- [ ] **Step 1: Implement defaults**

Defaults define the extracted package source path, service manager, state directory, daemon port, tokens, and smoke-test destinations.

- [ ] **Step 2: Implement tasks**

Tasks create `bn` user/group, install `/usr/sbin/bn`, render `/etc/init.d/bn`, render `/usr/local/sbin/bignetwork-smoketest`, optionally render token files, and enable the service only when explicitly requested.

- [ ] **Step 3: Run test to verify role files**

Run: `bash tests/shell/test_bignetwork_smoketest_roles.sh`
Expected: still fails until Devuan netboot role exists.

### Task 3: Devuan Netboot Smoke-Test Role

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/devuan_netboot_assets/defaults/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/devuan_netboot_assets/tasks/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/devuan_netboot_assets/templates/devuan-bignetwork-smoketest.ipxe.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/devuan_netboot_assets/templates/devuan-bignetwork-smoketest.preseed.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/devuan-bignetwork-smoketest-netboot.yml`

- [ ] **Step 1: Implement defaults**

Defaults use Devuan `excalibur`, `amd64`, `pkgmaster.devuan.org`, DHCP networking, serial console, and a small package set: `openssh-server`, `sudo`, `curl`, `nmap`, `tcpdump`, `iproute2`, `ca-certificates`, `openssl`.

- [ ] **Step 2: Implement templates**

The iPXE script boots the official Devuan netboot kernel/initrd and passes a preseed URL. The preseed file keeps destructive autopartitioning behind an explicit opt-in variable.

- [ ] **Step 3: Implement playbook**

The playbook targets `netboot_publishers` and applies `devuan_netboot_assets`.

- [ ] **Step 4: Run syntax check**

Run: `cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible && ansible-playbook -i inventories/examples/hosts.yml playbooks/devuan-bignetwork-smoketest-netboot.yml --syntax-check`
Expected: syntax check passes.

### Task 4: Documentation

**Files:**
- Create: `docs/BIGNETWORK-FMT2-SMOKETEST.md`
- Create: `docs/wiki/BigNetwork-FMT2-Smoke-Test.md`
- Modify: `docs/FMT2-CHECKMK-TRANSPORT.md`
- Modify: `docs/ROADMAP-AND-TODO.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/wiki/FMT2-CheckMK-Transport.md`
- Modify: `docs/wiki/Roadmap-and-TODO.md`
- Modify: `docs/wiki/Changelog.md`
- Modify: `docs/wiki/Home.md`
- Modify: `docs/wiki/_Sidebar.md`

- [ ] **Step 1: Document the smoke-test sequence**

Include source artifact paths, inspected package facts, Devuan-first rationale, validation gates, and backout.

- [ ] **Step 2: Update FMT2 transport docs**

Add BigNetwork smoke-test as the primary transport validation implementation path.

- [ ] **Step 3: Update roadmap/changelog/wiki**

Record the new role scaffolding and the distinction between disposable Devuan testing and later Gentoo service integration.

### Task 5: Verification and Commit

**Files:**
- All files above.

- [ ] **Step 1: Run targeted test**

Run: `bash tests/shell/test_bignetwork_smoketest_roles.sh`
Expected: `PASS: test_bignetwork_smoketest_roles.sh`

- [ ] **Step 2: Run full shell tests**

Run: `bash tests/shell/run-tests.sh`
Expected: `PASS: run-tests.sh`

- [ ] **Step 3: Run whitespace check**

Run: `git diff --check`
Expected: no output and exit `0`.

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "Add BigNetwork FMT2 smoke-test scaffolding"
git push origin HEAD:codex/workstation-nscde-profile
```

## Self-Review

- Spec coverage: covers disposable Devuan VM, BigNetwork binary/service handling, iPXE/preseed generation, validation docs, and backout.
- Placeholder scan: no `TBD` or undefined implementation placeholders remain.
- Scope: permanent Gentoo packaging and ZFSBootMenu Devuan root are intentionally out of scope until transport is validated.
