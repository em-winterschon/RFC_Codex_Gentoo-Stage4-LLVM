# NetBox DCIM/IPAM And CRS309 Router Replacement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a safe, repeatable overnight path to complete NetBox IPAM/DCIM intake for mixed environments and replace the failed OPNsense router with a MikroTik CRS309 only after source-of-truth and rollback gates pass.

**Architecture:** Treat NetBox as the source-of-truth gate before router mutation. Keep operator raw files outside the repo, convert them into sanitized structured intake files, validate/dry-run/apply NetBox changes, snapshot NetBox, then execute RouterOS changes in staged management-only, WAN, LAN, firewall, and service phases.

**Tech Stack:** NetBox `v4.5.9`, Ansible, RouterOS CRS309, repo-local Python intake validators, Proxmox snapshots, SSH/API token-file authentication, shell regression tests.

---

## Execution Status 2026-05-03

- Raw `/tmp/rfc99-sun99-host-networking.md` and
  `/tmp/crs309-router-mode-idc.wip.rsc` were archived under
  `/root/operator-private/network-intake/2026-05-03/`.
- Sanitized intake files now exist for `rfc99`, `sun99`, `yks99`, and `fmt2`.
- Local validation passes across all structured intake files.
- Offline dry-run apply plan is generated.
- Live NetBox apply remains blocked until `172.16.99.0/24` management
  reachability to `172.16.99.62` and Hasslehoff SSH is restored.
- CRS309 RouterOS mutation remains blocked until admin access/reset, serial
  fallback, backup/export, and management-only bootstrap are confirmed.

## File Structure

- `docs/NETBOX-IPAM-DCIM-COMPLETION-PLAN.md`
  - Human-readable source-of-truth completion plan for RFC99, SUN99, FMT2, and future sites.
- `docs/CRS309-ROUTEROS-REPLACEMENT-PLAN.md`
  - RouterOS replacement-router execution plan, risk register, validation gates, and rollback path.
- `docs/EOD-STATUS-2026-05-02.md`
  - End-of-day status and overnight execution plan.
- `docs/wiki/*.md`
  - Wiki mirrors for the above documents.
- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/*.yml`
  - Only add new files here after raw host/IP/MAC data exists and has been sanitized.
- `tests/shell/test_network_planning_docs.sh`
  - Regression coverage that required planning docs and wiki mirrors exist.

## Task 1: Confirm Raw Inputs

**Files:**
- Read-only: `/tmp/rfc99-sun99-host-networking.md`
- Read-only: `/tmp/crs309-router-mode-idc.wip.rsc`

- [ ] **Step 1: Check exact input file paths**

Run:

```bash
test -f /tmp/rfc99-sun99-host-networking.md
test -f /tmp/crs309-router-mode-idc.wip.rsc
```

Expected: both commands exit `0`. If the host/networking file is missing, stop any full NetBox import and proceed only with documentation and CRS309 planning.

- [ ] **Step 2: Copy raw files to operator-private storage**

Run:

```bash
install -d -m 0700 /root/operator-private/network-intake/2026-05-02
cp -p /tmp/rfc99-sun99-host-networking.md /root/operator-private/network-intake/2026-05-02/
cp -p /tmp/crs309-router-mode-idc.wip.rsc /root/operator-private/network-intake/2026-05-02/
chmod 0600 /root/operator-private/network-intake/2026-05-02/*
```

Expected: raw files are archived outside the repo.

## Task 2: Build Sanitized NetBox Intake Files

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/sun99.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/fmt2.yml`
- Modify: `docs/NETBOX-IPAM-DCIM-COMPLETION-PLAN.md`
- Test: `tests/shell/test_netbox_inventory_intake.sh`

- [ ] **Step 1: Extract site/environment records**

Create one intake file per environment. Each file must start with:

```yaml
---
inventory_intake_version: 1
datacenters:
  - name: sun99
    slug: sun99
    timezone: America/Los_Angeles
    facility: operator-confirmed
    management_prefixes: []
prefixes: []
devices: []
clusters: []
service_vips: []
```

Expected: every environment in the raw host/networking file has one intake file.

- [ ] **Step 2: Add prefixes and gateway IPs**

For every prefix in the raw source, add:

```yaml
  - prefix: 172.28.10.0/24
    site: sun99
    status: planned
    role: yukon-l3-metal-hosts
```

Expected: no duplicate `prefix` values in one site file unless an intentional migration exception is documented in the plan.

- [ ] **Step 3: Add hosts as devices or VMs**

For physical equipment:

```yaml
  - name: gw_sun99_mkcrs309
    site: sun99
    role: router
    manufacturer: MikroTik
    model: CRS309-1G-8S+IN
    status: planned
    management_ip: 10.128.128.1
```

For virtual hosts:

```yaml
  - name: example_vm
    site: sun99
    role: service-vm
    manufacturer: Generic
    model: virtual-machine
    status: planned
    management_ip: 172.28.10.20
```

Expected: every host with an IP or MAC in the raw input has a NetBox object path.

- [ ] **Step 4: Validate intake**

Run:

```bash
python3 scripts/validate_netbox_inventory_intake.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites
```

Expected: exit `0`.

## Task 3: Dry-Run And Apply NetBox

**Files:**
- Use: `scripts/netbox_apply_inventory_intake.py`
- Use: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/netbox-inventory-intake-apply.yml`

- [ ] **Step 1: Dry-run apply**

Run:

```bash
python3 scripts/netbox_apply_inventory_intake.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites \
  --api-url http://172.16.99.62 \
  --format json
```

Expected: `"dry_run": true` and no unexpected site/prefix/device labels.

- [ ] **Step 2: Snapshot NetBox before write**

Run:

```bash
ssh root@hasslehoff "qm snapshot 1062 codex-netbox-before-multisite-intake --description 'Before RFC99 SUN99 FMT2 NetBox intake apply'"
```

Expected: Proxmox snapshot command exits `0`.

- [ ] **Step 3: Apply with token file**

Run:

```bash
python3 scripts/netbox_apply_inventory_intake.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites \
  --api-url http://172.16.99.62 \
  --token-file /root/operator-private/netbox/svc-netbox-stage4-admin-token \
  --apply \
  --update-existing \
  --format json
```

Expected: created/updated labels match the reviewed dry-run plan.

- [ ] **Step 4: Run idempotence apply**

Run the same command without `--update-existing`.

Expected: `"created": []` and `"updated": []`.

- [ ] **Step 5: Snapshot NetBox after write**

Run:

```bash
ssh root@hasslehoff "qm snapshot 1062 codex-netbox-after-multisite-intake --description 'After RFC99 SUN99 FMT2 NetBox intake apply'"
```

Expected: Proxmox snapshot command exits `0`.

## Task 4: Prepare CRS309 Router Replacement

**Files:**
- Read-only: `/tmp/crs309-router-mode-idc.wip.rsc`
- Modify: `docs/CRS309-ROUTEROS-REPLACEMENT-PLAN.md`

- [ ] **Step 1: Export current router state**

On the CRS309 console:

```routeros
/system backup save name=pre-crs309
/export file=pre-crs309 hide-sensitive
```

Expected: both backup artifacts are present on-device and copied off-device before any destructive import.

- [ ] **Step 2: Apply management-only baseline**

Apply only identity, management IP, SSH, API/HTTPS, and management firewall rules.

Expected: SSH and WebFig/API remain reachable from the intended management subnet.

- [ ] **Step 3: Apply WAN DHCP**

Apply WAN DHCP only on `sfp-sfpplus1`.

Expected: default route is installed and DNS/internet egress works from the router.

- [ ] **Step 4: Apply LAN bridge with one member**

Add `br-lan` and a single low-risk LAN port.

Expected: one attached host can reach the gateway and the internet.

- [ ] **Step 5: Add remaining LAN prefixes and ports**

Apply one prefix group at a time, validating after each group.

Expected: no management loss, no unexpected route overlap, and NetBox matches RouterOS export.

## Task 5: Verification And Commit

**Files:**
- Modify: `docs/EOD-STATUS-2026-05-02.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/ROADMAP-AND-TODO.md`
- Modify: `docs/wiki/*`

- [ ] **Step 1: Run tests**

Run:

```bash
bash tests/shell/run-tests.sh
git diff --check
```

Expected: both commands exit `0`.

- [ ] **Step 2: Publish wiki mirror**

Run:

```bash
bash scripts/publish-wiki.sh --push
```

Expected: wiki worktree commits and pushes if there are mirrored changes.

- [ ] **Step 3: Commit repo changes**

Run:

```bash
git add docs gentoo_stage4_llvm_split-usr_no-multilib_hardened tests scripts
git commit -m "Document NetBox DCIM and CRS309 replacement plan"
git push origin codex/add-container-services-profile
```

Expected: branch pushes successfully.

## Self-Review

- Every destructive RouterOS action has a pre-change backup and console fallback gate.
- NetBox apply is gated by validation, dry-run, pre-write snapshot, apply, idempotence check, and post-write snapshot.
- The missing `/tmp/rfc99-sun99-host-networking.md` file is an explicit blocker for full IPAM/DCIM completion.
- No raw secrets or RouterOS sensitive exports belong in the repo.
