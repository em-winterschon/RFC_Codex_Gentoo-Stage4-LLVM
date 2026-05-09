# AAA Source Of Truth Design

## Goal

Create a repo-safe source-of-truth layer for identity and AAA that can drive
FreeIPA and FreeRADIUS reconciliation without committing passwords, shared
secrets, SNMP secrets, or bootstrap credentials.

## Architecture

The repo owns non-secret desired state: realms, groups, UID/GID assignments,
human and service principals, host enrollment targets, RADIUS client identity,
and rollout gates. Ansible Vault owns secret values: temporary passwords,
RADIUS shared secrets, local break-glass credentials, and bind credentials.

The first implementation is intentionally read-only/render-only. It validates a
YAML identity source file and renders a deterministic sync plan that later
playbooks can apply to FreeIPA and FreeRADIUS. Live mutation remains an explicit
operator action after K10 and AP7901 validation gates pass.

## Files

- `identity-source-definitions/local-rfc1918.yml` stores non-secret desired
  state for the local lab realm.
- `scripts/validate_identity_source.py` validates schema, references, UID/GID
  uniqueness, and secret hygiene.
- `scripts/render_identity_sync_plan.py` converts validated source data into a
  deterministic FreeIPA/FreeRADIUS sync-plan JSON document.
- `playbooks/identity-source-validate.yml` exposes the validation path through
  Ansible.
- `docs/IDENTITY-AAA.md` and the wiki mirror document the workflow.

## Initial Scope

The first source file covers:

- realm `RFC1918.HOST` and domain `rfc1918.host`
- groups `linux-admin`, `ci-builder`, `network-admin`, `network-readonly`,
  `power-admin`, and `power-readonly`
- users `codex-admin` and `radius-test`
- service bind account `radiusd`
- first host enrollment target `gmktek_nucbox_k10_stage5_candidate`
- first RADIUS power-device target `pdu_rfc99_corectrl_ap7901`

## Secret Handling

No plaintext secrets are allowed in the identity source. Secret references must
be variable names ending in `_var`, such as
`vault_radius_client_pdu_rfc99_corectrl_ap7901_secret`. Playbooks consume those
variables from Ansible Vault or operator-private environment files.

## Validation

The shell regression `test_identity_source_of_truth.sh` verifies:

- files exist and are wired into the test harness
- source validation passes for the local RFC1918 file
- invalid duplicate GID, unknown group, and plaintext RADIUS secret cases fail
- rendered sync plans contain FreeIPA groups/users, FreeRADIUS clients, vault
  secret references, and K10 enrollment data

