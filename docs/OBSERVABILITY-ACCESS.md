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
- `service_readiness`
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
- `container-haproxy-elasticsearch-test-vip`

VM profiles:

- `vm-elasticsearch-node`
- `vm-elasticsearch-test`
- `vm-kibana-interface`

## Current Intent

`rsyslog` is treated as the baseline host logging client. It can:

- listen locally when needed
- ship to a centralized collector over TCP or UDP
- use a consistent RFC5424-style forward template

The `container-rsyslog-collector` overlay renders a containerized collector that can:

- receive UDP and TCP syslog on port `514`
- normalize messages with `rsyslog`
- load `omelasticsearch`
- forward structured bulk payloads to an Elasticsearch VIP

The profile enforces `app-admin/rsyslog[elasticsearch]` and sets
`esVersion.major=9` for the current Elasticsearch test target.

The `container-elastic-apm` overlay renders a containerized APM ingress that publishes to the Elasticsearch cluster.

## Elastic Layout

The example inventory now includes:

- `elasticsearch_nodes`
  - `vm_elasticsearch_node01`
  - `vm_elasticsearch_node02`
  - `vm_elasticsearch_node03`
- `elasticsearch_test_nodes`
  - `vm_elasticsearch_test` on `10.9.8.91`
- `kibana_interfaces`
  - `vm_kibana_interface`

The example cluster wiring uses:

- `=app-misc/elasticsearch-9.3.1` as the native Gentoo-compatible Elasticsearch pin
- `stage5-observability` as the cluster name
- `elastic-vip.example.internal` as the client-facing Elasticsearch VIP
- `log-vip.example.internal` as the syslog shipping target

The Path B single-node test profile uses:

- `vm-elasticsearch-test` at `10.9.8.91`
- single-node discovery
- disabled Elasticsearch security and HTTP TLS for local lab ingestion tests
- `action.auto_create_index: stage5-*` for rsyslog bulk ingestion
- a `stage5-syslog*` index template with one shard and zero replicas for
  single-node lab health
- HAProxy test VIP `10.9.8.92:9200`, backed by the test node
- explicit `ES_JAVA_HOME=/opt/openjdk-bin-21.0.10_p7`
- `localmount` ordering for ZFS-backed Elasticsearch paths

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

The `container-haproxy-elasticsearch-test-vip` overlay adds a Path B test
frontend for Elasticsearch:

- host-side VIP command: resolve the default Path B interface with
  `ip -o route get 10.9.8.1`, then add `10.9.8.92/32` to that interface
- Podman published port: `10.9.8.92:9200:9200/tcp`
- HAProxy frontend: `*:9200`
- backend: `10.9.8.91:9200`

The CCR2004 gateway role now renders a SUN99-facing Elasticsearch/search VIP
without moving HAProxy into RouterOS containers:

- RouterOS service VIP: `172.16.99.92/32` on `br-lan`
- DNS: `obs-sun99-esvip-099092.rfc1918.host`
- CNAME: `obs-sun99-esvip.rfc1918.host`
- RouterOS DNAT: `172.16.99.92:9200` to
  `svc-container-services-safe-move-01` at `172.16.99.89:9200`
- temporary backend routes: `10.9.8.91/32` and `10.9.8.92/32` via
  `172.16.99.108` until Path B leaves the X12AGAIN transit path

RouterOS `7.22.3` and the `arm64` container package are cached under
`/opt/routeros/mikrotik-official` for future lab work, but production
observability ingress stays on the Stage4 HAProxy container-service role.

Additional HAProxy service-type definitions now exist for Jenkins, FreeIPA /
FreeRADIUS, Prometheus, Alertmanager, Grafana, Kibana, Elasticsearch,
Elasticsearch exporter, node exporter, Podman exporter, IPMI exporter,
Redfish exporter, rsyslog TCP, and Elastic APM.

## Service Readiness

`scripts/service_validator.py` wraps `nmap` and emits deterministic JSON for
TCP and UDP readiness checks. The `service_readiness` Ansible role runs those
checks through a modular task block, with per-check `target`, `port`,
`protocol`, `retries`, `delay`, and `allow_open_filtered` controls.

Example:

```bash
scripts/service_validator.py --target 10.9.8.92 --port 9200 --protocol tcp --service-name elasticsearch-test --json
```

`scripts/syslog_elasticsearch_validator.py` performs the deeper logging check:
it emits a unique RFC5424-style syslog marker, then queries Elasticsearch for
that marker in the configured index pattern and field. This catches receiver,
template, `omelasticsearch`, HAProxy, and Elasticsearch indexing regressions
that plain port checks cannot see.

Example:

```bash
scripts/syslog_elasticsearch_validator.py \
  --syslog-target 10.9.8.89 \
  --syslog-port 514 \
  --syslog-protocol tcp \
  --elasticsearch-url http://10.9.8.92:9200 \
  --index-pattern 'stage5-syslog*' \
  --field message \
  --json
```

The `service_readiness` role supports this as
`type: syslog_elasticsearch`; the Path B container-services inventory now runs
`rsyslog-elasticsearch-ingest` during `post_boot` validation.

Serial console helper mapping:

```bash
scripts/watch-vm-serial.sh --vm elasticsearch-test
```

Live Path B validation on `10.9.8.89` currently confirms:

- `rsyslog-collector`, `nginx`, and `haproxy` start from generated Podman
  wrappers.
- direct nginx ingress on `10.9.8.89:8080` returns HTTP `200`.
- HAProxy routes default HTTP traffic to nginx on `10.9.8.89:80`.
- rsyslog collector receives TCP messages on `10.9.8.89:514`.
- HAProxy exposes the Elasticsearch test VIP on `10.9.8.92:9200`.
- rsyslog collector forwards TCP syslog into Elasticsearch through the
  `10.9.8.92:9200` HAProxy VIP; a unique `forge-rsyslog-es-smoke-*` marker was
  searchable in `stage5-syslog.message`.
- ntfy is live on Hasslehoff VM `1089` behind HAProxy at
  `172.16.99.96:80`, with service names
  `msg-sun99-ntfysys-099096.rfc1918.host` and
  `msg-sun99-ntfysys.rfc1918.host`.

Live Elasticsearch validation on `10.9.8.91` currently confirms:

- `nmap` readiness reports `tcp/9200` open.
- Elasticsearch `9.3.1` responds on HTTP.
- cluster health is `green`.
- `elasticsearch_exporter` serves metrics on `tcp/9114`.
- test documents and rsyslog-ingested documents can be written to and read back
  from `stage5-syslog`, validating the index settings required by rsyslog
  `omelasticsearch`.

Live Kibana validation on `172.16.99.67` currently confirms:

- Hasslehoff VM `1067`, `obs-sun99-kibana-099067`, boots as a Stage4/OpenRC VM.
- Kibana `9.3.1` is installed from the verified Elastic upstream tarball because
  Gentoo `www-apps/kibana-bin-7.17.25` is incompatible with Elasticsearch
  `9.3.1`.
- `/api/status` returns HTTP `200` with overall level `available`.
- Elasticsearch is available through `http://10.9.8.92:9200`.
- CCR2004 render intent now adds SUN99 VIP
  `obs-sun99-esvip-099092.rfc1918.host` / `172.16.99.92` with DNAT to the
  container-services HAProxy listener, providing the planned non-Path-B client
  front door.
- the default Kibana data view is `stage5-syslog*` with `@timestamp`.
- OpenRC exports `TZ=UTC`; without that, Kibana's bundled Node runtime reports
  `Etc/Unknown` and Moment Timezone terminates the process.
- X12AGAIN currently carries a narrow temporary SNAT rule for
  `172.16.99.0/24 -> 10.9.8.0/24` over `br-pathb`; promote this to CCR2004
  routing or a production HAProxy frontend before treating Path-B Elasticsearch
  as a stable SUN99 dependency.

If an existing test index was created before the zero-replica template was
installed, apply the rendered helper and update the existing index settings:

```bash
/usr/local/sbin/stage5-elasticsearch-apply-index-templates
curl -XPUT http://127.0.0.1:9200/stage5-syslog/_settings \
  -H 'Content-Type: application/json' \
  -d '{"index":{"number_of_replicas":0}}'
```

The live rsyslog-to-Elasticsearch validation found and corrected one collector
template issue: `message` must be quoted in the rendered JSON while
`property(name="msg" format="json")` handles escaping. Without that correction,
`omelasticsearch` rejects bulk requests before they reach Elasticsearch.

## NetBox

`netbox_connector` is intentionally package-light. It uses the Ansible `uri` module and renders:

- connector configuration under `/etc/stage5-inventory/netbox.d/`
- optional API snapshots under `/var/lib/stage5-inventory/netbox/`

That keeps IPAM and inventory synchronization inside the repo’s existing profile model without introducing a second inventory source of truth.

## ZeroTier

`zerotier_access` renders local configuration and a managed network manifest, then enables the native `zerotier` OpenRC service when the overlay is applied.

The current overlay is opt-in. It is not forced onto every example host yet.

## Remaining Work

1. Promote the live rsyslog template fix through the normal container-services
   redeploy path so the mounted config is regenerated instead of hand-edited.
2. Promote the live Kibana upstream-tarball workflow into a full Ansible apply
   path, including persistent SUN99-to-Path-B routing through CCR2004 or a
   production HAProxy frontend.
3. Extend `netbox_connector` from snapshots into push or reconciliation workflows if desired.
