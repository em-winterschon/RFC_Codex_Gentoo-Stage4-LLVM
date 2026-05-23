# CoreDNS Local Resolver Cluster

## Purpose

SUN99/FMT2 needs local DNS resolution that does not depend on ad hoc SSH config
aliases or `/etc/hosts` edits. The first deployment target is a small CoreDNS
resolver set, backed by repo-managed zone data and existing Hetzner DNS API
automation for external authoritative records.

## Policy

- CoreDNS runs native on Gentoo/OpenRC targets by default.
- Containerized CoreDNS remains available for container-capable VMs or Rocky
  hosts by setting `coredns_resolver_runtime: podman`.
- OpenRC is preferred for service management.
- Native systemd service units are rendered only on systemd-only distributions
  such as Rocky or Debian.
- Hetzner DNS writes remain gated through the existing dry-run/apply workflow.
- Local CoreDNS should serve RFC1918 names first and forward unknown zones
  upstream.

## Initial Resolver

Initial inventory target:

- `admin_sun99_forge_099070` / `172.16.99.70`

Initial managed zone:

- `rfc1918.host`

Seed records include:

- `admin-sun99-forge-099070.rfc1918.host` -> `172.16.99.70`
- `kvm-sfo200-pri-9922.rfc1918.host` -> `10.200.99.22`
- `kvm-sfo200-sec-9923.rfc1918.host` -> `10.200.99.23`
- `kvm-sfo200-ter-9924.rfc1918.host` -> `10.200.99.24`

## Ansible

Primary playbook:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook \
  -i inventories/local-network/hosts.yml \
  playbooks/coredns-resolver.yml \
  -l admin_sun99_forge_099070
```

The role is `coredns_resolver`. It renders:

- `/etc/coredns/Corefile`
- `/etc/coredns/zones/db.rfc1918.host`
- `/usr/local/sbin/coredns-resolver-start`
- OpenRC or native systemd service wrappers depending on target OS

`coredns_resolver_runtime` is currently `native` for M70. Podman is not required
for the first resolver path, which avoids pulling in the Podman/netavark
dependency chain solely to run DNS on an OpenRC Gentoo host.

`coredns_resolver_start_service` is enabled for M70 after validation showed
`named` stopped and port `53/tcp` plus `53/udp` clear.

Validated live on M70:

```bash
dig @127.0.0.1 kvm-sfo200-sec-9923.rfc1918.host A +short
dig @172.16.99.70 kvm-sfo200-ter-9924.rfc1918.host A +short
```

## Hetzner Integration

Existing workflows remain authoritative for public/provider DNS:

```bash
ansible-playbook \
  -i inventories/local-network/hosts.yml \
  playbooks/hetzner-dns-plan-from-inventory.yml

ansible-playbook \
  -i inventories/local-network/hosts.yml \
  playbooks/hetzner-dns-plan-from-netbox.yml
```

Apply stays gated:

```bash
ansible-playbook \
  -i inventories/local-network/hosts.yml \
  playbooks/hetzner-dns-apply.yml \
  -e dns_hetzner_cloud_apply_enabled=true
```

## Validation

After service start:

```bash
dig @172.16.99.70 kvm-sfo200-sec-9923.rfc1918.host A +short
dig @172.16.99.70 forge.rfc1918.host CNAME +short
dig @172.16.99.70 github.com A +short
```

Expected result: local RFC1918 names resolve from CoreDNS and public names
forward through configured upstream resolvers.
