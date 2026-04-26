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

- gateway: `10.9.8.1/24`
- lab network: `10.9.8.0/24`
- DHCP pool: `10.9.8.10-10.9.8.99`
- bootstrap URL: `http://10.9.8.108:8080/bootstrap.ipxe`
- management CIDR: `10.9.8.0/24`
- NTP client: enabled
- NTP server broadcast/multicast: enabled
- SNMP v2c + v3: enabled
- SSH: enabled and restricted
- Winbox: disabled
- HTTP: disabled
- HTTPS: enabled

## Future HA

The role currently records a single-node `standalone` posture, but the intended
future state is dual RouterOS systems at the remote datacenter edge.
