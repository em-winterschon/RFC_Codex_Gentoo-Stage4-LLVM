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
  service_manager: sysvinit
  service_enabled: true
  service_started: true
```

Secrets such as BigNetwork auth tokens must come from Ansible Vault. Do not
commit token material or generated `/var/lib/bn/*.secret` files.

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
