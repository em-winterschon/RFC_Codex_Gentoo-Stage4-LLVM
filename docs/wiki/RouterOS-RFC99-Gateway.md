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

The rendered management plane enables SSH, HTTPS, and API-SSL only. It disables
telnet, FTP, HTTP, plaintext API, and WinBox. Management services are restricted
to configured management CIDRs.

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
CCR2004 render normalizes that to only `172.16.228.1/22`.

## Live Apply Gate

No live apply task exists in this role yet. Before adding one, keep serial
console open, export the current RouterOS config, review the rendered RSC, and
validate SSH, HTTPS, API-SSL, WAN DHCP, default route, DNS, SNAT, and VLAN
gateway reachability before retiring the existing gateway path.
