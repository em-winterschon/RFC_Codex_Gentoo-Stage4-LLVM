# BMC Redfish iDRAC And GPU Policy Design

## Goal

Create an Ansible-managed BMC control plane for Redfish-capable hosts, Dell iDRAC hosts, and future iPXE reinstall workflows, while adding an inventory-driven GPU compute host policy that prevents `nouveau` and `nvidiafb` from binding NVIDIA PCIe GPUs by default.

## Scope

This first implementation provides safe scaffolding:

- A vendor-neutral `bmc_redfish` role that validates Redfish credentials, collects service/system/manager facts, and exposes mutation actions only when explicitly enabled.
- A Dell-specific `bmc_idrac` wrapper role for R630/R730xd-style iDRAC defaults and future lifecycle-controller behavior.
- A `gpu_host_policy` role that renders modprobe and GRUB drop-in config for NVIDIA GPU compute or passthrough hosts.
- Local-network inventory updates for Hasslehoff after the CCR2004-PCIe removal, K1200 GPU installation, and QLogic CNA installation.

Out of scope for this pass:

- Live iDRAC firmware update orchestration.
- Live OS reinstall of Dell or IBM hosts.
- Importing plaintext BMC credentials into Ansible Vault; that remains tracked by `PNR-023`.

## Safety Model

BMC roles default to read-only operations. Power actions, boot override changes, virtual media insertion, and reset behavior must set both an action variable and the relevant allow variable:

- `bmc_redfish_allow_mutation: true`
- `bmc_idrac_allow_mutation: true` for Dell wrapper actions

GPU policy roles do not reboot hosts. They render configuration and optionally run `update-grub` or `update-initramfs` only when explicit booleans are enabled.

## Components

`bmc_redfish`

- Uses `ansible.builtin.uri` rather than vendor modules so it can work before external collections are installed.
- Discovers Redfish service root, systems, managers, and chassis endpoints.
- Produces `bmc_redfish_facts` for NetBox/DCIM and validation workflows.
- Supports gated mutation blocks for power reset, boot override, and virtual media insertion.

`bmc_idrac`

- Wraps `bmc_redfish` with Dell iDRAC endpoint conventions.
- Defaults the system ID to `System.Embedded.1` and manager ID to `iDRAC.Embedded.1`.
- Validates that the observed Redfish vendor/manufacturer appears Dell-like unless validation is disabled.

`gpu_host_policy`

- Detects NVIDIA PCI devices with `lspci -Dnmm` when detection is enabled.
- Renders `/etc/modprobe.d/blacklist-nouveau.conf` equivalent content through Ansible.
- Renders `/etc/default/grub.d/99-gpu-compute-blacklist.cfg` equivalent content through Ansible.
- Uses a configurable root path so render checks can run safely against `/tmp`.

## Inventory Model

Hosts with GPU compute or passthrough needs should be members of `gpu_compute` and set:

```yaml
gpu_compute_enabled: true
gpu_host_policy_blacklisted_modules:
  - nouveau
  - nvidiafb
```

BMC-managed hosts should be members of `bmc_managed`. Dell hosts should also be members of `dell_idrac`.

Credential values must come from Ansible Vault. Plaintext temporary credential files are only intake sources and must not be committed.

## Validation

Validation is intentionally lightweight for scaffolding:

- `ansible-playbook playbooks/gpu-host-policy-render-check.yml` must render blacklist and GRUB drop-in files into a temporary root and assert their contents.
- `ansible-playbook --syntax-check playbooks/bmc-redfish-validate.yml` must parse the BMC playbook and roles.
- `git diff --check` must pass before commit.
