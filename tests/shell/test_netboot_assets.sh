#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  grep -Fq "${needle}" "${path}" || fail "expected '${needle}' in ${path}"
}

test_netboot_assets_exist() {
  assert_file_contains "${ANSIBLE_ROOT}/playbooks/netboot-path-b.yml" "hosts: netboot_publishers"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/defaults/main.yml" "netboot_publish_root:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/defaults/main.yml" "netboot_boot_type_enum:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/defaults/main.yml" "netboot_protocol_flow_enum:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/defaults/main.yml" "netboot_initramfs_boot_name:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/defaults/main.yml" "netboot_tftp_autoexec_chain_url:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/defaults/main.yml" "netboot_first_stage_binaries:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/defaults/main.yml" "netboot_tftp_service_enabled:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/defaults/main.yml" "netboot_roles_extra: {}"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/defaults/main.yml" "root=live:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" "Build effective Path B role map"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" "Build resolved Path B host map from install_targets inventory"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" "netboot_protocol_flow"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" "Render Path B bootstrap iPXE script"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" "Install Path B first-stage boot binaries"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" "Install RFC99 netboot TFTP server"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" "Render Path B TFTP autoexec iPXE script"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" "Render Path B MAC dispatch iPXE script"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/files/rfc99-tftp-server.py" "threading.Thread"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/netboot-tftp.initd.j2" "RFC99 netboot TFTP publisher"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/bootstrap.ipxe.j2" "chain \${base-url}/hosts/by-mac.ipxe"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/autoexec.ipxe.j2" "netboot_tftp_autoexec_chain_url"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/autoexec.ipxe.j2" "isset \${net0/ip} || dhcp"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/autoexec.ipxe.j2" "chain \${base-url}/hosts/by-mac.ipxe"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/host.ipxe.j2" "isset \${net0/ip} || dhcp"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/hosts-by-mac.ipxe.j2" "iseq \${net0/mac}"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/menu.ipxe.j2" "RFC Codex Gentoo Stage4 LLVM - Path B iPXE"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/menu.ipxe.j2" "isset \${net0/ip} || dhcp"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/role.ipxe.j2" "isset \${net0/ip} || dhcp"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/role.ipxe.j2" "imgfree"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/role.ipxe.j2" "set initrd-name {{ netboot_role.value.initrd_boot_name | default(netboot_initramfs_boot_name) }}"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/role.ipxe.j2" "initrd=initrd.magic"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/role.ipxe.j2" "kernel --name vmlinuz"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/role.ipxe.j2" "initrd --name \${initrd-name}"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/role.ipxe.j2" "boot || shell"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/netboot-manifest.json.j2" "\"bootType\":"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/netboot-manifest.json.j2" "\"protocolFlow\":"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/k10-stage5-workstation.yml" "kind: NetbootImageManifest"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/k10-stage5-workstation.yml" "gmktek_nucbox_k10_stage5_candidate"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/k10-stage5-workstation.yml" "rtl_nic/rtl8125b-2.fw"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/k10-stage5-workstation.yml" "initrd=initrd.magic"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/k10-stage5-workstation.yml" "PATHB_REUSE_INITRAMFS_NETWORK=0"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/k10-stage5-workstation.yml" "PATHB_STATIC_INTERFACE=enp4s0"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/k10-stage5-workstation.yml" "PATHB_STATIC_ADDRESS_CIDR=172.16.99.156/24"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/k10-stage5-workstation.yml" "PATHB_STATIC_GATEWAY=172.16.99.1"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/k10-stage5-workstation.yml" "PATHB_STATIC_DNS="
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/thinkpad-x1gen8-workstation.yml" "kind: NetbootImageManifest"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/thinkpad-x1gen8-workstation.yml" "lab_sun99_x1gen8_099082"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/thinkpad-x1gen8-workstation.yml" "54:05:DB:34:CC:75"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/thinkpad-x1gen8-workstation.yml" "i915"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/thinkpad-x1gen8-workstation.yml" "initrd=initrd.magic"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "Built Path B netboot artifacts"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "sys-kernel/linux-firmware"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "PATHB_PACKAGE_USE_APPEND"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "PATHB_PROFILE_DEFINITION_FILES"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "PATHB_PROFILE_PACKAGE_LIST_FILES"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "PATHB_OPENRC_SERVICES_EXTRA"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "PATHB_STAGE3_CACHE_DIR_EXPLICIT"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "PATHB_STATIC_INTERFACE"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "PATHB_STATIC_ADDRESS_CIDR"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" 'ln -sfn net.lo /etc/init.d/net.${PATHB_STATIC_INTERFACE}'
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" 'config_${PATHB_STATIC_INTERFACE}'
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" 'routes_${PATHB_STATIC_INTERFACE}'
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" 'dns_servers_${PATHB_STATIC_INTERFACE}'
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "cleanup_mounts"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "findmnt -Rrn -o TARGET"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "sort -r"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "mktemp"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "rm -f"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "path-b-extra"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "initramfs-gz.img"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" '\${boot_iface}'
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" '\${#boot_ipv4_addrs[@]}'
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" 'boot_iface="\$(ip route show default'
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" 'print \$4'
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" 'print \$5'
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "rtl_nic/rtl8125b-2.fw"
  assert_file_contains "${ANSIBLE_ROOT}/profile-package-lists/stage5-domain-client.packages" "net-fs/samba"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/netboot_publishers.yml" "netboot_host_map_extra:"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" "netboot_machine_type: qemu"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "netboot_protocol_flow: pxe-to-ipxe"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "lab_sun99_x1gen8_099082:"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "netboot_mac_address: \"54:05:DB:34:CC:75\""
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "netboot_static_address: 172.16.99.82"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "netboot_bootfile_name: x1gen8-ipxe.efi"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "netboot_role: thinkpad-x1gen8-workstation"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "boot_sun99_netboot_099088:"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml" "172.16.99.88:8080"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml" "dest: x1gen8-ipxe.efi"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml" "src: /opt/gentoo-netboot/path-b/path-b-by-mac-172.16.99.88-ipxe.efi"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml" "thinkpad-x1gen8-workstation:"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml" "ifname=eth0:54:05:db:34:cc:75"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml" "ip=172.16.99.82::172.16.99.1:255.255.255.0:lab-sun99-x1gen8-099082:eth0:none"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml" "rd.hostname=lab-sun99-x1gen8-099082"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml" "hostname=lab-sun99-x1gen8-099082"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/m70_canary.yml" "netboot_role: localdisk"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/m70_canary.yml" "netboot_status: local-zfsbootmenu-validation"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/k10-stage5-workstation.yml" "http://172.16.99.88:8080/g/rootfs.img"
  assert_file_contains "${ANSIBLE_ROOT}/netboot-image-manifests/thinkpad-x1gen8-workstation.yml" "http://172.16.99.88:8080/g/rootfs.img"
  assert_file_contains "${REPO_ROOT}/docs/workflows/stage4-netboot-path-b.json" "\"name\": \"stage4-netboot-path-b\""
}

test_netboot_playbook_syntax() {
  (
    cd "${ANSIBLE_ROOT}"
    ansible-playbook -i inventories/examples/hosts.yml playbooks/netboot-path-b.yml --syntax-check > /dev/null
  )
}

test_netboot_assets_exist
test_netboot_playbook_syntax

printf 'PASS: %s\n' "$(basename "$0")"
