# BMC Management

This document covers Ansible-managed baseboard management controller workflows
for Redfish-capable systems, Dell iDRAC systems, and future netboot reinstall
automation.

## Roles

### `bmc_redfish`

`bmc_redfish` is the vendor-neutral Redfish role. It uses
`ansible.builtin.uri` directly so the first control-plane pass does not depend
on vendor-specific collections.

Default behavior is safe:

- `bmc_redfish_enabled: false`
- `bmc_redfish_allow_mutation: false`

When enabled with vaulted credentials, the role reads:

- `/redfish/v1/`
- the systems collection
- the selected system
- the managers collection
- the chassis collection

It publishes `bmc_redfish_facts` for later NetBox/DCIM intake, validation, and
health checks.

Mutation actions are refused unless `bmc_redfish_allow_mutation: true` is set.
The gated actions are:

- `bmc_redfish_power_action`
- `bmc_redfish_boot_override.enabled`
- `bmc_redfish_virtual_media.enabled`

### `bmc_idrac`

`bmc_idrac` is a Dell wrapper around `bmc_redfish`. It applies iDRAC defaults:

- system ID: `System.Embedded.1`
- manager ID: `iDRAC.Embedded.1`
- virtual media path:
  `/redfish/v1/Managers/iDRAC.Embedded.1/VirtualMedia/CD`

The wrapper validates Dell-like manufacturer/model facts when
`bmc_idrac_validate_vendor: true`.

## Inventory Groups

Use these groups in `inventories/local-network/hosts.yml`:

- `bmc_managed`: any host with BMC Redfish management.
- `dell_idrac`: Dell PowerEdge iDRAC hosts such as R630 and R730xd.

Hasslehoff is already in `bmc_managed`, but live Redfish is intentionally
disabled until its IPMI/Redfish credentials are imported into Ansible Vault
under `PNR-023`.

## Validation

Syntax-check the BMC playbook without making BMC changes:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ANSIBLE_STDOUT_CALLBACK=default ansible-playbook --syntax-check playbooks/bmc-redfish-validate.yml
```

The `ANSIBLE_STDOUT_CALLBACK=default` override is useful on hosts where the
`community.general.yaml` callback collection is not installed locally.

## Mutation Example

Power actions require explicit operator intent:

```yaml
bmc_redfish_enabled: true
bmc_redfish_allow_mutation: true
bmc_redfish_power_action: GracefulRestart
```

iPXE or installer boot override also requires the mutation gate:

```yaml
bmc_redfish_enabled: true
bmc_redfish_allow_mutation: true
bmc_redfish_boot_override:
  enabled: true
  target: Pxe
  mode: UEFI
  override_enabled: Once
```

Virtual media insertion requires a vendor-correct endpoint and image URL:

```yaml
bmc_redfish_enabled: true
bmc_redfish_allow_mutation: true
bmc_redfish_virtual_media:
  enabled: true
  insert_endpoint: /redfish/v1/Managers/iDRAC.Embedded.1/VirtualMedia/CD
  image_url: http://boot.example.net/path-b/installer.iso
  inserted: true
  write_protected: true
```

Do not enable these mutation variables in broad groups. Put them in a targeted
host vars file or an extra-vars file for a specific maintenance window.
