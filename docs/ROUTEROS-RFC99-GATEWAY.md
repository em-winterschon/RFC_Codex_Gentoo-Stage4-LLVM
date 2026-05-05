# RouterOS RFC99 Gateway Role

`routeros_rfc99_gateway` renders the physical CCR2004 replacement-router
configuration for the RFC99 management and services fabric. It is intentionally
render-only until the generated `.rsc` file has been reviewed against the live
serial console state.

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

## Live Apply Gate

No live apply task exists in this role yet. Before adding one:

1. Keep `/dev/ttyUSB2` serial console open.
2. Export current RouterOS config and binary backup.
3. Review the rendered RSC line-by-line.
4. Confirm cabling: `sfp-sfpplus1` WAN and `sfp-sfpplus2` LAN trunk.
5. Confirm management access source is inside the allowed CIDRs.
6. Apply a management-only subset first if reachability risk is high.
7. Validate SSH, HTTPS, API-SSL, WAN DHCP, default route, DNS, SNAT, and VLAN
   gateway reachability before retiring the existing gateway path.

## Validation

Focused validation:

```bash
bash tests/shell/test_routeros_rfc99_gateway_role.sh
```

Full validation:

```bash
bash tests/shell/run-tests.sh
```
