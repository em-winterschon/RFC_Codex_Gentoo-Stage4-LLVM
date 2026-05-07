# FMT2 Check_MK Transport

## Goal

Bring the existing FMT2 Check_MK VM into the managed observability plan after a
stable RFC99/SUN99 to FMT2 transport path exists.

## Legacy Evidence Dependency

Use `docs/FMT2-INFRA-UPGRADE-PLANNING.md` as the evidence index before making
FMT2 Check_MK or transport changes. The old SFO-200 wiki contains useful
references for Check_MK, Prometheus, HA routers, VLANs, OOB access, and rack
serial paths, but it is not authoritative until live validation confirms each
item.

Minimum evidence to confirm before Check_MK integration:

- selected transport path reaches at least one FMT2 management prefix
- DNS resolves `app-sfo200-monitoring-9927.vernetzen.io`
- Check_MK HTTPS endpoint answers on the expected `/vernetzen/` path
- Check_MK API endpoint and agent-download path are reachable
- return routing from FMT2 to RFC99/SUN99 works for management checks

## Preferred Path

Primary path: enable the BigNetwork SDN route to the FMT2 SDN device.

Rationale:

- lower operational risk than reimplementing the legacy OPNsense tunnel first
- keeps CCR2004 focused on routing/firewall duties
- avoids RouterOS OpenVPN feature mismatch with the old cert/static-key profile
- should be easier to validate with simple route and service checks

## Fallback Path

Fallback path: run a compatibility OpenVPN endpoint in a dedicated VyOS VM or
small Linux VM on Proxmox.

Do not use RouterOS as the compatibility OpenVPN endpoint unless no other path is
available. RouterOS should carry routes/firewall state for the tunnel, not be the
legacy VPN compatibility shim.

## Validation Gates

1. Confirm the selected transport endpoint is up.
2. Confirm RFC99/SUN99 can reach the FMT2 tunnel address.
3. Confirm FMT2 can route back to RFC99/SUN99 management prefixes.
4. Validate DNS resolution for FMT2 management names.
5. Run targeted nmap checks against Check_MK web/API and agent ports.
6. Add Check_MK VM/service records to NetBox after connectivity is stable.
7. Add route/firewall state to the managed inventory.
8. Compare live results against the legacy SFO-200 evidence map.
9. Only then add Check_MK targets and alerting dependencies.

## Backout

Disable the new route or tunnel endpoint and return to the pre-change RouterOS
route table. Check_MK integration must remain non-blocking until the transport is
stable for repeated validation windows.
