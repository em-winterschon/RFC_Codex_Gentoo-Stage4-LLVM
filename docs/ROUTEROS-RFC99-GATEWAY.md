# RouterOS RFC99 Gateway Role

`routeros_rfc99_gateway` renders the physical CCR2004 replacement-router
configuration for the RFC99 management and services fabric. The role remains
render-first: generated `.rsc` files must be reviewed against live gateway
state before any operator-applied import or SSH command stream.

## Target

- device: MikroTik `CCR2004-16G-2S+PC`
- observed RouterOS board-name: `CCR2004-16G-2S+`
- observed architecture: `arm64`
- WAN uplink: `sfp-sfpplus1`
- LAN switch uplink/trunk: `sfp-sfpplus2`
- copper interface naming: `ether1` through `ether16` become `ge1` through
  `ge16`

## Render

Example inventory:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_CALLBACKS_ENABLED=control_flow \
  ansible-playbook \
  -i inventories/examples/hosts.yml \
  playbooks/routeros-rfc99-gateway.yml \
  -l gw_rfc99_mkccr2004_16g_example
```

Vault-backed local-network inventory:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_CALLBACKS_ENABLED=control_flow \
  ../../scripts/with-ansible-vault-env.sh ansible-playbook \
  -i inventories/local-network/hosts.yml \
  playbooks/routeros-rfc99-gateway.yml \
  -l gw_rfc99_mkccr2004_16g \
  -e routeros_rfc99_gateway_render_root=/tmp/routeros-rfc99-gateway
```

Rendered artifacts:

- `/tmp/routeros-rfc99-gateway/<host>-rfc99-gateway.rsc`
- `/tmp/routeros-rfc99-gateway/<host>-rfc99-gateway.json`

## RouterOS Artifact Cache

The on-host RouterOS package cache for this target is
`/opt/routeros/mikrotik-official`.

Current staged artifacts:

- RouterOS `7.22.3` arm64 package:
  `/opt/routeros/mikrotik-official/os-systems/arm64/routeros-7.22.3-arm64.npk`
- RouterOS container `7.22.3` arm64 package:
  `/opt/routeros/mikrotik-official/containers/arm64/container-7.22.3-arm64.npk`

The container package is tracked for lab validation only. Production service
VIPs should continue to terminate on the Stage4 container-services VM through
HAProxy, not inside RouterOS containers on the primary gateway.

## Security Posture

The rendered management plane enables:

- SSH on TCP/22
- HTTPS on TCP/443 with a self-signed RouterOS certificate
- API-SSL on TCP/8729 with the same certificate

The rendered management plane disables:

- telnet
- FTP
- HTTP
- plaintext RouterOS API
- WinBox

Management services are restricted to configured management CIDRs. The default
CIDRs are `172.16.99.0/24`, `10.9.8.0/24`, and `10.128.128.0/24`.

The gateway also disables IPv4 redirect acceptance/sending and installs an
output-chain suppressor for ICMP redirect type `5` toward LAN interfaces. This
is required while multiple legacy `/24` prefixes, including `172.16.99.0/24`
and `172.16.199.0/24`, share `br-lan`; hosts must consistently use the
CCR2004 as their L3 transit point instead of learning direct same-L2 host
redirects.

## Network Plan

The role encodes current VLAN intent:

| VLAN | Name | Gateway |
| --- | --- | --- |
| `1` | `management-compat` | `172.16.99.1/24` |
| `98` | `proxmox-sdn-lab` | `172.16.98.1/24` |
| `1098` | `pathb-lab-services` | `10.9.8.1/24` |
| `1077` | `container-management` | `10.77.0.1/24` |
| `1078` | `container-applications` | `10.77.1.1/24` |
| `1200` | `oob-power-management` | planned |
| `1300` | `builder-farm` | planned |
| `1400` | `roce-v2-control` | planned |
| `1500` | `llm-rag-service-control` | planned |
| `1501` | `llm-rag-inference-data` | planned |

The CRS309 WIP declared overlapping `172.16.228.0/22` gateway entries. The
CCR2004 render normalizes that to only `172.16.228.1/22` and intentionally omits
the duplicate `172.16.229.1/22` and `172.16.230.1/22` entries.

## Service VIP Routing

The approved production boundary is:

- CCR2004 owns L3 service VIPs and narrowly scoped DNAT rules.
- Stage4 container-services VMs run HAProxy/nginx and own application behavior.
- RouterOS containers remain a lab-only experiment until package enablement,
  external storage, image provenance, health checks, and private key handling
  are validated away from the primary gateway.

Initial SUN99 Elasticsearch/search VIP:

| Field | Value |
| --- | --- |
| VIP | `172.16.99.92/32` |
| FQDN | `obs-sun99-esvip-099092.rfc1918.host` |
| Alias | `obs-sun99-esvip.rfc1918.host` |
| CCR2004 action | DNAT TCP/9200 to `172.16.99.89:9200` |
| CCR2004 hairpin | SRCNAT LAN clients to the backend for symmetric replies |
| HAProxy host | `svc-container-services-safe-move-01` |
| Backend path | HAProxy forwards to the Path B Elasticsearch test endpoint |

The service VIP was applied live on `2026-05-10` after pre-change RouterOS
backup/export capture. Validation passed for ICMP reachability, TCP/9200
readiness, RouterOS DNS A/CNAME resolution, Elasticsearch cluster health
`green`, and syslog-to-Elasticsearch marker ingestion through the VIP.

The role also renders temporary `/32` static routes for `10.9.8.91` and
`10.9.8.92` via `172.16.99.108` while Path B services remain behind X12AGAIN.
The container-services VM must also keep matching backend routes through
`172.16.99.108`; `scripts/migrate-container-services-runtime.sh` persists
those routes during safe-move redeploys. Remove these routes once VLAN `1098`
and the Elasticsearch service path are fully owned by the physical
CCR2004/spine fabric.

## DHCP Scope

The active gateway provides a narrow DHCP scope for the management-compat
subnet:

| Field | Value |
| --- | --- |
| Server | `rfc99-management-compat` |
| Interface | `br-lan` |
| Network | `172.16.99.0/24` |
| Pool | `172.16.99.150-172.16.99.158` |
| Gateway | `172.16.99.1` |
| DNS | `172.16.99.1` |
| Next server | optional, currently `172.16.99.108` for K10 UEFI PXE/TFTP |
| Lease time | `1h` |

Additional DHCP scopes should move to NetBox/IPAM-backed automation before
being enabled.

The DHCP renderer supports scoped RouterOS DHCP options and static leases for
UEFI/EFI handoff paths. x86/amd64 netboot definitions must use UEFI/EFI assets;
legacy BIOS PXE is not supported for normal host, VM, or workstation install
paths.

Current K10 validation lease:

| Field | Value |
| --- | --- |
| Host | `gmktek-k10-stage5-ipxe` |
| MAC | `84:47:09:5F:21:64` |
| Address | `172.16.99.156` |
| DHCP option | `k10-pxe-bootfile` |
| Option 67 | `k10-ipxe.efi` |
| Next server | `172.16.99.108` |
| TFTP root | `/var/lib/netboot/path-b` |

Native K10 UEFI HTTPBoot accepted DHCP only after option 60 echoed
`HTTPClient`, but packet captures showed no subsequent ARP or TCP from the K10
to `172.16.99.108`. UEFI PXE IPv4 did ARP and attempted TFTP, so the active
path is now PXE/TFTP with filename `k10-ipxe.efi`.

## Live Apply Gate

The first scoped live apply covered only the Elasticsearch/search service VIP.
Before adding broader apply automation:

1. Keep `/dev/ttyUSB2` serial console open.
2. Export current RouterOS config and binary backup.
3. Review the rendered RSC line-by-line.
4. Confirm cabling: `sfp-sfpplus1` WAN and `sfp-sfpplus2` LAN trunk.
5. Confirm management access source is inside the allowed CIDRs.
6. Apply a management-only subset first if reachability risk is high.
7. Validate SSH, HTTPS, API-SSL, WAN DHCP, default route, DNS, SNAT, and VLAN
   gateway reachability before retiring any existing gateway path.

Captured operator artifacts from the scoped service-VIP apply:

- pre-change state:
  `/root/operator-private/routeros/ccr2004-16g/pre-service-vip-20260510T175807Z`
- reviewed render:
  `/root/operator-private/routeros/ccr2004-16g/render-20260510T180201Z`
- applied RSC:
  `/root/operator-private/routeros/ccr2004-16g/service-vip-apply-20260510T180226Z.rsc`
- post-change state:
  `/root/operator-private/routeros/ccr2004-16g/post-service-vip-20260510T180309Z`

## Validation

Focused validation:

```bash
bash tests/shell/test_routeros_rfc99_gateway_role.sh
```

Full validation:

```bash
bash tests/shell/run-tests.sh
```
