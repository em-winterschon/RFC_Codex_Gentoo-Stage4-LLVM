# RouterOS Path B Role

## Purpose

This document describes the RouterOS CHR role used to operationalize the Path B
iPXE lab network on the isolated `10.9.8.0/24` segment.

The role is the config-as-code layer for:

- Path B DHCP handoff to `bootstrap.ipxe`
- RouterOS management-plane hardening
- NTP client and server behavior
- SSH / HTTPS / serial-console expectations
- SNMP v2c and v3 posture
- package and architecture caveats
- future HA notation

## Operator Entry Point

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

Rendered local artifacts:

- `/tmp/routeros-pathb/routeros_pathb_primary-pathb.rsc`
- `/tmp/routeros-pathb/routeros_pathb_primary-pathb.json`

## Current Defaults

- boot mode: `uefi-http-ipxe`
- lab gateway / LAN: `10.9.8.1/24` on `pathb-lan`
- lab network: `10.9.8.0/24`
- upstream / WAN: `192.168.1.222/24` on `pathb-wan`
- upstream gateway: `192.168.1.254`
- upstream DNS: `9.9.9.9`, `8.8.8.8`
- DHCP pool: `10.9.8.10-10.9.8.99`
- iPXE bootstrap URL: `http://10.9.8.108:8080/bootstrap.ipxe`
- DHCP client DNS: `10.9.8.1`
- management CIDR: `10.9.8.0/24`
- RouterOS architecture for CHR lab: `x86`

## Hypervisor Launch

The current validated launch path uses a fresh CHR qcow2 disk, one LAN tap on
`br-pathb`, and one WAN tap on a dedicated L2 bridge backed by `eno2`.

```bash
cd /root/RFC_Codex_Gentoo-Stage4-LLVM
FRESH_DISK=true \
WAN_PHYS_IF=eno2 \
bash gentoo-virt-qemu/qemu-launch-routeros-pathb-vm.sh
```

The launcher does not assign a host IP to `br-ros-wan`. It bridges `eno2` into
the RouterOS WAN L2 so RouterOS owns `192.168.1.222/24` and routes via
`192.168.1.254`.

## Security and Service Posture

The role currently enforces or documents these defaults:

- UEFI-only boot policy
- telnet, ftp, api, and api-ssl disabled
- SSH enabled and CIDR-restricted
- `strong-crypto=yes`
- SSH forwarding disabled
- SSH password authentication is tracked as policy; first-boot CHR rebuilds use
  a temporary local admin password until key-only management is installed
- Winbox disabled
- plain HTTP disabled
- HTTPS enabled with a generated self-signed certificate
- DNS configured for the lab segment with remote requests enabled
- SNMP public community removed
- SNMP v2c read/write restricted to configured management ranges
- SNMP v3 `authPriv` style configuration rendered with read/write enabled
- remote syslog client configured
- LAN-to-WAN masquerade enabled for `10.9.8.0/24`
- baseline firewall drops direct input from `pathb-wan`

## Important Platform Constraints

### CHR / x86 / amd64

This lab uses RouterOS CHR on the MikroTik `x86` architecture. That matters for
two reasons:

1. `container` is supported on `x86`.
2. `zerotier` is documented by MikroTik only for `ARM` and `ARM64`, not `x86`.

The role therefore records:

- `container` as supported on the current CHR architecture
- `zerotier` as a desired future package, but unsupported on the current CHR
  lab host

### HTTP Redirect

RouterOS does not expose a simple native “redirect all WebFig HTTP to HTTPS”
toggle in the way a normal web server does. The current secure default is:

- HTTP disabled
- HTTPS enabled

If a real redirect is needed later, it should be implemented and validated as a
separate firewall/proxy/container strategy.

### Syslog Server

RouterOS acts as a remote log client here. Native BSD-syslog remote logging is
UDP-oriented. Native RouterOS does not provide the full local syslog server role
needed for both UDP and TCP ingestion on the standard ports.

Current policy:

- RouterOS sends remote logs outward
- syslog receive/service behavior is expected from:
  - an external collector, or
  - a future RouterOS-hosted container adjunct once container mode is enabled

### Serial Console

RouterOS CHR/x86 serial access is hypervisor-provided. The role documents the
expected serial posture instead of attempting to fabricate it inside RouterOS:

- hypervisor transport: QEMU telnet-backed serial
- RouterOS x86 default serial speed: `9600`

This is intended to emulate the access pattern of physical RouterOS devices as
closely as practical in the VM lab.

## NTP Policy

The role configures:

- NTP client enabled
- client mode `unicast`
- configured upstream server list
- NTP server enabled
- broadcast enabled
- multicast enabled
- explicit broadcast addresses

This meets the current lab requirement for RouterOS to act as both:

- an NTP client of upstream time
- a network time service for the Path B segment

## SNMP Policy

The role enables both:

- SNMP v2c
- SNMP v3

With current defaults:

- v2c read/write limited to configured addresses
- public community removed
- v3 uses authentication + privacy settings
- v3 write access enabled

This is intentionally aggressive for lab automation because the requirement was
explicitly for read+write capability. For broader deployment, the first thing to
tighten would be v2c write access.

## Package Handling

RouterOS extra packages are not installed magically by the role. The role can:

- render the intended package posture
- upload package files if `routeros_pathb_package_files` is populated
- import the RouterOS `.rsc`

But package activation may still require:

- `.npk` files appropriate to the RouterOS version and architecture
- reboot / `apply-changes`
- physical-access-style enablement for container mode

## Future HA

The role defaults to:

- `routeros_pathb_ha_mode: standalone`

But also records the intended future state:

- dual RouterOS systems
- remote-datacenter HA
- active/passive or equivalent edge failover

That is not implemented yet, but it is tracked in both the rendered manifest
and the wiki/change-control docs.
