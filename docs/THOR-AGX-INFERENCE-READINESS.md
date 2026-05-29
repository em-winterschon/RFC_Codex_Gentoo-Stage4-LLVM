# Thor AGX Inference Readiness

Audit timestamp: `2026-05-26T16:56:00-07:00`

Target:

```text
agx-rfc99-bunnydev.rfc1918.host
172.16.99.34/24
ssh alias: thor
```

## Summary

Thor is reachable and has a working NVIDIA Thor GPU stack. Podman is installed and validated on Thor.
Ollama and Open WebUI are live through Podman on the management address.

The safest first workload sequence is:

1. preserve headless multi-user operation;
2. keep Docker inactive and masked;
3. deploy Ollama and Open WebUI first using Podman plus NVIDIA CDI;
4. use the current OVS userspace LACP MGBE staging only after validating with
   distinct endpoints, not same-host bridge hairpin tests;
5. defer vLLM and SGLang until arm64/L4T/CUDA 13 images are validated.

## Live Evidence

| Check | Result |
| --- | --- |
| SSH | reachable as `eva` through alias `thor` |
| OS | Ubuntu 24.04.4 LTS |
| kernel | `6.8.12-tegra` |
| architecture | `aarch64` |
| device model | NVIDIA Jetson AGX Thor Developer Kit |
| L4T | R38 revision 4.0 |
| primary management interface | `enP2p1s0`, `172.16.99.34/24` |
| default route | `172.16.99.70` via `enP2p1s0` |
| GPU | `NVIDIA Thor`, driver `580.00`, CUDA runtime `13.0` from `nvidia-smi` |
| GPU utilization | `0%`, no GPU processes reported by `nvidia-smi` |
| CUDA compiler | `nvcc` missing from `PATH` |
| NVIDIA container tooling | `nvidia-ctk` and `nvidia-container-runtime` version `1.18.1` present |
| container engine | Podman `4.9.3` with netavark backend |
| NVIDIA CDI | `/etc/cdi/nvidia.yaml`; `nvidia.com/gpu=0`, `nvidia.com/gpu=all` |
| legacy Docker state | Docker remains masked and inactive. |
| system default target | `multi-user.target` |
| display manager | `gdm3` inactive; `display-manager` not found |
| failed units | `openipmi.service` failed |
| inference units | `inference-ollama.service` and `inference-open-webui.service` enabled and running |

## Network State

Management is up:

```text
enP2p1s0 UP 172.16.99.34/24
```

The MGBE/QSFP-facing interfaces link at 10G and are staged through Open
vSwitch userspace bridges because the NVIDIA L4T kernel does not include the
Linux bonding or kernel OVS datapaths:

```text
CONFIG_BONDING is not set
CONFIG_OPENVSWITCH is not set
CONFIG_NET_TEAM is not set
```

Current host-side bridge layout:

| Bridge | Bond | Members | Intended use | Implementation |
| --- | --- | --- | --- | --- |
| `br-podman0` | `bond-podman0` | `mgbe0_0`, `mgbe1_0` | Podman service/container data plane | OVS `datapath_type=netdev` |
| `br-kata0` | `bond-kata0` | `mgbe2_0`, `mgbe3_0` | QEMU and Kata container data plane | OVS `datapath_type=netdev` |

Observed interface state on 2026-05-26:

```text
mgbe0_0    UP
mgbe1_0    UP
mgbe2_0    UP
mgbe3_0    UP
br-podman0 UNKNOWN fe80::4ebb:47ff:fe0e:178/64
br-kata0   UNKNOWN fe80::4ebb:47ff:fe0e:17a/64
```

The OVS bonds are configured as active LACP `balance-tcp` with fast LACP timing
and MTU 9000. CRS354 `qsfpplus2` now has matching `802.3ad` LACP groups and
both Thor OVS bonds report `lacp_status: negotiated`.

The OVS userspace LACP fallback has moved from peer-pending staging to
peer-negotiated staging; it still requires distinct-endpoint performance
validation before production traffic assignment.

Switch-side LACP and cross-bridge performance validation are tracked in
`docs/THOR-CRS354-LACP-PERF-RUNBOOK.md`. The Thor-local validation harness is
`scripts/thor-ovs-cross-bridge-iperf.sh`; it refuses to run by default while OVS
LACP members remain disabled.

Live validation from 2026-05-27:

```text
CRS354 bond-thor-podman: running, qsfpplus2-1 and qsfpplus2-2
CRS354 bond-thor-kata:   running, qsfpplus2-3 and qsfpplus2-4
Thor bond-podman0:       LACP negotiated, members enabled
Thor bond-kata0:         LACP negotiated, members enabled
```

The same-host Thor hairpin path is not a valid throughput acceptance path.
ICMP across `br-kata0 -> CRS354 -> br-podman0` passed with zero packet loss,
but TCP iperf3 did not produce a valid result. Use two distinct endpoints, or a
routed/VLAN split, before assigning production Podman, QEMU, or Kata traffic to
the MGBE data plane.

Legacy Docker-created networks may remain present until a later cleanup window:

```text
docker0 DOWN 172.17.0.1/16
br-8c52b4f58767 UP 172.18.0.1/16
```

Rollback for the host-side OVS fallback was staged on Thor at:

```text
/root/forge-backups/thor-ovs-netdev-pre-20260526T235234Z/rollback-thor-ovs-netdev.sh
```

## Package Action Ledger

Thor host-local package actions from `/tmp/thor-apt-actions-cleanup-virts.log`
are tracked in this repo as
`docs/evidence/thor-apt-actions-cleanup-virts.2026-05-26.log`.

Important package state from that ledger:

| Category | State |
| --- | --- |
| held packages | `mailutils`, `postfix`, `systemd-container`, `thunderbird` |
| purged packages | `snapd`, `thunderbird` |
| Podman tooling | `podman-toolbox`, `python3-podman`, `podman-remote`, `podman-compose`, `cockpit-podman` |
| virtualization tooling | `libvirt-*`, `qemu-*`, `ipxe-qemu`, `virtiofsd`, `open-iscsi`, `nfs-common` |
| OVS fallback tooling | `openvswitch-switch`, `python3-openvswitch` |
| packet diagnostics | `tcpdump` |

snapd was purged. systemd-container is held. Keep both states explicit in
future Thor playbooks so cleanup or upgrades do not reintroduce unwanted
Ubuntu defaults.

## Readiness Decision

Thor is ready for Podman-first Ollama and Open WebUI service use through the
management interface.

Historical update `2026-05-25T03:00Z`: active operator approval became available
for bounded Thor inference playbook work. The rollout remained gated to
preflight, Ollama first, and Open WebUI only after Ollama was healthy; vLLM and
SGLang remain deferred until arm64/L4T/CUDA 13 images are validated.

Historical update `2026-05-25T03:17:53Z`: root SSH preflight found
`docker.service` and `docker.socket` masked and inactive, while older Ollama
wrapper files still contained Docker `--gpus all`. That state is now superseded
by Podman/CDI deployment validation, but the wrapper renderer retains a
compatibility check so any explicitly approved Docker exception uses Docker's
`--gpus all` flag rather than Podman CDI device selectors.

Recommended inventory stance:

```yaml
inference_service_architecture: arm64
inference_service_accelerator: nvidia
inference_service_container_engine: podman
inference_service_manager: systemd
inference_service_cdi_devices:
  - nvidia.com/gpu=all
```

Keep Ollama as the first model-serving backend and Open WebUI as the first
frontend. Use `nvidia.com/gpu=all` for the initial Thor service profile.

The temporary Docker wrapper path is not Thor's current service default. The
Podman/CDI path continues to use `--device nvidia.com/gpu=all`, and Docker must
remain inactive unless a separate operator-approved maintenance window changes
that host policy.

## Backend Defaults

| Backend | Thor default | Rationale |
| --- | --- | --- |
| Ollama | deployed | Lower integration risk for initial API service validation. |
| Open WebUI | deployed | Decouples UI from model-serving backend URLs. |
| vLLM | defer | Requires arm64/L4T/CUDA 13 image and command validation. |
| SGLang | defer | Same arm64/L4T/CUDA 13 validation risk as vLLM. |

## Deployment Validation

Live validation from M70 `forge1` on 2026-05-25:

| Check | Result |
| --- | --- |
| Ollama unit | `inference-ollama.service` active and enabled |
| Ollama API | `GET http://127.0.0.1:11434/api/version` returned `{"version":"0.24.0"}` |
| Ollama container | `inference-ollama` running under Podman |
| Ollama accelerator | journal reports CUDA `NVIDIA Thor`, compute `11.0`, driver `13.0` |
| Open WebUI unit | `inference-open-webui.service` active and enabled |
| Open WebUI HTTP | `HEAD http://127.0.0.1:8080/` returned `HTTP/1.1 200 OK` |
| Open WebUI container | `inference-open-webui` running under Podman |
| Legacy Docker state | `docker.service` and `docker.socket` inactive and masked |

Live validation from M70 `forge1` on 2026-05-26:

| Check | Result |
| --- | --- |
| Ollama API from M70 | `GET http://172.16.99.34:11434/api/version` returned `{"version":"0.24.0"}` |
| Open WebUI HTTP from M70 | `HEAD http://172.16.99.34:8080/` returned `HTTP/1.1 200 OK` |
| OVS bridges | `br-podman0` and `br-kata0` exist with `datapath_type=netdev` |
| OVS LACP state | bonds were staged until CRS354 peer LACP was configured on 2026-05-27 |

Live validation from M70 `forge1` on 2026-05-27:

| Check | Result |
| --- | --- |
| CRS354 management | `172.16.99.7` reachable after disabling broken `mgmt-source-rule` |
| CRS354 Thor LACP | `bond-thor-podman` and `bond-thor-kata` running |
| Thor OVS LACP | `bond-podman0` and `bond-kata0` negotiated |
| Cross-bridge ICMP | `10/10` packets passed across `br-kata0 -> CRS354 -> br-podman0` |
| Cross-bridge TCP | iperf3 not valid in same-host hairpin topology; use distinct endpoints |

## Blockers

- `nvcc` is not in `PATH`; CUDA developer tooling is not confirmed.
- FreeIPA/SSSD enrollment and central operator identity remain outside this
  audit.
- MGBE/QSFP bridges have negotiated LACP, but production Podman, QEMU, and Kata
  traffic should wait for performance validation with distinct endpoints.

## Non-Mutation Rule

Earlier audits were read-only. The current approved mutation lane allows Podman
inference service deployment while preserving headless operation, current
management networking, and the inactive legacy Docker state.
