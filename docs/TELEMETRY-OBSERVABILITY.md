# Telemetry And Observability

This repo now carries a Stage 5 telemetry scaffold based on:

- `Prometheus` for metrics scrape and rule evaluation
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
- `telemetry_prometheus`
- `telemetry_alertmanager`
- `telemetry_grafana`

Containerized exporter roles:

- `container_app_ipmi_exporter`
- `container_app_redfish_exporter`

## Profile Layers

Reusable overlays:

- `telemetry-node-exporter-client`
- `telemetry-podman-exporter`
- `telemetry-elasticsearch-exporter`
- `container-ipmi-exporter`
- `container-redfish-exporter`

VM profiles:

- `vm-observability-prometheus`
- `vm-observability-grafana`

## Collection Model

The current model is intentionally split by scope:

- host and VM baseline metrics:
  - `node_exporter`
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

This keeps the repo aligned with the Stage 4 / Stage 5 layering:

- `Stage 4` remains the shared hardened Gentoo baseline
- `Stage 5` adds workload telemetry, alerting, and service probes

## Current Example Topology

The example inventory now includes:

- `observability_prometheus`
  - `vm_observability_prometheus`
- `observability_grafana`
  - `vm_observability_grafana`
- `container_service_hosts`
  - `vm_container_services`

The example Prometheus group vars demonstrate:

- node scrape jobs for VMs, builder nodes, and service hosts
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

## Power And Device Notes

The current SNMP scaffold favors conservative, low-risk modules:

- `stage5_rfc1628_ups`
- `stage5_apc_powernet`
- `stage5_blackbox_oob`
- `stage5_if_mib`

That is enough to stand up collection and exporter availability checks without
pretending the repo has already finished vendor-specific MIB tuning for every
SKU.

The example alert rules focus on:

- exporter / scrape availability
- HTTP probe failure
- TCP probe failure
- host filesystem pressure
- host memory pressure

Vendor-specific threshold alerts for battery runtime, transfer state, branch
load, feed redundancy, and PSU sensor conditions should be added after the
target devices are walked and their preferred OIDs are validated.

## Raw Scrape Config Policy

`telemetry_prometheus` intentionally accepts raw Prometheus `scrape_configs`
from inventory and profile policy.

That means the repo does not hide scrape logic behind a custom abstraction.
Operators can use the full Prometheus configuration model for:

- `static_configs`
- `params`
- `relabel_configs`
- multi-target exporter patterns
- custom job labels

This is deliberate because SNMP, IPMI, Redfish, and blackbox jobs often need
fine-grained relabeling and target-specific parameters.

## Remaining Work

1. Validate the native Gentoo `prometheus`, `alertmanager`, `blackbox_exporter`,
   `snmp_exporter`, `node_exporter`, `elasticsearch_exporter`, and `grafana-bin`
   service behavior on fresh VMs.
2. Validate the `prometheuscommunity/ipmi-exporter` container on the live
   container-services host.
3. Validate the `sapcc/redfish-exporter` container image choice or replace it
   with an internally built image if the upstream image path is unsuitable.
4. Walk the listed APC, CyberPower, Eaton, and Black Box devices and refine the
   SNMP modules and alert rules around real OIDs and threshold policy.
5. Decide whether Prometheus remains standalone or later remote-writes into a
   longer-retention backend.
