#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROFILE_DIR="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions"
PACKAGE_LIST_DIR="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-package-lists"
HOST_VARS_DIR="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/examples/host_vars"
PORTAGE_ROLE="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/portage/tasks/main.yml"
PREFLIGHT_ROLE="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/preflight/tasks/load_profile_definition.yml"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q "${pattern}" "${file}"
}

for profile in \
  aaa-domain-client.yml \
  base-hypervisor-qemu-libvirt.yml \
  base-hypervisor-xen.yml \
  base-hypervisor-xen-qemu-libvirt.yml \
  base-minimal-nox.yml \
  base-minimal-xorg-slim.yml \
  cloud-init-baremetal.yml \
  cloud-init-vm.yml \
  documentation-diagram-renderer.yml \
  container-elastic-apm.yml \
  container-ipmi-exporter.yml \
  container-rsyslog-collector.yml \
  container-redfish-exporter.yml \
  hardened-llvm-stage4-merged-usr.yml \
  hardened-llvm-stage4-split-usr.yml \
  llvm-clang-hardened-portage.yml \
  hypervisor-xen-qemu-libvirt-host.yml \
  metal-fmt2-r630-openstack-roce.yml \
  metal-forge-automation-admin.yml \
  logging-rsyslog-client.yml \
  metal-builder-farm-node.yml \
  metal-identity-controller.yml \
  nfs-storage-client.yml \
  netbox-managed-inventory.yml \
  netbox-pathb-lab-ipam-plan.yml \
  telemetry-collectd-client.yml \
  telemetry-elasticsearch-exporter.yml \
  telemetry-node-exporter-client.yml \
  telemetry-podman-exporter.yml \
  virt-minimal.yml \
  virt-xorg.yml \
  vm-binpkg-repository.yml \
  vm-container-services.yml \
  vm-elasticsearch-node.yml \
  vm-identity-controller.yml \
  vm-jenkins-controller.yml \
  vm-guest-application-server.yml \
  vm-guest-simple-ipxe.yml \
  vm-observability-grafana.yml \
  vm-observability-prometheus.yml \
  vm-observability-victoriametrics.yml \
  vm-redfish-emulator.yml \
  vm-trac-service.yml \
  vm-workstation-nscde.yml \
  vm-kibana-interface.yml \
  vm-mcp-control-plane.yml \
  vm-nexus-repository.yml \
  zerotier-managed-access.yml; do
  test -f "${PROFILE_DIR}/${profile}"
  assert_file_contains "${PROFILE_DIR}/${profile}" '^gentoo_profile_definition:'
done

for metadata in \
  aaa-domain-client.metadata.yml \
  base-hypervisor-qemu-libvirt.metadata.yml \
  base-hypervisor-xen.metadata.yml \
  base-hypervisor-xen-qemu-libvirt.metadata.yml \
  base-minimal-nox.metadata.yml \
  base-minimal-xorg-slim.metadata.yml \
  cloud-init-baremetal.metadata.yml \
  cloud-init-vm.metadata.yml \
  hardened-llvm-stage4-merged-usr.metadata.yml \
  hardened-llvm-stage4-split-usr.metadata.yml \
  hypervisor-xen-qemu-libvirt-host.metadata.yml \
  metal-fmt2-r630-openstack-roce.metadata.yml \
  metal-forge-automation-admin.metadata.yml \
  metal-builder-farm-node.metadata.yml \
  metal-identity-controller.metadata.yml \
  nfs-storage-client.metadata.yml \
  virt-minimal.metadata.yml \
  virt-xorg.metadata.yml \
  vm-container-services.metadata.yml \
  vm-elasticsearch-node.metadata.yml \
  vm-identity-controller.metadata.yml \
  vm-jenkins-controller.metadata.yml \
  vm-binpkg-repository.metadata.yml \
  vm-guest-application-server.metadata.yml \
  vm-guest-simple-ipxe.metadata.yml \
  vm-observability-grafana.metadata.yml \
  vm-observability-prometheus.metadata.yml \
  vm-observability-victoriametrics.metadata.yml \
  vm-redfish-emulator.metadata.yml \
  vm-trac-service.metadata.yml \
  vm-workstation-nscde.metadata.yml \
  vm-kibana-interface.metadata.yml \
  vm-mcp-control-plane.metadata.yml \
  vm-nexus-repository.metadata.yml; do
  test -f "${PROFILE_DIR}/${metadata}"
  assert_file_contains "${PROFILE_DIR}/${metadata}" '^gentoo_system_profile_metadata:'
done

for host_var in \
  builder-farm-node01.yml \
  builder-farm-node02.yml \
  builder-farm-node03.yml \
  builder-farm-node04.yml \
  builder-farm-node05.yml \
  builder-farm-node06.yml \
  hypervisor-host.yml \
  vm-elasticsearch-node01.yml \
  vm-elasticsearch-node02.yml \
  vm-elasticsearch-node03.yml \
  vm-identity-controller.yml \
  vm-jenkins-controller.yml \
  vm-binpkg-repository.yml \
  vm-container-services.yml \
  vm-guest-appserver.yml \
  vm-guest-simple.yml \
  vm-observability-grafana.yml \
  vm-observability-prometheus.yml \
  vm-observability-victoriametrics.yml \
  vm-workstation-nscde.yml \
  vm-kibana-interface.yml \
  vm-nexus-repository.yml; do
  test -f "${HOST_VARS_DIR}/${host_var}"
  assert_file_contains "${HOST_VARS_DIR}/${host_var}" '^profile_definition_files:'
done

for package_list in \
  cloud-init-base.packages \
  stage5-base-hypervisor-common.packages \
  stage5-base-hypervisor-qemu-libvirt.packages \
  stage5-base-hypervisor-xen.packages \
  stage5-base-minimal-nox.packages \
  stage5-base-minimal-xorg-slim.packages \
  stage5-domain-client.packages \
  stage5-managed-access-zerotier.packages \
  stage5-metal-intel-platform.packages \
  stage5-metal-forge-automation-admin.packages \
  stage5-metal-host-builder-farm-node.packages \
  stage5-metal-host-hypervisor.packages \
  stage5-metal-host-identity-controller.packages \
  stage5-storage-nfs-client.packages \
  stage5-observability-client.packages \
  stage5-observability-metrics-collectd-client.packages \
  stage5-observability-metrics-client.packages \
  stage5-observability-metrics-elasticsearch-exporter.packages \
  stage5-observability-metrics-podman-exporter.packages \
  stage5-virt-minimal.packages \
  stage5-virt-xorg.packages \
  stage5-virtual-host-base.packages \
  stage5-virtual-host-appserver.packages \
  stage5-virtual-host-binpkg-repository.packages \
  stage5-virtual-host-elasticsearch-node.packages \
  stage5-virtual-host-identity-controller.packages \
  stage5-virtual-host-jenkins-controller.packages \
  stage5-virtual-host-kibana-interface.packages \
  stage5-virtual-host-mcp-control-plane.packages \
  stage5-virtual-host-nexus-repository.packages \
  stage5-virtual-host-observability-grafana.packages \
  stage5-virtual-host-observability-prometheus.packages \
  stage5-virtual-host-observability-victoriametrics.packages \
  stage5-virtual-host-redfish-emulator.packages \
  stage5-virtual-host-trac-service.packages \
  stage5-virtual-host-workstation-nscde.packages \
  stage5-virtual-host-container-services.packages; do
  test -f "${PACKAGE_LIST_DIR}/${package_list}"
done

test -d "${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/nscde_workstation"
test -f "${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-workstation-nscde-vm.sh"
assert_file_contains "${PACKAGE_LIST_DIR}/stage5-virtual-host-workstation-nscde.packages" '^=x11-drivers/nvidia-drivers-580\.159\.03-r1$'
assert_file_contains "${PACKAGE_LIST_DIR}/stage5-virtual-host-workstation-nscde.packages" '^=dev-util/nvidia-cuda-toolkit-12\.9\.1-r1$'
assert_file_contains "${PACKAGE_LIST_DIR}/stage5-virtual-host-workstation-nscde.packages" '^sys-block/ndctl$'
assert_file_contains "${PROFILE_DIR}/vm-workstation-nscde.yml" 'VIDEO_CARDS=.*nvidia'
assert_file_contains "${PROFILE_DIR}/vm-workstation-nscde.yml" 'CONFIG_DEV_DAX_PMEM'
assert_file_contains "${PROFILE_DIR}/vm-workstation-nscde.yml" 'nd_pmem'
assert_file_contains "${PROFILE_DIR}/vm-workstation-nscde.yml" '=x11-drivers/nvidia-drivers-580\.159\.03-r1 ~amd64'
assert_file_contains "${PROFILE_DIR}/vm-workstation-nscde.yml" '=dev-util/nvidia-cuda-toolkit-12\.9\.1-r1 NVIDIA-CUDA'
assert_file_contains "${PREFLIGHT_ROLE}" 'resolved_portage_patch_files'
assert_file_contains "${PORTAGE_ROLE}" '/etc/portage/patches'
assert_file_contains "${PROFILE_DIR}/vm-kibana-interface.yml" 'install_method: upstream_tarball'
assert_file_contains "${PACKAGE_LIST_DIR}/stage5-virtual-host-kibana-interface.packages" '^net-misc/curl$'
assert_file_contains "${PROFILE_DIR}/documentation-diagram-renderer.yml" 'media-gfx/plantuml'
assert_file_contains "${PROFILE_DIR}/documentation-diagram-renderer.yml" 'media-gfx/graphviz'
assert_file_contains "${PROFILE_DIR}/documentation-diagram-renderer.yml" 'media-libs/gd fontconfig jpeg png truetype zlib'
assert_file_contains "${PROFILE_DIR}/documentation-diagram-renderer.yml" 'media-libs/freetype harfbuzz png'
assert_file_contains "${PROFILE_DIR}/documentation-diagram-renderer.yml" 'diagram-render-native-cc.conf'
assert_file_contains "${PROFILE_DIR}/documentation-diagram-renderer.yml" 'dev-libs/fribidi diagram-render-native-cc.conf'
assert_file_contains "${PROFILE_DIR}/documentation-diagram-renderer.yml" 'harfbuzz-12.3.2-clang21-varc-extra-semi.patch'
assert_file_contains "${PROFILE_DIR}/documentation-diagram-renderer.yml" '#pragma GCC diagnostic ignored "-Wextra-semi-stmt"'
assert_file_contains "${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/host_vars/m70_canary.yml" 'documentation-diagram-renderer.yml'

test -f "${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/aaa-policy-definitions/site-baseline.yml"

printf 'PASS: %s\n' "$(basename "$0")"
