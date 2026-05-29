# Sunrise Critical Path

This runbook defines the daily launch gate for high-leverage infrastructure work.
It is intentionally read-only. It answers one question before we mutate live
systems:

> Are the current control-plane, backup, transport, notification, and scheduler
> prerequisites healthy enough to proceed?

## Execution Priority

1. Preserve continuity: do not start risky X12AGAIN work until M70 or the next
   Forge admin host can run the operator toolchain, vault, GitHub, RouterOS,
   Proxmox, NetBox, ntfy, and X12AGAIN SoL checks.
2. Preserve recovery: Hasslehoff needs scheduled external backup coverage before
   we depend on it as the heavy-lift VM platform for more services.
3. Preserve FMT2 reachability: the M70 `openvpn.fmt2` bridge is temporary but
   currently functional and should be checked before Check_MK, NetBox, or
   discovery work touches FMT2.
4. Bring compute online incrementally: SLURM starts as a non-production pilot
   controller plus first worker, not as a wholesale fleet scheduler.

## Daily Gate

Run:

```bash
bash scripts/validate-sunrise-critical-path.sh
```

For CI or repo-only checks:

```bash
SUNRISE_SKIP_LIVE=1 bash scripts/validate-sunrise-critical-path.sh
```

To notify the local ntfy bus:

```bash
SUNRISE_NOTIFY=1 \
SUNRISE_NTFY_URL=http://msg-sun99-ntfysys.rfc1918.host \
SUNRISE_NTFY_TOPIC=forge-change \
bash scripts/validate-sunrise-critical-path.sh
```

## Live Checks

The validator checks:

- repo artifacts for FMT2 OpenVPN transport, Hasslehoff backup, SLURM pilot,
  X12AGAIN reimage prep, and Forge memory spool
- M70 SSH reachability through the `forge` alias
- M70 `openvpn.fmt2` service state
- M70 route selection for `172.18.20.4` and `10.200.99.1` through `tun-fmt2`
- local client ICMP reachability to `10.200.99.1` and `172.18.20.4`
- Hasslehoff SSH and Proxmox CLI reachability
- Hasslehoff backup dry-run rendering
- local ntfy HTTP and HTTPS health

## Pass Criteria

Proceed with normal daily mutations only when the validator exits `0`.

If it fails:

- fix the failed gate first
- document the correction in the relevant runbook or roadmap item
- re-run the validator
- only then proceed with dependent changes

## Current Strategic Lanes

| Lane | First objective | Hard stop |
| --- | --- | --- |
| M70 continuity | Prove Forge can operate without X12AGAIN state | Any missing vault, GitHub, RouterOS, Proxmox, NetBox, or SoL access |
| Hasslehoff backup | Schedule and validate external backup flow | No restore or integrity validation path |
| FMT2 transport | Keep temporary OpenVPN path working until BigNetwork or RouterOS replacement is ready | Route flaps, tunnel instability, or untracked live route changes |
| SLURM pilot | Bring up controller and first worker with observability | Missing MUNGE/database secret delivery or DNS/IPAM records |
| X12AGAIN reimage | Execute only after M70/X11 admin host gates and backup gates pass | Any dependency still sourced only from X12AGAIN |

## Operator Notes

The daily gate is not a deployment tool. It does not restart services, change
routes, write secrets, or modify state. It is safe to run repeatedly during
planning and before change windows.
