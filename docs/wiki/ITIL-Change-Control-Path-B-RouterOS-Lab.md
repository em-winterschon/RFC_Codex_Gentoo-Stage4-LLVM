# ITIL Change Control: Path B RouterOS Lab Bring-Up

This page mirrors the versioned source document:

- `docs/CHANGE-CONTROL-PATH-B-ROUTEROS-LAB.md`

It also depends on:

- `docs/workflows/stage4-routeros-pathb-deployment.json`
- `docs/wiki/RouterOS-Path-B.md`

## Summary

Purpose:

- stand up a safe, isolated Path B iPXE lab on `10.9.8.0/24`
- keep Path A LiveISO-driven imaging intact as fallback
- validate the full boot chain before any production or physical-host adoption

Scope:

1. build Path B provisioning artifacts
2. publish Path B iPXE assets
3. bring up isolated host-side lab networking
4. create a RouterOS CHR VM in QEMU
5. configure DHCP/iPXE handoff on the isolated segment
6. boot one client VM into the Gentoo provisioning flow

## Command Sequence Reference

### 1. Build Path B provisioning artifacts

```bash
cd /root/RFC_Codex_Gentoo-Stage4-LLVM/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
bash scripts/build-path-b-netboot-artifacts.sh
```

### 2. Publish Path B assets

```bash
cd /root/RFC_Codex_Gentoo-Stage4-LLVM
bash tests/shell/test_netboot_assets.sh

cd /root/RFC_Codex_Gentoo-Stage4-LLVM/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook -i inventories/examples/hosts.yml playbooks/netboot-path-b.yml -l netboot_control_local
```

### 3. Prepare isolated lab network

```bash
ip addr add 10.9.8.108/24 dev lo
ip link add br-pathb type bridge
ip addr add 10.9.8.108/24 dev br-pathb
ip link set br-pathb up
```

### 4. Launch RouterOS CHR VM

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

### 5. Validate client iPXE boot

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

### 6. Hand off to Stage4 installer

```bash
cd /root/RFC_Codex_Gentoo-Stage4-LLVM/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
bash scripts/run-install-sequence.sh \
  --inventory inventories/examples/hosts.yml \
  --limit target_system_remote \
  --sequence storage-foundation \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/path-b-client.storage.jsonl
```

## Validation Gates

- artifact build completes
- asset render completes
- host lab address is reachable
- RouterOS CHR VM boots
- client reaches iPXE
- iPXE fetches Path B assets
- provisioning environment reaches installer handoff
- Path A remains unaffected

## Rollback

```bash
pkill -f qemu-system-x86_64 || true
ip addr del 10.9.8.108/24 dev br-pathb || true
ip link set br-pathb down || true
ip link del br-pathb type bridge || true
ip addr del 10.9.8.108/24 dev lo || true
```

## Status

This document is planning and execution guidance only. The lab build itself has
not yet been executed under this change record.
