# Network Fabric Normalization Design

## Goal

Normalize the local management, virtualization, routing, and service-hosting
fabric so CSS326, CRS354, CCR2004, Hasslehoff, NetBox, and the container
services VMs have explicit source-of-truth definitions and repeatable backup,
validation, and rollout workflows.

The immediate purpose is to prevent another ambiguous LACP/VLAN/multicast
failure while preparing to move RouterOS duties from the temporary QEMU CHR
gateway to the CCR2004-1G-2XS-PCIe card and to move container-service VMs onto
Hasslehoff.

## Current Facts

| Element | Current Fact | Evidence |
| --- | --- | --- |
| CSS326 management | `172.16.99.6`, SwOS HTTP/Digest | live access validated |
| CSS326 `ge4` | CCR2004 1GbE management physical port | operator-confirmed; RouterOS services seen at `172.16.99.120` on the management network |
| CSS326 `ge5` | Hasslehoff `eno1` LACP member | Linux bond partner port `5` |
| CSS326 `ge6` | Hasslehoff `eno2` LACP member | Linux bond partner port `6` |
| CSS326 `ge24` | CRS354 management interface | operator-confirmed; MAC `04:f4:1c:4b:9f:7e` |
| CSS326 `sfp1` | OPNsense router uplink | operator-confirmed; OPNsense at `172.16.99.1` |
| CSS326 `sfp2` | CRS354 fabric/uplink path | operator-confirmed target topology; LLDP should validate neighbor identity |
| Hasslehoff management | `172.16.99.9/24` on `vmbr0` over `bond0` | live Proxmox access validated |
| Hasslehoff LACP | `bond0 = eno1 + eno2`, 802.3ad, `Number of ports: 2` | live `/proc/net/bonding/bond0` |
| Hasslehoff ConnectX-5 | `enp2s0f0np0`, `enp2s0f1np1`, currently down | live Proxmox link inventory |
| CCR2004 PCIe exposed NICs | `enp1s0f0` through `enp1s0f3`, currently down in Proxmox | live Proxmox link inventory |
| CSS326 reserved multicast | `Forward Reserved Multicast = off` | required for LACP correctness |
| CSS326 VLAN state | no explicit VLAN table, per-port VLAN mode currently optional/default VLAN 1 | live SwOS state |

## Design Principles

- NetBox becomes the source of truth for devices, interfaces, cables, VLANs,
  prefixes, IPs, and VIPs before broad network mutations.
- Every network device mutation starts with a config backup and ends with a
  connectivity validation using deterministic probes.
- SwOS devices are treated as limited L2 switches: configure VLAN/LACP/SNMP and
  poll them, but do not assume they can emit syslog.
- RouterOS and Linux systems are responsible for syslog egress to the eventual
  HAProxy VIP for rsyslog ingest.
- The temporary QEMU RouterOS CHR path remains rollback until the CCR2004
  gateway path passes DNS, internet egress, binpkg access, and service VIP
  validation.
- Hasslehoff ConnectX-5 ports are dedicated to RoCE-v2 and are not used for
  general management, VM default routing, or accidental bridge forwarding.

## Target Topology

### CSS326

CSS326 remains the local management and access switch for the current
`172.16.99.0/24` management segment.

Port assignments:

| Port | Role | Policy |
| --- | --- | --- |
| `ge4` | CCR2004 1GbE management | access/management segment only |
| `ge5` | Hasslehoff LACP member | LACP active, group `1` |
| `ge6` | Hasslehoff LACP member | LACP active, group `1` |
| `ge24` | CRS354 management | access/management segment only |
| `sfp1` | OPNsense uplink | management/default upstream path during transition |
| `sfp2` | CRS354 uplink/fabric | trunk only after CRS354 VLAN plan is validated |

Required normalized settings:

- LACP active on `ge5+ge6` only.
- `Forward Reserved Multicast` disabled.
- IGMP snooping and querier policy explicitly documented and rendered.
- MikroTik discovery enabled only where useful for inventory discovery.
- SNMP enabled with a non-public community or SNMPv3 profile once credentials
  are defined in operator-local secrets.
- Config backup captured before and after each change.

CSS326 syslog egress is not part of the target state because this SwOS build
does not expose a syslog client in the web UI. CSS326 health and counters should
be collected through SNMP polling.

### CRS354

CRS354 is the next distribution switch and should be normalized after CSS326 is
safe and backed up.

Required baseline:

- Confirm management IP and RouterOS access method.
- Enable LLDP on the CRS354 and validate the CSS326 `sfp2` neighbor.
- Enable syslog egress to the HAProxy rsyslog VIP once that VIP is stable.
- Enable SNMP telemetry for interface counters, health, temperature, and fans.
- Document and, where possible, remediate the current fan blast by checking
  RouterOS health, fan mode, temperature sensors, and firmware state before
  changing switching behavior.

### CCR2004-1G-2XS-PCIe

The CCR2004 becomes the RouterOS target for routing duties currently handled by
temporary QEMU CHR.

Phased state:

1. Management-only baseline reachable via CSS326 `ge4`.
2. RouterOS identity, users, SSH/API policy, SNMP, LLDP, and syslog client.
3. VLAN interfaces and gateway services for lab and service networks.
4. DHCP/DNS/NAT/firewall rules migrated from the CHR role.
5. Path B cutover only after repeat validation.

The role must remain distinct from the CHR/x86 role because CCR2004 hardware,
interfaces, package support, and operational rollback differ from a QEMU VM.

### Hasslehoff

Hasslehoff remains on `172.16.99.9/24` over `vmbr0` backed by `bond0`.

Management path:

- `bond0`: `eno1+eno2`, 802.3ad, CSS326 `ge5+ge6`.
- `vmbr0`: management bridge for Proxmox and management-reachable VMs.
- `sdn0vn0`: existing Proxmox SDN bridge remains separate until explicitly
  modeled.

RoCE-v2 path:

- `enp2s0f0np0` and `enp2s0f1np1` are reserved for dedicated RDMA/RoCE-v2.
- Do not add these ports to `vmbr0`.
- Do not use them for default route, management SSH, or container-service VM
  public ingress.
- Add MTU, PFC/ETS/DSCP, and lossless fabric policy only after the CRS354 side
  is documented and validated.

### Container Services

Container-service VMs can move to Hasslehoff once:

- Hasslehoff management LACP is stable.
- CCR2004 gateway migration is validated or the current CHR rollback path is
  explicitly retained.
- HAProxy VIPs for rsyslog and service ingress are modeled.
- NetBox has the VM, interface, IP, and VIP records.

The existing Path B container-services stack remains the working reference
until Hasslehoff-hosted VMs pass service validation.

## VLAN And Prefix Model

The first normalized VLAN set should be conservative:

| VLAN | Purpose | Initial Prefix | Notes |
| --- | --- | --- | --- |
| 1 | current management compatibility | `172.16.99.0/24` | retain during transition |
| 98 | Proxmox SDN/lab compatibility | `172.16.98.0/24` | already present on Hasslehoff |
| 1098 | Path B lab/services | `10.9.8.0/24` | current CHR-backed lab |
| 1077 | container management | `10.77.0.0/24` | planned |
| 1078 | container applications | `10.77.1.0/24` | planned |
| 1200 | OOB and power management | operator-assigned prefix | UPS/PDU/ATS/OOB devices |
| 1300 | builder farm | operator-assigned prefix | Atom C3758 distcc/Jenkins workers |
| 1400 | RoCE-v2 fabric control | operator-assigned prefix | only if L3 control is needed |
| 1500 | LLM/RAG service control | operator-assigned prefix | Ollama, OpenWebUI, vLLM, SourceBot, API proxy control plane |
| 1501 | LLM/RAG inference data | operator-assigned prefix | GPU-backed inference, embedding, vector/RAG data path |

NetBox should hold the final VLAN IDs and prefixes before CSS326 or CRS354 are
converted from optional VLAN behavior to strict trunk/access behavior.

## LLM API And RAG Service Track

The network fabric must reserve room for a follow-on service track that fronts
multiple LLM providers and local GPU resources.

Known future components:

- Ollama server
- OpenWebUI
- vLLM providers
- SourceBot
- LLM API proxy that can route traffic across local vLLM providers and external
  APIs such as OpenAI
- RAG pipeline services for document ingestion, embedding, retrieval, and
  provider-aware request routing

Initial network requirements:

- dedicated service-control VLAN and prefix for management/API control traffic
- separate inference/data VLAN and prefix for GPU/RAG data paths
- HAProxy VIPs for OpenWebUI, LLM API proxy, vLLM provider pools, embedding
  endpoints, and SourceBot
- rsyslog and metrics collection for every API proxy, model runtime, and RAG
  component
- NetBox records for provider pools, VIPs, GPU hosts, and service ownership

This is intentionally a next-phase requirement. The current fabric work should
not block on it, but VLAN/VIP naming and NetBox models must avoid assumptions
that make the LLM/RAG service layer hard to add later.

## Observability And Logging

Logging:

- Linux hosts and VMs use the repo `rsyslog_base` role.
- RouterOS devices send remote syslog to the HAProxy rsyslog VIP.
- CRS354 should send RouterOS logs to the HAProxy rsyslog VIP.
- CSS326 is SNMP-polled; it is not expected to send syslog.

Metrics:

- Proxmox/Hasslehoff uses node exporter plus Proxmox API scraping in a
  follow-on telemetry role.
- RouterOS devices use SNMP and RouterOS health telemetry.
- CSS326/CRS354 use SNMP interface and health polling.
- Power/OOB devices use SNMP exporters already planned in observability docs.

## Automation Units

Implementation should add these repo-managed units:

- `network-fabric` inventory/profile data for devices, ports, VLANs, and
  expected neighbors.
- SwOS CSS326 backup/render/validate helper for LACP, VLAN, RSTP, SNMP, and
  discovery state.
- RouterOS CCR2004 role variant derived from `routeros_pathb` but with hardware
  interface maps and management-first sequencing.
- CRS354 RouterOS baseline role for identity, LLDP, syslog, SNMP, VLAN trunking,
  and fan/health inspection.
- Proxmox Hasslehoff role data for `vmbr0`, `bond0`, SDN separation, VM target
  networking, and ConnectX-5 RoCE reservation.
- NetBox seed/validation data for devices, interfaces, cables, VLANs, prefixes,
  IPs, and VIPs.
- LLM/RAG service inventory stubs for future Ollama, OpenWebUI, vLLM, SourceBot,
  API proxy, provider pool, and VIP definitions.

## Rollout Sequence

1. Capture CSS326, Hasslehoff, Proxmox, CHR, CCR2004, and CRS354 read-only
   facts.
2. Commit the discovered topology as source-of-truth data.
3. Add validation scripts that compare live switch/host state to expected
   topology.
4. Normalize CSS326 only for already-proven safety settings: LACP `ge5+ge6`,
   reserved multicast off, backups, and SNMP/discovery posture.
5. Build CRS354 read-only discovery and fan/health inspection.
6. Apply CCR2004 management-only baseline.
7. Add CCR2004 lab gateway services without removing CHR.
8. Move one test VM/service route at a time from CHR to CCR2004.
9. Move container-services VM workload to Hasslehoff.
10. Retire CHR only after repeated DNS, internet egress, binpkg, rsyslog,
    HAProxy VIP, and container-service validation.

## Validation Requirements

Every network-affecting task must validate:

- SSH/API access to the modified device.
- Expected LACP member count and partner MACs where bonding is used.
- Expected VLAN access/trunk behavior by probe host or service validator.
- No regression in Proxmox API access on `172.16.99.9:8006`.
- No regression in OPNsense/default gateway reachability at `172.16.99.1`.
- RouterOS DNS forwarding and egress after CCR2004 gateway changes.
- HAProxy VIP reachability for rsyslog and service ingress.
- NetBox data matches live LLDP/MAC/interface observations.

## Risks And Controls

| Risk | Control |
| --- | --- |
| SwOS silently accepting partial malformed config | backup before write, read back endpoint after write |
| LACP hash blackholing | verify partner MAC, member count, and varied source-port probes |
| VLAN cutover isolating management | leave VLAN 1 compatibility until out-of-band path is validated |
| CRS354 fan/thermal issue hiding hardware fault | inspect health/fan telemetry before using it as a critical trunk |
| CCR2004 migration breaking lab egress | keep CHR rollback until repeated service validation passes |
| RoCE fabric leaking into management | do not bridge ConnectX-5 ports into Proxmox management or VM bridges |

## Approval State

This design reflects operator approval of the phased approach and the corrected
physical mapping for CSS326 `ge4`, `ge5`, `ge6`, `ge24`, `sfp1`, and `sfp2`.
