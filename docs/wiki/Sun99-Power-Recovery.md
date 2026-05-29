# SUN99 Power Recovery

## Post-Incident Recovery Gate

The SUN99 power incident exposed a bad failure mode: the rack ATS was expected
to bridge a utility-side drop, but several systems and switches still power
cycled. The recovery gate is `scripts/validate-sun99-power-recovery.sh`.

Use repo-only mode in CI:

```bash
SUN99_POWER_SKIP_LIVE=1 scripts/validate-sun99-power-recovery.sh
```

Use notification mode during operator recovery:

```bash
SUN99_POWER_NOTIFY=1 scripts/validate-sun99-power-recovery.sh
```

The validator is read-only and checks Hasslehoff service VM autostart, M70
chronyd/OpenVPN/ZFS health, K10 reachability, ntfy HTTP/HTTPS health, and
management reachability for the known SUN99 power/OOB endpoints.

## Resolved Follow-Up

- Hasslehoff core service VMs were restarted and now have explicit autostart
  policy.
- M70 recovered, has chronyd running, and still carries the temporary FMT2
  OpenVPN transport.
- K10 recovered and is reachable; durable SSSD enrollment remains separate
  Stage5 work.
- Local ntfy works over HTTP and HTTPS.

## Power Inventory To Audit

| Address | Current evidence | Audit status |
| --- | --- | --- |
| `172.16.99.241` | APC AP7901 PDU, `pdu-rfc99-corectrl-p08-099241` | reachable and usable for outlet recovery |
| `172.16.99.242` | APC/Schneider network card | identify as APC SRT1500RMXLA or ATS/PDU member |
| `172.16.99.244` | APC/Schneider network card | identify as APC SRT1500RMXLA or ATS/PDU member |
| `172.16.99.250` | Zyxel management switch | reachable; not a power device |

## CyberPower USB Plan

Cable the CyberPower CP1500PFCRM2U USB port to
`admin-sun99-forge-099070.rfc1918.host` first. Use NUT with `usbhid-ups`,
then publish read-only metrics through node_exporter textfile output after
`upsc` exposes model, serial, charge, runtime, voltage, load, and status.

M70 read-only telemetry runs `upsdrv` and `upsd` only. The `upsmon` shutdown
path is intentionally disabled. node_exporter scrapes
`/var/lib/node_exporter/nut_ups.prom` for metrics prefixed
`rfc1918_nut_ups_`.

Do not enable automated shutdown from the CyberPower path until ATS transfer
behavior and alerting are understood.

## APC Network Plan

Use the APC SRT1500RMXLA/AP9641 network module for APC UPS telemetry. Existing
APC-compatible `apcupsd` configs from FMT2 are useful references, but Prometheus
SNMP exporter coverage should become the steady-state metrics path for APC UPS,
PDU, and ATS devices.

The AP7901 is legacy firmware. Keep it TLS-exempt and manage it through SNMP,
serial, or plain HTTP.

## Blackbox Position

Moving the Blackbox Infrastructure Manager into SUN99 is useful, but not the
first recovery dependency. Prioritize network power control, CyberPower USB/NUT,
APC device identity, and exporter coverage first. Move Blackbox when serial
rescue/configuration is needed for ATS/PDU/UPS devices or when there is a
dedicated serial audit window.
