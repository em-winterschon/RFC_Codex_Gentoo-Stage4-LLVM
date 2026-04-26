# ITIL Change Control: Path B RouterOS Lab Bring-Up

## Document Control

- Change title: Path B iPXE lab on isolated `10.9.8.0/24` using a RouterOS CHR VM
- Change type: Standard change candidate after first successful validation
- Current state: Planned, not yet executed
- Related PRs:
  - `#17` Path B iPXE netboot workflow
  - `#16` default LLVM/Clang Portage profile and linting
- Related workflow manifests:
  - `docs/workflows/stage4-netboot-path-b.json`
  - `docs/workflows/stage4-routeros-lab-bringup.json`
  - `docs/workflows/stage4-routeros-pathb-deployment.json`

## 1. Purpose

Bring up a safe, isolated Path B netboot lab that allows:

- testing iPXE fleet imaging without touching production switching or routing
- booting bare-metal-like guests and future physical hosts into a Gentoo
  provisioning environment
- keeping the existing Path A LiveISO workflow available for hosts that cannot
  reach the iPXE network

The lab network will use:

- subnet: `10.9.8.0/24`
- host control IP: `10.9.8.108/24`
- RouterOS CHR VM as the lab gateway/router
- Gentoo host services for Path B boot asset publication

## 2. Scope

This change covers:

1. preparing the isolated host-side network segment
2. creating a RouterOS CHR VM in QEMU
3. exposing Path B iPXE assets on the host
4. configuring DHCP/iPXE handoff on the isolated segment
5. boot-testing one VM client into the Gentoo provisioning flow

This change does not yet cover:

- production router changes
- production DHCP or PXE infrastructure
- physical host migration into the Path B network
- ntfy server deployment

## 3. Target Architecture

### Path A

- boot existing Gentoo LiveISO
- run the staged Ansible installer directly
- keep as fallback for disconnected or exception hosts

### Path B

- client firmware reaches PXE or UEFI HTTP
- chainload or directly load iPXE
- iPXE fetches kernel/initramfs/rootfs over HTTP/HTTPS
- provisioning environment runs the same Stage4 installer workflow

### Lab topology

```text
Gentoo host
├── host control address: 10.9.8.108/24
├── HTTP boot asset publish root: /var/lib/netboot/path-b
├── Path B asset publication playbook
├── optional DHCP/TFTP helper process on host if needed
└── QEMU VMs
    ├── RouterOS CHR VM
    │   └── gateway / DHCP domain control for 10.9.8.0/24
    └── client VM(s)
        └── PXE/iPXE boot validation target(s)
```

## 4. Risk Assessment

### Primary risks

- accidental disruption of host networking on a LiveISO control node
- overlap between alias-mode validation paths and the new isolated subnet
- DHCP leakage if the isolated segment is bridged incorrectly
- boot loop or misrouting caused by incorrect iPXE host mappings

### Risk controls

- use a dedicated isolated `10.9.8.0/24` segment
- prefer host-side alias and isolated bridge/tap work before any production
  L2 exposure
- keep RouterOS VM and test clients confined to the lab network
- do not repurpose the existing Path A alias-mode workflow during initial Path B
  bring-up

## 5. Preconditions

Before implementation:

1. `#17` is available for reference and its asset-publishing workflow is known.
2. Host QEMU validation remains working.
3. No production DHCP listener is attached to the isolated lab segment.
4. A RouterOS CHR image is available locally.
5. Operator understands the rollback steps below.

## 6. Implementation Plan

### Stage 1: Confirm repo and publish Path B assets

Purpose:
- ensure the current repo can render the Path B asset tree before any network work

Commands:

```bash
cd /root/RFC_Codex_Gentoo-Stage4-LLVM
bash tests/shell/test_netboot_assets.sh

cd /root/RFC_Codex_Gentoo-Stage4-LLVM/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook -i inventories/examples/hosts.yml playbooks/netboot-path-b.yml -l netboot_control_local
```

Expected result:

- `/var/lib/netboot/path-b/bootstrap.ipxe`
- `/var/lib/netboot/path-b/menu.ipxe`
- `/var/lib/netboot/path-b/roles/*.ipxe`
- `/var/lib/netboot/path-b/hosts/*.ipxe`
- `/var/lib/netboot/path-b/manifests/path-b-netboot.json`

### Stage 2: Prepare isolated host-side lab network

Purpose:
- create the local network endpoint used by the host to reach lab VMs and serve
  Path B assets

Planned host configuration:

- host address: `10.9.8.108/24`
- isolated bridge or equivalent host-side network anchor for the lab

Initial command sequence:

```bash
ip addr add 10.9.8.108/24 dev lo
ip link add br-pathb type bridge
ip addr add 10.9.8.108/24 dev br-pathb
ip link set br-pathb up
```

Operational note:

- if `lo` aliasing and bridge use conflict in practice, keep only the bridge
  address and retire the loopback alias
- final implementation should converge on one authoritative lab interface

### Stage 3: Build Path B provisioning artifacts

Purpose:
- build the Gentoo provisioning kernel, initramfs, and SquashFS root that Path
  B iPXE clients will boot

Command sequence:

```bash
cd /root/RFC_Codex_Gentoo-Stage4-LLVM/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
bash scripts/build-path-b-netboot-artifacts.sh
```

Expected artifact paths:

- `/opt/gentoo-netboot/path-b/artifacts/gentoo-installer/vmlinuz`
- `/opt/gentoo-netboot/path-b/artifacts/gentoo-installer/initramfs.img`
- `/opt/gentoo-netboot/path-b/artifacts/gentoo-installer/rootfs.squashfs`
- `/opt/gentoo-netboot/path-b/artifacts/gentoo-rescue/vmlinuz`
- `/opt/gentoo-netboot/path-b/artifacts/gentoo-rescue/initramfs.img`
- `/opt/gentoo-netboot/path-b/artifacts/gentoo-rescue/rootfs.squashfs`

Success criteria for this stage:

- stage3 bootstrap completes without package or dracut failure
- installer and rescue artifacts both exist under `/opt/gentoo-netboot/path-b`
- artifact tree is ready for HTTP publication

### Stage 4: Create the RouterOS CHR VM

Purpose:
- provide a controlled lab gateway/router and DHCP domain manager inside the
  isolated segment

Planned QEMU assets:

- RouterOS CHR disk image
- dedicated QEMU launcher script in `gentoo-virt-qemu/`

Interim command sequence pattern:

```bash
qemu-img create -f qcow2 /opt/routeros/routeros-lab.qcow2 2G

qemu-system-x86_64 \
  -enable-kvm \
  -machine q35,accel=kvm \
  -cpu host \
  -m 2048 \
  -smp 2 \
  -drive if=virtio,file=/opt/routeros/routeros-lab.qcow2,format=qcow2 \
  -nic bridge,br=br-pathb,model=virtio-net-pci \
  -serial mon:stdio
```

Implementation target:

- replace the raw command with a repo-managed launcher script

### Stage 5: Configure lab DHCP and iPXE handoff

Purpose:
- make PXE clients on `10.9.8.0/24` chain into the Path B asset tree

Preferred control split:

- RouterOS VM:
  - L3 gateway for `10.9.8.0/24`
  - DHCP scope control
- Gentoo host:
  - HTTP/HTTPS publication of Path B assets
  - optional TFTP or proxyDHCP helper if RouterOS chainloading proves awkward

Planned DHCP/iPXE policy:

- BIOS clients: boot to `undionly.kpxe`
- UEFI clients: boot to `ipxe.efi`
- after iPXE loads, use HTTP/HTTPS for all further assets

Planned operator steps:

1. define DHCP options for next-server / bootfile
2. validate that the client reaches `bootstrap.ipxe`
3. validate that `bootstrap.ipxe` resolves into either `hosts/*.ipxe` or
   `menu.ipxe`

### Stage 5a: Render RouterOS configuration as code

Purpose:
- ensure the RouterOS CHR configuration is repo-driven and repeatable on
  alternate hosts or alternate isolated subnets

Commands:

```bash
cd /root/RFC_Codex_Gentoo-Stage4-LLVM/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook -i inventories/examples/hosts.yml playbooks/routeros-path-b.yml -l routeros_pathb_primary
```

Optional live apply:

```bash
cd /root/RFC_Codex_Gentoo-Stage4-LLVM/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook \
  -i inventories/examples/hosts.yml \
  playbooks/routeros-path-b.yml \
  -l routeros_pathb_primary \
  -e routeros_pathb_apply=true
```

Expected render artifacts:

- `/tmp/routeros-pathb/routeros_pathb_primary-pathb.rsc`
- `/tmp/routeros-pathb/routeros_pathb_primary-pathb.json`

Current enforced or documented policy:

- UEFI only
- CHR lab architecture `x86`
- HTTPS on, plain HTTP off
- SSH restricted and hardened
- NTP client and NTP broadcast/multicast server
- SNMP v2c and SNMPv3 read/write enabled
- remote syslog client enabled
- native syslog receive/server behavior deferred to a future collector/container
- `container` support tracked as valid on `x86`
- `zerotier` tracked as unsupported on current CHR/x86 labs
- future HA explicitly recorded but not yet implemented

### Stage 6: Create a client validation VM

Purpose:
- prove the full boot chain before any physical host is pointed at the lab

Planned boot profile:

- UEFI client first
- then BIOS client if needed

Command pattern:

```bash
qemu-system-x86_64 \
  -enable-kvm \
  -machine q35,accel=kvm \
  -cpu host \
  -m 4096 \
  -smp 2 \
  -boot order=n \
  -nic bridge,br=br-pathb,model=virtio-net-pci \
  -serial mon:stdio
```

Success criteria for this stage:

- client acquires DHCP lease on `10.9.8.0/24`
- client reaches iPXE
- iPXE fetches Path B assets over HTTP/HTTPS
- provisioning kernel/initramfs begin boot

### Stage 7: Validate provisioning-to-installer handoff

Purpose:
- confirm that Path B reaches the same installer execution model as Path A

Validation targets:

- network comes up inside the provisioning environment
- the provisioning environment can reach the repo/bootstrap data
- operator can run staged installer sequences against the booted target

Command pattern after the provisioning environment is reachable:

```bash
cd /root/RFC_Codex_Gentoo-Stage4-LLVM/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
bash scripts/run-install-sequence.sh \
  --inventory inventories/examples/hosts.yml \
  --limit target_system_remote \
  --sequence storage-foundation \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/path-b-client.storage.jsonl
```

## 7. Validation Plan

### Technical validation

1. Path B provisioning artifact build succeeds.
2. Path B asset render succeeds.
3. Host lab interface is reachable at `10.9.8.108`.
4. RouterOS CHR VM boots and is reachable from the host.
5. Client VM receives DHCP and reaches iPXE.
6. iPXE fetches `bootstrap.ipxe` and the selected role script.
7. Provisioning kernel/initramfs boot begins.
8. Installer control-flow logging works once the provisioning environment is up.

### Documentary validation

The following must remain updated:

- `docs/workflows/stage4-netboot-path-b.json`
- `docs/wiki/Workflows.md`
- `docs/wiki/Configurations-and-Examples.md`
- `docs/wiki/Repository-Layout.md`

## 8. Backout / Rollback Plan

If the lab setup causes instability or does not validate:

1. stop all lab VMs
2. remove the host-side lab bridge/address
3. stop any temporary DHCP/TFTP/HTTP helper processes
4. keep Path A as the active imaging path

Rollback command pattern:

```bash
pkill -f qemu-system-x86_64 || true
ip addr del 10.9.8.108/24 dev br-pathb || true
ip link set br-pathb down || true
ip link del br-pathb type bridge || true
ip addr del 10.9.8.108/24 dev lo || true
```

## 9. Success Criteria

The change is considered successful when:

- Path B assets are rendered and published
- RouterOS CHR VM is operational on the isolated subnet
- at least one test client boots into iPXE and fetches Path B assets
- provisioning reaches the Gentoo installer handoff point
- Path A remains unaffected and available

## 10. Next Automation Targets

After the first successful manual lab bring-up:

1. add a repo-managed RouterOS CHR launcher
2. add repo-managed host bridge/tap bring-up helpers
3. add DHCP/iPXE helper automation for the isolated subnet
4. add a machine-readable client boot validation manifest
5. promote the change into a repeatable standard-change workflow
