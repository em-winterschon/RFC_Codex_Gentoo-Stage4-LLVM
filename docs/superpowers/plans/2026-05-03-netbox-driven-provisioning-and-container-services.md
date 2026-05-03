# NetBox-Driven Provisioning And Container Services Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make NetBox the source of truth for host inventory, IPAM, DNS validation, and VM/container-service provisioning, then deploy the container-services VM and application containers on Hasslehoff.

**Architecture:** NetBox owns sites, clusters, devices, VMs, prefixes, VLANs, IP addresses, DNS names, service VIPs, and tags. Repo tooling exports NetBox inventory into Ansible-ready host/service definitions, cross-checks Hetzner DNS provider state, provisions Proxmox VMs on Hasslehoff, applies Stage4/Stage5 profiles, and validates exposed services with nmap-backed readiness checks. DNS writes stay dry-run until explicit apply/delete gates are enabled.

**Tech Stack:** NetBox `v4.5.9`, Proxmox `8.4.13`, Ansible/OpenRC, Gentoo Stage4/Stage5 profiles, Podman/netavark/nftables, HAProxy, nginx, ntfy, rsyslog, Elasticsearch/Kibana/APM profiles, Hetzner DNS API, nmap service validator.

---

## Current Verified Baseline

- NetBox VM: `1062`, `svc-netbox-stage4`, `172.16.99.62`, API validates when `netbox_seed_token_file=/root/operator-private/netbox/svc-netbox-stage4-admin-token` is supplied.
- Hasslehoff Proxmox: `172.16.99.9`, API validates, version `8.4.13`, current VM count `5`.
- Running VMs: `1062 svc-netbox-stage4`, `1063 svc-identity-ipa01`.
- Stopped VMs: `1001 gw-rfc99-vyos-routeprime`, `1011 ctbsd-rfc99-jailerprime-099099`, `1012 eph-sun99-sourcebot-099229`.
- Hasslehoff storage checked over SSH: `/var/lib/vz` has roughly `283G` available.
- Hetzner DNS provider inventory: `8/8` zones readable, `221` records, `99` address-bearing connectivity hosts, `0` errors.
- NetBox-to-Hetzner dry-run plan: `7` records, `5` skipped unnamed IPs, no DNS writes.

## File Map

- Read: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/*.yml`
- Read: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml`
- Read: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/vm-container-services.yml`
- Read: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/pathb-container-services/host_vars/vm_container_services.yml`
- Read: `scripts/report-hetzner-dns-inventory.py`
- Read: `scripts/plan-hetzner-dns-from-netbox.py`
- Read: `scripts/service_validator.py`
- Create: `scripts/export-netbox-provisioning-inventory.py`
- Create: `tests/shell/test_export_netbox_provisioning_inventory.sh`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/netbox-provisioning-inventory-export.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/netbox-generated/README.md`
- Create: `scripts/proxmox-create-stage4-service-vm.sh`
- Create: `tests/shell/test_proxmox_create_stage4_service_vm.sh`
- Modify: `tests/shell/run-tests.sh`
- Modify: `docs/NETBOX-IPAM-DCIM-COMPLETION-PLAN.md`
- Modify: `docs/PROXMOX-NETBOX-ROUTEROS-ACTION-PLAN.md`
- Modify: `docs/CONTAINER-SERVICES-VALIDATION.md`
- Modify: `docs/ROADMAP-AND-TODO.md`
- Modify: `docs/CHANGELOG.md`

## Task 1: Normalize NetBox Object Ownership For Provisioning

Purpose: make every automation-owned object discoverable and safe to reconcile.

- [ ] **Step 1: Add NetBox tags through existing intake data**

Edit each relevant site intake file under:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/
```

Ensure automation-owned VMs, VIPs, service IPs, and management devices carry these logical tags in their source records:

```yaml
tags:
  - codex-managed
  - stage4-stage5
  - netbox-source-of-truth
```

- [ ] **Step 2: Validate intake schema**

Run:

```bash
python3 scripts/validate_netbox_inventory_intake.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites
```

Expected: validation exits `0` and reports the same or higher site/device/prefix counts.

- [ ] **Step 3: Apply only after a NetBox snapshot**

Run on Hasslehoff:

```bash
ssh root@hasslehoff 'qm snapshot 1062 nb-pre-provisioning-$(date +%Y%m%d) --description "Before NetBox provisioning ownership tags"'
```

Then run:

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/netbox-inventory-intake-apply.yml \
  -e netbox_inventory_apply=true \
  -e netbox_inventory_update_existing=true \
  -e netbox_seed_token_file=/root/operator-private/netbox/svc-netbox-stage4-admin-token
```

Expected: apply completes with no destructive changes.

- [ ] **Step 4: Commit**

```bash
git add gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake docs/CHANGELOG.md docs/ROADMAP-AND-TODO.md
git commit -m "Tag NetBox provisioning-owned inventory"
```

## Task 2: Export NetBox Into Ansible Provisioning Inventory

Purpose: generate host inventory and IPAM maps directly from NetBox instead of hand-maintaining static host files.

- [ ] **Step 1: Write failing shell test**

Create `tests/shell/test_export_netbox_provisioning_inventory.sh` with fixture JSON that includes:

```json
{
  "virtual_machines": [
    {
      "name": "container-services",
      "status": {"value": "planned"},
      "primary_ip4": {"address": "10.9.8.89/24", "dns_name": "container-services.rfc1918.host"},
      "cluster": {"name": "hasslehoff"},
      "tags": [{"name": "codex-managed"}],
      "custom_fields": {"stage5_role": "container-services"}
    }
  ]
}
```

The test must assert that the exporter writes:

```yaml
all:
  children:
    install_targets:
      hosts:
        container_services:
          ansible_host: 10.9.8.89
          install_hostname: container-services
          stage5_role: container-services
```

- [ ] **Step 2: Run failing test**

```bash
bash tests/shell/test_export_netbox_provisioning_inventory.sh
```

Expected before implementation: failure because `scripts/export-netbox-provisioning-inventory.py` does not exist.

- [ ] **Step 3: Implement exporter**

Create `scripts/export-netbox-provisioning-inventory.py`.

Required behavior:

```text
Input: NetBox VM/device/IP API JSON or live NetBox API.
Filter: tag `codex-managed` by default.
Output 1: Ansible inventory YAML.
Output 2: IPAM map JSON.
Output 3: service validation target JSON.
Safety: never serialize API tokens.
```

- [ ] **Step 4: Add Ansible wrapper**

Create:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/netbox-provisioning-inventory-export.yml
```

The playbook must read `/root/operator-private/netbox/svc-netbox-stage4-admin-token`, run the exporter, and write:

```text
/tmp/netbox-provisioning-inventory/hosts.yml
/tmp/netbox-provisioning-inventory/ipam.json
/tmp/netbox-provisioning-inventory/service-targets.json
```

- [ ] **Step 5: Verify**

```bash
bash tests/shell/test_export_netbox_provisioning_inventory.sh
python3 -m py_compile scripts/export-netbox-provisioning-inventory.py
```

Expected: both commands exit `0`.

- [ ] **Step 6: Live read-only export**

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/netbox-provisioning-inventory-export.yml
```

Expected: generated inventory includes Hasslehoff-hosted service VMs and no API tokens.

- [ ] **Step 7: Commit**

```bash
git add scripts/export-netbox-provisioning-inventory.py tests/shell/test_export_netbox_provisioning_inventory.sh \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/netbox-provisioning-inventory-export.yml \
  tests/shell/run-tests.sh docs/CHANGELOG.md docs/ROADMAP-AND-TODO.md
git commit -m "Export NetBox provisioning inventory"
```

## Task 3: Reconcile DNS, NetBox, And Healthcheck Targets

Purpose: detect unmanaged DNS hosts, missing DNS names, and stale provider records before provisioning.

- [ ] **Step 1: Generate current DNS provider report**

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/hetzner-dns-inventory-report.yml
```

- [ ] **Step 2: Generate NetBox desired DNS plan**

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/hetzner-dns-plan-from-netbox.yml
```

- [ ] **Step 3: Compare results manually before automation**

Read:

```text
/tmp/hetzner-dns-inventory-report.json
/tmp/hetzner-dns-plan-from-netbox.json
/tmp/netbox-provisioning-inventory/service-targets.json
```

Decision rule:

```text
If a DNS A/AAAA host exists in Hetzner but not NetBox, mark it unmanaged first.
If a NetBox host has no DNS name, add dns_name in NetBox before provisioning service checks.
If a NetBox desired record conflicts with provider DNS, do not apply DNS changes until owner tags are set.
```

- [ ] **Step 4: Run service validator against generated targets**

For each generated target, run:

```bash
python3 scripts/service_validator.py --target "${target}" --port "${port}" --protocol tcp --service-name "${service_name}" --json
```

Expected before services are created: planned services may fail; existing management services should report open.

## Task 4: Prepare Hasslehoff Proxmox VM Provisioning Path

Purpose: make VM creation repeatable and NetBox-backed.

- [x] **Step 1: Validate Proxmox API and SSH**

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/proxmox-api-validate.yml

ssh -o BatchMode=yes -o ConnectTimeout=5 root@hasslehoff 'pveversion; qm list; df -h /var/lib/vz'
```

Expected: Proxmox version reports `8.4.13`, SSH succeeds, and `/var/lib/vz` has sufficient free space.

- [x] **Step 2: Write failing shell test for generic Proxmox VM script**

Create `tests/shell/test_proxmox_create_stage4_service_vm.sh`.

The test must assert that `scripts/proxmox-create-stage4-service-vm.sh --dry-run` emits safe commands for:

```text
qm create
qm importdisk
qm set --scsihw virtio-scsi-single
qm set --net0 virtio,bridge=vmbr0
qm set --agent enabled=1
qm set --serial0 socket
qm set --boot order=scsi0
```

- [x] **Step 3: Implement generic Proxmox VM creation script**

Create `scripts/proxmox-create-stage4-service-vm.sh`.

Required inputs:

```text
VMID
VM_NAME
VM_MEMORY_MIB
VM_CORES
VM_BRIDGE
VM_MAC
VM_IP_CIDR
VM_GATEWAY
VM_STORAGE
SOURCE_QCOW
NETBOX_ROLE
```

Required safety behavior:

```text
Default mode is dry-run.
Live mode requires PROXMOX_APPLY=1.
Existing VMID aborts unless PROXMOX_REPLACE=1.
No destructive deletion without explicit PROXMOX_REPLACE=1.
```

- [x] **Step 4: Verify script**

```bash
bash tests/shell/test_proxmox_create_stage4_service_vm.sh
bash -n scripts/proxmox-create-stage4-service-vm.sh
```

Expected: both commands exit `0`.

- [x] **Step 5: Commit**

```bash
git add scripts/proxmox-create-stage4-service-vm.sh tests/shell/test_proxmox_create_stage4_service_vm.sh tests/shell/run-tests.sh
git commit -m "Add Proxmox Stage4 service VM creator"
```

## Task 5: Provision Container-Services VM On Hasslehoff

Purpose: deploy the Podman host VM from the existing Stage4/Stage5 container-services profile.

- [ ] **Step 1: Reserve or confirm NetBox VM/IP**

Confirm NetBox owns:

```text
name: container-services
cluster: hasslehoff
primary_ip4: 10.9.8.89/24
role: container-services
profile: vm-container-services
```

- [ ] **Step 2: Confirm Stage4 source image**

Find the current validated Stage4 base image:

```bash
find /opt /var/lib/vz -type f \( -name '*stage4*.qcow2' -o -name '*gentoo*.qcow2' \) 2>/dev/null | sort
```

Expected: one chosen image is documented before importing into Proxmox.

- [ ] **Step 3: Dry-run VM creation**

```bash
VMID=1089 \
VM_NAME=svc-container-services-01 \
VM_MEMORY_MIB=32768 \
VM_CORES=16 \
VM_BRIDGE=vmbr0 \
VM_MAC=52:54:00:12:34:78 \
VM_IP_CIDR=10.9.8.89/24 \
VM_GATEWAY=10.9.8.1 \
VM_STORAGE=local-zfs \
SOURCE_QCOW=/path/to/chosen-stage4.qcow2 \
NETBOX_ROLE=container-services \
scripts/proxmox-create-stage4-service-vm.sh --dry-run
```

- [ ] **Step 4: Snapshot NetBox and apply live VM creation**

```bash
ssh root@hasslehoff 'qm snapshot 1062 nb-pre-container-vm-$(date +%Y%m%d) --description "Before container-services VM provisioning"'
PROXMOX_APPLY=1 scripts/proxmox-create-stage4-service-vm.sh
```

- [ ] **Step 5: Boot and validate VM**

```bash
ssh root@hasslehoff 'qm start 1089'
ssh -o BatchMode=yes -o ConnectTimeout=10 root@10.9.8.89 'hostname; rc-status; podman --version; podman info --format json'
```

Expected: SSH connects, OpenRC responds, and Podman reports a valid runtime.

## Task 6: Apply Container Service Roles

Purpose: bring up Podman networks, nftables policy, and base app service definitions.

- [ ] **Step 1: Run Ansible profile install against the container VM**

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/pathb-container-services/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/install.yml
```

- [ ] **Step 2: Validate Podman networks**

```bash
ssh root@10.9.8.89 'podman network ls; podman network inspect apps mgmt'
```

Expected: `apps` and `mgmt` networks exist with the configured `10.77.1.0/24` and `10.77.0.0/24` ranges.

- [ ] **Step 3: Validate nftables policy**

```bash
ssh root@10.9.8.89 'nft list ruleset'
```

Expected: ruleset includes management CIDRs, container NAT, and default drop posture for input/forward.

- [ ] **Step 4: Start nginx and HAProxy containers**

```bash
ssh root@10.9.8.89 '/usr/local/sbin/stage5-podman-app-run nginx'
ssh root@10.9.8.89 '/usr/local/sbin/stage5-podman-app-run haproxy'
```

Expected: `podman ps` shows both containers running.

- [ ] **Step 5: Validate published service ports**

```bash
python3 scripts/service_validator.py --target 10.9.8.89 --port 80 --protocol tcp --service-name container-services-haproxy-http --json
python3 scripts/service_validator.py --target 10.9.8.89 --port 8080 --protocol tcp --service-name container-services-nginx --json
```

Expected: both return `success: true`.

## Task 7: Expand Application VM And Container Matrix

Purpose: deploy the required services in priority order after the container host is stable.

- [ ] **Step 1: Deploy logging ingress first**

Service order:

```text
rsyslog collector container
HAProxy rsyslog VIP
Elasticsearch test VM
Kibana VM
Elastic APM container
```

Validation:

```bash
python3 scripts/service_validator.py --target 10.9.8.20 --port 514 --protocol tcp --service-name rsyslog-ingest-vip --json
python3 scripts/service_validator.py --target 10.9.8.21 --port 9200 --protocol tcp --service-name elasticsearch-vip --json
```

- [ ] **Step 2: Deploy operator-facing services**

Service order:

```text
ntfy container
nginx container
HAProxy web VIP
NetBox TLS frontend
FreeIPA/RADIUS validation endpoints
```

- [ ] **Step 3: Deploy observability exporters**

Service order:

```text
node exporter
podman exporter
elasticsearch exporter
redfish exporter
ipmi exporter
UPS/PDU/ATS/OOB collectors
```

- [ ] **Step 4: Record every service endpoint in NetBox**

Each service must have:

```text
owning VM or container host
VIP or concrete IP address
DNS name
port/protocol
HAProxy frontend name if applicable
healthcheck command
log destination
metrics destination
```

## Task 8: Documentation, Wiki, And EOD Discipline

Purpose: keep the operational state recoverable after each infrastructure change.

- [ ] **Step 1: Update docs after each major phase**

Update:

```text
docs/NETBOX-IPAM-DCIM-COMPLETION-PLAN.md
docs/PROXMOX-NETBOX-ROUTEROS-ACTION-PLAN.md
docs/CONTAINER-SERVICES-VALIDATION.md
docs/ROADMAP-AND-TODO.md
docs/CHANGELOG.md
```

- [ ] **Step 2: Sync wiki mirror**

```bash
cp docs/CHANGELOG.md docs/wiki/Changelog.md
cp docs/ROADMAP-AND-TODO.md docs/wiki/Roadmap-and-TODO.md
```

- [ ] **Step 3: Verify**

```bash
bash tests/shell/run-tests.sh
git diff --check
```

- [ ] **Step 4: Commit and push**

```bash
git status --short --branch
git add docs scripts tests gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
git commit -m "Advance NetBox-driven provisioning workflow"
git push origin HEAD:codex/add-container-services-profile
```

## Execution Priority

1. Export NetBox-driven provisioning inventory.
2. Reconcile DNS provider inventory with NetBox desired records.
3. Add generic Proxmox Stage4 service VM creation tooling.
4. Provision `svc-container-services-01` on Hasslehoff.
5. Apply `vm-container-services` profile and start nginx/HAProxy containers.
6. Add rsyslog collector, Elasticsearch/Kibana/APM, ntfy, observability, and remaining app service containers.

## Stop Conditions

- Do not enable DNS apply/delete gates until unmanaged provider records are labeled or imported.
- Do not delete or replace any Proxmox VM unless a snapshot exists and `PROXMOX_REPLACE=1` is explicit.
- Do not mutate CRS309/RouterOS configs as part of this plan.
- Do not proceed with service deployment if NetBox API, Hasslehoff SSH, or Proxmox API validation fails.
- Do not publish secrets, token values, or generated temporary token files.
