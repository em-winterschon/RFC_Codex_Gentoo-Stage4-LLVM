# BigNetwork FMT2 Smoke-Test

## Purpose

Validate whether the BigNetwork SDN client can provide a stable transport path
from RFC99/SUN99 into FMT2/SFO200 before rebuilding the legacy Check_MK,
NetBox, OOB, and observability integrations around that path.

Devuan smoke-test first. The vendor package is a Debian package, so the first
validation target is a disposable Devuan VM. If transport works, the same
binary can be promoted into a Gentoo/OpenRC role after the network path is
proven useful.

## Source Artifact

Local package sources:

```text
/opt/repos/remote/bignetwork/APT/bignetwork_edge-linux-cli.amd64.deb
/opt/repos/remote/bignetwork/APT/bignetwork_edge-linux-cli.amd64_extracted
```

Observed package facts:

| Field | Value |
| --- | --- |
| Debian package | `bn` |
| Version | `1.12.2` |
| Architecture | `amd64` |
| Installed binary | `/usr/sbin/bn` |
| Runtime dependencies | `adduser`, `libstdc++6`, `openssl` |
| Default port | `9995` for UDP and TCP/HTTP |
| Service files | SysV init, upstart, and systemd |
| Local state | `/var/lib/bn` |

The binary is a dynamically linked x86-64 glibc executable and showed safe
`-h` / `-v` output on the Gentoo host. Positional arguments such as `bn help`
and `bn version` started the control plane during inspection, so operational
tests must run only inside a disposable VM or controlled service host.

## Implementation Path

### Phase 1: Disposable Devuan VM

Use `devuan_netboot_assets` to publish:

```text
devuan-bignetwork-smoketest.ipxe
devuan-bignetwork-smoketest.preseed
```

The default iPXE path boots Devuan `excalibur` amd64 netboot installer assets
from `pkgmaster.devuan.org`. Disk partitioning remains interactive by default.
Set `devuan_netboot_autoinstall_enabled=true` only for a known disposable VM
disk.

Recommended VM profile:

| Item | Value |
| --- | --- |
| vCPU | `2` |
| RAM | `2048 MiB` minimum |
| Disk | disposable QCOW, `20 GiB` minimum |
| NIC | RFC99/SUN99 management bridge with internet egress |
| Console | serial console required |
| Snapshot | before installing `bn`, before enabling service |

After install, apply the `bignetwork_edge` role with:

```yaml
resolved_profile_bignetwork_edge:
  enabled: true
  user: root
  group: root
  service_manager: sysvinit
  service_enabled: true
  service_started: true
  orbit_enabled: true
  orbit_worlds:
    - world_id: 6aaf7fee5a
      seed: 6aaf7fee5a
  join_networks:
    - network_id: <fmt2-bignetwork-network-id>
```

Secrets such as BigNetwork auth tokens must come from Ansible Vault. Do not
commit token material or generated `/var/lib/bn/*.secret` files.

The Forge/Codexian portal token is operator-local at:

```text
/root/.ssh/codex.d/tokens/BIGNETWORK_TOKEN_CODEXIAN
```

Import or rotate it with:

```bash
scripts/import-bignetwork-vault.sh
scripts/validate-ansible-vaults.sh
```

The local-network inventory exposes the token to `bignetwork_edge` through
`vault_bignetwork_codexian_api_token`; role tasks write the runtime token file
with `no_log` enabled.

The BigNetwork desktop package runs the service as root and executes:

```bash
bn-cli orbit 6aaf7fee5a 6aaf7fee5a
```

The Ansible role mirrors that orbit bootstrap before attempting network joins.
Keep service execution root-owned unless a disposable host proves the daemon can
create TUN interfaces and routes correctly as an unprivileged user.

### Preferred Permanent Edge

The preferred long-term path is to re-onboard the local NanoPi R6S beta system
as a BigNetwork Edge Lite endpoint and use it as a transparent L2 bridge to
FMT2/SFO200. That avoids running per-host/per-user `bn` clients once the bridge
is validated. The Devuan VM remains useful as an interim smoke-test and as a
safe place to validate portal token behavior before touching the bridge device.

### Phase 2: Transport Validation

Run:

```bash
/usr/local/sbin/bignetwork-smoketest
```

Minimum acceptance gates:

1. `bn -q /var/lib/bn` returns local service/API state without crashing.
2. BigNetwork interface or managed routes appear in `ip addr` / `ip route`.
3. RFC99/SUN99 can reach at least one FMT2 management prefix candidate.
4. FMT2 has return routing to the source VM.
5. DNS resolves `app-sfo200-monitoring-9927.vernetzen.io`.
6. Targeted TCP checks reach Check_MK HTTPS and agent ports where expected.
7. Route and interface state is captured before making NetBox imports.

## Issue #114 Readiness Runbook

Issue #114 is the tracking anchor for promoting BigNetwork from repo scaffold
to a validated FMT2/SFO-200 transport. This runbook is intentionally split into
backup-safe overnight work and live morning work so X12AGAIN preservation does
not compete with transport experiments.

### Backup-Safe Overnight Scope

No live BigNetwork, RouterOS, NetBox, or Check_MK mutation while X12AGAIN off-host backup is active.

Safe actions during the backup window:

1. Keep repo documentation, tests, roadmap entries, and GitHub issue comments
   current.
2. Validate that the Devuan smoke-test role, `bignetwork_edge` role, and
   smoke-test helper syntax still pass local tests.
3. Confirm the BigNetwork token is vaulted by variable name only; do not print
   or copy token material into logs, docs, or issue comments.
4. Prepare the evidence bundle paths and acceptance checklist before running
   the transport.

### Morning Live Preconditions

Do not start the BigNetwork service or modify routes until these are true:

1. The off-host X12AGAIN backup has completed successfully.
2. A disposable Devuan or Gentoo transport VM is snapshotted or trivially
   destroyable.
3. The VM has RFC99/SUN99 internet egress and DNS resolution before `bn`
   starts.
4. BigNetwork portal state shows the expected Forge/Codexian account and target
   FMT2/SFO-200 network association.
5. The first live run has a rollback path: stop `bn`, remove temporary routes,
   revert VM snapshot, and leave CCR2004 state unchanged.

### Evidence Bundle For Issue #114

Evidence bundle for issue #114:

```text
/var/log/rfc1918/fmt2-bignetwork/
  preflight.txt
  bn-query.json
  ip-address.txt
  ip-route.txt
  resolvectl-or-resolvconf.txt
  dns-checks.txt
  reachability.txt
  nmap-targeted.txt
  post-stop-routes.txt
```

Minimum captured commands:

```bash
hostname -f
date -u
bn -q /var/lib/bn
ip -brief address
ip route
getent hosts app-sfo200-monitoring-9927.vernetzen.io
ping -c 3 10.200.99.1
nmap -Pn -p 22,80,443,6556 app-sfo200-monitoring-9927.vernetzen.io
```

If the target hostnames do not resolve through LAN DNS, record that as a DNS
blocker instead of substituting guessed IPs.

### Live M70 Smoke-Test: 2026-05-14

M70 host: `admin-sun99-forge-099070.rfc1918.host` / `172.16.99.70`.

Observed state after installing the extracted `bn` binary and starting it with
`/var/lib/bn`:

1. `bn-cli orbit 6aaf7fee5a 6aaf7fee5a` returned `200 orbit OK`.
2. `bn-cli info` reported `ONLINE`.
3. Public planet/root peers were reachable.
4. `bn-cli listnetworks` returned no joined networks.
5. No overlay interface or route to `10.200.99.0/24` appeared.
6. Pings to `10.200.99.27` and `10.200.99.1` failed, as expected with no joined network.
7. `https://api.bignetwork.com/consumer/networks` returned `401` with the current operator token when tested as a bearer/API-key style portal token.
8. Joining FMT2/SFO200 network `607daa3a01933028` succeeded locally and created interface `bnlj6dscrj`, but the controller returned `ACCESS_DENIED`; no assigned address or managed route was installed.

Current blocker: M70 is online in the BigNetwork control plane and has attempted
to join FMT2/SFO200 network `607daa3a01933028`, but the controller has not
authorized the device. The next live action is to authorize M70 BigNetwork node
address `26b37d60fe` for that network in the BigNetwork portal, or provide a
portal-auth token/session that can issue the device-join authorization.

### Promotion Gates

Promote FMT2 transport from smoke-test to managed service only after all gates
pass:

1. BigNetwork service starts repeatedly after reboot or service restart.
2. RFC99/SUN99 reaches at least one FMT2 management prefix.
3. Return routing from FMT2 to the transport source is proven or explicitly
   remediated.
4. Check_MK URL and agent-port checks are reachable through the transport.
5. NetBox imports remain dry-run until live reachability evidence is attached
   to issue #114.
6. Check_MK onboarding waits for NetBox prefix/device promotion.

### Phase 3: Gentoo/OpenRC Promotion

Only after the Devuan VM validates transport:

1. Re-run `bignetwork_edge` on a Gentoo Stage4 VM with `service_manager=openrc`.
2. Keep the service isolated as a small managed-access VM unless there is a
   clear reason to install it on a core router or container host.
3. Add NetBox service and interface records for the transport endpoint.
4. Update `docs/FMT2-CHECKMK-TRANSPORT.md` with validated routes and targets.

## ZFSBootMenu And Permanent Devuan Images

Do not block BigNetwork validation on a perfect Devuan platform build. A
Devuan plus ZFSBootMenu role may be useful later for long-lived Debian-family
service VMs, but it is out of scope for this smoke-test. The first objective is
transport evidence.

## Backout

1. Stop the `bn` service.
2. Remove any temporary static routes added for validation.
3. Revert the VM snapshot or destroy the disposable VM.
4. Leave the CCR2004 route table unchanged unless a separate reviewed change
   explicitly promotes the transport path.
