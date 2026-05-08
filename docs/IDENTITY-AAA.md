# Identity And AAA

This repo now carries a first-pass Stage 5 scaffold for domain RBAC and AAA built around:

- `FreeIPA` as the identity and policy source of truth
- `SSSD` as the Linux host and VM domain client
- `FreeRADIUS` as the network AAA bridge for switches, routers, firewalls, WAPs, and VPN edges

## Current Shape

New roles:

- `freeipa_controller`
- `ipa_client`
- `freeradius_bridge`

New profile overlays:

- `aaa-domain-client`
- `vm-identity-controller`
- `metal-identity-controller`

New policy data:

- `gentoo-liveiso-ansible/aaa-policy-definitions/site-baseline.yml`

The scaffold is intentionally opt-in. Existing install flows do not become domain-bound unless a host profile includes the identity overlays.

## Live Bootstrap

Because native FreeIPA server packaging is not available in the current Gentoo
image, the first live controller is a dedicated Rocky 9 VM on Hasslehoff:

- inventory host: `svc_identity_ipa01`
- Proxmox VMID: `1063`
- management address: `172.16.99.63/24`
- hostname: `ipa01.rfc1918.host`
- realm: `RFC1918.HOST`
- domain: `rfc1918.host`
- bootstrap scripts:
  - `scripts/proxmox-create-freeipa-rocky-vm.sh`
  - `scripts/bootstrap-freeipa-rocky.sh`
  - `scripts/configure-freeradius-freeipa.sh`
- validated services:
  - `ipa.service`
  - `dirsrv@RFC1918-HOST.service`
  - `krb5kdc.service`
  - `httpd.service`
  - `sssd.service`
  - `radiusd.service`
- recovery snapshot: `codex-freeipa-radius-live`
- validation playbook:
  - `playbooks/identity-controller-validate.yml`

Secrets for the controller are generated outside the repo under
`/root/operator-private/identity/` and are copied to root-only state on the VM.

The initial live policy includes:

- `codex-admin` as the central non-root SSH identity, in `linux-admin`
- `radius-test` as the redacted validation identity, in `network-readonly`
- `radiusd` LDAP bind account under `cn=sysaccounts,cn=etc`
- local management RADIUS client scope: `172.16.99.0/24`

Validate the live controller with:

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/identity-controller-validate.yml
```

The optional `radtest` path is disabled by default to avoid passing secrets in
normal operator output. Enable it only with vault-backed variables.

## Important Constraint

The current local Gentoo tree used by this repo exposes the directory, Kerberos, SSSD, and FreeRADIUS primitives, but it does **not** currently expose a native `FreeIPA` server package. Because of that:

- the `freeipa_controller` role renders manifests, seed configs, and bootstrap helpers
- the controller package source is modeled as `overlay-managed`
- Linux client enrollment and RADIUS bridge policy are still kept in repo-native Ansible data

## Recommended Topology

- `FreeIPA` controller on a dedicated VM or metal host
- `FreeRADIUS` bridge on the same controller first, split later if scale demands it
- `SSSD` on:
  - Jenkins controller
  - distcc builder nodes
  - container host VMs
  - other managed Linux machines

Applications inside containers should prefer app-layer identity such as OIDC later; the current scaffold is for host and infrastructure AAA first.

## Example Inventory Layers

Controller example:

- host var: `inventories/examples/host_vars/vm-identity-controller.yml`
- group var: `inventories/examples/group_vars/identity_controllers.yml`

Domain client example:

- overlay profile: `profile-definitions/aaa-domain-client.yml`
- group var: `inventories/examples/group_vars/aaa_domain_clients.yml`

The Jenkins controller and builder-farm node examples now include the `aaa-domain-client` overlay.

## AAA Policy Model

The baseline policy file currently models:

- Linux roles
  - `linux-admin`
  - `ci-builder`
- Network roles
  - `network-admin`
  - `network-readonly`
- Device groups
  - `switches`
  - `routers`
  - `firewalls`
  - `waps`

This keeps group and role naming stable while allowing vendor-specific RADIUS reply attributes to differ by device class.

## Next Steps

1. Move identity controller secrets into Ansible Vault and replace live helper scripts with role-driven operations.
2. Enroll the Jenkins controller as the first `aaa-domain-client`.
3. Enroll one builder-farm node.
4. Validate network AAA against one switch or router before widening device rollout.
5. Decide whether TACACS+ is needed for Cisco device coverage.
6. Add power-management AAA coverage for APC PDUs, APC ATS, and UPS network
   management cards through FreeRADIUS, with local break-glass accounts retained.

## Enrollment Sequence

The active rollout sequence is deliberately conservative:

1. Normalize FreeIPA and FreeRADIUS controller secrets into vault-backed
   role operations.
2. Enroll one Linux VM or host through SSSD and validate non-root SSH key
   login through the domain.
3. Enroll one network device through FreeRADIUS using a read-only operator role.
4. Enroll the AP7901 PDU at `172.16.99.241` through FreeRADIUS after its
   non-secret NetBox inventory exists.
5. Expand to APC UPS, APC ATS, additional PDUs, switches, WAPs, routers, VPN
   endpoints, and HTTP applications.

Power and network infrastructure must retain local break-glass credentials
until RADIUS behavior is validated per device class. NetBox stores device
identity, management IP, protocol capability, and outlet/port metadata only;
AAA bind passwords, SNMPv3 secrets, and local fallback passwords remain in
Ansible Vault or operator-private storage.
