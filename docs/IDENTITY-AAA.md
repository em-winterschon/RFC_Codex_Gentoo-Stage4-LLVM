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

1. Introduce the selected FreeIPA server package source through an overlay or external packaging path.
2. Validate one `vm-identity-controller` install end to end.
3. Enroll the Jenkins controller as the first `aaa-domain-client`.
4. Enroll one builder-farm node.
5. Validate `radiusd` against one switch or router before widening device rollout.
