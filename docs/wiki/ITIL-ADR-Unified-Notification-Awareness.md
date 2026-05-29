# ITIL ADR: Unified Notification Awareness Engine

Status: proposed.

Adopt local ntfy as the internal notification bus, HAProxy as the TLS edge,
Shoutrrr as the outbound fanout adapter, and a future notification-gateway as
the normalization layer for webhooks, build events, E2ET reports, service-SLO
checks, and operator approval prompts.

Key decisions:

- local ntfy remains canonical for LAN notifications
- public `ntfy.sh` fallback is not used for infrastructure-critical alerts
- Shoutrrr provides multi-provider fanout
- UnifiedPush is supported first through self-hosted ntfy
- NextPush is deferred until Nextcloud is a core service dependency
- secrets and destination URLs stay in Ansible Vault
- rsyslog and Prometheus track delivery audit and metrics

Primary service:

- `msg-sun99-ntfysys-099096.rfc1918.host`
- `msg-sun99-ntfysys.rfc1918.host`
- `172.16.99.96`

Initial topics:

- `forge-change`
- `forge-build`
- `forge-e2et`
- `forge-net`
- `forge-obs`
- `forge-security`
- `forge-emergency`

Implementation order:

1. Validate local ntfy over HTTP and HTTPS and remove public fallback usage.
2. Add vault-backed topic, token, Shoutrrr URL, and webhook signing schemas.
3. Provision ntfy topic/token policy with Ansible.
4. Add Shoutrrr service role behind HAProxy.
5. Add minimal notification-gateway profile and event schema.
6. Wire build, E2ET, RouterOS backup, and SLO validation producers.
7. Add rsyslog audit logging and Prometheus metrics.

Canonical document:

- `docs/CHANGE-CONTROL-NOTIFICATION-AWARENESS.md`
