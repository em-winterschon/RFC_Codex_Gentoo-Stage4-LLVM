# SUN99 Power Recovery

## Post-Incident Recovery Gate

The SUN99 power incident exposed a bad failure mode: the rack ATS was expected
to bridge a utility-side drop, but several systems and switches still power
cycled. The immediate recovery target is therefore not just "hosts are back",
but a repeatable gate that proves core automation, notification, transport,
and power-control paths survived the event.

Run the read-only gate from this repo:

```bash
scripts/validate-sun99-power-recovery.sh
```

For repo-only CI checks:

```bash
SUN99_POWER_SKIP_LIVE=1 scripts/validate-sun99-power-recovery.sh
```

For operator-visible status:

```bash
SUN99_POWER_NOTIFY=1 scripts/validate-sun99-power-recovery.sh
```

After the CyberPower USB cable is connected to the M70, require USB detection:

```bash
SUN99_POWER_EXPECT_CYBERPOWER_USB=1 scripts/validate-sun99-power-recovery.sh
```

The script must not mutate hosts, outlets, routes, services, or secrets. It
validates Hasslehoff service VM autostart, M70 chronyd/OpenVPN/ZFS health, K10
reachability, ntfy HTTP/HTTPS health, and management reachability for the known
SUN99 power/OOB endpoints.

## Resolved Follow-Up

- Hasslehoff recovered after its reboot and the critical service VMs were
  restarted.
- Hasslehoff core service VMs now have explicit `onboot` and ordered `startup`
  policy so a future Proxmox host reboot should restore NetBox, FreeIPA,
  observability, netboot, container services, Elasticsearch, and Kibana without
  manual VM starts.
- The M70 recovered after AP7901 outlet control and now has `chronyd` installed
  and started so time drift does not corrupt Kerberos, TLS, logs, or Git
  evidence.
- K10 recovered after AP7901 outlet control and is reachable again. Its SSSD
  state remains a known Stage5 firstboot/enrollment issue, not a power recovery
  blocker.
- Local ntfy is healthy over HTTP and HTTPS, so power recovery and audit events
  can be published without falling back to the public `ntfy.sh` service.

## Power Inventory To Audit

Known or suspected SUN99 endpoints:

| Address | Current evidence | Audit status |
| --- | --- | --- |
| `172.16.99.241` | APC AP7901 PDU, `pdu-rfc99-corectrl-p08-099241` | reachable and usable for SNMP-backed outlet actions |
| `172.16.99.242` | APC/Schneider network card, HTTPS management observed | identify as APC SRT1500RMXLA or ATS/PDU member |
| `172.16.99.244` | APC/Schneider network card, HTTPS management observed | identify as APC SRT1500RMXLA or ATS/PDU member |
| `172.16.99.250` | Zyxel management switch | reachable; not a power device |

The APC SRT1500RMXLA with AP9641 should be monitored through network SNMP and
existing APC tooling. The APC PDU and ATS families remain candidates for
`apcupsd` where the daemon has correct support, and for SNMP exporter coverage
where Prometheus should scrape power telemetry.

## CyberPower USB Plan

The CyberPower CP1500PFCRM2U has no network module, so its first supported
automation path should be USB to a stable administrative host. Use the M70
first because it is already the near-term automation-admin node and should stay
powered from the protected rack feed.

Recommended operator action:

```text
Cable CyberPower CP1500PFCRM2U USB -> admin-sun99-forge-099070.rfc1918.host
```

Recommended software path:

- Install `sys-power/nut` on the M70.
- Use NUT `usbhid-ups` for the CyberPower CP1500PFCRM2U.
- Add a Prometheus NUT exporter after `upsc` reports model, serial, charge,
  runtime, line voltage, load, and status.
- Do not enable automated host shutdown from the CyberPower feed until the ATS
  cutover behavior is understood and alerting has been tested.

This is preferable to forcing `apcupsd` onto the CyberPower path because NUT is
the more general USB-HID UPS integration point and can coexist with APC-specific
network monitoring.

## APC Network Plan

Use the APC SRT1500RMXLA/AP9641 network module as the primary APC UPS
telemetry source. The initial audit should collect:

- device identity, model, serial, firmware, management IP, DNS name, and clock
- outlet/load state, input source, transfer events, battery charge/runtime, and
  self-test status
- supported SNMP versions and exporter OIDs
- whether `apcupsd` should be the operational client or only a compatibility
  reference for existing FMT2 configurations
- RADIUS readiness with local break-glass retained

The AP7901 is old firmware and should remain TLS-exempt. Use SNMP, serial, or
plain HTTP only for that device; do not spend time trying to force modern TLS.

## Blackbox Position

Moving the Blackbox Infrastructure Manager into SUN99 is useful but not the
first recovery dependency. The current priority order is:

1. Keep AP7901 network/SNMP power control working for remote outlet recovery.
2. Cable the CyberPower USB feed to M70 and validate NUT.
3. Identify the APC network devices at `172.16.99.242` and `172.16.99.244`.
4. Add Prometheus/NUT/APC exporter coverage and alerting.
5. Move Blackbox into SUN99 when serial rescue is needed for ATS/PDU/UPS
   configuration, or when a dedicated serial audit window is available.

The Blackbox should not block the immediate recovery closeout because the
network power-control path already recovered M70 and K10.

## Next Audit Actions

- Create NetBox non-secret device records for the APC UPS, ATS, second PDU if
  present, and CyberPower UPS after identity is confirmed.
- Add DNS names for confirmed management IPs.
- Tune Prometheus SNMP exporter modules for APC PDU, APC UPS, APC ATS, and
  Zyxel management switch telemetry.
- Add NUT exporter coverage for the CyberPower CP1500PFCRM2U after USB is
  cabled.
- Add FreeIPA/FreeRADIUS client records for APC management devices only after
  local break-glass login is verified.
- Review ATS transfer settings and event logs to determine why Path-A to Path-B
  transfer did not keep all loads online during the outage.
