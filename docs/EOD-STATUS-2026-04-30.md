# EOD Status 2026-04-30

## Executive State

The Path B `container-services` VM redeploy is back in a useful state after the
site internet outage. The VM is online at `10.9.8.89`, Podman is running, and
the package-backed Stage5 service images for `nginx`, `haproxy`, and
`rsyslog-collector` are serving traffic through generated OpenRC wrappers.

The base image and service-layer image path is now the practical path:

- base image:
  - `ghcr.io/em-winterschon/gentoo-stage3-llvm-clang-openrc:latest`
- service images:
  - `ghcr.io/em-winterschon/gentoo-stage5-nginx:latest`
  - `ghcr.io/em-winterschon/gentoo-stage5-haproxy:latest`
  - `ghcr.io/em-winterschon/gentoo-stage5-rsyslog-collector:latest`

`ntfy` remains the only runtime app still dependent on an upstream Docker Hub
image. The post-outage pull for `docker.io/binwiederhier/ntfy:v2.14.0` stalled,
so it is intentionally stopped until we either complete that pull or replace it
with a package-backed Stage5 image.

## Validated Runtime State

Live VM:

- name: `container-services`
- address: `10.9.8.89`
- runtime scratch: `/var/lib/container-services-ephemeral`
- scratch backing: tmpfs
- scratch size: `32G`
- last observed scratch use after archive cleanup: about `6.2G`

Started services:

- `container-rsyslog-collector`
  - `514/tcp`
  - `514/udp`
- `container-nginx`
  - `8080/tcp`
- `container-haproxy`
  - `80/tcp`
  - `443/tcp`
  - `10.9.8.92:9200/tcp`

Stopped services:

- `container-ntfy`
  - blocker: upstream image pull stalled after the internet outage

Host-side checks passed:

```bash
scripts/service_validator.py --target 10.9.8.89 --port 8080 --protocol tcp --service-name container-services-nginx --json
scripts/service_validator.py --target 10.9.8.89 --port 80 --protocol tcp --service-name container-services-haproxy-http --json
scripts/service_validator.py --target 10.9.8.89 --port 514 --protocol tcp --service-name container-services-rsyslog-tcp --json
scripts/service_validator.py --target 10.9.8.92 --port 9200 --protocol tcp --service-name elasticsearch-haproxy-vip --json
```

HTTP checks passed:

- `http://10.9.8.89:8080/`
  - direct nginx container ingress
- `http://10.9.8.89:80/`
  - HAProxy to nginx backend
- `http://10.9.8.92:9200/`
  - HAProxy Elasticsearch test VIP

## Major Fixes Landed

- Fixed target ZFS child-dataset mount ordering during provisioning.
- Preserved the provisioning hostid into the installed root-on-ZFS target.
- Fixed kernel asset discovery when `/usr/lib/modules/*/vmlinuz` is a symlink.
- Rebuilds `sys-fs/zfs-kmod` for the selected target kernel when needed.
- Fixed nftables generation for Podman port maps with explicit bind addresses.
- Replaced iptables-style `podman+` matching with nftables-compatible `podman*`.
- Added a deterministic local image archive fallback for service-image loading
  when external pulls are slow or unavailable.
- Added HAProxy test VIP handling for Elasticsearch at `10.9.8.92:9200`.

## Documentation And Repo State

Committed and pushed checkpoint before this EOD note:

- `a11ef4e Validate container services VM redeploy`
- branch:
  - `codex/add-container-services-profile`
- remote:
  - `origin/codex/add-container-services-profile`

Validation for that checkpoint passed:

```bash
bash tests/shell/run-tests.sh
ansible-playbook -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/pathb-container-services/hosts.yml --syntax-check gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/install.yml
git diff --check
```

One unrelated local branch push issue remains outside this branch:

- `codex/add-ntfy-notifications`
  - remote rejected a non-fast-forward push
  - no action taken from this branch

## Risks And Blockers

| ID | Item | Impact | Next Action |
| --- | --- | --- | --- |
| `NTFY-001` | `ntfy` still uses Docker Hub image path | redeploys can stall when upstream pulls are slow | build a package-backed Stage5 `ntfy` image or preload a verified image archive |
| `IMG-001` | service images loaded into tmpfs are ephemeral | VM reboot requires GHCR pull or archive preload | keep GHCR tags current and add explicit image preload policy |
| `NET-001` | Path B routing is still lab-local | future RouterOS move changes default gateway assumptions | migrate routing/IPAM to Proxmox and CCR2004 deliberately |
| `IPAM-001` | NetBox source of truth is not wired into this repo yet | subnet allocation is still manually tracked | connect to NetBox API and import planned prefixes tomorrow |

## Tomorrow Action Plan

### Access Bootstrap

1. Confirm Proxmox management address, SSH user, and preferred sudo policy.
2. Install the Codex SSH public key on:
   - Proxmox host
   - NetBox VM
   - RouterOS/CCR2004 management account
3. Verify noninteractive SSH from this host to each target.
4. Record host aliases in inventory after access is verified.

### NetBox IPAM/DCIM Plan

Start with a conservative model and confirm exact prefixes before writing live
objects into NetBox:

| Purpose | Proposed Prefix Or Record | Notes |
| --- | --- | --- |
| Proxmox management | existing management subnet, exact prefix TBD | do not infer until host confirms |
| Path B lab | `10.9.8.0/24` | current container-services/binpkg/Elasticsearch test lab |
| RouterOS upstream WAN | `192.168.1.0/24` | upstream gateway `192.168.1.254`; previous CHR static `192.168.1.222/24` |
| Container services VM | `10.9.8.89/32` | current live VM |
| Binpkg repository VM | `10.9.8.90/32` | current live binhost |
| Elasticsearch test VM | `10.9.8.91/32` | test node address |
| Elasticsearch test VIP | `10.9.8.92/32` | HAProxy listener |
| Container network mgmt | `10.77.0.0/24` | proposed Podman/netavark management segment |
| Container network apps | `10.77.1.0/24` | proposed Podman/netavark application segment |
| OOB network | TBD | include BlackBox OOB, UPS/PDU/ATS management later |
| ZeroTier overlay | TBD | reserve only after ZeroTier network ID is known |

NetBox objects to create or reconcile:

- sites:
  - homelab/local site name TBD
- racks:
  - optional until physical layout is stable
- devices:
  - Proxmox host
  - CCR2004 PCIe RouterOS card
  - VM records for NetBox, binpkg, container-services, Elasticsearch test
- prefixes:
  - lab, management, upstream, container, and OOB networks
- IP addresses:
  - gateway, VIPs, VM addresses, management endpoints
- roles:
  - `hypervisor`
  - `router`
  - `ipam`
  - `container-host`
  - `binpkg-repository`
  - `observability`

### RouterOS CCR2004 Migration

1. Export and archive the current QEMU RouterOS Path B config before making any
   changes.
2. Keep the current QEMU RouterOS VM available as rollback until CCR2004
   routing is validated.
3. Model CCR2004 physical and logical interfaces in NetBox.
4. Apply a management-only CCR2004 baseline first.
5. Move Path B gateway functions after management is stable:
   - LAN gateway for `10.9.8.0/24`
   - DHCP if still desired for the lab segment
   - DNS forwarding to `9.9.9.9` and `8.8.8.8`
   - NAT/masquerade toward upstream
   - explicit firewall baseline
6. Validate:
   - VM DNS egress
   - VM internet egress
   - container-services host ingress
   - binpkg repo access
   - HAProxy VIP access

### Container-Services Follow-Through

1. Add explicit image pull/preload policy so package-backed GHCR images do not
   repeatedly hit the network when already present.
2. Replace `ntfy` upstream-image dependency with a Stage5 package-backed image
   or a controlled archive preload path.
3. Keep HAProxy service-type coverage expanding for Elasticsearch, rsyslog,
   Kibana, APM, and future multi-container services.
4. Wire NetBox IPAM lookups into the container/network profile inputs after the
   NetBox API endpoint and token are available.

## Resumption Notes

The fastest useful next move tomorrow is access and source-of-truth setup:
Proxmox SSH, NetBox API, and CCR2004 management. Do not tear down the current
QEMU RouterOS Path B gateway until the CCR2004 path passes DNS, internet
egress, and service ingress checks.
