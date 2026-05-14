# EOD Status 2026-05-08

## Completed

- Promoted the K10/AP7901 intake sequence into a stacked draft PR:
  - PR `#103`: `codex/netbox-aaa-first-enrollment`
  - base: `codex/workstation-nscde-profile`
  - status: draft, mergeable
- Added the AAA identity source-of-truth scaffold:
  - PR `#105`: `codex/aaa-source-of-truth-sync`
  - base: `codex/netbox-aaa-first-enrollment`
  - status: draft, mergeable
  - commit: `8f157f1 Add AAA source-of-truth sync scaffold`
- Created `identity-source-definitions/local-rfc1918.yml` with non-secret
  desired state for:
  - `codex-admin`
  - `radius-test`
  - `radiusd`
  - K10 host enrollment
  - AP7901 RADIUS client enrollment
  - rollout gates for break-glass, SSSD login, and RADIUS validation
- Added source validation and deterministic render-only sync planning:
  - `scripts/validate_identity_source.py`
  - `scripts/render_identity_sync_plan.py`
  - `playbooks/identity-source-validate.yml`
- Updated AAA documentation and wiki mirror to describe the identity
  source-of-truth model, vault boundary, rollout targets, and validation
  commands.
- Wired `test_identity_source_of_truth.sh` into the full shell test harness.
- Sent local ntfy progress for the AAA PR through:
  - `https://msg-sun99-ntfysys.rfc1918.host/codex-progress`

## Verification

- `bash tests/shell/run-tests.sh`
  - result: `PASS: run-tests.sh`
- `python3 -m py_compile scripts/validate_identity_source.py scripts/render_identity_sync_plan.py`
  - result: pass
- `ansible-playbook --syntax-check -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/identity-source-validate.yml`
  - result: pass
- `git diff --check`
  - result: pass
- Changed-file secret-pattern scan:
  - no live secret material found
  - expected hits were the fake invalid-fixture `plaintext-secret`, field-name
    literals, and historical changelog/service names

## Current Gates

- The AAA source-of-truth path is render-only. It does not mutate FreeIPA,
  FreeRADIUS, SSSD clients, or APC devices yet.
- Live FreeIPA/FreeRADIUS apply needs an idempotent, audit-friendly playbook
  that resolves vault variables at runtime without printing secrets.
- K10 remains the correct first Linux SSSD client, but Stage5 install and
  domain enrollment still need to be executed on the target disk.
- AP7901 remains the correct first power-device RADIUS target, but local
  break-glass access and non-secret NetBox power-chain modeling must be
  validated before any authentication change.
- Open PR stack still needs merge sequencing:
  - PR `#20`: workstation/NsCDE base branch
  - PR `#103`: NetBox K10/AP7901 first enrollment
  - PR `#105`: AAA source-of-truth sync scaffold

## Major Pivots And Errors

- AAA moved from loose policy notes into a repo-safe source-of-truth model.
  This intentionally separates non-secret identity intent from Ansible Vault
  secret values and avoids premature live mutations.
- GitHub PR publishing is functioning with the Forge token for this workflow.
  PR `#105` was created as a stacked draft PR from the local branch.

## Outstanding Actions

1. Merge or advance the PR stack in dependency order:
   - `#20` workstation/NsCDE base
   - `#103` NetBox first-enrollment intake
   - `#105` AAA source-of-truth scaffold
2. Add an idempotent FreeIPA/FreeRADIUS apply playbook for the rendered
   identity sync plan.
3. Add a dry-run diff mode for identity sync so planned FreeIPA and RADIUS
   changes are reviewable before mutation.
4. Enroll K10 as the first SSSD/RBAC workstation client after the Stage5
   target install path is ready.
5. Validate AP7901 RADIUS auth with break-glass local admin retained and
   documented.
6. Continue FMT2/BigNetwork transport validation once the local bridge path is
   available.

## Backout Summary

The AAA scaffold is non-mutating. Backout is a normal git revert of PR `#105`.
No FreeIPA, FreeRADIUS, PDU, or host authentication state is changed by the
branch.

The NetBox first-enrollment branch is intended to remain non-secret. Any live
NetBox corrections should be made through the intake/apply workflow, not direct
manual database edits.

## Next Work Block

1. Commit and push this EOD report and wiki mirror.
2. Build the AAA apply path:
   - validate source
   - render sync plan
   - resolve vault variables
   - dry-run FreeIPA/RADIUS delta
   - apply only with an explicit mutation gate
3. Run first-client AAA validation on K10:
   - install Stage5 workstation target
   - enroll into FreeIPA
   - validate SSH key lookup, sudo policy, group membership, and SSSD cache
4. Run first-device AAA validation on AP7901:
   - confirm local break-glass
   - configure RADIUS client/server path
   - validate readonly and admin role behavior
