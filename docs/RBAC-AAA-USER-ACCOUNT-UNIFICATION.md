# RBAC-AAA User Account Unification Analysis

## Scope

This analysis turns the emergency local user bootstrap notes from
`/root/operator-private/ephemeral-notes/2026-0528/CRITICAL-PATH/2026-0528_m70-forge.users-bootstrapping.shx`
into an implementation plan for central, FreeIPA-backed user, group, sudo,
SSH-key, and home-directory management.

The source script is intentionally not copied into this repository. It contains
operator SSH public-key material and an imperative local-host bootstrap shape
that should be replaced by repo-managed identity intent plus gated FreeIPA and
Ansible applies.

## Current repo baseline

The repo already has the correct control-plane direction:

- FreeIPA is the identity and policy source of truth in `docs/IDENTITY-AAA.md`.
- Non-secret identity intent is modeled in
  `gentoo-liveiso-ansible/identity-source-definitions/local-rfc1918.yml`.
- `scripts/validate_identity_source.py` validates UID/GID ranges, duplicate
  IDs, group references, and secret-free identity data.
- `scripts/render_identity_sync_plan.py` and
  `scripts/apply_identity_sync_plan.py` render and optionally apply FreeIPA
  groups, users, SSH public keys, host enrollment records, and FreeRADIUS
  client data.
- `playbooks/identity-source-apply.yml` runs that apply path through explicit
  mutation gates.
- `playbooks/ipa-client-live-apply.yml` enrolls Linux hosts into FreeIPA/SSSD
  and validates NSS, PAM, SSSD SSH-key lookup, and host keytab state.

The source notes expose a legacy local POSIX account set that predates that
control-plane shape. The implementation must therefore migrate intent into the
FreeIPA identity source rather than running `groupadd`, `useradd`,
`ssh-keygen`, or local `/etc/sudoers.d` writes on every host.

## Legacy account inventory from the notes

The bootstrap script creates the following groups and users locally:

| Principal | Type | POSIX ID | Primary group | Supplemental groups | Shell | Notes |
| --- | --- | ---: | --- | --- | --- | --- |
| `ltcol-forge` | system user/group | 64 | `ltcol-forge` | `yukon`, `wheel`, `dialout`, `adm`, `forge-superusers`, `verwalterin` | `/usr/bin/bash` | Central Forge operator account; old script creates `/home/ltcol-forge`. |
| `forge-superusers` | group | 1000 | n/a | n/a | n/a | Current script grants passwordless sudo. |
| `forge1`..`forge6` | user/group | 1001..1006 | same-name group | `yukon`, `wheel`, `dialout`, `forge-superusers`, `verwalterin` | `/bin/bash` | Worker identities; old script creates local SSH keys. |
| `eva` | user/group | 1024 | `eva` | `yukon`, `wheel`, `tty`, `dialout`, `adm` | `/bin/bash` | Human operator identity. |
| `backups` | user/group | 2048 | `backups` | `wheel` | `/bin/sh` | Data archival automation. |
| `verwalterin` | user/group | 4096 | `verwalterin` | `wheel`, `tty`, `dialout`, `adm` | `/bin/sh` | Network/admin automation and `nfsnasa` replacement per notes. |
| `yukon` | group | 5120 | n/a | n/a | n/a | Shared operator group. |
| `robin` | user/group | 16385 | `robin` | `yukon`, `wheel`, `tty`, `dialout`, `adm` | `/bin/bash` | Human operator identity. |

The notes also install static `authorized_keys` files and local sudoers files
for `%wheel` and `%forge-superusers`. Those behaviors need to move to FreeIPA
SSH public-key attributes and FreeIPA sudo rules.

## Critical design decision: preserve low IDs or remap?

The current repo identity source reserves FreeIPA-managed POSIX IDs in the
`200000-399999` range through `RFC1918.HOST_low_id_range`. The noted accounts
use historic low POSIX IDs (`64`, `1000-1006`, `1024`, `2048`, `4096`, `5120`,
`16385`). That creates the main design fork:

1. **Preserve historic IDs exactly.** This keeps existing NFS ownership and
   restored home trees valid, but requires a dedicated FreeIPA legacy POSIX ID
   range and strict collision checks against every host's local `/etc/passwd`
   and `/etc/group` before enrollment.
2. **Remap into `200000-399999`.** This matches the current identity source
   policy, but requires a controlled ownership migration for every preserved
   home directory and shared data tree.

The operational requirement says the associated UID/GID mappings and permission
structures must be retained. Therefore the implementation plan should preserve
historic IDs, but only after adding explicit repo validation for a separate
legacy ID-range policy. Do not bypass the validator by hand-editing FreeIPA.

## Target architecture

### 1. FreeIPA is authoritative for accounts and policy

- Add legacy account and group records to the identity source.
- Extend the identity source schema if necessary to support multiple FreeIPA
  local ID ranges or an explicit `legacy_posix_id_range` section.
- Require validation to prove every UID/GID is inside an approved range and has
  no duplicate across users, service accounts, and groups.
- Apply groups and users on the FreeIPA controller first.
- Store SSH public keys as FreeIPA user attributes; do not render host-local
  `authorized_keys` except for root/break-glass accounts outside the domain.
- Implement sudo through FreeIPA sudo rules:
  - `%linux-admin` and carefully named operator groups can receive normal host
    admin policy.
  - `%forge-superusers` can receive passwordless sudo only as an explicit,
    audited sudo rule with host or hostgroup scope.
  - Avoid retaining `%wheel ALL=(ALL:ALL) NOPASSWD: ALL` as a fleet-wide local
    file.

### 2. Hosts are FreeIPA/SSSD clients, not account databases

- Use `ipa-client-live-apply.yml` or a hardened successor for host enrollment.
- Keep local root break-glass until FreeIPA NSS/PAM/SSH/sudo validation passes
  for each canary host.
- Use SSSD for `passwd`, `group`, `shadow`, `services`, `netgroup`, `sudo`, and
  `ssh` lookups.
- Continue validating `getent passwd`, `sss_ssh_authorizedkeys`, `su -s
  /bin/true`, and `sudo -l -U` on each host class before widening rollout.

### 3. Floating home directories use NFSv4.2

Local `useradd -m` is the wrong persistence model. The target should be:

- Home path intent lives in FreeIPA user attributes and/or an identity-source
  `home` object.
- Home-directory backing storage is provisioned by Ansible on the NFS service
  side before users are enabled broadly.
- Linux clients mount floating homes through autofs/SSSD automount maps or a
  repo-managed `/home` mount policy.
- Default client transport is NFSv4.2.
- Hosts with validated multiple LACP links can use the multipath-capable mount
  profile. The implementation should model this as a host capability, not as a
  global assumption. Candidate controls include bonded management links,
  validated NFS session trunking/pNFS support, or Linux `nconnect` where the
  server/client pair supports it.
- Hosts without validated multi-link transport use the same NFSv4.2 export with
  a single-path mount profile.
- Kerberized NFS should be the preferred steady state for domain homes; if
  initial rollout uses `sec=sys`, it must be called out as transitional and
  bounded by a follow-up gate.

### 4. SSH key and generated-key handling

The old script generates SSH private keys on hosts for every identity. That is
not acceptable as a fleet-wide steady state for human or privileged Forge
accounts.

- Human/operator keys should be operator-held and enrolled as FreeIPA public
  keys.
- Forge automation keys should be generated by a controlled key-management
  workflow with rotation, not by repeated host-local `ssh-keygen` calls.
- The identity source should reference vault variables for SSH public keys if
  the repo must not carry key material directly.
- No private key material belongs in repo, Ansible stdout, CI logs, or FreeIPA
  audit summaries.

## Implementation plan

### Phase 0 - audit and import model

1. Add a parser or hand-authored identity-source fragment for the legacy account
   map above.
2. Add a host audit playbook that collects local `/etc/passwd`, `/etc/group`,
   `/etc/sudoers.d`, home path ownership, and NFS mount state from all Linux
   hosts.
3. Produce a gap report:
   - local-only account exists but is absent from FreeIPA;
   - FreeIPA account exists but host cannot resolve it through SSSD;
   - UID/GID collision with host-local system accounts;
   - home directory exists locally but has no NFS-backed target;
   - sudo policy exists locally but has no FreeIPA equivalent.

### Phase 1 - identity source and validator changes

1. Extend `identity-source-definitions/local-rfc1918.yml` with the legacy
   principals.
2. Add schema support for multiple local ID ranges or a named legacy range.
3. Add tests that fail if the low-ID principals are outside declared ranges,
   duplicate IDs, or carry plaintext secrets.
4. Teach the renderer/apply path to include FreeIPA sudo-rule intent if this is
   not already modeled.
5. Keep `radiusd` sysaccount handling separate; it is not part of the Forge
   user-account migration.

### Phase 2 - FreeIPA controller apply

1. Run `identity-source-validate.yml` and `render_identity_sync_plan.py` in
   dry-run mode.
2. Apply groups and users on `svc_identity_ipa01` through
   `identity-source-apply.yml` with `IDENTITY_SYNC_APPLY=1` and
   `IDENTITY_SYNC_APPLY_FREEIPA=1`.
3. Apply SSH public keys through the same path or the existing
   `freeipa-ssh-key-sync.yml` workflow.
4. Add FreeIPA sudo rules and HBAC rules with hostgroup scoping.
5. Validate on the controller:
   - `ipa group-show`, `ipa user-show --all`, `ipa sudorule-show`,
     `ipa hbactest`;
   - no secret or public-key material appears in Ansible logs except redacted
     variable names.

### Phase 3 - NFSv4.2 home service

1. Select the authoritative home export root and storage host.
2. Provision home directories with exact UID/GID ownership before client login
   tests.
3. Add client mount profiles:
   - `nfsv4_2_single_path_home` for ordinary hosts;
   - `nfsv4_2_multipath_home` for hosts with validated multiple LACP links or
     other proven NFS multipath capability.
4. Gate all multipath claims with live checks: active links, server support,
   client mount options, and actual failover/throughput smoke evidence.

### Phase 4 - host rollout

1. Enroll or validate FreeIPA/SSSD on one canary host per class:
   - M70 automation admin;
   - Slurm controller;
   - Slurm worker;
   - VM/service host;
   - workstation if still needed.
2. Validate identity end-to-end for each canary:
   - `getent passwd ltcol-forge` and representative `forgeN` identities;
   - `id <user>` group expansion;
   - `sss_ssh_authorizedkeys <user>`;
   - SSH login with FreeIPA key lookup;
   - `sudo -l -U <user>` for sudo-scoped groups;
   - home path mounted from NFSv4.2 and write/read permissions correct.
3. Roll out with the Slurm/Ansible workflow only after the canary target set is
   correctly limited and preflight dependency validation passes.

## Validation requirements

Minimum repo-side validation before live mutation:

```bash
python3 scripts/validate_identity_source.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/identity-source-definitions/local-rfc1918.yml \
  --format json

python3 scripts/render_identity_sync_plan.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/identity-source-definitions/local-rfc1918.yml \
  --format json

ansible-playbook --syntax-check \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/identity-source-apply.yml
```

Minimum live validation before widening beyond canary:

```bash
ipa user-show ltcol-forge --all
ipa group-show forge-superusers --all
getent passwd ltcol-forge
getent group forge-superusers
sss_ssh_authorizedkeys ltcol-forge
sudo -l -U ltcol-forge
findmnt -T /home/ltcol-forge
nfsstat -m
```

## Risks and controls

| Risk | Control |
| --- | --- |
| Low UID/GID collision with system or local accounts | Fleet audit before apply; identity validator must know declared legacy ranges. |
| NFS ownership drift | Provision server-side home directories with exact IDs before host rollout; validate `stat -c '%u:%g'`. |
| Passwordless sudo too broad | Use FreeIPA sudo rules scoped by hostgroup; keep local sudoers only for break-glass. |
| SSH key sprawl | Store public-key intent centrally; never generate private keys on every host as a side effect of account rollout. |
| Multipath claims outpace network reality | Treat multipath as a host capability with explicit validation, not a default. |
| Lockout during SSSD/PAM changes | Preserve root break-glass, run one host class at a time, and require rollback commands in the runbook. |

## Recommended next branch

The next implementation branch should be narrow and test-first:

1. Add identity-source schema support for the legacy Forge account set and low
   POSIX ID range.
2. Add validator tests for duplicate IDs, out-of-range IDs, and forbidden
   plaintext secrets.
3. Add renderer output for FreeIPA user/group/sudo/HBAC intent without live
   mutation.
4. Add an NFSv4.2 home-directory client/server plan doc and a dry-run Ansible
   role skeleton.

Only after that branch is green should the live FreeIPA controller be mutated.
