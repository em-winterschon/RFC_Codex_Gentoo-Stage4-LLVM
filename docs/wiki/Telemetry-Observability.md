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

## Remaining Work

1. Validate the native Gentoo metrics services on fresh VMs.
2. Validate the containerized IPMI and Redfish exporters on the live
   container-services host.
3. Tune vendor-specific SNMP walks and alert thresholds against real hardware.
