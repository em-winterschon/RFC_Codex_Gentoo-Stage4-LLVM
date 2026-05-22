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

## Identity Source Of Truth

The first repo-safe source-of-truth layer is:

- `identity-source-definitions/local-rfc1918.yml`
- `scripts/validate_identity_source.py`
- `scripts/render_identity_sync_plan.py`
- `playbooks/identity-source-validate.yml`

This layer stores only non-secret identity intent: realm, domain, groups,
UID/GID assignments, users, service accounts, host enrollment targets, RADIUS
clients, and rollout gates. Passwords, RADIUS shared secrets, LDAP bind
passwords, local break-glass credentials, SNMP secrets, and bootstrap tokens
remain in Ansible Vault or operator-private paths.

The local RFC1918 source currently models:

- FreeIPA local ID range `RFC1918.HOST_low_id_range`, reserving POSIX IDs
  `200000-399999` for repo-managed local identities
- `codex-admin` as the first central non-root operator identity
- `radius-test` as the redacted validation identity
- `radiusd` as the FreeRADIUS LDAP bind service account
- `gmktek_nucbox_k10_stage5_candidate` as the first Linux SSSD enrollment
  target
- `pdu_rfc99_corectrl_ap7901` as the first RADIUS power-device client

Validate and render the non-mutating sync plan with:

```bash
python3 scripts/validate_identity_source.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/identity-source-definitions/local-rfc1918.yml \
  --format json

python3 scripts/render_identity_sync_plan.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/identity-source-definitions/local-rfc1918.yml \
  --format json
```

The renderer intentionally outputs secret variable names such as
`vault_radius_client_pdu_rfc99_corectrl_ap7901_secret`, not secret values. Live
FreeIPA and FreeRADIUS mutation should remain an explicit operator-run or
approval-gated CI action until rollback and audit behavior are proven.

## Gated Apply

The first apply path is now available through:

- `scripts/apply_identity_sync_plan.py`
- `playbooks/identity-source-apply.yml`

The apply tool is dry-run by default and prints only redacted plan metadata. Live
mutation requires all relevant gates:

```bash
IDENTITY_SYNC_APPLY=1 \
IDENTITY_SYNC_APPLY_FREEIPA=1 \
python3 scripts/apply_identity_sync_plan.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/identity-source-definitions/local-rfc1918.yml \
  --apply \
  --provider freeipa \
  --audit-log /var/log/identity-sync/freeipa.jsonl

IDENTITY_SYNC_APPLY=1 \
IDENTITY_SYNC_APPLY_FREERADIUS=1 \
vault_radius_client_pdu_rfc99_corectrl_ap7901_secret='from-vault-not-shell-history' \
python3 scripts/apply_identity_sync_plan.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/identity-source-definitions/local-rfc1918.yml \
  --apply \
  --provider freeradius \
  --freeradius-output /etc/raddb/clients.d/rfc1918-generated.conf \
  --audit-log /var/log/identity-sync/freeradius.jsonl
```

In normal operations, pass vault-backed values through Ansible environment data,
not through shell history. The JSON summary and audit log intentionally preserve
vault variable names but redact resolved secret values and SSH key material.

Current apply scope:

- FreeIPA local ID range creation and UID/GID guard checks before account
  mutation.
- FreeIPA groups, users, SSH public keys, supplemental group membership, hosts,
  and hostgroups through the `ipa` CLI.
- FreeRADIUS `clients.d` rendering for managed client records, with shared
  secrets resolved only during gated apply.
- LDAP sysaccount creation for bind DNs remains a manual action in the plan
  because the current `radiusd` account uses a FreeIPA sysaccount DN rather than
  a normal IPA user object.

## NetBox Admin Access

As of 2026-05-22, `svc-netbox-stage4` is not yet using FreeIPA-backed NetBox
group or superuser mapping. The live NetBox API shows only the local `admin`
account and no NetBox groups or object permissions, so adding a FreeIPA user
does not by itself grant NetBox login or admin rights.

Current process:

1. Model the human identity in
   `identity-source-definitions/local-rfc1918.yml`, including a UID/GID from
   the reserved human-user range, the correct FreeIPA groups, and vault-backed
   password or SSH-key variable references.
2. Run `scripts/validate_identity_source.py` and
   `scripts/render_identity_sync_plan.py`, then review the rendered plan.
3. Apply the FreeIPA side only through the explicit gated apply path
   (`IDENTITY_SYNC_APPLY=1`, `IDENTITY_SYNC_APPLY_FREEIPA=1`,
   `--provider freeipa`) from an operator context with the required vault
   values loaded.
4. Grant NetBox admin access separately in NetBox using the local `admin`
   account, the NetBox admin UI/API, or an on-host Django management command.
   Until FreeIPA/NetBox SSO mapping is implemented, this is a NetBox-local
   permission step, not an identity-source apply side effect.

The intended durable path is to add a repo-modeled `netbox-admin` FreeIPA group,
configure NetBox authentication against FreeIPA, and map that group to NetBox
staff/superuser or an equivalent least-privilege permission set. That mapping is
not active yet.

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

## FreeIPA Online Gates

For operational purposes, FreeIPA "domain online" means the SSSD IPA backend can
bind to the domain provider, not merely that `ipa.service` is active. The
minimum gates are:

- the IPA server FQDN resolves to the canonical hostname used by
  `/etc/ipa/default.conf`, `/etc/krb5.conf`, certificates, and keytabs
- `/etc/krb5.keytab` can obtain a host ticket for the IPA host principal
- Kerberos KDC and LDAP/LDAPS are reachable with acceptable time skew
- LDAP GSSAPI bind succeeds against the canonical `ldap/<fqdn>` service
  principal
- SSSD can resolve the IPA provider and reports `Online status: Online`
- NSS/PAM can resolve the target user and pass account checks

The 2026-05-09 outage was caused by local `/etc/hosts` fallback ordering:
`identity-ldap-radius.rfc1918.host` appeared before `ipa01.rfc1918.host` for
`172.16.99.63`, so Kerberos looked for
`ldap/identity-ldap-radius.rfc1918.host@RFC1918.HOST`. The DNS inventory
planner now renders device canonical records before service VIP aliases on
shared IPs.

The initial live policy includes:

- `codex-admin` as the central non-root SSH identity: UID `200100`, primary GID
  `201000` / `linux-admin`, with `ci-builder`, `network-admin`, and
  `power-admin` supplemental groups
- `radius-test` as the redacted validation identity: UID `200101`, primary GID
  `201110` / `network-readonly`, with `power-readonly` supplemental group
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

## First Live Linux Client

The first live SSSD/RBAC workstation client gate is the GMKtek K10:

- inventory host: `gmktek_nucbox_k10_stage5_candidate`
- intended FQDN: `gmktek-k10-stage5.rfc1918.host`
- live address: `172.16.99.156`
- enrollment playbook: `playbooks/ipa-client-live-apply.yml`
- validation playbook: `playbooks/ipa-client-live-validate.yml`

On 2026-05-09 the K10 live Gentoo image passed the repo-managed FreeIPA client
gates before reboot. A later PDU reboot proved the first rootfs did not persist
the live mutation because it lacked SSSD and `/usr/lib64/sssd/libsss_ipa.so`.
The promoted 2026-05-11 rootfs now reboots with SSSD, Samba, Kerberos,
OpenLDAP, and `libsss_ipa.so`; post-boot `ipa-client-live-apply.yml` and
`ipa-client-live-validate.yml` passed, and floating SSH as `codex-admin`
resolved the expected UID/GID/group mappings. The remaining blocker is
unattended durable enrollment without putting `/etc/krb5.keytab` into public
HTTP netboot artifacts.

The root cause of the initial SSSD failure was package policy: Gentoo's
`sys-auth/sssd-2.12.0-r2` did not install the IPA backend unless SSSD was built
with `samba`, and Samba also required `winbind`. The AAA profile now applies:

- `sys-auth/sssd samba`
- `net-fs/samba winbind`

SSSD `2.12` also rejects `config_file_version = 2` in `[sssd]`, so the client
template and live playbooks omit that directive.

The live image does not keep system D-Bus running by default, so
`sssctl domain-status` can fail with `Unable to connect to system bus` even
while the IPA backend is functional. The validation path accepts that specific
live-image failure only when all stronger local gates pass:

- `/usr/lib64/sssd/libsss_ipa.so` exists
- `sssctl config-check` reports zero validator issues
- `getent passwd codex-admin` resolves UID `200100`
- `getent group linux-admin` resolves GID `201000`
- `sss_ssh_authorizedkeys codex-admin` returns the FreeIPA SSH key
- PAM account validation for `codex-admin` succeeds
- `sshd -T` reports PAM enabled and SSSD authorized-key lookup configured

The first transient floating SSH validation passed from the operator host:

```bash
ssh codex-admin@172.16.99.156 'id; hostname -f; pwd'
```

It resolved `codex-admin` with UID `200100`, primary group `linux-admin`, and
supplemental `ci-builder`, `network-admin`, and `power-admin` memberships.

## Secure First-Boot Enrollment Producer

The safe enrollment model is now split into two sides:

- operator-side bundle production and encryption
- host-side first-boot consumption and FreeIPA enrollment

The producer side is intentionally not part of the public HTTP netboot rootfs.
It renders a short-lived FreeIPA host OTP bundle, validates its hostname and
expiry, encrypts it with `age`, and refuses to write the encrypted artifact
inside the git repository unless explicitly overridden. The primary command
wrapper is:

```bash
SECURE_FIRSTBOOT_BUNDLE_APPLY=1 \
scripts/with-ansible-vault-env.sh ansible-playbook \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/secure-firstboot-bundle-stage.yml
```

The playbook must receive vault-backed values for:

- target FQDN
- FreeIPA realm, domain, and server
- bundle expiry
- generation ID
- host OTP
- target host `age` recipient

The corresponding low-level producer is:

```bash
scripts/stage_secure_firstboot_bundle.py \
  --bundle /root/operator-private/secure-firstboot/bundle.json \
  --expected-fqdn gmktek-k10-stage5.rfc1918.host \
  --recipient "${AGE_RECIPIENT}" \
  --output /root/operator-private/secure-firstboot/bundle.json.age \
  --apply
```

Secrets are protected by three gates:

- plaintext OTP bundles remain under operator-private paths only
- `no_log: true` wraps Ansible tasks that handle OTP or encrypted bundle data
- encrypted bundles are denied under the repo tree by default

## Tang And Clevis NBDE Policy

Tang/Clevis is tracked as optional hardening for disk-installed hosts, not as a
replacement for host-bound identity. Tang-only decryption is not sufficient for
first-boot enrollment because any host that can reach the Tang advertisement can
recover the secret. The only approved NBDE policy for this path is:

```text
tpm2+tang
```

The initial Tang service role is mutation-gated:

- profile: `vm-tang-nbde-server`
- role: `tang_nbde_server`
- service atom: `tang-advertisement`
- default state: disabled
- package source: Guru overlay until `app-crypt/tang` and `app-crypt/clevis`
  are available in the base package policy

The client package overlay is `secure-firstboot-nbde-client` and includes
Clevis plus TPM2 tooling. It should be enabled only for disk-install profiles
that have a real TPM, a measured boot plan, and an E2ET gate proving that
unlock and FreeIPA enrollment still work after power loss.

## Secure First-Boot Enrollment

The approved durable enrollment path is FreeIPA one-time host password delivery
through a short-lived encrypted first-boot bundle:

- FreeIPA creates or resets the host OTP with `ipa host-add --random` or the
  equivalent host OTP reset flow.
- `scripts/render_secure_firstboot_bundle.py` renders a plaintext JSON bundle
  from non-secret CLI input plus the OTP supplied through an environment
  variable.
- The bundle is encrypted to the target host with `age` and fetched by the
  opt-in OpenRC `stage5-firstboot-enroll` service.
- The first-boot script decrypts the bundle, validates expiry and FQDN with
  `scripts/validate_secure_firstboot_bundle.py`, runs the configured enrollment
  command, and requires `/etc/krb5.keytab` to be created on the target.
- Tang/Clevis remains optional future work because Gentoo requires Guru repo
  ebuilds for `clevis` and `tang`, newer Clevis ebuilds are masked for dracut
  boot concerns, and Tang-only decryption proves network presence rather than
  host identity.

The K10 gate is still not reboot-durable until either disk install or this
secure first-boot bundle path is applied live, then hostname policy, offline
cache, sudo rules, and local break-glass behavior pass across reboot before
broad Linux enrollment.

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
2. Enroll the GMKtek K10 as the first bare-metal `aaa-domain-client`.
3. Enroll the Jenkins controller.
4. Enroll one builder-farm node.
5. Validate network AAA against one switch or router before widening device rollout.
6. Decide whether TACACS+ is needed for Cisco device coverage.
7. Add power-management AAA coverage for APC PDUs, APC ATS, and UPS network
   management cards through FreeRADIUS, with local break-glass accounts retained.

## Enrollment Sequence

The active rollout sequence is deliberately conservative:

1. Normalize FreeIPA and FreeRADIUS controller secrets into vault-backed
   role operations.
2. Enroll the GMKtek K10 through SSSD and validate non-root SSH key login
   through the domain. K10 is now live in NetBox as
   `gmktek_nucbox_k10_stage5_candidate` with primary management IP
   `172.16.99.156/24`.
3. Enroll one network device through FreeRADIUS using a read-only operator role.
4. Enroll the AP7901 PDU at `172.16.99.241` through FreeRADIUS. Its non-secret
   NetBox inventory now exists as `pdu_rfc99_corectrl_ap7901`, with management
   interface `mgmt`, primary IP `172.16.99.241/24`, and outlet `outlet6`
   labeled `host_gmktec_k10`.
5. Expand to APC UPS, APC ATS, additional PDUs, switches, WAPs, routers, VPN
   endpoints, and HTTP applications.

Power and network infrastructure must retain local break-glass credentials
until RADIUS behavior is validated per device class. NetBox stores device
identity, management IP, protocol capability, and outlet/port metadata only;
AAA bind passwords, SNMPv3 secrets, and local fallback passwords remain in
Ansible Vault or operator-private storage.
