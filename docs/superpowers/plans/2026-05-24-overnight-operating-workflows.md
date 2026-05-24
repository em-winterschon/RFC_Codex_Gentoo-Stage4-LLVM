# Overnight Operating Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep overnight Forge work productive after the M70 canary package/initramfs lane completes, prioritizing open GitHub issues without racing live infrastructure changes.

**Architecture:** Use one supervised live-mutation lane for M70 canary and multiple read-only or repo-only worker lanes for FMT2, NetBox/DNS, observability, and RDMA planning. Workers must keep write sets disjoint and produce dry-run artifacts before applying source-of-truth changes.

**Tech Stack:** Gentoo/OpenRC, Ansible, dracut, ZFS, distcc, NetBox, Hetzner DNS planning scripts, GitHub Issues, shell tests.

---

### Task 1: Finish M70 Canary Live Lane

**Files:**
- Modify: `docs/EOD-STATUS-2026-05-24.md`
- Modify: `docs/OVERNIGHT-EXECUTION-2026-05-24.md`

- [ ] **Step 1: Wait for the active Ansible session**

Use the Codex session supervisor on the active Ansible execution:

```json
{"session_id":19396,"chars":"","yield_time_ms":30000,"max_output_tokens":30000}
```

Expected: the Ansible recap prints before any further mutation starts.

- [x] **Step 2: Record package result**

The selected `system_packages` role completed successfully and was recorded in
the EOD verification section:

```markdown
- `system_packages` selected role run
  - result: pass
```

- [x] **Step 3: Regenerate universal initramfs after package convergence**

Ran:

```bash
ssh root@172.16.99.22 '/root/gentoo-liveiso-work/chroot-runner.sh '\''set -o pipefail
kver=6.18.32-p2-gentoo-dist-hardened
dracut --force --no-hostonly --early-microcode "/boot/initramfs-${kver}.img" "${kver}"
'\'''
```

Result: exit code `0`.

- [x] **Step 4: Verify initramfs payload**

Ran:

```bash
ssh root@172.16.99.22 '/root/gentoo-liveiso-work/chroot-runner.sh '\''set -o pipefail
img=/boot/initramfs-6.18.32-p2-gentoo-dist-hardened.img
lsinitrd "$img" | grep -E "kernel/x86/microcode|AuthenticAMD|GenuineIntel"
lsinitrd "$img" | grep -E "usr/bin/zfs$|usr/bin/mount.zfs|extra/zfs.ko|parse-zfs|mount-zfs" | head -40
lsinitrd "$img" | grep -E "dhclient|network-legacy" | head -40
'\'''
```

Result: output included `AuthenticAMD.bin`, `GenuineIntel.bin`, ZFS entries,
and dracut legacy network content.

- [ ] **Step 5: Commit verified M70 policy changes**

Run:

```bash
git status --short
git diff --check
bash tests/shell/test_ci_builder_farm_roles.sh
```

Expected: `git diff --check` exits `0` and the shell test prints `PASS`.

- [x] **Step 6: Apply verified distcc concurrency uplift**

Rendered and verified the M70 canary package concurrency policy:

```text
MAKEOPTS=-j24
EMERGE_DEFAULT_OPTS=--jobs=2 --load-average=16 ...
DISTCC_HOSTS=172.16.99.108/48,lzo
DISTCC_FALLBACK=0
```

This keeps the aggregate distcc compile envelope at 48 jobs while allowing two
Portage package builds to proceed concurrently.

### Task 2: Build FMT2 Evidence Plan

**Files:**
- Create: `docs/reports/fmt2-transport-gap-2026-05-24.md`

- [ ] **Step 1: Gather repo references**

Run:

```bash
rg -n "FMT2|SFO-200|BigNetwork|R630|Arista|7060|RDMA" docs gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories
```

Expected: command exits `0` and prints the current FMT2/RDMA references.

- [ ] **Step 2: Create the report**

Create the report directory and add this table header to
`docs/reports/fmt2-transport-gap-2026-05-24.md`:

```markdown
# FMT2 Transport Gap Report 2026-05-24

| Issue | Host/Device | Expected Source | Observed Evidence | Missing Validation | Safe Next Command |
| --- | --- | --- | --- | --- | --- |
```

- [ ] **Step 3: Populate rows from evidence only**

Add rows only for facts backed by repo docs, NetBox output, or captured command
output. Use `not yet observed` only in the Missing Validation column.

- [ ] **Step 4: Validate docs**

Run:

```bash
test -s docs/reports/fmt2-transport-gap-2026-05-24.md
```

Expected: exit code `0`.

### Task 3: Prepare NetBox/DNS Dry-Run

**Files:**
- Create: `docs/reports/netbox-dns-gap-2026-05-24.md`

- [ ] **Step 1: Confirm script interfaces**

Run:

```bash
./scripts/plan-hetzner-dns-from-netbox.py --help
./scripts/plan-hetzner-dns-from-inventory.py --help
```

Expected: both commands exit `0` and print usage.

- [ ] **Step 2: Create the dry-run report**

Create the report directory and add this content to
`docs/reports/netbox-dns-gap-2026-05-24.md`:

```markdown
# NetBox/DNS Gap Report 2026-05-24

| Object | NetBox Status | DNS Status | Proposed Action | Apply Gate |
| --- | --- | --- | --- | --- |
```

- [ ] **Step 3: Keep apply gated**

Do not run `apply-hetzner-dns-plan.py` unless the dry-run report has explicit
operator-approved rows.

### Task 4: Add Post-Install Assertions

**Files:**
- Modify: `tests/shell/test_ci_builder_farm_roles.sh`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/netboot_assets/defaults/main.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/netboot_assets/tasks/main.yml`

- [ ] **Step 1: Add failing DNS validation assertion**

Add this assertion to `tests/shell/test_ci_builder_farm_roles.sh`:

```bash
assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/defaults/main.yml" 'netboot_dns_validation_enabled: true'
assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" 'Validate Path B role DNS resolver command lines'
assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" '--mode'
assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" 'static'
assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" 'live'
```

- [ ] **Step 2: Run the focused test**

Run:

```bash
bash tests/shell/test_ci_builder_farm_roles.sh
```

Expected: fails if any DNS validation invariant is missing.

- [ ] **Step 3: Implement the smallest matching role change if the test fails**

Edit only `roles/netboot_assets/defaults/main.yml` or
`roles/netboot_assets/tasks/main.yml` so the role keeps static validation
enabled by default and supports both static and live DNS validation modes before
netboot assets are published.

- [ ] **Step 4: Re-run the focused test**

Run:

```bash
bash tests/shell/test_ci_builder_farm_roles.sh
```

Expected: prints `PASS: test_ci_builder_farm_roles.sh`.
