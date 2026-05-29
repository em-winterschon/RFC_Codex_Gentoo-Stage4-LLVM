# Stratum 1 Time Authority

The RFC99/SUN99 time authority is a dedicated Raspberry Pi CM4 node using a
U-Blox MAX-M8Q GNSS HAT as the primary reference clock and a USB GPS as a
secondary reference. Chrony provides Stratum 1 NTP first; PTP grandmaster mode
is gated until the selected NIC proves hardware timestamp support.

## Profile

- Role: `metal-time-authority-stratum1`
- Package list:
  `profile-package-lists/stage5-metal-host-time-authority-stratum1.packages`
- Primary services: `chronyd`, `gpsd`
- Metrics: `chrony_exporter`
- Gated PTP tooling: `linuxptp`, `ethtool`

## Validation

- `chronyc tracking`
- `chronyc sources -v`
- `chronyc sourcestats -v`
- GNSS fix state through `gpsd`
- PPS device visibility through `/dev/pps*`
- NIC timestamp capability through `ethtool -T`

See `docs/CHANGE-CONTROL-STRATUM1-TIME-AUTHORITY.md` for the ITIL change plan.
