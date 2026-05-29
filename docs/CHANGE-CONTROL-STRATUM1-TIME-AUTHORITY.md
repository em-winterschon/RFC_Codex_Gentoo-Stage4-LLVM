# ITIL Change Control: Stratum 1 Time Authority

## Summary

Build a dedicated RFC99/SUN99 time authority using a Raspberry Pi CM4, a
U-Blox MAX-M8Q GNSS HAT as the primary reference clock, and a USB GPS as the
secondary reference. The node provides Stratum 1 NTP with Chrony first. PTP grandmaster mode is gated until the NIC timestamp capability is verified.

## Decision

Use a dedicated hardware role named `metal-time-authority-stratum1`.

The first implementation is intentionally small:

- Gentoo Stage5 OpenRC on Raspberry Pi CM4.
- `chronyd` provides NTP service.
- `gpsd` provides GNSS data.
- Linux PPS devices provide PPS discipline.
- `chrony_exporter` exposes Chrony metrics to Prometheus.
- `linuxptp` is installed but not promoted to service until hardware timestamp
  validation passes.

## Hardware Allocation

- Compute: Raspberry Pi CM4.
- Primary GNSS: U-Blox MAX-M8Q GPIO HAT.
- Secondary GNSS: USB GPS module and antenna.
- Carrier: DIN-rail CM4 carrier with wired Ethernet, redundant power input, and
  TTL-to-RS232 OOB console.
- Reference repos:
  - `/opt/repos/remote/yukon/SysOps-NTP-MaxQ__RPi-GPS-PPS-StratumOne`
  - `/opt/repos/remote/yukon/SysOps-OCP-NTP-StratumN__Time-Card`

## Scope

In scope:

- Stage5 package/profile scaffolding.
- Kernel symbol requirements for PPS, GPIO PPS, serial, and PTP.
- Chrony/GPSD/PPS validation gates.
- Metrics and alert requirements.
- PTP as a gated candidate only.

Out of scope for the first pass:

- PTP grandmaster enablement without timestamp-capable NIC evidence.
- NTP pool serving outside local RFC99/SUN99 networks.
- Any `local stratum` emergency mode unless explicitly enabled and alerted.

## Implementation Plan

1. Build the CM4 host with `metal-time-authority-stratum1`.
2. Validate `/dev/pps*`, GNSS fix state, and Chrony source selection.
3. Validate `chronyc tracking`, `chronyc sources -v`, and
   `chronyc sourcestats -v`.
4. Validate `chrony_exporter` on TCP `9123`.
5. Validate `ethtool -T` on the selected NIC before enabling PTP service.
6. Add router/switch NTP client configuration after the Stratum 1 node is
   stable.
7. Add Prometheus alerts for lost GNSS fix, lost PPS lock, high offset, high
   root dispersion, exporter down, and holdover mode.

## Backout

Clients must retain their existing upstream NTP/Chrony pool configuration until
the local authority passes validation. Backout is to remove the local NTP
server from client config and restart client time sync. PTP remains disabled by
default, so no PTP-specific backout is required in the first pass.

## Acceptance Gates

- `chronyd` and `gpsd` are OpenRC-enabled and running.
- Chrony selects the PPS-disciplined source under normal GNSS lock.
- `chronyc tracking` reports stable low offset and sane root dispersion.
- `chrony_exporter` exposes metrics to the observability scrape path.
- Prometheus alerts exist for GNSS/PPS/offset failure modes.
- PTP is either disabled with a documented NIC limitation or enabled only after
  hardware timestamp validation.
