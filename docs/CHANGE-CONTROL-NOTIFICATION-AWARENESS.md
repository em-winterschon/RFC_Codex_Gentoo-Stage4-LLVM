# ITIL ADR: Unified Notification Awareness Engine

## Document Control

- Change title: Unified notification fanout for LAN services, mobile devices, and webhook sources
- Change type: Normal change, standard-change candidate after first successful production validation
- ADR status: Proposed
- Primary service: `msg-sun99-ntfysys-099096.rfc1918.host`
- Primary alias: `msg-sun99-ntfysys.rfc1918.host`
- Primary IP: `172.16.99.96`
- Existing transport: self-hosted ntfy over HTTP and HTTPS
- Supersedes: public `https://ntfy.sh` fallback for infrastructure-critical alerts

## Context

The current local ntfy service already provides a low-friction publish and
subscribe path for infrastructure work. The public `ntfy.sh` fallback caused
rate-limit exposure against the site WAN address, so infrastructure-critical
notifications must stay on local services by default. The next design needs to
support direct ntfy topics, mobile push, webhooks from source-control systems,
service health events, build notifications, and future outbound adapters without
hard-coding every destination into every producer.

Reviewed option sources:

- ntfy server configuration, access control, cache, TLS/proxy, health checks,
  and monitoring: `https://docs.ntfy.sh/config/`
- ntfy API and integrations: `https://docs.ntfy.sh/subscribe/api/`,
  `https://docs.ntfy.sh/integrations/`
- UnifiedPush ntfy distributor:
  `https://unifiedpush.org/users/distributors/ntfy/`
- NextPush / Nextcloud UnifiedPush option:
  `https://unifiedpush.org/users/distributors/nextpush/`
- Shoutrrr service fanout and ntfy target support:
  `https://containrrr.dev/shoutrrr/v0.8/services/overview/`,
  `https://containrrr.dev/shoutrrr/v0.8/services/ntfy/`
- Forgejo/Codeberg-style webhook reference:
  `https://forgejo.org/docs/latest/user/webhooks/`

## Decision

Adopt a layered notification architecture:

1. Local ntfy is the canonical internal publish/subscribe bus.
2. HAProxy terminates TLS and routes both HTTP and HTTPS access to the ntfy
   backend.
3. A small notification-gateway service accepts normalized webhook/event JSON,
   applies routing policy, and publishes to ntfy plus optional downstream
   adapters.
4. Shoutrrr is the preferred outbound fanout adapter for services such as
   Pushover, Matrix, Google Chat, generic webhooks, email, and ntfy-compatible
   endpoints.
5. UnifiedPush is supported through self-hosted ntfy first; NextPush is a later
   option only if Nextcloud becomes a core service dependency.
6. Secrets, destination URLs, topic tokens, webhook signing secrets, and mobile
   push credentials live in Ansible Vault, not in NetBox, docs, or GitHub
   issues.

This keeps simple producers simple: most services publish either an ntfy
message or a normalized event to the gateway. The gateway handles routing,
dedupe, severity mapping, and destination fanout.

## Options Considered

### Option A: ntfy Only

Use local ntfy topics directly from all services.

Advantages:

- simplest operational model
- already deployed locally
- low friction for curl, scripts, phones, and browser clients

Disadvantages:

- producers must know topic naming and auth policy
- weak abstraction for multi-destination fanout
- no central place for routing, dedupe, or severity translation

### Option B: ntfy plus Shoutrrr Fanout

Use ntfy for internal pub/sub and Shoutrrr as a local multi-provider outbound
adapter.

Advantages:

- keeps ntfy as the primary LAN-native path
- adds many outbound destinations without each producer learning every API
- supports generic webhook output for services not modeled yet

Disadvantages:

- requires URL/credential policy hygiene
- Shoutrrr delivery errors need monitoring and retry policy

### Option C: Full Notification Gateway

Add an internal notification-gateway service in front of ntfy and Shoutrrr.

Advantages:

- single normalized API for service alerts, build events, approvals, and
  operator notifications
- can validate HMAC signatures on inbound webhooks
- can dedupe noisy events, enforce topic policy, and route by severity or
  service ownership
- can publish audit logs to rsyslog/Elasticsearch and metrics to Prometheus

Disadvantages:

- more code and operational surface area
- must be treated as infrastructure-critical after adoption

Recommended path: implement Option B immediately and design Option C as the
stable target. Option A remains the minimum viable fallback.

## Target Architecture

```text
Producers
├── Ansible / Jenkins / Forge scripts
├── GitHub / Forgejo / Codeberg webhooks
├── Prometheus / Alertmanager / Check_MK
├── E2ET / SLO validators
├── RouterOS / switch backup jobs
└── human approval tools
    │
    ├── direct ntfy publish for simple low-risk events
    │
    └── notification-gateway for normalized events
          ├── topic policy and authz
          ├── dedupe / rate control / severity mapping
          ├── audit log to rsyslog
          ├── metrics exporter
          ├── ntfy publish
          └── Shoutrrr fanout
                ├── Pushover / mobile fallback
                ├── Matrix / chat
                ├── generic webhooks
                └── email or other integrations
```

## Topic Policy

Initial topics:

- `forge-change`: change-control prompts and approvals
- `forge-build`: build start, failure, retry, and completion events
- `forge-e2et`: host validation and conformance results
- `forge-net`: network config backup, router/switch changes, link-state gates
- `forge-obs`: observability pipeline readiness and alerting system status
- `forge-security`: auth, vault, certificate, and RBAC/AAA-sensitive events
- `forge-emergency`: paging-grade operator interruption path

Topic access defaults:

- anonymous read/write is denied
- producers use scoped publish tokens
- operator devices use scoped subscribe tokens
- emergency topics require explicit subscription
- all topic-token material is generated from vault-backed variables

## Implementation Sequence

1. Confirm ntfy local HTTP and HTTPS endpoints both work and remove public
   `ntfy.sh` fallback from automation.
2. Add vault schema for notification topics, ntfy tokens, Shoutrrr URLs,
   webhook signing secrets, and operator-device subscriptions.
3. Add Ansible role or role extension for ntfy topic/token provisioning.
4. Add Shoutrrr container/VM profile as a fanout adapter behind HAProxy.
5. Add a minimal notification-gateway service profile and OpenAPI-style event
   contract.
6. Wire first producers:
   `scripts/ntfy-tools`, E2ET reports, build wrappers, RouterOS config backup,
   and service-SLO validation.
7. Add Prometheus metrics and rsyslog logs for notification delivery success,
   retries, drops, and fanout latency.
8. Add Forgejo/Codeberg/GitHub webhook receiver support after HMAC validation
   and replay protection are implemented.
9. Add UnifiedPush mobile validation through self-hosted ntfy.
10. Evaluate NextPush only after Nextcloud is a deployed, monitored, and
    HAProxy-managed service.

## Validation Plan

- `curl` publish to each initial ntfy topic returns success over HTTP and HTTPS.
- operator device receives test notifications for normal and emergency topics.
- Shoutrrr dry-run or test mode publishes to ntfy and one non-ntfy sink.
- gateway rejects unsigned or incorrectly signed webhooks.
- duplicate event IDs are suppressed within the configured dedupe window.
- failure to reach an optional downstream sink does not block local ntfy
  delivery.
- rsyslog receives delivery audit events.
- Prometheus scrapes delivery counters and failure metrics.
- E2ET and build wrappers can publish start, failure, and completion events
  without external WAN dependencies.

## Risk Controls

- Keep local ntfy direct publish available as the fallback path.
- Keep public ntfy disabled for infrastructure-critical notifications.
- Use HAProxy health checks before switching service aliases.
- Use short-lived or revocable tokens for experimental producers.
- Do not store secrets in NetBox custom fields or docs.
- Avoid push loops by tagging gateway-generated messages and dropping recursive
  webhook events.
- Rate-limit noisy producers before fanout to mobile or chat destinations.

## Backout Plan

1. Disable notification-gateway ingress in HAProxy.
2. Stop Shoutrrr fanout service.
3. Revert producers to direct local ntfy publish.
4. Preserve ntfy cache/auth data for forensic review.
5. Revoke experimental tokens from vault-generated ntfy config.
6. Keep `forge-emergency` local ntfy path available unless ntfy itself is the
   failed component.

## Open Decisions

- Whether notification-gateway should be a small Python service, Go service, or
  HAProxy-backed webhook router with scripts.
- Whether Alertmanager should publish directly to ntfy or always traverse the
  gateway.
- Whether Matrix should be the first chat sink or remain deferred until central
  auth and service inventory are fully stable.
- Whether Nextcloud/NextPush is worth the dependency cost before Nextcloud has a
  separate business requirement.

## Initial Recommendation

Proceed with local ntfy hardening and Shoutrrr fanout first. Defer Nextcloud
and NextPush. Build notification-gateway as a small, auditable internal service
only after topic/token policy is stable and at least three producers are using
the common event schema.
