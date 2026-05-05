# Ansible Vault Workflow

## Goal

Keep operational credentials encrypted in the repository while preserving a
simple local workflow for Codex and operator-run Ansible commands.

The local vault environment file is intentionally outside the repo:

```bash
/root/.ssh/vault/ANSIBLE_VARS.ENV
```

That file exports the Ansible Vault identity and password-file settings used by
the helper scripts. Do not commit the env file, vault password files, decrypted
vault output, API tokens, or plaintext device passwords.

## Helper Scripts

Use the wrapper for every command that needs vault access:

```bash
scripts/with-ansible-vault-env.sh ansible-vault view \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/vault.yml
```

Use the validator before committing vault changes:

```bash
scripts/validate-ansible-vaults.sh
```

The validator checks two things:

- vault files start with the Ansible Vault header
- vault files decrypt with the configured local vault identity

It never prints decrypted content.

## Editing Secrets

Use:

```bash
scripts/with-ansible-vault-env.sh ansible-vault edit \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/vault.yml
```

The initial local-network vault may contain `SET-ME-IN-VAULT` placeholders.
Replace those placeholders only through `ansible-vault edit` or an immediate
encrypt-and-remove temporary workflow; do not stage plaintext replacements.

For noninteractive automation, create a plaintext file only in a private
operator directory or secure temporary file, encrypt it immediately, then remove
the plaintext. Never place plaintext secret files under the repo.

## Inventory Pattern

The local network inventory keeps non-secret topology in normal YAML and secret
values in encrypted `vault.yml`:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/
  hosts.yml
  group_vars/all/network_fabric.yml
  group_vars/all/vault.yml
```

Examples:

- `ansible_password: "{{ vault_crs354_admin_password }}"`
- `swos_password: "{{ vault_css326_admin_password }}"`
- `proxmox_api_token_secret: "{{ vault_hasslehoff_proxmox_api_token_secret }}"`
- `api_token: "{{ vault_hetzner_dns_rfc1918_api_token }}"`
- `github_forge_token: "{{ vault_github_forge_token }}"`

## Hetzner DNS Tokens

Import Hetzner Cloud DNS token groups from an operator-private token file:

```bash
scripts/import-hetzner-dns-vault.sh /tmp/rfc-vernetzen-yukon.dns-api-info.cfg
```

The importer preserves existing vault content, writes only encrypted
`vault_hetzner_dns_*` variables, and never prints token values. DNS policy and
token-group references live in:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/dns_hetzner_cloud.yml
```

Validate token access with:

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/hetzner-dns-api-validate.yml
```

## GitHub Forge Token

The operator-private Forge GitHub token is sourced from:

```bash
/root/.ssh/codex.d/tokens/FORGE_TOKEN
```

The encrypted local-network vault stores the token and repo-safe metadata under:

```text
vault_github_forge_token
vault_github_forge_token_name
vault_github_forge_token_owner
vault_github_forge_token_required_scopes
vault_github_forge_token_optional_scopes
```

Use `GH_TOKEN="$(cat /root/.ssh/codex.d/tokens/FORGE_TOKEN)" gh ...` for
operator-local GitHub CLI calls. Do not commit the token file or print token
contents to logs.

## Safety Rules

- Commit only encrypted vault files.
- Run `scripts/validate-ansible-vaults.sh` before every commit touching vaults.
- Do not echo secrets into terminal output.
- Do not add decrypted vault files to documentation or EOD reports.
- Rotate device passwords after bootstrap credentials have been vaulted and
  automation access is validated.
