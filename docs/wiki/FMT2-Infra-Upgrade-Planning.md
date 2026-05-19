# FMT2 Infra Upgrade Planning

## Purpose

FMT2 is also referenced as `SFO-200`, `sfo200`, `the colo`, `HE.net`, and
`Hurricane`. This document captures legacy evidence from an old infrastructure
wiki and turns it into a verification plan for FMT2 transport, NetBox IPAM/DCIM,
observability, and service restoration work.

The old wiki is evidence, not authority. Treat every host, IP, credential path,
port map, and access method as pending validation until it is confirmed through
live reachability, device inventory, NetBox, or operator confirmation.

## Legacy Source

- Local path:
  `/opt/repos/remote/blumens/wikis-mkdocs/blumen-arch.wiki`
- Git branch:
  `main`
- Observed commit:
  `bd5b71b`
- Commit subject:
  `if codeberg's integrated wiki doesn't work this time then why even bother offering it`

Do not copy plaintext credentials from the legacy wiki into this repository.
Secrets belong in Ansible Vault or operator-private storage only.

## Evidence Handling Rules

1. Preserve source paths and source commit in docs so evidence can be traced.
2. Summarize legacy values instead of bulk-copying obsolete configs.
3. Mark inferred data as `legacy-evidence-pending-validation`.
4. Promote data into NetBox only after at least one validation source agrees.
5. Record conflicts explicitly rather than overwriting current inventory.

## High-Value Evidence Map

| Legacy source file | Evidence class | Use in current work | Validation requirement |
| --- | --- | --- | --- |
| `SFO-200-DC-Deployment-Notes.md` | Router HA, CARP/VIPs, Aruba switching, HE.net notes | Reconstruct WAN/LAN/IPMI gateway expectations and router backout references | Confirm live router reachability, interface state, and active VIP ownership |
| `SFO-200-High-Availability-WAN-Router-Reference.md` | Primary/secondary router summary | Seed router inventory and HA service checks | Verify current router OS, CARP status, and tunnel compatibility |
| `SFO-200-Switch-Access-References.md` | Switch models, OOB ports, serial methods, Arista/Aruba link maps | Seed DCIM device/interface/cable records | Verify LLDP, serial access, switch running configs, and cable labels |
| `Network-Architecture.md` | VLANs, prefixes, service ports, physical host table | Seed IPAM prefixes, service validation ports, host candidates | Validate every prefix and host/IP/MAC before authoritative import |
| `Rack-Elevation-and-Serial-Port-Mapping.md` | Rack elevations, BlackBox serial ports, PDU/UPS placements | Seed rack, device bay, serial-console, and power inventory | Confirm rack locations and serial port mappings through OOB access |
| `CheckMK-Monitoring-System.md` | Check_MK URLs and API references | Drive Check_MK reachability and API validation | Confirm DNS, TLS, login/API availability, and Check_MK version |
| `Monitoring-Alerting-Logging-and-Telemetry.md` | Prometheus, Alertmanager, Grafana, Check_MK references | Align observability migration targets | Confirm which services still exist before monitoring imports |
| `SFO-200-JBOD-Storage-Overview.md` | JBOD and DigiBox serial paths | Seed storage/OOB inventory | Confirm hardware presence and serial console path |
| `Dell-PowerEdge-MD1200.md` | MD1200 firmware, fan, HBA, serial details | Preserve storage maintenance procedures | Validate against live controller firmware before using commands |

## Legacy Topology Clues

The old wiki indicates FMT2 has three cabinet/rack identifiers:

- `FMT2.68`
- `FMT2.69`
- `FMT2.70`

The current legacy evidence is strongest for racks `68` and `69`. Rack `70`
must be treated as a named scope with incomplete evidence until more source
material or live inventory is available.

Legacy network notes identify these FMT2/SFO-200 networks:

| Network | Legacy role | Notes |
| --- | --- | --- |
| `10.200.99.0/24` | LAN/access network | Legacy gateway/VIP uses `.1`; routers referenced as `.2` and `.3`. |
| `10.100.99.0/24` | VM/data VLAN20 | Legacy access/data network for virtualization traffic. |
| `172.18.20.0/24` | IPMI/management | Legacy gateway/VIP uses `.1`; routers referenced as `.2` and `.3`; several BMCs and power devices live here. |
| `172.17.17.0/24` | OOB device network | Legacy BigNetwork OOB device network. |
| `192.168.132.0/24` | Legacy OpenVPN path | Used for SFO-000 to SFO-200 tunnel references. |
| `192.168.133.0/24` | Legacy OpenVPN path | Used for bastion to SFO-200 tunnel references. |
| `192.168.134.0/24` | Legacy OpenVPN path | Used for bastion to SFO-200 tunnel references. |
| `192.168.252.0/24` | Router HA sync | Legacy CARP/pfSense or OPNsense sync network. |

Legacy WAN evidence references HE.net public space around `66.160.146.144/28`,
with `66.160.146.145` as an upstream gateway candidate and
`66.160.146.148/28` as a public VIP candidate. These values must be verified
with live routing or provider records before use.

## Candidate Devices to Verify

| Candidate | Legacy role | Legacy evidence |
| --- | --- | --- |
| `gw-sfo200-pri` | Primary HA router | Dell R630, management `10.200.99.2`, IPMI `172.18.20.102`. |
| `gw-sfo200-sec` | Secondary HA router | Dell R630, management `10.200.99.3`, IPMI `172.18.20.103`. |
| `sw-border-sfo200-ein-2005` | Border management switch | Aruba 2530-24G, legacy management `172.18.20.5`. |
| `sw-ipmi-sfo200-ein-2004` | IPMI switch | Aruba 2530-24G, legacy management `172.18.20.4`. |
| `sw-sfo200-7060cx32s-2010` | Access/data switch | Arista DCS-7060CX-32S, live management `172.18.20.10`, legacy reference `172.16.40.10`. HTTPS/eAPI is reachable; SSH was filtered during 2026-05-19 checks. |
| `kvm-sfo200-pri-9922` | Virtualization host | Dell R630, legacy management `10.200.99.22`, IPMI `172.18.20.122`. |
| `kvm-sfo200-sec-9923` | Virtualization host | Dell R630, legacy management `10.200.99.23`, IPMI `172.18.20.123`. |
| `kvm-sfo200-ter-9924` | Virtualization/OOB host | Dell R630, legacy management `10.200.99.24`, IPMI `172.18.20.124`. |
| `kvm-sfo200-nasa-9918` | Storage/virtualization host | Dell R730xd, legacy management `10.200.99.18`, IPMI `172.18.20.118`. |
| `app-sfo200-monitoring-9927` | Check_MK service | Legacy Check_MK site URL uses `/vernetzen/`. |
| `app-sfo200-prometheus-9946` | Prometheus/Alertmanager | Legacy Prometheus on `9090`, Alertmanager on `9093`. |

## Access Methods to Rebuild

The legacy access model includes several paths. Re-enable them in this order:

1. SD-WAN or compatibility VPN transport from RFC99/SUN99 to FMT2.
2. Router management reachability for `gw-sfo200-pri` and `gw-sfo200-sec`.
3. Switch SSH and serial/OOB reachability.
4. BMC/IPMI reachability for Dell hosts.
5. Check_MK and Prometheus web/API reachability.
6. Storage/JBOD serial reachability only after OOB access is stable.

## NetBox Intake Targets

Create or update these NetBox objects only after validation:

- Site aliases:
  - `fmt2`
  - `sfo200`
  - `he-net`
  - `hurricane`
- Racks:
  - `FMT2.68`
  - `FMT2.69`
  - `FMT2.70`
- Prefixes:
  - `10.200.99.0/24`
  - `10.100.99.0/24`
  - `172.18.20.0/24`
  - `172.17.17.0/24`
  - `192.168.132.0/24`
  - `192.168.133.0/24`
  - `192.168.134.0/24`
  - `192.168.252.0/24`
- Device categories:
  - HA routers
  - Aruba management/IPMI switches
  - Arista access/data switch
  - Dell virtualization hosts
  - BMC interfaces
  - BlackBox/DigiBox OOB serial devices
  - APC/TrippLite power devices
  - JBOD/storage shelves
- Service records:
  - Check_MK
  - Prometheus
  - Alertmanager
  - Grafana
  - legacy Puppet/Foreman references if still live

## Transport Validation Gates

1. Confirm chosen transport path:
   - primary: BigNetwork SDN route
   - fallback: compatibility OpenVPN endpoint in VyOS or a small Linux VM
2. Confirm RFC99/SUN99 can route to FMT2 management prefixes.
3. Confirm FMT2 has return routes to RFC99/SUN99.
4. Confirm DNS resolution for `*.vernetzen.io` and any future `*.rfc1918.host`
   aliases used for FMT2.
5. Run targeted `nmap` checks for:
   - SSH `22/tcp`
   - Check_MK agent `6556/tcp`
   - HTTP/HTTPS `80/tcp`, `443/tcp`
   - Prometheus `9090/tcp`
   - Alertmanager `9093/tcp`
   - SNMP `161/udp` where applicable
   - IPMI `623/udp` where applicable
6. Snapshot current device configs before changing routing, switching, or HA
   state.
7. Add verified records to NetBox and tag imported evidence with the old wiki
   source commit.

## Immediate Next Actions

1. Add the legacy evidence references to the existing FMT2 Check_MK transport
   plan.
2. Add roadmap tasks for FMT2 evidence validation and NetBox intake.
3. Once transport exists, run a read-only discovery pass against the candidate
   hosts and compare live results with the legacy evidence map.
4. Promote verified records into NetBox in small batches:
   prefixes first, then routers/switches, then hosts/BMCs, then services.

## R630 HCI Rebuild Note

The three Dell R630 virtualization hosts are now tracked in
`docs/FMT2-R630-HCI-STAGED-REBUILD.md`. The key storage rule is that
`kvm-sfo200-ter-9924` must preserve and use its existing `dstore` ZFS pool for
VM hosting, migration staging, backups, ISO caches, and provisioning artifacts.
The `ter` OS RAID1 SATA SSD set is OS-only and must not become a VM or backup
payload target.

The R630 fabric policy is also tracked there: `eno1`/`eno2` form the host
management LACP pair, `eno3`/`eno4` form the VM front-end LACP/OVS pair, and
the ConnectX-4 50GbE interfaces carry RDMA/RoCEv2 storage traffic through the
Arista 7060. Do not mutate switch lossless settings or host SR-IOV state until
read-only port mapping, config snapshots, and rollback commands are captured.
