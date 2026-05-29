# MCP Control Plane Design

## Purpose

The MCP control plane tracks which Model Context Protocol servers are allowed
inside the infrastructure automation environment, how they are audited, and what
operations they may perform. The first implementation is intentionally
render-only: it creates repo-managed policy and candidate registry files, not a
running MCP gateway with mutation authority.

## Design

The control plane uses a conservative promotion pipeline:

`Discovery -> audit -> pin -> sandbox -> smoke test -> vault-backed auth -> audit logging -> gated writes`

Every MCP candidate starts in `quarantine` or `candidate` state. Default mode is
read-only. Any integration that can mutate infrastructure, CI state, tickets,
VMs, Kubernetes/OpenShift clusters, or observability config requires explicit
change-control promotion before write operations are enabled.

## Candidate Classes

The first-batch registry tracks:

- Hugging Face MCP for model, dataset, Space, and paper discovery.
- Trac MCP for ticket, milestone, wiki, and change-control integration.
- NetBox MCP for read-only IPAM/DCIM source-of-truth queries.
- Grafana MCP for observability queries with `--disable-write`.
- Jenkins MCP for CI/build context, initially read-only.
- Proxmox MCP for virtualization inventory only until destructive gates exist.
- Context7 MCP for documentation lookup and context freshness.
- Kubernetes/OpenShift MCP as a deferred candidate for future OpenShift service
  profiles and cluster validation.

## Security Model

The role renders three files under `/etc/mcp-control-plane` by default:

- `candidate-registry.yml`: candidates, sources, risk tiers, allowed operations,
  auth methods, and promotion state.
- `promotion-policy.yml`: promotion stages, required evidence, and write gates.
- `mcp-control-plane.env`: non-secret runtime hints for later service wrappers.

Secrets stay in Ansible Vault and are referenced by variable name only. The
registry deliberately records source URLs and intent but does not import tokens,
private keys, passwords, client certificates, or API secrets.

## OpenShift And OpenStack Track

OpenShift and OpenStack are platform-service profiles, not MCP servers. They
belong in the broader automation roadmap because MCP and service orchestration
will eventually need controlled cluster visibility. OpenShift should be modeled
first as a VM-hosted single-node OpenShift/OKD appliance using the vendor
installer and RHCOS/FCOS-style node OS expectations, with Gentoo/OpenRC acting
as the hypervisor and automation fabric. OpenStack requires a separate
Gentoo/OpenRC feasibility review before we decide whether to run service daemons
natively or treat it as a VM-hosted appliance on an upstream-supported OS.

## Acceptance Criteria

- The registry and policy are generated from profile data.
- Default operation mode is read-only.
- Write-capable tools have explicit promotion gates.
- The candidate set includes the first-batch MCP servers selected for audit.
- OpenShift/OpenStack requirements are tracked as platform-service TODOs without
  forcing unsupported Gentoo/OpenRC assumptions into this branch.
