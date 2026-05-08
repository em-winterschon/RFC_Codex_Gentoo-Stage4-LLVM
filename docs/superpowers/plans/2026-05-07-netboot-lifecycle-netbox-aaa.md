# Netboot Lifecycle, NetBox Intake, And AAA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit netboot protocol-flow modeling, reproducible boot-image manifest data, repo-safe K10/AP7901 NetBox intake, and the next AAA dependency sequence.

**Architecture:** Keep existing `netboot_type` semantics for IP assignment and add `netboot_protocol_flow` for firmware/handoff behavior. Promote K10 and AP7901 facts through existing inventory-intake files and dry-run tooling before any live NetBox write.

**Tech Stack:** Ansible roles, YAML inventory, Jinja templates, Python NetBox intake validator/apply scripts, shell regression tests, Markdown docs.

---

### Task 1: Add Failing Tests For Netboot Flow

**Files:**
- Modify: `tests/shell/test_netboot_assets.sh`
- Modify: `tests/shell/test_routeros_pathb_role.sh`

- [ ] **Step 1: Extend netboot asset assertions**

Add assertions for `netboot_protocol_flow_enum`, `netboot_protocol_flow`,
`protocolFlow`, and the K10 `pxe-to-ipxe` inventory value.

- [ ] **Step 2: Extend RouterOS assertions**

Add assertions for `routeros_pathb_netboot_protocol_flow_enum`,
`protocol_flow`, and target manifest visibility.

- [ ] **Step 3: Run tests and confirm failure**

Run:

```bash
bash tests/shell/test_netboot_assets.sh
bash tests/shell/test_routeros_pathb_role.sh
```

Expected before implementation: at least one assertion fails because the enum
and manifest fields do not exist.

### Task 2: Implement Netboot Flow

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/netboot_assets/defaults/main.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/netboot_assets/tasks/main.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/netboot_assets/templates/netboot-manifest.json.j2`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/routeros_pathb/defaults/main.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/routeros_pathb/tasks/main.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/routeros_pathb/templates/routeros-pathb-manifest.json.j2`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/routeros_pathb/templates/routeros-pathb.rsc.j2`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml`

- [ ] **Step 1: Add enum defaults**

Add protocol-flow enum values:

```yaml
netboot_protocol_flow_enum:
  - ipxe-direct
  - pxe-to-ipxe
  - uefi-httpboot
  - disabled
```

RouterOS gets the equivalent `routeros_pathb_netboot_protocol_flow_enum`.

- [ ] **Step 2: Validate host vars**

Assert `netboot_protocol_flow | default('ipxe-direct')` is in the enum for both
roles.

- [ ] **Step 3: Carry the value into resolved host maps**

Add `protocol_flow` to netboot and RouterOS target dictionaries.

- [ ] **Step 4: Render manifests**

Add `"protocolFlow": "{{ ... }}"` to netboot and RouterOS manifests.

- [ ] **Step 5: Mark K10 explicitly**

Set:

```yaml
netboot_protocol_flow: pxe-to-ipxe
```

on `gmktek_nucbox_k10_stage5_candidate`.

- [ ] **Step 6: Verify tests pass**

Run:

```bash
bash tests/shell/test_netboot_assets.sh
bash tests/shell/test_routeros_pathb_role.sh
```

Expected: both tests pass.

### Task 3: Add Boot-Image Manifest Data

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/netboot-image-manifests/k10-stage5-workstation.yml`
- Modify: `tests/shell/test_netboot_assets.sh`
- Modify: `docs/GMKTEK-K10-STAGE5-VALIDATION.md`
- Modify: `docs/wiki/GMKtek-K10-Stage5-Validation.md`

- [ ] **Step 1: Add test assertion**

Assert the manifest contains `kind: NetbootImageManifest`,
`gmktek_nucbox_k10_stage5_candidate`, `rtl_nic/rtl8125b-2.fw`, and
`initrd=initrd.magic`.

- [ ] **Step 2: Create manifest**

Create a YAML manifest with kernel/initramfs/rootfs URLs, dracut modules,
firmware list, static command line, and build script.

- [ ] **Step 3: Document usage**

Reference the manifest in K10 validation docs as the Jenkins rebuild source.

- [ ] **Step 4: Verify**

Run:

```bash
bash tests/shell/test_netboot_assets.sh
```

Expected: pass.

### Task 4: Add NetBox Intake For K10 And AP7901

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/local-rfc1918-lab.yml`
- Modify: `tests/shell/test_netbox_inventory_intake.sh`

- [ ] **Step 1: Add failing intake assertions**

Assert the local intake file contains `gmktek_nucbox_k10_stage5_candidate`,
`pdu_rfc99_corectrl_ap7901`, `172.16.99.156`, `172.16.99.241`, and
`host_gmktec_k10`.

- [ ] **Step 2: Add K10 device**

Add a K10 device row with management IP, manufacturer/model, boot interface,
MAC, CSS326 `ge16`, and netboot notes.

- [ ] **Step 3: Add AP7901 device**

Add an AP7901 device row with management IP, serial, SNMPv3 capability note,
and outlet 6 mapping note. Do not add secrets.

- [ ] **Step 4: Update expected count**

Change all-sites validation expected device count from `15` to `17`.

- [ ] **Step 5: Verify dry-run plan**

Run:

```bash
bash tests/shell/test_netbox_inventory_intake.sh
```

Expected: pass and dry-run plan includes the new devices and IPs.

### Task 5: Update AAA And Operator Docs

**Files:**
- Modify: `docs/IDENTITY-AAA.md`
- Modify: `docs/wiki/Identity-AAA.md`
- Modify: `docs/ANSIBLE-VAULT.md`
- Modify: `docs/ROADMAP-AND-TODO.md`
- Modify: `docs/wiki/Roadmap-and-TODO.md`

- [ ] **Step 1: Add the rollout sequence**

Document Linux-client, network-device, AP7901, and broad device enrollment.

- [ ] **Step 2: Add power-device guardrail**

Document that RADIUS enrollment must retain local break-glass credentials and
that NetBox stores only non-secret metadata.

- [ ] **Step 3: Verify docs syntax**

Run:

```bash
git diff --check
```

Expected: no whitespace errors.

### Task 6: Full Verification And Commit

**Files:**
- All modified files from earlier tasks.

- [ ] **Step 1: Run focused tests**

Run:

```bash
bash tests/shell/test_netboot_assets.sh
bash tests/shell/test_routeros_pathb_role.sh
bash tests/shell/test_netbox_inventory_intake.sh
git diff --check
```

Expected: all pass.

- [ ] **Step 2: Review diff**

Run:

```bash
git status --short
git diff --stat
```

Expected: only planned files are modified.

- [ ] **Step 3: Commit and push**

Run:

```bash
git add <planned files>
git commit -m "Add netboot lifecycle and inventory intake planning"
git push
```

Expected: branch updates on origin.
