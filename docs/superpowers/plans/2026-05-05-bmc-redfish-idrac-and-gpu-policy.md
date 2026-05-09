# BMC Redfish iDRAC And GPU Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe Redfish/iDRAC BMC scaffolding and an Ansible GPU host policy for NVIDIA compute/passthrough hosts.

**Architecture:** Keep BMC telemetry exporters separate from BMC control-plane roles. Use vendor-neutral Redfish first, wrap Dell iDRAC defaults in a Dell role, and keep all mutation operations disabled unless explicit allow variables are set. GPU policy is a host configuration role driven by `gpu_compute` inventory membership.

**Tech Stack:** Ansible Core, `ansible.builtin.uri`, Jinja2 templates, local-network YAML inventory, Ansible syntax/render validation.

---

### Task 1: Add Validation Fixtures

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/gpu-host-policy-render-check.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/bmc-redfish-validate.yml`

- [ ] **Step 1: Add GPU render check playbook**

Create a localhost playbook that sets `gpu_compute_enabled: true`, writes role output under `/tmp/gpu-host-policy-render-check`, and asserts that the blacklist and GRUB drop-in files contain `nouveau` and `nvidiafb`.

- [ ] **Step 2: Add BMC syntax check playbook**

Create a playbook targeting `bmc_managed` with the `bmc_redfish` role and `dell_idrac` with the `bmc_idrac` role. Keep it safe by relying on role defaults and not setting mutation variables.

- [ ] **Step 3: Verify RED**

Run:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook playbooks/gpu-host-policy-render-check.yml
```

Expected: failure because `gpu_host_policy` does not exist yet.

### Task 2: Add GPU Host Policy Role

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/gpu_host_policy/defaults/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/gpu_host_policy/tasks/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/gpu_host_policy/templates/blacklist-nvidia-gpu.conf.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/gpu_host_policy/templates/grub-gpu-compute-blacklist.cfg.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/gpu-host-policy.yml`

- [ ] **Step 1: Implement defaults**

Defaults must include `gpu_compute_enabled: false`, `gpu_host_policy_blacklisted_modules: [nouveau, nvidiafb]`, a configurable `gpu_host_policy_root`, and disabled update commands.

- [ ] **Step 2: Implement tasks**

Tasks must detect NVIDIA PCI devices, decide whether policy should apply, render modprobe/GRUB files, and optionally run update commands only when explicitly enabled.

- [ ] **Step 3: Verify GREEN**

Run:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook playbooks/gpu-host-policy-render-check.yml
```

Expected: play recap with `failed=0`.

### Task 3: Add Redfish And iDRAC Roles

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/bmc_redfish/defaults/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/bmc_redfish/tasks/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/bmc_idrac/defaults/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/bmc_idrac/tasks/main.yml`

- [ ] **Step 1: Implement `bmc_redfish` defaults**

Defaults must include endpoint, credentials, cert validation, system/manager IDs, mutation gate, power action, boot override, and virtual media settings.

- [ ] **Step 2: Implement read-only Redfish fact collection**

Tasks must authenticate to `/redfish/v1/`, discover systems, managers, chassis, gather the selected system, and set `bmc_redfish_facts`.

- [ ] **Step 3: Implement gated mutations**

Tasks must fail before making changes if mutation variables are requested but `bmc_redfish_allow_mutation` is not true.

- [ ] **Step 4: Implement Dell wrapper**

The Dell role must call `bmc_redfish` with iDRAC endpoint defaults and validate the observed vendor/manufacturer when enabled.

- [ ] **Step 5: Verify syntax**

Run:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook --syntax-check playbooks/bmc-redfish-validate.yml
```

Expected: syntax check passes.

### Task 4: Wire Local Inventory

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/host_vars/hasslehoff.yml`

- [ ] **Step 1: Add inventory groups**

Add `gpu_compute`, `bmc_managed`, and `dell_idrac` groups. Put Hasslehoff in `gpu_compute` and `bmc_managed`; keep Dell iDRAC groups empty until remote hosts are inventoried.

- [ ] **Step 2: Update Hasslehoff facts**

Record the K1200 GPU, QLogic CNA ports, expected driver blacklist, and removed CCR2004-PCIe state.

- [ ] **Step 3: Verify inventory parse**

Run:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-inventory -i inventories/local-network/hosts.yml --list
```

Expected: inventory parses with vault environment available.

### Task 5: Documentation And Commit

**Files:**
- Modify: `docs/ROADMAP-AND-TODO.md`
- Modify: `docs/wiki/Roadmap-and-TODO.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/wiki/Changelog.md`

- [ ] **Step 1: Document scaffold state**

Add roadmap entries for BMC control-plane automation and GPU compute blacklist policy.

- [ ] **Step 2: Run final checks**

Run:

```bash
git diff --check
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook playbooks/gpu-host-policy-render-check.yml
ansible-playbook --syntax-check playbooks/bmc-redfish-validate.yml
```

Expected: all commands exit `0`.

- [ ] **Step 3: Commit and push**

Commit all changes with:

```bash
git add docs gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
git commit -m "Add BMC Redfish and GPU host policy scaffolding"
git push origin HEAD
```
