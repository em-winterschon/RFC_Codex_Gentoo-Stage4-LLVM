# Morning SITREP Next Steps - 2026-05-08

This document converts the current morning planning thread into executable
dependencies. It deliberately avoids starting every subsystem at once; the goal
is sequencing with clear removal conditions.

| ID | Priority | Task | Dependency | Removal Condition |
| --- | --- | --- | --- | --- |
| `MORN-001` | high | Promote NetBox-driven inventory as the provisioning source of truth | NetBox API, existing intake files, DNS report | NetBox export can generate host bootstrap inventory, DNS targets, and service validation targets without manual copy/paste. |
| `MORN-002` | high | Define common-to-all base system services | existing Stage5 profile taxonomy | Base profile has explicit rsyslog, node exporter, ntfy alerting, SSSD/AAA client, NTP/chrony, TLS trust, package repo, and health-check policy. |
| `MORN-003` | high | Define service-role overlay services | `MORN-002` | Each Stage5 service profile declares only its role-specific packages, ports, SLO checks, HAProxy entries, logs, metrics, and backup requirements. |
| `MORN-004` | high | Advance centralized AAA | FreeIPA/SSSD/RADIUS baseline | Non-root accounts use centralized identity; SSH key sprawl is replaced with SSSD/FreeIPA policy; network devices remain RADIUS-first with TACACS+ deferred. |
| `MORN-005` | medium | Evaluate Trac as Kanban, change-control, wiki, and issue plane | Trac service profile branch, Trac MCP evaluation | Trac service profile has HAProxy/TLS/VIP plan, workflow fields, backup plan, and read-only MCP smoke-test. |
| `MORN-006` | medium | Track GitHub-to-Codeberg mirror and repo rename plan | current GitHub PR branch state | Mirror plan defines remote names, token/vault needs, branch protections, wiki sync, and candidate repo name such as `rfc1918-platform-fabric`. |
| `MORN-007` | medium | Keep MCPs read-only until promoted | MCP control-plane registry | Candidate audit is complete and first smoke tests are limited to Context7, NetBox, Grafana read-only, and Hugging Face. |
| `MORN-008` | medium | Prepare FMT2 discovery once BigNetwork L2 is active | BigNetwork token, legacy wiki evidence | FMT2 hosts/prefixes are discovered, tagged with evidence source, and staged for NetBox apply. |

## Execution Preference

1. Finish `MORN-001` and `MORN-002` first because they reduce manual effort
   across all later tasks.
2. Run Trac and MCP work in read-only mode until central AAA and TLS are stable.
3. Treat Codeberg mirror and repo rename as repository governance, not a blocker
   for infra provisioning.
4. Keep OpenShift/OpenStack as platform-service design tracks until their VM
   sizing, storage, DNS, and service assumptions are documented.
