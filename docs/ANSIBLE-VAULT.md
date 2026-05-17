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

## BigNetwork Token

The operator-private BigNetwork API/client token for the Forge/Codexian portal
account is sourced from:

```bash
/root/.ssh/codex.d/tokens/BIGNETWORK_TOKEN_CODEXIAN
```

Import or rotate it with:

```bash
scripts/import-bignetwork-vault.sh
```

The encrypted local-network vault stores the token and repo-safe metadata under:

```text
vault_bignetwork_codexian_api_token
vault_bignetwork_codexian_token_name
vault_bignetwork_codexian_account_name
vault_bignetwork_codexian_token_owner
vault_bignetwork_codexian_purpose
```

Repo-safe transport intent and role wiring live in:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/bignetwork.yml
```

## Context7 MCP Token

The operator-private Context7 API token used by the Codex MCP wrapper is
sourced from:

```bash
/root/.codex/secrets/context7_api_key
```

Import or rotate it with:

```bash
scripts/import-context7-vault.sh
```

The encrypted local-network vault stores the token and repo-safe metadata under:

```text
vault_context7_api_token
vault_context7_token_name
vault_context7_token_owner
vault_context7_purpose
```

Materialize the runtime token file after vault import or host rebuild with:

```bash
scripts/materialize-context7-mcp-secret.sh
```

The materializer writes `/root/.codex/secrets/context7_api_key` with mode `0600`
and never prints the token value. The Codex MCP wrapper
`/root/.codex/bin/context7-mcp-wrapper.sh` reads that runtime file so `codex mcp
list` does not expose the token in command arguments.

## Private CA

The shared RFC1918 private certificate authority should be imported from an
operator-private source file, not generated in the repo. The default source path
is:

```bash
/root/.ssh/vault/private-ca/RFC1918_PRIVATE_CA.env
```

Import or rotate the encrypted vault values with:

```bash
scripts/import-private-ca-vault.sh
```

The source file may provide PEM material, PKCS#12 material, or paths to
operator-private files:

```bash
RFC1918_PRIVATE_CA_NAME="rfc1918_private_ca"
RFC1918_PRIVATE_CA_CERT_PEM="-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----"
RFC1918_PRIVATE_CA_KEY_PEM="-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----"
RFC1918_PRIVATE_CA_CHAIN_PEM="-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----"
RFC1918_PRIVATE_CA_PKCS12_BASE64="base64-encoded-pkcs12"
RFC1918_PRIVATE_CA_PKCS12_PASSWORD="replace-me"
```

The encrypted local-network vault stores the material or references under:

```text
vault_private_ca_rfc1918_name
vault_private_ca_rfc1918_cert_pem
vault_private_ca_rfc1918_key_pem
vault_private_ca_rfc1918_chain_pem
vault_private_ca_rfc1918_pkcs12_base64
vault_private_ca_rfc1918_pkcs12_password
vault_private_ca_rfc1918_cert_path
vault_private_ca_rfc1918_key_path
vault_private_ca_rfc1918_chain_path
vault_private_ca_rfc1918_pkcs12_path
```

Until this CA is imported and distributed to clients, service TLS may use
runtime-generated self-signed certificates for transport testing only.

Service leaf certificates are tracked separately from the CA under a nested
vault namespace:

```text
vault_service_tls_certificates.<service_id>.fullchain_pem
vault_service_tls_certificates.<service_id>.private_key_pem
vault_service_tls_certificates.<service_id>.pkcs12_base64
vault_service_tls_certificates.<service_id>.pkcs12_password
```

FreeIPA server certificate migration additionally requires the existing
Directory Manager password:

```text
vault_freeipa_ipa01_directory_manager_password
```

`cn=Directory Manager` is the 389-DS LDAP root DN created during FreeIPA
installation. It is not a Kerberos admin user and it bypasses normal IPA RBAC,
so it must be stored only in Ansible Vault and consumed only by the gated
`freeipa_server_certificate` role. If the value is unknown, rotate or reset it
in a dedicated identity maintenance window before adding the new value to vault.

The `freeipa_ipa01` service TLS vault entry must include PKCS#12 material:

```text
vault_service_tls_certificates.freeipa_ipa01.pkcs12_base64
vault_service_tls_certificates.freeipa_ipa01.pkcs12_password
```

The migration playbook is opt-in and should be run only after FreeIPA health and
backout paths are validated:

```bash
ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/freeipa-server-cert-migration.yml \
  -e freeipa_server_certificate_enabled=true \
  -e freeipa_server_certificate_apply=true \
  -e freeipa_server_certificate_service_id=freeipa_ipa01
```

The non-secret deployment matrix is:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/service_tls_certificates.yml
```

Do not commit literal leaf PEM, private-key PEM, or PKCS#12 data. File-backed
services use `fullchain_pem` and `private_key_pem`; supported RouterOS and
device APIs may additionally require PKCS#12 material. Legacy firmware that
cannot run modern TLS belongs in `legacy_oob_devices.yml`, not in the service
TLS certificate matrix.

## APC PDU Credentials

The operator-private AP7901 RFC99 core-control PDU credential source is:

```bash
/root/.ssh/codex.d/tokens/PDU_RFC99_CORECTRL
```

Import or rotate it with:

```bash
scripts/import-pdu-rfc99-corectrl-vault.sh
```

The importer copies `vault_pdu_rfc99_corecontrol_*` keys into the encrypted
local-network vault and never prints secret values. Keep the source file outside
git. K10 power-cycle automation must validate the AP7901 outlet label
`host_gmktec_k10` before setting outlet control OIDs.

NetBox inventory for the AP7901 must remain non-secret. It may contain the
device model, management IP, serial number, SNMPv3 capability marker, and outlet
labels, but it must not contain SNMPv3 usernames, authentication secrets,
privacy secrets, or local break-glass passwords.

The AP7901 PDU is TLS-exempt legacy firmware. Do not create
`vault_service_tls_certificates.pdu_rfc99_corectrl` entries for it. Manage it
through SNMPv3 first, serial rescue/configuration second, and management-only
legacy HTTP as break-glass. The non-secret policy lives in:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/legacy_oob_devices.yml
```

## SUN99 Power Device Credentials

The SUN99 white-rack UPS, ATS, and PDU credential source is:

```bash
/root/operator-private/voltage-ops/ups-ats-pdu.sun99-white-rack-infra.info
```

Import or rotate it with:

```bash
scripts/import-sun99-power-device-vault.sh
```

The importer accepts the operator-private markdown/key-value source and copies
only section-scoped `username` and `password` fields into the encrypted
local-network vault. It supports these source sections:

- `Primary UPS`
- `Secondary UPS`
- `Primary ATS`
- `Primary PDU`

The resulting vault variables use the
`vault_power_devices_sun99_white_rack_*` prefix. The non-secret variable map
lives in:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/power_devices.yml
```

Do not commit the operator-private source file, decrypted vault views, local
device passwords, SNMP communities, SNMPv3 auth/privacy secrets, or rendered
configuration files that contain those values.

## Safety Rules

- Commit only encrypted vault files.
- Run `scripts/validate-ansible-vaults.sh` before every commit touching vaults.
- Do not echo secrets into terminal output.
- Do not add decrypted vault files to documentation or EOD reports.
- Rotate device passwords after bootstrap credentials have been vaulted and
  automation access is validated.
