# ITIL Change Control: Container Services Safe Move

See the repository source document:

`docs/CHANGE-CONTROL-CONTAINER-SERVICES-SAFE-MOVE.md`

## Current State

- Staging hostname: `svc-container-services-safe-move-01.rfc1918.host`
- Staging IP: `172.16.99.89/24`
- Proxmox VMID: `1089`
- Hypervisor: `hasslehoff`
- Source workload: `10.9.8.89`
- Source Elasticsearch test VIP: `10.9.8.92:9200`

## Validation Gates

- Pre-move source SLO: HAProxy, nginx, rsyslog TCP, Elasticsearch VIP.
- Target boot SLO: SSH management on the staging VM.
- Post-move core SLO: source guard checks plus staging SSH, HAProxy, nginx, and
  rsyslog TCP.
- Elasticsearch dependency SLO: staging-local HAProxy listener on
  `172.16.99.89:9200` forwarding to the Elasticsearch backend.

Current execution evidence:

- Pre-move source SLO passed `4/4`.
- Target boot SLO passed `1/1`.
- Post-move core SLO passed `8/8`.
- Elasticsearch dependency SLO currently fails with HAProxy `503` because the
  staging VM cannot reach the existing `10.9.8.91` / `10.9.8.92` path from the
  Hasslehoff management subnet.

## Safety Notes

- Do not stop the source VM until post-move validation passes.
- Do not bind `10.9.8.92/32` on the staging VM.
- Do not apply Hetzner DNS writes without an explicit apply gate.
- Use `scripts/migrate-container-services-runtime.sh --dry-run` before the
  live runtime copy.
