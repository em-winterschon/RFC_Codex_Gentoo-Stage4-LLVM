# CI Builder Farm

## Purpose

This document defines the first repo-native CI/CD topology for:

- Jenkins as the Stage 5 CI controller
- distributed `distcc` build workers on dedicated builder-farm nodes
- future binpkg publication and container-image promotion

The immediate target shape is:

- one Jenkins controller VM
- six bare-metal builder nodes
  - Intel Atom `C3758`
  - `8` cores
  - `32 GiB` ECC RAM
  - `6x` `1GbE`
  - `2x` NVMe
- dedicated builder-fabric switch
- switch uplinked to one of the on-host BlueField2 ports:
  - `ens7f0np0`
  - `ens7f1np0`

## Stage 5 profiles

Controller VM:

- `profile-definitions/vm-jenkins-controller.yml`
- package layer:
  - `profile-package-lists/stage5-virtual-host-jenkins-controller.packages`

Builder-farm node:

- `profile-definitions/metal-builder-farm-node.yml`
- package layer:
  - `profile-package-lists/stage5-metal-host-builder-farm-node.packages`

## Roles

Controller role:

- `roles/jenkins_controller`

What it renders:

- Jenkins launcher wrapper under `/usr/local/libexec/jenkins`
- JCasC manifest under `/var/lib/jenkins/casc_configs/jenkins.yaml`
- plugin catalog manifest under `/var/lib/jenkins/seed-manifests/plugins.txt`
- builder-farm inventory manifest under `/var/lib/jenkins/builder-farm/builder-farm.json`
- OpenRC-managed `jenkins-controller` action service

Builder-farm role:

- `roles/distcc_farm`

What it renders:

- `/etc/distcc/hosts` for distcc clients
- `/etc/distcc/builder-farm.json`
- managed `DISTCC_HOSTS` block in `/etc/portage/make.conf`
- worker launcher wrapper under `/usr/local/libexec/distcc-farm`
- OpenRC-managed `distccd-farm` action service

## Example inventory

Controller host vars:

- `inventories/examples/host_vars/vm-jenkins-controller.yml`

Controller group vars:

- `inventories/examples/group_vars/ci_controllers.yml`

Builder-farm group vars:

- `inventories/examples/group_vars/builder_farm_nodes.yml`

Example host group definitions:

- `inventories/examples/hosts.yml`

Per-node host vars:

- `inventories/examples/host_vars/builder-farm-node01.yml`
- `inventories/examples/host_vars/builder-farm-node02.yml`
- `inventories/examples/host_vars/builder-farm-node03.yml`
- `inventories/examples/host_vars/builder-farm-node04.yml`
- `inventories/examples/host_vars/builder-farm-node05.yml`
- `inventories/examples/host_vars/builder-farm-node06.yml`

## Recommended fabric model

Use a dedicated build LAN for distcc traffic.

Recommended first pass:

- controller VM on `10.66.40.10`
- six builder nodes on `10.66.40.11` through `10.66.40.16`
- builder-fabric CIDR:
  - `10.66.40.0/24`
- allow only builder-fabric CIDRs to reach `distccd`
- keep management SSH on a separate network or VLAN where possible

The BlueField2 uplink note is intentional:

- the builder fabric should terminate on a small switch
- that switch can then uplink to:
  - `ens7f0np0`
  - or `ens7f1np0`

This keeps distcc traffic off the general-purpose host path and leaves room for
future isolation or QoS work.

## Example install stacks

Jenkins controller VM:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-vm.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-guest-application-server.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-jenkins-controller.yml"
```

Builder-farm node:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-baremetal.yml"
  - "{{ playbook_dir }}/../profile-definitions/metal-builder-farm-node.yml"
```

## Build telemetry

Long-running Gentoo builds can now be exported into machine-readable metrics
with:

```bash
python3 scripts/export_build_metrics.py \
  --emerge-log /path/to/emerge.log \
  --builder-log /path/to/container-base-rerun.log \
  --output-dir /tmp/build-metrics
```

Artifacts produced:

- `summary.json`
- `emerge-events.csv`
- `builder-samples.csv`
- `burndown.svg`
- `builder-load.svg`
- `report.html`

This is intended to feed Jenkins build artifacts and future trend tracking for:

- package burn-down
- builder load and merge pressure
- elapsed time versus completion count
- later p90/p95 duration modeling across profile revisions

## First-node bring-up workflow

Machine-readable bring-up manifest:

- `docs/workflows/stage5-ci-builder-farm-bringup.json`

That workflow is intended to:

- review the example CIDR and SSH-key placeholders
- validate the Jenkins controller VM
- validate `builder_farm_node01` first
- only then roll the same profile to `node02` through `node06`

## Outstanding actions

- validate the Jenkins controller package and launcher on a real installed VM
- validate the `distccd-farm` wrapper on one Atom builder node before rolling to all six
- add a Stage 5 `binpkg-repo` profile after the first CI controller is online
- add pipeline jobs for:
  - base container build
  - binpkg publication
  - GHCR push and promotion
