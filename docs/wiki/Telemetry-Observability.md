# Telemetry And Observability

This repo now carries a Stage 5 telemetry scaffold based on:

- `Prometheus` for metrics scrape and rule evaluation
- `VictoriaMetrics` for single-node long-retention metrics storage
- `collectd` for legacy host/service metrics aggregation and Graphite forwarding
- `Alertmanager` for grouping, routing, silencing, and inhibition
- `Grafana` for metrics dashboards
- native exporters where Gentoo packages exist
- containerized exporters where native Gentoo packaging is absent

## Roles

Native metrics roles:

- `telemetry_node_exporter`
- `telemetry_podman_exporter`
- `telemetry_elasticsearch_exporter`
- `telemetry_blackbox_exporter`
- `telemetry_snmp_exporter`
- `telemetry_collectd`
- `telemetry_victoriametrics`
- `telemetry_prometheus`
- `telemetry_alertmanager`
- `telemetry_grafana`

Containerized exporter roles:

- `container_app_ipmi_exporter`
- `container_app_redfish_exporter`

## Profile Layers

Reusable overlays:

- `telemetry-node-exporter-client`
- `telemetry-collectd-client`
- `telemetry-podman-exporter`
- `telemetry-elasticsearch-exporter`
- `container-ipmi-exporter`
- `container-redfish-exporter`

VM profiles:

- `vm-observability-prometheus`
- `vm-observability-victoriametrics`
- `vm-observability-grafana`

## Collection Model

The current model is intentionally split by scope:

- host and VM baseline metrics:
  - `node_exporter`
- legacy host/service counters and central aggregation:
  - `collectd`
- container-host and pod/container runtime metrics:
  - `prometheus-podman-exporter`
- clustered Elasticsearch metrics:
  - `elasticsearch_exporter`
- service-role reachability and protocol checks:
  - `blackbox_exporter`
- network and power device metrics:
  - `snmp_exporter`
- BMC and chassis metrics over IPMI:
  - containerized `ipmi_exporter`
- server health, power, and sensor metrics over Redfish:
  - containerized `redfish-exporter`

Prometheus remote-writes scrape data to VictoriaMetrics. collectd agents forward
to the VictoriaMetrics VM, where collectd writes Graphite-format samples into
VictoriaMetrics and exposes a Prometheus scrape endpoint.

VictoriaMetrics stores data under `/srv/metrics/victoriametrics`, modeled as a
managed NFSv3 mount that can later move to NFSv4/RDMA.

## Current Example Topology

The example inventory now includes:

- `observability_prometheus`
  - `vm_observability_prometheus`
- `observability_victoriametrics`
  - `vm_observability_victoriametrics`
- `observability_grafana`
  - `vm_observability_grafana`
- `container_service_hosts`
  - `vm_container_services`

The example Prometheus group vars demonstrate:

- node scrape jobs for VMs, builder nodes, and service hosts
- Prometheus `remote_write` to VictoriaMetrics
- collectd aggregation and Graphite ingest
- `podman_exporter` scrape for the container-services host
- `elasticsearch_exporter` scrape for the three-node cluster
- HTTP and TCP blackbox probes for:
  - HAProxy
  - nginx
  - APM ingress
  - Kibana
  - Jenkins
  - FreeIPA web endpoints
  - syslog and distcc TCP endpoints
- SNMP jobs for:
  - APC `SRT1500RMXLA-NC`
  - CyberPower `CP1500PFCRM2U`
  - Eaton `OMNI1500LCDT`
  - APC `AP4450`
  - APC `AP7901`
  - APC `AP7902`
  - Black Box `LES1248A-R2`
- IPMI jobs for builder-farm and hypervisor BMC endpoints
- Redfish jobs for health and performance endpoints

## SUN99 Live Deployment State

The local-network inventory now reserves the first live observability VM set on
Hasslehoff:

- `obs-sun99-prometheus-099064.rfc1918.host`
  - IP `172.16.99.64`
  - Proxmox VMID `1064`
  - CNAME `obs-sun99-prometheus.rfc1918.host`
- `obs-sun99-vmetrics-099065.rfc1918.host`
  - IP `172.16.99.65`
  - Proxmox VMID `1065`
  - CNAME `obs-sun99-vmetrics.rfc1918.host`
- `obs-sun99-grafana-099066.rfc1918.host`
  - IP `172.16.99.66`
  - Proxmox VMID `1066`
  - CNAME `obs-sun99-grafana.rfc1918.host`

The corresponding DNS RRsets are tracked in
`inventories/local-network/group_vars/all/dns_hetzner_cloud.yml`, and the same
objects are modeled in the local NetBox intake file before live provisioning.

VictoriaMetrics persistence is intentionally separated from the VM disk:

- provider: `hasslehoff`
- NFS export: `/srv/exports/metrics/victoriametrics`
- client mountpoint: `/srv/metrics/victoriametrics`
- default transport: NFSv3/TCP

Future protocol flags for NFSv4 UID/GID/RBAC consistency, NFS-RDMA, and NFS
multipath are recorded in
`inventories/local-network/group_vars/all/observability_metrics_storage.yml`.

As of the current live rollout:

- Hetzner DNS records for the canonical hostnames and short CNAMEs have been
  applied.
- NetBox inventory intake has been applied and validated for the three
  observability VMs.
- Hasslehoff exports `/srv/exports/metrics/victoriametrics` to
  `172.16.99.65` over NFS.
- Proxmox VMs `1064`, `1065`, and `1066` are created from the populated Stage4
  service image, have grown root filesystems, and answer on their static SUN99
  management IPs.
- The cloned Stage4 service image does not currently consume Proxmox cloud-init
  metadata inside Gentoo. Static OpenRC networking is materialized with
  `scripts/proxmox-materialize-gentoo-openrc-static-net.sh` until the base image
  gains a durable cloud-init or firstboot path.
- The Prometheus VM is live with Prometheus, Alertmanager, blackbox_exporter,
  snmp_exporter, and node_exporter listening on their service ports. Prometheus
  is scraping its local exporters plus the observability VM targets and
  remote-writing to VictoriaMetrics.
- The Grafana VM is live with `grafana-bin`, node_exporter, provisioned
  Prometheus/VictoriaMetrics datasource definitions, and a baseline SUN99
  overview dashboard.
- The first live VictoriaMetrics package pass hit a reproducible protobuf
  compile OOM because the guest inherited `ninja -j64`. The
  `vm-observability-victoriametrics` profile now pins conservative
  `MAKEOPTS`/`NINJAOPTS`/`NINJAFLAGS` for service-VM builds.
- collectd is explicitly built without `rrdtool` or `rrdcached` plugins for
  this profile. Metrics retention is handled by VictoriaMetrics, so pulling in
  RRDTool adds an unnecessary linker-sensitive dependency.
- The VictoriaMetrics VM is live with the Hasslehoff NFSv3/TCP export mounted,
  VictoriaMetrics listening on HTTP and Graphite ports, node_exporter running,
  and collectd exporting both write_prometheus and write_graphite samples.
- Grafana datasource health checks pass for both Prometheus and VictoriaMetrics.

## Remaining Work

1. Validate the native Gentoo metrics services on fresh VMs.
2. Validate the containerized IPMI and Redfish exporters on the live
   container-services host.
3. Tune vendor-specific SNMP walks and alert thresholds against real hardware.
4. Convert the live service-package bridge into a first-class post-install
   Ansible apply path so fresh Stage4 service VMs do not need manual Portage
   commands after provisioning.
5. Add CA trust handling for HTTPS ntfy notifications so local HTTPS notices do
   not require explicit insecure transport during bootstrap.
