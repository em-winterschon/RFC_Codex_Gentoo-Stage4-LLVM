# FMT2 R630 Kolla-Ansible Podman Rocky 10 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the first FMT2 OpenStack pilot on the Dell R630 `pri` and `sec` hosts using Kolla-Ansible + Podman on Rocky Linux 10, while preserving `ter` as the storage and provisioning anchor.

**Architecture:** `pri` and `sec` use Rocky Linux 10 as the OpenStack substrate because Kolla-Ansible supports Rocky 10 hosts and Podman, while Gentoo remains the repo's preferred substrate for non-OpenStack hypervisor and infrastructure roles. A dedicated Rocky 10 deployer VM runs Kolla-Ansible from FMT2-local storage, drives `/etc/kolla` configuration, and applies changes only after firmware, SOL, network, and storage gates pass. `ter` is not wiped and remains the ZFS `dstore` anchor until replacement storage capacity is validated.

**Tech Stack:** Rocky Linux 10, Kolla-Ansible 2026.1 pinned deployment tooling, Podman, OpenStack 2026.1 containers with `kolla_base_distro: "rocky"`, Dell iDRAC/SOL, Arista DCS-7060CX-32S, X710 LACP front-end, ConnectX-4 RoCEv2 back-end, FreeIPA/SSSD, RFC1918 internal CA, Prometheus/VictoriaMetrics/Grafana, rsyslog, Check_MK.

---

## Upstream Support Anchors

- Kolla-Ansible support matrix: <https://docs.openstack.org/kolla-ansible/latest/user/support-matrix.html>
- Kolla-Ansible advanced configuration, including container engine selection: <https://docs.openstack.org/kolla-ansible/2026.1/admin/advanced-configuration.html>
- Kolla-Ansible quickstart and bootstrap/precheck/deploy/post-deploy flow: <https://docs.openstack.org/kolla-ansible/latest/user/quickstart.html>
- Kolla-Ansible production architecture guide: <https://docs.openstack.org/kolla-ansible/latest/admin/production-architecture-guide.html>
- Rocky Linux lifecycle reference: <https://wiki.rockylinux.org/rocky/version/>

## File Map

- Create: `tests/shell/test_fmt2_kolla_podman_rocky10_plan.sh`
- Modify: `tests/shell/run-tests.sh`
- Create: `docs/superpowers/plans/2026-05-20-fmt2-r630-kolla-podman-rocky10.md`
- Modify: `docs/FMT2-R630-HCI-STAGED-REBUILD.md`
- Modify: `docs/wiki/FMT2-R630-HCI-Staged-Rebuild.md`
- Future create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/fmt2-openstack-kolla/hosts.yml`
- Future create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/group_vars/fmt2_openstack_kolla.yml`
- Future create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/fmt2-kolla-rocky10-preflight.yml`
- Future create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/fmt2_kolla_rocky10_preflight/`
- Future create: `docs/workflows/fmt2-r630-kolla-podman-rocky10.json`
- Future create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/host-e2et-definitions/fmt2-r630-kolla-podman-rocky10.yml`

## Decision Constraints

- Do not use native Gentoo OpenStack services for the first FMT2 OpenStack pilot.
- Do not use Rocky 9 for the first Kolla deployment unless Rocky 10 Kolla prechecks fail for a documented upstream defect.
- Do not use EL10 package-native OpenStack RPMs as the pilot path.
- Do not wipe `ter`; it remains the FMT2 storage/provisioning anchor.
- Do not install the firmware-maintenance OS onto SAS hot-swap bays.
- SOL remains enabled on `pri`, `sec`, and `ter` before and after every firmware or OS maintenance gate.
- Kolla uses Podman, not Docker: `kolla_container_engine: podman`.
- Kolla images use Rocky base containers: `kolla_base_distro: "rocky"`.
- OpenStack-Ansible + LXC fallback remains the second-choice track if Kolla's Neutron, SR-IOV, or RDMA behavior blocks the pilot.

## Target Topology

| Host | Role | First-pass OS | Notes |
| --- | --- | --- | --- |
| `kvm-sfo200-pri-9922` | Kolla controller, network, compute | Rocky Linux 10 | First destructive rebuild candidate after firmware maintenance and ConnectX state are resolved. |
| `kvm-sfo200-sec-9923` | Kolla compute, optional second controller | Rocky Linux 10 | Positive-control RDMA host; rebuild only after `pri` can carry pilot services. |
| `kvm-sfo200-ter-9924` | Storage/provisioning anchor | Existing Rocky 8.9 until migration gate | Do not wipe; provides `dstore` staging, deployer VM storage, and rollback capacity. |
| `ops-fmt2-kolla-deployer-9928` | Kolla deployer VM | Rocky Linux 10 | Runs Kolla-Ansible tooling, stores `/etc/kolla` working tree, and drives Kolla commands. |

Proposed initial VIP reservations, pending NetBox and ping validation before use:

```text
kolla_internal_vip_address: 10.200.99.220
kolla_external_vip_address: 10.200.99.221
openstack public DNS: os-api-sfo200-9921.rfc1918.host
openstack internal DNS: os-int-sfo200-9920.rfc1918.host
```

If either VIP answers ping, appears in NetBox, appears in ARP tables, or is already assigned in DNS, stop before deployment and reserve a replacement in NetBox and DNS as a separate change.

## Network Contract

First-pass host interface mapping:

```text
eno1 + eno2 -> bond0 -> Kolla management/API interface
eno3 + eno4 -> bond1 -> Neutron external/provider interface, no host IP
enp130s0f0np0 -> independent RoCEv2 storage path A
enp130s0f1np1 -> independent RoCEv2 storage path B
```

First-pass Kolla globals contract:

```yaml
kolla_container_engine: podman
kolla_base_distro: "rocky"
openstack_release: "2026.1"
network_interface: "bond0"
api_interface: "bond0"
kolla_external_vip_interface: "bond0"
neutron_external_interface: "bond1"
enable_haproxy: "yes"
enable_openvswitch: "yes"
enable_neutron_provider_networks: "yes"
enable_cinder: "no"
enable_barbican: "yes"
enable_prometheus: "no"
enable_grafana: "no"
```

Prometheus and Grafana stay external to Kolla for the pilot because RFC1918 already has an observability pipeline. Cinder stays disabled for the first deploy so the API/control plane and Nova/Neutron path can be validated before storage service complexity enters the failure domain.

## Task 1: Preserve the Planning Contract

**Files:**
- Create: `tests/shell/test_fmt2_kolla_podman_rocky10_plan.sh`
- Modify: `tests/shell/run-tests.sh`
- Create: `docs/superpowers/plans/2026-05-20-fmt2-r630-kolla-podman-rocky10.md`
- Modify: `docs/FMT2-R630-HCI-STAGED-REBUILD.md`
- Modify: `docs/wiki/FMT2-R630-HCI-Staged-Rebuild.md`

- [ ] **Step 1: Run the failing contract test before adding the plan**

Run:

```bash
bash tests/shell/test_fmt2_kolla_podman_rocky10_plan.sh
```

Expected: FAIL because the plan file and doc anchors are not present.

- [ ] **Step 2: Add this plan and doc anchors**

Add the plan file and add a `Kolla-Ansible + Podman on Rocky Linux 10` section to both the canonical R630 rebuild doc and its wiki export.

- [ ] **Step 3: Wire the test into the shell suite**

Patch `tests/shell/run-tests.sh` so it includes:

```bash
bash "${SCRIPT_DIR}/test_fmt2_kolla_podman_rocky10_plan.sh"
```

Expected: the new test runs with the rest of the repo's static shell tests.

- [ ] **Step 4: Verify the planning contract passes**

Run:

```bash
bash tests/shell/test_fmt2_kolla_podman_rocky10_plan.sh
```

Expected:

```text
PASS: test_fmt2_kolla_podman_rocky10_plan.sh
```

- [ ] **Step 5: Commit the planning contract**

Run:

```bash
git add tests/shell/test_fmt2_kolla_podman_rocky10_plan.sh tests/shell/run-tests.sh docs/superpowers/plans/2026-05-20-fmt2-r630-kolla-podman-rocky10.md docs/FMT2-R630-HCI-STAGED-REBUILD.md docs/wiki/FMT2-R630-HCI-Staged-Rebuild.md
git commit -m "Plan FMT2 Kolla Podman Rocky 10 deployment"
```

Expected: commit succeeds without touching live host state.

## Task 2: Build the Rocky 10 Firmware-to-OpenStack Host Gate

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/fmt2-kolla-rocky10-preflight.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/fmt2_kolla_rocky10_preflight/defaults/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/fmt2_kolla_rocky10_preflight/tasks/main.yml`
- Create: `tests/shell/test_fmt2_kolla_rocky10_preflight_role.sh`

- [ ] **Step 1: Write the failing role test**

Expected assertions:

```bash
grep -q 'Rocky Linux 10' roles/fmt2_kolla_rocky10_preflight/defaults/main.yml
grep -q 'SOL remains enabled' roles/fmt2_kolla_rocky10_preflight/tasks/main.yml
grep -q 'ansible_distribution_major_version' roles/fmt2_kolla_rocky10_preflight/tasks/main.yml
grep -q '10' roles/fmt2_kolla_rocky10_preflight/tasks/main.yml
grep -q 'kolla_container_engine.*podman' roles/fmt2_kolla_rocky10_preflight/defaults/main.yml
grep -q 'kolla_base_distro.*rocky' roles/fmt2_kolla_rocky10_preflight/defaults/main.yml
```

Run:

```bash
bash tests/shell/test_fmt2_kolla_rocky10_preflight_role.sh
```

Expected: FAIL before the role exists.

- [ ] **Step 2: Implement the preflight defaults**

Create defaults:

```yaml
---
fmt2_kolla_target_os_name: Rocky Linux
fmt2_kolla_target_os_major: "10"
fmt2_kolla_container_engine: podman
fmt2_kolla_base_distro: rocky
fmt2_kolla_openstack_release: "2026.1"
fmt2_kolla_required_sol: true
fmt2_kolla_disallowed_storage_patterns:
  - HUSMM3240ASS
  - INTEL SSDPED1D480GA
fmt2_kolla_allowed_os_media_patterns:
  - SSDSCKKB240G8R
  - IDSDM
```

- [ ] **Step 3: Implement read-only host gates**

Role tasks must assert:

```yaml
- ansible_distribution == "Rocky"
- ansible_distribution_major_version | string == "10"
- virtualization extensions are exposed
- `/sys/class/net/eno1` through `/sys/class/net/eno4` exist
- `/sys/class/net/enp130s0f0np0` and `/sys/class/net/enp130s0f1np1` exist when RDMA admission is requested
- SOL remains enabled according to the repo's iDRAC/SOL inventory evidence
- SAS hot-swap media is not selected as an OS install target
```

Expected: `apply=false` mode only reads facts and emits explicit blockers.

- [ ] **Step 4: Verify the role test**

Run:

```bash
bash tests/shell/test_fmt2_kolla_rocky10_preflight_role.sh
```

Expected: PASS.

- [ ] **Step 5: Commit the preflight role**

Run:

```bash
git add gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/fmt2-kolla-rocky10-preflight.yml gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/fmt2_kolla_rocky10_preflight tests/shell/test_fmt2_kolla_rocky10_preflight_role.sh tests/shell/run-tests.sh
git commit -m "Add FMT2 Kolla Rocky 10 preflight role"
```

Expected: commit succeeds with no live mutation.

## Task 3: Create the Kolla Deployer VM on `ter`

**Files:**
- Create: `docs/workflows/fmt2-kolla-deployer-vm.json`
- Create: `tests/shell/test_fmt2_kolla_deployer_vm_workflow.sh`

- [ ] **Step 1: Write the workflow contract test**

Expected assertions:

```bash
grep -q 'ops-fmt2-kolla-deployer-9928' docs/workflows/fmt2-kolla-deployer-vm.json
grep -q 'Rocky Linux 10' docs/workflows/fmt2-kolla-deployer-vm.json
grep -q 'dstore/libvirt' docs/workflows/fmt2-kolla-deployer-vm.json
grep -q 'kolla-ansible' docs/workflows/fmt2-kolla-deployer-vm.json
grep -q 'podman' docs/workflows/fmt2-kolla-deployer-vm.json
```

Run:

```bash
bash tests/shell/test_fmt2_kolla_deployer_vm_workflow.sh
```

Expected: FAIL before the workflow exists.

- [ ] **Step 2: Create the workflow manifest**

Workflow variables:

```json
{
  "deployer_vm": "ops-fmt2-kolla-deployer-9928",
  "deployer_ip": "10.200.99.28",
  "host": "kvm-sfo200-ter-9924",
  "storage": "dstore/libvirt/images",
  "os": "Rocky Linux 10",
  "packages": ["python3", "python3-devel", "python3-venv", "gcc", "libffi-devel", "openssl-devel", "podman", "git"],
  "kolla": {
    "container_engine": "podman",
    "base_distro": "rocky",
    "openstack_release": "2026.1"
  }
}
```

- [ ] **Step 3: Provision the VM**

Run from M70 after the workflow is committed:

```bash
ssh kvm-sfo200-ter-9924 'sudo virsh pool-info dstore-images && sudo zfs list dstore/libvirt/images'
```

Expected: `dstore-images` is active and the ZFS dataset exists.

Create the VM through the repo's VM provisioning workflow and pin the VM disk under `/srv/libvirt/images`, not the OS RAID1 mirror.

- [ ] **Step 4: Install Kolla-Ansible into a venv**

Run on the deployer VM:

```bash
python3 -m venv /opt/kolla-ansible-2026.1
/opt/kolla-ansible-2026.1/bin/pip install --upgrade pip
/opt/kolla-ansible-2026.1/bin/pip install 'kolla-ansible==2026.1.*'
sudo mkdir -p /etc/kolla
sudo cp -r /opt/kolla-ansible-2026.1/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
```

Expected: `kolla-ansible --version` reports a 2026.1 build and `/etc/kolla` contains `globals.yml` and `passwords.yml`.

- [ ] **Step 5: Verify and commit the workflow**

Run:

```bash
bash tests/shell/test_fmt2_kolla_deployer_vm_workflow.sh
git add docs/workflows/fmt2-kolla-deployer-vm.json tests/shell/test_fmt2_kolla_deployer_vm_workflow.sh tests/shell/run-tests.sh
git commit -m "Define FMT2 Kolla deployer VM workflow"
```

Expected: workflow test passes and commit succeeds.

## Task 4: Generate `/etc/kolla` Configuration from Repo Data

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/templates/kolla/globals.yml.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/templates/kolla/multinode.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/render-fmt2-kolla-config.yml`
- Create: `tests/shell/test_fmt2_kolla_config_templates.sh`

- [ ] **Step 1: Write the failing template test**

Expected assertions:

```bash
grep -q 'kolla_container_engine: podman' templates/kolla/globals.yml.j2
grep -q 'kolla_base_distro: "rocky"' templates/kolla/globals.yml.j2
grep -q 'openstack_release: "2026.1"' templates/kolla/globals.yml.j2
grep -q 'network_interface: "bond0"' templates/kolla/globals.yml.j2
grep -q 'api_interface: "bond0"' templates/kolla/globals.yml.j2
grep -q 'kolla_external_vip_interface: "bond0"' templates/kolla/globals.yml.j2
grep -q 'neutron_external_interface: "bond1"' templates/kolla/globals.yml.j2
grep -q 'enable_cinder: "no"' templates/kolla/globals.yml.j2
grep -q 'kvm-sfo200-pri-9922' templates/kolla/multinode.j2
grep -q 'kvm-sfo200-sec-9923' templates/kolla/multinode.j2
```

Run:

```bash
bash tests/shell/test_fmt2_kolla_config_templates.sh
```

Expected: FAIL before templates exist.

- [ ] **Step 2: Create `globals.yml.j2`**

Template content:

```yaml
kolla_container_engine: podman
kolla_base_distro: "rocky"
openstack_release: "2026.1"
kolla_internal_vip_address: "10.200.99.220"
kolla_external_vip_address: "10.200.99.221"
network_interface: "bond0"
api_interface: "bond0"
kolla_external_vip_interface: "bond0"
neutron_external_interface: "bond1"
enable_haproxy: "yes"
enable_openvswitch: "yes"
enable_neutron_provider_networks: "yes"
enable_cinder: "no"
enable_barbican: "yes"
enable_prometheus: "no"
enable_grafana: "no"
```

- [ ] **Step 3: Create `multinode.j2`**

Inventory content:

```ini
[control]
kvm-sfo200-pri-9922

[network]
kvm-sfo200-pri-9922

[compute]
kvm-sfo200-pri-9922
kvm-sfo200-sec-9923

[monitoring]
kvm-sfo200-pri-9922

[deployment]
localhost ansible_connection=local
```

Expected: `sec` starts as compute-only until `pri` passes controller admission.

- [ ] **Step 4: Render config on the deployer**

Run:

```bash
ansible-playbook -i inventories/fmt2-openstack-kolla/hosts.yml playbooks/render-fmt2-kolla-config.yml -l ops-fmt2-kolla-deployer-9928
```

Expected: `/etc/kolla/globals.yml` and `/etc/kolla/multinode` are rendered on the deployer VM. `passwords.yml` is generated on the deployer from Kolla tooling and then encrypted into the private vault workflow, not committed as plaintext.

- [ ] **Step 5: Verify and commit templates**

Run:

```bash
bash tests/shell/test_fmt2_kolla_config_templates.sh
git add gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/templates/kolla gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/render-fmt2-kolla-config.yml tests/shell/test_fmt2_kolla_config_templates.sh tests/shell/run-tests.sh
git commit -m "Template FMT2 Kolla Podman configuration"
```

Expected: template test passes and commit succeeds.

## Task 5: Validate Rocky 10 Node Prep Before Kolla

**Files:**
- Create: `docs/workflows/fmt2-r630-rocky10-kolla-node-prep.json`
- Create: `tests/shell/test_fmt2_r630_rocky10_kolla_node_prep.sh`

- [ ] **Step 1: Write the node-prep workflow test**

Expected assertions:

```bash
grep -q 'Rocky Linux 10' docs/workflows/fmt2-r630-rocky10-kolla-node-prep.json
grep -q 'bond0' docs/workflows/fmt2-r630-rocky10-kolla-node-prep.json
grep -q 'bond1' docs/workflows/fmt2-r630-rocky10-kolla-node-prep.json
grep -q 'podman' docs/workflows/fmt2-r630-rocky10-kolla-node-prep.json
grep -q 'chrony' docs/workflows/fmt2-r630-rocky10-kolla-node-prep.json
grep -q 'sssd' docs/workflows/fmt2-r630-rocky10-kolla-node-prep.json
grep -q 'node_exporter' docs/workflows/fmt2-r630-rocky10-kolla-node-prep.json
```

Run:

```bash
bash tests/shell/test_fmt2_r630_rocky10_kolla_node_prep.sh
```

Expected: FAIL before the workflow exists.

- [ ] **Step 2: Define node prep**

Node prep contract:

```text
install Rocky Linux 10 on OS mirror only
preserve IDSDM EFI handoff
exclude SAS hot-swap bays from OS install
create bond0 on eno1+eno2 for management/API
create bond1 on eno3+eno4 for Neutron external/provider traffic with no host IP
leave ConnectX ports independent for RoCEv2 validation
install podman and Kolla host dependencies
enable chrony against RFC1918 time sources
enroll SSSD/FreeIPA if the FreeIPA path is reachable
install node exporter and Check_MK agent
ship rsyslog to the RFC1918 syslog VIP
trust RFC1918 internal CA
```

- [ ] **Step 3: Run non-destructive checks on `pri` and `sec`**

Run:

```bash
ansible-playbook -i inventories/fmt2-openstack-kolla/hosts.yml playbooks/fmt2-kolla-rocky10-preflight.yml -l kvm-sfo200-pri-9922,kvm-sfo200-sec-9923
```

Expected: hosts fail until they are Rocky Linux 10, but the failure explains the missing gate and makes no mutation.

- [ ] **Step 4: Verify and commit node prep workflow**

Run:

```bash
bash tests/shell/test_fmt2_r630_rocky10_kolla_node_prep.sh
git add docs/workflows/fmt2-r630-rocky10-kolla-node-prep.json tests/shell/test_fmt2_r630_rocky10_kolla_node_prep.sh tests/shell/run-tests.sh
git commit -m "Define FMT2 Rocky 10 Kolla node prep workflow"
```

Expected: workflow test passes and commit succeeds.

## Task 6: Execute Kolla Prechecks and Deploy

**Files:**
- Create: `docs/workflows/fmt2-kolla-deploy-sequence.json`
- Create: `tests/shell/test_fmt2_kolla_deploy_sequence.sh`

- [ ] **Step 1: Write the deploy-sequence workflow test**

Expected assertions:

```bash
grep -q 'kolla-ansible bootstrap-servers' docs/workflows/fmt2-kolla-deploy-sequence.json
grep -q 'kolla-ansible prechecks' docs/workflows/fmt2-kolla-deploy-sequence.json
grep -q 'kolla-ansible validate-config' docs/workflows/fmt2-kolla-deploy-sequence.json
grep -q 'kolla-ansible deploy' docs/workflows/fmt2-kolla-deploy-sequence.json
grep -q 'kolla-ansible post-deploy' docs/workflows/fmt2-kolla-deploy-sequence.json
grep -q 'openstack endpoint list' docs/workflows/fmt2-kolla-deploy-sequence.json
```

Run:

```bash
bash tests/shell/test_fmt2_kolla_deploy_sequence.sh
```

Expected: FAIL before the workflow exists.

- [ ] **Step 2: Define the deploy command sequence**

Run on `ops-fmt2-kolla-deployer-9928`:

```bash
source /opt/kolla-ansible-2026.1/bin/activate
cd /etc/kolla
kolla-genpwd
kolla-ansible -i /etc/kolla/multinode bootstrap-servers
kolla-ansible -i /etc/kolla/multinode prechecks
kolla-ansible -i /etc/kolla/multinode validate-config
kolla-ansible -i /etc/kolla/multinode deploy
kolla-ansible -i /etc/kolla/multinode post-deploy
```

Expected: bootstrap and prechecks pass before deploy. If prechecks fail, stop and capture the exact failed check in the issue and E2ET evidence instead of bypassing it.

- [ ] **Step 3: Run API smoke**

Run on the deployer:

```bash
source /etc/kolla/admin-openrc.sh
openstack endpoint list
openstack service list
openstack hypervisor list
openstack network agent list
```

Expected: Keystone, Nova, Neutron, Glance, Placement, and Horizon endpoints exist; both `pri` and `sec` appear as compute capacity only after `sec` is intentionally added.

- [ ] **Step 4: Run instance smoke**

Run on the deployer after uploading a tiny test image:

```bash
openstack flavor create --ram 512 --disk 1 --vcpus 1 rfc1918.smoke.tiny
openstack network create rfc1918-smoke-net
openstack subnet create --network rfc1918-smoke-net --subnet-range 192.0.2.0/24 rfc1918-smoke-subnet
openstack server create --flavor rfc1918.smoke.tiny --image cirros --network rfc1918-smoke-net rfc1918-smoke-001
openstack server show rfc1918-smoke-001
```

Expected: server reaches `ACTIVE` or the failure path is captured with Nova, Neutron, libvirt, and Podman logs.

- [ ] **Step 5: Verify and commit deploy sequence**

Run:

```bash
bash tests/shell/test_fmt2_kolla_deploy_sequence.sh
git add docs/workflows/fmt2-kolla-deploy-sequence.json tests/shell/test_fmt2_kolla_deploy_sequence.sh tests/shell/run-tests.sh
git commit -m "Define FMT2 Kolla deploy sequence"
```

Expected: workflow test passes and commit succeeds.

## Task 7: Promote Storage and RDMA After API Baseline

**Files:**
- Create: `docs/workflows/fmt2-kolla-storage-rdma-promotion.json`
- Create: `tests/shell/test_fmt2_kolla_storage_rdma_promotion.sh`

- [ ] **Step 1: Write the promotion workflow test**

Expected assertions:

```bash
grep -q 'Cinder remains disabled before promotion' docs/workflows/fmt2-kolla-storage-rdma-promotion.json
grep -q 'NFS backend smoke' docs/workflows/fmt2-kolla-storage-rdma-promotion.json
grep -q 'NVMe-oF promotion gate' docs/workflows/fmt2-kolla-storage-rdma-promotion.json
grep -q 'NFS-RDMA promotion gate' docs/workflows/fmt2-kolla-storage-rdma-promotion.json
grep -q 'one-path-failure' docs/workflows/fmt2-kolla-storage-rdma-promotion.json
grep -q 'do not use ConnectX LACP before pairwise RDMA evidence' docs/workflows/fmt2-kolla-storage-rdma-promotion.json
```

Run:

```bash
bash tests/shell/test_fmt2_kolla_storage_rdma_promotion.sh
```

Expected: FAIL before the workflow exists.

- [ ] **Step 2: Define storage promotion order**

Promotion order:

```text
1. API/control plane baseline with Cinder disabled.
2. Glance image import/export smoke.
3. Nova ephemeral instance smoke.
4. NFSv3/NFSv4 backend smoke from NASA or ter.
5. Cinder NFS backend pilot.
6. Pairwise RoCEv2 RDMA smoke between sec and ter, then pri after ConnectX repair.
7. NVMe-oF or iSER backend pilot.
8. NFS-RDMA backend pilot.
9. one-path-failure and reboot conformance.
```

- [ ] **Step 3: Define RDMA no-LACP gate**

Required policy text:

```text
do not use ConnectX LACP before pairwise RDMA evidence
```

Expected: the initial ConnectX design remains independent 50GbE links with protocol-layer multipath until RDMA failure testing passes.

- [ ] **Step 4: Verify and commit storage/RDMA promotion workflow**

Run:

```bash
bash tests/shell/test_fmt2_kolla_storage_rdma_promotion.sh
git add docs/workflows/fmt2-kolla-storage-rdma-promotion.json tests/shell/test_fmt2_kolla_storage_rdma_promotion.sh tests/shell/run-tests.sh
git commit -m "Define FMT2 Kolla storage RDMA promotion gates"
```

Expected: workflow test passes and commit succeeds.

## Task 8: Publish E2ET Admission Criteria

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/host-e2et-definitions/fmt2-r630-kolla-podman-rocky10.yml`
- Create: `tests/shell/test_fmt2_kolla_podman_rocky10_e2et.sh`

- [ ] **Step 1: Write the E2ET contract test**

Expected assertions:

```bash
grep -q 'Rocky Linux 10' host-e2et-definitions/fmt2-r630-kolla-podman-rocky10.yml
grep -q 'Kolla-Ansible' host-e2et-definitions/fmt2-r630-kolla-podman-rocky10.yml
grep -q 'Podman' host-e2et-definitions/fmt2-r630-kolla-podman-rocky10.yml
grep -q 'kolla-ansible prechecks' host-e2et-definitions/fmt2-r630-kolla-podman-rocky10.yml
grep -q 'openstack hypervisor list' host-e2et-definitions/fmt2-r630-kolla-podman-rocky10.yml
grep -q 'SOL remains enabled' host-e2et-definitions/fmt2-r630-kolla-podman-rocky10.yml
grep -q 'Cinder disabled for first-pass baseline' host-e2et-definitions/fmt2-r630-kolla-podman-rocky10.yml
```

Run:

```bash
bash tests/shell/test_fmt2_kolla_podman_rocky10_e2et.sh
```

Expected: FAIL before the E2ET manifest exists.

- [ ] **Step 2: Create admission manifest**

Admission checks:

```yaml
checks:
  - Rocky Linux 10 installed on approved OS mirror media
  - SOL remains enabled
  - Podman container engine active
  - Kolla-Ansible 2026.1 deployer available
  - kolla-ansible bootstrap-servers passed
  - kolla-ansible prechecks passed
  - kolla-ansible validate-config passed
  - kolla-ansible deploy passed
  - kolla-ansible post-deploy passed
  - openstack endpoint list passed
  - openstack hypervisor list passed
  - OpenStack smoke instance reached ACTIVE
  - Cinder disabled for first-pass baseline
  - rsyslog, node exporter, Check_MK, NTP, CA trust, and AAA validated
```

- [ ] **Step 3: Verify and commit E2ET**

Run:

```bash
bash tests/shell/test_fmt2_kolla_podman_rocky10_e2et.sh
git add gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/host-e2et-definitions/fmt2-r630-kolla-podman-rocky10.yml tests/shell/test_fmt2_kolla_podman_rocky10_e2et.sh tests/shell/run-tests.sh
git commit -m "Define FMT2 Kolla Rocky 10 E2ET admission"
```

Expected: E2ET static contract passes and live evidence remains `blocked` until the actual Kolla deployment passes.

## Execution Order

1. Complete Task 1 now so the selected deployment direction is committed.
2. Finish `pri` Dell firmware maintenance on the disposable Rocky image.
3. Repair or replace the missing `pri` ConnectX path if the host will participate in RDMA admission.
4. Provision `ops-fmt2-kolla-deployer-9928` on `ter` storage.
5. Rebuild `pri` as Rocky Linux 10 on approved OS media.
6. Run Kolla preflight against `pri`.
7. Deploy single-node Kolla on `pri`.
8. Rebuild `sec` as Rocky Linux 10.
9. Add `sec` as compute-only.
10. Promote storage and RDMA features only after API, Nova, Neutron, and observability baselines pass.

## Rollback Policy

- If `pri` install fails before Kolla, use iDRAC SOL and virtual media/PXE to reinstall Rocky Linux 10 or return to the disposable firmware-maintenance boot.
- If Kolla prechecks fail, do not deploy; capture `/etc/kolla/globals.yml`, `multinode`, Kolla logs, host facts, and network state.
- If Kolla deploy fails, do not add `sec`; run `kolla-ansible destroy --yes-i-really-really-mean-it` only after saving logs and after a separate destructive cleanup approval.
- If API baseline passes but storage/RDMA fails, keep Cinder disabled and keep RDMA out of OpenStack scheduling until the storage workflow passes.
