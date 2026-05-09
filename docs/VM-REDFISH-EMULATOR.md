# VM Redfish Emulator

## Purpose

`vm-redfish-emulator` provides a Stage5 virtual-host profile for exposing VM
inventory and lifecycle operations through a Redfish-compatible API. The target
use case is automation parity: callers can query VMs through the same broad
shape used for baremetal Redfish/iDRAC/IPMI inventory without pretending the VM
emulator is a hardware security boundary.

## Selected Implementation

Primary implementation: `sushy-tools` virtual Redfish BMC backed by libvirt.

The OpenStack `sushy-tools` project ships a virtual Redfish BMC that can map
some Redfish client operations to VM control through libvirt or OpenStack. This
is the closest fit for QEMU/libvirt managed VMs because service root, systems,
power state, and reset operations can be driven from live virtualization state.

Fallback implementation: DMTF Redfish Interface Emulator.

The DMTF emulator is useful for static mockups and schema development. It can
serve canned Redfish resources and custom dynamic resources, but it is less
useful as the first automation target because it does not naturally derive VM
state from QEMU/libvirt.

## Repo Wiring

- Profile: `profile-definitions/vm-redfish-emulator.yml`
- Metadata: `profile-definitions/vm-redfish-emulator.metadata.yml`
- Package list: `profile-package-lists/stage5-virtual-host-redfish-emulator.packages`
- Role: `roles/vm_redfish_emulator/`
- Test: `tests/shell/test_vm_redfish_emulator_role.sh`

The role creates a Python virtualenv, installs `sushy-tools`, `gunicorn`, and
`libvirt-python`, renders a sushy emulator config, and installs an OpenRC
service. TLS defaults to enabled so the service can later use the RFC1918
private CA.

## Security Position

- Keep the service on management networks only.
- Gate Redfish mutations with inventory variables and RBAC once central
  FreeIPA/SSSD/RADIUS policy is active.
- Use private-CA TLS for operator clients and service-to-service validation.
- Treat this as an automation compatibility shim, not a substitute for a real
  BMC on baremetal hosts.
