# Observability And Alternate Access

This repo now carries a Stage 5 scaffold for:

- `rsyslog` client shipping on managed hosts and VMs
- centralized `rsyslog` collection in a container role
- clustered `Elasticsearch` node profiles
- `Kibana` interface profiles
- containerized `Elastic APM` ingress
- generic `HAProxy` service-type catalog entries
- `NetBox` API inventory and IPAM snapshots
- `ZeroTier` alternate-access plumbing

## Roles

Native host and VM roles:

- `rsyslog_base`
- `elasticsearch_cluster`
- `kibana_interface`
- `netbox_connector`
- `zerotier_access`

Container application roles:

- `container_app_rsyslog_collector`
- `container_app_elastic_apm`

## Profile Layers

Reusable overlays:

- `logging-rsyslog-client`
- `netbox-managed-inventory`
- `zerotier-managed-access`
- `container-rsyslog-collector`
- `container-elastic-apm`

VM profiles:

- `vm-elasticsearch-node`
- `vm-kibana-interface`

## Current Intent

`rsyslog` is treated as the baseline host logging client. It can:

- listen locally when needed
- ship to a centralized collector over TCP or UDP
- use a consistent RFC5424-style forward template

The `container-rsyslog-collector` overlay renders a containerized collector that can:

- receive UDP and TCP syslog on port `514`
- normalize messages with `rsyslog`
- forward structured payloads to an Elasticsearch VIP

The `container-elastic-apm` overlay renders a containerized APM ingress that publishes to the Elasticsearch cluster.

## Elastic Layout

The example inventory now includes:

- `elasticsearch_nodes`
  - `vm_elasticsearch_node01`
  - `vm_elasticsearch_node02`
  - `vm_elasticsearch_node03`
- `kibana_interfaces`
  - `vm_kibana_interface`

The example cluster wiring uses:

- `stage5-observability` as the cluster name
- `elastic-vip.example.internal` as the client-facing Elasticsearch VIP
- `log-vip.example.internal` as the syslog shipping target

## HAProxy Service Types

The repo now supports `profile_haproxy_service_types` as a generic catalog.

This is intended to describe frontends and backends for:

- container services such as `ntfy`, `nginx`, `rsyslog`, and `elastic-apm`
- VM services such as `jenkins`, `elasticsearch`, `kibana`, and identity endpoints
- future metal-host published services where HAProxy is the front door

The current `container_app_haproxy` role renders this catalog additively. That
means an explicit service such as `syslog-tcp` does not suppress the default
HTTP frontend for `nginx` and `ntfy` when those runtime applications are
registered.

Live Path B validation on `10.9.8.89` currently confirms:

- `rsyslog-collector`, `nginx`, `ntfy`, and `haproxy` start from generated
  Podman wrappers.
- direct nginx ingress on `127.0.0.1:8080` returns HTTP `200`.
- HAProxy routes default HTTP traffic to nginx and `Host: ntfy.local` traffic
  to ntfy, both returning HTTP `200`.
- rsyslog collector receives UDP and TCP messages on port `514`.
- rsyslog Elasticsearch forwarding is pending the real
  `elastic-vip.example.internal` DNS/VIP target.

## NetBox

`netbox_connector` is intentionally package-light. It uses the Ansible `uri` module and renders:

- connector configuration under `/etc/stage5-inventory/netbox.d/`
- optional API snapshots under `/var/lib/stage5-inventory/netbox/`

That keeps IPAM and inventory synchronization inside the repo’s existing profile model without introducing a second inventory source of truth.

## ZeroTier

`zerotier_access` renders local configuration and a managed network manifest, then enables the native `zerotier` OpenRC service when the overlay is applied.

The current overlay is opt-in. It is not forced onto every example host yet.

## Remaining Work

1. Validate the native Gentoo `elasticsearch` and `kibana-bin` service behavior on a fresh VM.
2. Stand up the Elasticsearch VIP/cluster target and complete rsyslog
   end-to-end forwarding validation.
3. Extend `netbox_connector` from snapshots into push or reconciliation workflows if desired.
4. Decide which host classes should get `zerotier-managed-access` by default versus remaining opt-in.
