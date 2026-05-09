# Configurations and Examples

## Stage Language

Use this vocabulary consistently:

- `Stage 4`
  - shared OS baseline
  - LLVM/Clang, hardening, Portage, OpenRC, and common policy
- `Stage 5`
  - role overlay
  - host or service intent layered on top of Stage 4

Current Stage 5 role classes:

- `metal-host`
- `virtual-host`
- `service-container`
- `cloud-init-overlay`

For scalability, Stage 5 package sets should be stored in
`profile-package-lists/*.packages` and referenced by `package_list_files`.

## 1. Local LiveISO Target

Use when Ansible runs directly on the booted target host.

Inventory:

```yaml
target_system_local:
  ansible_connection: local
  ansible_python_interpreter: /usr/bin/python3
```

Typical command:

```bash
ansible-playbook playbooks/install.yml -l target_system_local --connection=local
```

## 2. Remote Bare-Metal LiveISO Target

Use when a host is booted into a Gentoo LiveISO and managed over SSH.

Inventory pattern:

```yaml
target_system_remote:
  ansible_host: 10.9.8.7
  ansible_user: root
  ansible_python_interpreter: /usr/bin/python3
```

Recommended staged flow:

```bash
bash scripts/run-install-sequence.sh \
  --inventory inventories/examples/hosts.yml \
  --limit target_system_remote \
  --sequence storage-foundation \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/target-system-remote.storage.jsonl
```

Then:

- `chroot-bootstrap`
- `target-integration`

This is Path A.

## 3. QEMU Alias-Mode Installer VM

Use when validating inside a VM without changing the host’s physical bridge configuration.

Launcher:

```bash
QEMU_NETWORK_MODE=alias bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

Control path:

- guest network: `10.9.8.7/24`
- host alias: `10.9.8.108/24`
- SSH target for Ansible: `10.9.8.108:2222`

Inventory:

```yaml
target_system_remote:
  ansible_host: 10.9.8.108
  ansible_port: 2222
  ansible_user: root
```

Disk IDs inside the VM:

```yaml
zfs_boot_pool_devices:
  - /dev/disk/by-id/ata-QEMU_HARDDISK_bpool-0
  - /dev/disk/by-id/ata-QEMU_HARDDISK_bpool-1
zfs_root_pool_devices:
  - /dev/disk/by-id/ata-QEMU_HARDDISK_rpool-0
  - /dev/disk/by-id/ata-QEMU_HARDDISK_rpool-1
```

This is also Path A.

## 4. Path B iPXE Publisher

Use when a host or VM fleet should boot a Gentoo provisioning environment via
DHCP/TFTP or UEFI HTTP into iPXE, then fetch boot assets over HTTP/HTTPS.

Inventory pattern:

```yaml
netboot_publishers:
  hosts:
    netboot_control_local:
      ansible_connection: local
      ansible_python_interpreter: /usr/bin/python3
```

Render the asset tree:

```bash
ansible-playbook \
  -i inventories/examples/hosts.yml \
  playbooks/netboot-path-b.yml \
  -l netboot_control_local
```

Published artifacts:

- `/var/lib/netboot/path-b/bootstrap.ipxe`
- `/var/lib/netboot/path-b/menu.ipxe`
- `/var/lib/netboot/path-b/roles/*.ipxe`
- `/var/lib/netboot/path-b/hosts/*.ipxe`
- `/var/lib/netboot/path-b/manifests/path-b-netboot.json`

Path B target metadata should be carried by the `install_targets` inventory
hosts that will be provisioned:

```yaml
target_system_remote:
  ansible_host: 10.9.8.7
  ansible_user: root
  ansible_python_interpreter: /usr/bin/python3
  netboot_enabled: true
  netboot_interface_name: eth0
  netboot_mac_address: "52:54:00:12:34:56"
  netboot_type: dhcp
  netboot_dhcp_client_options:
    - "class-id=PXEClient:Arch:00000:UNDI:002001"
  netboot_os_type: linux
  netboot_os_name: gentoo
  netboot_os_version: stage4-current
  netboot_machine_type: qemu
  netboot_platform: uefi
  netboot_arch: amd64
  netboot_role: installer
```

Relevant enums:

- `netboot_type`: `static`, `dhcp`, `bootp`
- `netboot_os_type`: `linux`, `bsd`, `router-os`, `solaris`, `other`
- `netboot_os_name`: `gentoo`, `centos`, `rocky`, `debian`, `devuan`, `solaris`, `tribblix`, `dietpi`, `fedora`, `freebsd`, `netbsd`, `other`
- `netboot_machine_type`: `metal`, `qemu`, `xen`, `embedded`
- `netboot_platform`: `bios`, `uefi`, `other`
- `netboot_arch`: `amd64`, `arm64`, `ppc64le`, `other`

## 5. Tap Mode

Use when the VM should get a dedicated tap interface without full bridge automation.

Example:

```bash
QEMU_NETWORK_MODE=tap \
QEMU_TAP_IFNAME=tap-stage4 \
QEMU_TAP_HOST_CIDR=10.9.8.108/24 \
WAIT_FOR_SSH=0 \
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

## 6. Bridge Mode

Use when the VM must participate more directly in the external network fabric.

Example:

```bash
QEMU_NETWORK_MODE=bridge \
QEMU_TAP_IFNAME=tap-stage4 \
QEMU_BRIDGE_IFNAME=br0 \
WAIT_FOR_SSH=0 \
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

This is the preferred long-term network model, but alias mode is the safer first validation path on a LiveISO host.

## 7. RouterOS Path B CHR Example

Use when the isolated `10.9.8.0/24` Path B segment is backed by a RouterOS CHR
VM.

Example inventory:

```yaml
routeros_pathb:
  hosts:
    routeros_pathb_primary:
      ansible_host: 10.9.8.1
      ansible_user: admin
```

Example variables:

```yaml
routeros_pathb_routeros_arch: x86
routeros_pathb_lan_interface: ether1
routeros_pathb_lan_cidr: 10.9.8.1/24
routeros_pathb_lan_network_cidr: 10.9.8.0/24
routeros_pathb_boot_next_server: 10.9.8.108
routeros_pathb_boot_file_name: http://10.9.8.108:8080/bootstrap.ipxe
routeros_pathb_ntp_client_servers:
  - 10.9.8.108
routeros_pathb_ntp_server_broadcast_addresses:
  - 10.9.8.255
routeros_pathb_required_packages:
  - container
  - zerotier
```

Render only:

```bash
ansible-playbook -i inventories/examples/hosts.yml playbooks/routeros-path-b.yml -l routeros_pathb_primary
```

Important current constraints:

- UEFI only
- CHR uses RouterOS `x86`
- `container` is supportable on `x86`
- `zerotier` is not documented for `x86`, only `ARM` and `ARM64`
- native HTTP is disabled instead of redirected
- native RouterOS does not satisfy the full local UDP+TCP syslog-server role
- serial console is hypervisor-backed; RouterOS x86 default serial speed is `9600`

## 8. Boot Source Modes

## 8. Container-Services VM Profile

Use when the simple guest base should become a Podman container host with OpenRC,
serial and SSH console only, `netavark`, and `nftables` site-security policy.

Example host-vars overlay:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-vm.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-guest-simple-ipxe.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-container-services.yml"

profile_container_app_profiles:
  ntfy:
    enabled: true
  nginx:
    enabled: true
  haproxy:
    enabled: true

profile_site_security_profile:
  compliance_mode: strict
  firewall:
    allowed_management_cidrs:
      - 10.9.8.0/24
      - 172.16.99.0/24
  ipam:
    source: flat-file-json
    flat_file_json:
      site: example-lab
      networks:
        apps:
          subnet: 10.77.1.0/24
          gateway: 10.77.1.1
```

Role flow in `target-integration`:

- `container_host`
- `container_app_ntfy`
- `container_app_nginx`
- `container_app_haproxy`
- `container_net_policy`
- `container_service_segments`
- `services`

This produces:

- Podman host config under `/etc/containers`
- `nftables` policy in `/etc/nftables.conf`
- site-security and IPAM snapshots under `/etc/container-services`
- OpenRC-managed Podman service wrappers under `/usr/local/libexec/container-services`
- a narrow `sys-apps/systemd-utils` exception scoped only to the Podman/netavark container stack while preserving the repo-wide `without-systemd` stance elsewhere

Optional guest-side tmpfs mounts for the same profile:

```yaml
profile_container_services:
  runtime_root: /var/lib/container-services-ephemeral

profile_memory_storage:
  enabled: true
  mounts:
    - path: /var/lib/container-services-ephemeral
      size: 32G
      mode: "0755"
      options:
        - noatime
```

Operational notes:

- for generic VM and container-host validation, prefer `portage_cpu_profile:
  x86_64_v2_generic`
- reserve host-specific microarchitecture profiles for guest fleets that are
  guaranteed to match that CPU contract
- the current Path B lab uses a temporary upstream workaround:
  - guest default route override to `10.9.8.108`
  - explicit `resolv.conf` population
  - host-side IPv4 forwarding and NAT
- that workaround is acceptable for isolated validation but should be replaced
  by a proper RouterOS upstream path before promoting the lab into a standard
  external-host service environment

## 9. Hypervisor-side tmpfs-backed VM disks

Use when the QEMU host should provide extra ephemeral disks out of RAM-backed
tmpfs instead of persistent SSD/NVMe storage.

Inventory group:

```yaml
qemu_hypervisors:
  hosts:
    qemu_control_local:
      ansible_connection: local
      ansible_python_interpreter: /usr/bin/python3
```

Example group vars:

```yaml
qemu_memory_drives_enabled: true
qemu_memory_drives_mount_root: /dev/shm/qemu-memory-drives
qemu_memory_drives_tmpfs_size: 256G
qemu_memory_drives_instance_name: stage4-devvm
qemu_memory_drives:
  - name: portage-cache
    size_gib: 64
    format: qcow2
    serial: mem-portage-cache
    device_model: virtio-blk-pci
```

Prepare the drives:

```bash
ansible-playbook -i inventories/examples/hosts.yml playbooks/qemu-memory-drives.yml -l qemu_control_local
```

Then launch with:

```bash
QEMU_MEMORY_DRIVES_FILE=/dev/shm/qemu-memory-drives/stage4-devvm/memory-drives.json \
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

## 10. Boot Source Modes

### Installer QCOW

Used for building and imaging:

```bash
QEMU_BOOT_SOURCE=qcow bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

Expected result:

- root on QCOW `ext4`
- target disks attached for provisioning
- no `bpool` / `rpool` mounted as `/` yet

### Target Disks

Used for final validation:

```bash
QEMU_BOOT_SOURCE=target-disks \
QEMU_SERIAL_MODE=stdio \
QEMU_DAEMONIZE=0 \
WAIT_FOR_SSH=0 \
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

## 9. Gentoo System Profiles

The installer now supports stackable profile-definition files so the LLVM/Clang
Portage baseline can be reused across multiple host classes.

Common base:

- `profile-definitions/llvm-clang-hardened-portage.yml`
- `profile-definitions/cloud-init-baremetal.yml`
- `profile-definitions/cloud-init-vm.yml`

Host-specific overlays:

- `profile-definitions/hypervisor-xen-qemu-libvirt-host.yml`
- `profile-definitions/vm-guest-application-server.yml`
- `profile-definitions/vm-guest-simple-ipxe.yml`

### Hypervisor Host

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-baremetal.yml"
  - "{{ playbook_dir }}/../profile-definitions/hypervisor-xen-qemu-libvirt-host.yml"
```

Highlights:

- Xen + Xen tools
- QEMU + Libvirt
- Open vSwitch
- NVMe-oF / RDMA support packages
- PMem / NVDIMM tooling
- ZFS 2.4.x testing-track atoms
- kernel-module load hints for `mlx5_*`, `qede`, `nvme-rdma`, `openvswitch`, and `zfs`

### VM Guest Application Server

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-vm.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-guest-application-server.yml"
```

Highlights:

- `qemu-guest-agent`
- `xe-guest-utilities`
- cloud-init behavior supplied by the separate `cloud-init-vm` overlay
- serial + SSH operational model
- `bonding`, `virtio_*`, and `xen_*front` module hints

### VM Guest Simple iPXE

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-vm.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-guest-simple-ipxe.yml"
```

Highlights:

- lean Path B validation guest
- cloud-init behavior supplied by the separate `cloud-init-vm` overlay
- `qemu-guest-agent`
- `virtio_*` module hints only

### Per-host Users and Cloud-init

Use the modular cloud-init overlays to enable package and datasource defaults, then
keep host-specific accounts and NoCloud seed values in inventory:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-vm.yml"

profile_local_user_accounts:
  - name: deploy
    groups:
      - wheel
    sudo_nopasswd: true
    ssh_authorized_keys: []

profile_cloud_init:
  instance_id: vm-guest-appserver
  local_hostname: appserver
```

Example host variable files:

- `inventories/examples/host_vars/hypervisor-host.yml`
- `inventories/examples/host_vars/vm-guest-appserver.yml`
- `inventories/examples/host_vars/vm-guest-simple.yml`

Expected result:

- UEFI boots from `bpool`
- ZFSBootMenu loads
- root on `rpool/ROOT/gentoo`
- `/boot` on `bpool/BOOT/gentoo`

## 9. Profile Overlay Configuration

The default combined target uses a local overlay profile that composes:

- `default/linux/amd64/23.0/llvm`
- `default/linux/amd64/23.0/split-usr/no-multilib/hardened`

Additional YAML profile definitions can be layered via:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/hardened-llvm-stage4-split-usr.yml"
```

For merged-usr VM and container consumers, prefer:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/hardened-llvm-stage4-merged-usr.yml"
```

## 9. Service Definition Configuration

Managed OpenRC services can be defined as data:

```yaml
openrc_action_services:
  - name: stage4-example
    description: Example managed daemon action
    command: /usr/sbin/crond -f
    runlevel: default
    user: root
    group: root
    enabled: false
```

Or loaded from repo-managed definitions such as:

- `service-definitions/stage4-heartbeat.yml`

## 10. Notification Configuration

### Ansible callback

```bash
export ANSIBLE_NTFY_ENABLED=true
export ANSIBLE_NTFY_URL=http://msg-sun99-ntfysys.rfc1918.host
export ANSIBLE_NTFY_TOPIC=replace-with-your-topic
```

### Codex/operator

```bash
export CODEX_NTFY_ENV_FILE=/root/.codex/ntfy-pub-subs.export.sh
bash scripts/install_codex_approval_watcher_service.sh
```

### GitHub workflow

Configure repository secrets or variables for:

- `NTFY_URL`
- `NTFY_TOPIC`
- optional state-specific topic keys

## 11. Sequence Examples

### Storage only

```bash
bash scripts/run-install-sequence.sh \
  --inventory inventories/qemu-alias/hosts.yml \
  --limit target_system_remote \
  --sequence storage-foundation \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/target-system-remote.storage.jsonl
```

### Bootstrap only

```bash
bash scripts/run-install-sequence.sh \
  --inventory inventories/qemu-alias/hosts.yml \
  --limit target_system_remote \
  --sequence chroot-bootstrap \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/target-system-remote.bootstrap.jsonl
```

### Integration only

```bash
bash scripts/run-install-sequence.sh \
  --inventory inventories/qemu-alias/hosts.yml \
  --limit target_system_remote \
  --sequence target-integration \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/target-system-remote.integration.jsonl
```

## 12. Jenkins controller and builder farm

Controller profile example:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-vm.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-guest-application-server.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-jenkins-controller.yml"
```

Builder node profile example:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-baremetal.yml"
  - "{{ playbook_dir }}/../profile-definitions/metal-builder-farm-node.yml"
```

Example inventory data:

- controller host vars:
  - `inventories/examples/host_vars/vm-jenkins-controller.yml`
- controller group vars:
  - `inventories/examples/group_vars/ci_controllers.yml`
- builder-farm group vars:
  - `inventories/examples/group_vars/builder_farm_nodes.yml`

The intended first builder fabric is:

- controller:
  - `10.66.40.10`
- workers:
  - `10.66.40.11` through `10.66.40.16`
- fabric CIDR:
  - `10.66.40.0/24`
- suggested host uplinks for the build switch:
  - `ens7f0np0`
  - `ens7f1np0`

The new roles manage:

- Jenkins controller launch and JCasC seed material
- distcc worker and client manifests
- `DISTCC_HOSTS` injection into `make.conf`
- OpenRC action services:
  - `jenkins-controller`
  - `distccd-farm`
