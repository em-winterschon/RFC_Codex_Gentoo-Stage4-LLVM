# RouterOS Path B Role

This page mirrors the versioned source in `docs/ROUTEROS-PATH-B.md`.

## Purpose

The RouterOS CHR role operationalizes the Path B iPXE lab network on the
isolated `10.9.8.0/24` segment. It is the config-as-code layer for:

- DHCP handoff to `bootstrap.ipxe`
- management-plane hardening
- NTP client/server behavior
- SSH / HTTPS / serial-console expectations
- SNMP posture
- package and architecture caveats
- WAN egress and NAT for the Path B lab
- future HA notation

## Commands

Render only:

```bash
cd /root/RFC_Codex_Gentoo-Stage4-LLVM/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook -i inventories/examples/hosts.yml playbooks/routeros-path-b.yml -l routeros_pathb_primary
```

Render and apply:

```bash
cd /root/RFC_Codex_Gentoo-Stage4-LLVM/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook \
  -i inventories/examples/hosts.yml \
  playbooks/routeros-path-b.yml \
  -l routeros_pathb_primary \
  -e routeros_pathb_apply=true
```

## Constraints That Matter

- UEFI only
- CHR lab architecture is `x86`
- `container` is supportable on `x86`
- `zerotier` is not documented by MikroTik for `x86`; treat it as unsupported
  on CHR/amd64
- plain HTTP is disabled; HTTPS is enabled with a self-signed certificate
- native RouterOS remote syslog in BSD syslog format is UDP-oriented
- native RouterOS does not satisfy the full local UDP+TCP syslog-server role
- CHR serial access is hypervisor-backed; RouterOS x86 default serial speed is
  `9600`

## Operational Defaults

- LAN gateway: `10.9.8.1/24` on `pathb-lan`
- lab network: `10.9.8.0/24`
- WAN: `192.168.1.222/24` on `pathb-wan`
- upstream gateway: `192.168.1.254`
- upstream DNS: `9.9.9.9`, `8.8.8.8`
- DHCP pool: `10.9.8.10-10.9.8.99`
- DHCP client DNS: `10.9.8.1`
- bootstrap URL: `http://10.9.8.108:8080/bootstrap.ipxe`
- management CIDR: `10.9.8.0/24`
- NTP client: enabled
- NTP server broadcast/multicast: enabled
- SNMP v2c + v3: enabled
- SSH: enabled and restricted
- Winbox: disabled
- HTTP: disabled
- HTTPS: enabled
- NAT: masquerade `10.9.8.0/24` out `pathb-wan`
- WAN firewall: drop direct input from `pathb-wan`

## Hypervisor Launch

```bash
cd /root/RFC_Codex_Gentoo-Stage4-LLVM
FRESH_DISK=true WAN_PHYS_IF=eno2 bash gentoo-virt-qemu/qemu-launch-routeros-pathb-vm.sh
```

The launcher creates or reuses `br-ros-wan` without assigning a host IP, bridges
`eno2` and `tap-ros-wan` into it, and exposes serial on `127.0.0.1:5001`.

## Future HA

The role currently records a single-node `standalone` posture, but the intended
future state is dual RouterOS systems at the remote datacenter edge.
