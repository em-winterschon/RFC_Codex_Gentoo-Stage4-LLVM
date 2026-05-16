# RFC1918 CA TLS Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the RFC1918 private CA trust anchor and vault-backed TLS leaf certificates consistently across LAN services, observability, identity, Proxmox, CheckMK, RouterOS, and power/OOB devices.

**Architecture:** Keep private CA and leaf private-key material in Ansible Vault or operator-private files only. Track non-secret desired state in `service_tls_certificates.yml`, then apply it with small roles: one role distributes CA trust, one role deploys service leaf material to file-backed services, and one gated role imports device certificates into network or OOB firmware. Validation is certificate-chain first, then service-specific health checks.

**Tech Stack:** Ansible, Ansible Vault, OpenSSL, Gentoo/OpenRC trust stores, Rocky/RHEL trust stores, HAProxy, nginx, Apache/httpd, RouterOS certificate store, Proxmox `pveproxy`, CheckMK, local ntfy.

---

### Task 1: Service Certificate Matrix

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/service_tls_certificates.yml`
- Create: `tests/shell/test_rfc1918_ca_tls_deployment.sh`
- Modify: `tests/shell/run-tests.sh`
- Modify: `docs/ANSIBLE-VAULT.md`

- [ ] **Step 1: Write the matrix guard test**

```bash
bash tests/shell/test_rfc1918_ca_tls_deployment.sh
```

Expected before the matrix exists: `FAIL: missing file .../service_tls_certificates.yml`.

- [ ] **Step 2: Add non-secret matrix content**

Create `service_tls_certificate_policy` and `service_tls_certificate_matrix` with these required service IDs: `ntfy_lan`, `rsyslog_tls_vip`, `elasticsearch_sun99_vip`, `netbox_stage4`, `freeipa_ipa01`, `prometheus_sun99`, `victoriametrics_sun99`, `grafana_sun99`, `kibana_sun99`, `checkmk_fmt2`, `mcp_control_plane`, `routeros_ccr2004_gateway`, `proxmox_hasslehoff`, and `pdu_rfc99_corectrl`.

- [ ] **Step 3: Wire the test runner**

Add:

```bash
bash "${SCRIPT_DIR}/test_rfc1918_ca_tls_deployment.sh"
```

immediately after `test_private_ca_vault.sh` in `tests/shell/run-tests.sh`.

- [ ] **Step 4: Run matrix tests**

```bash
bash tests/shell/test_rfc1918_ca_tls_deployment.sh
bash tests/shell/test_private_ca_vault.sh
```

Expected: both commands print `PASS`.

### Task 2: CA Trust Distribution Role

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/rfc1918_ca_trust/defaults/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/rfc1918_ca_trust/tasks/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/rfc1918_ca_trust/handlers/main.yml`
- Create: `tests/shell/test_rfc1918_ca_trust_role.sh`

- [ ] **Step 1: Write the role test**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROLE_DIR="${ROOT_DIR}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/rfc1918_ca_trust"

grep -Fq "rfc1918_ca_trust_enabled: false" "${ROLE_DIR}/defaults/main.yml"
grep -Fq "copy:" "${ROLE_DIR}/tasks/main.yml"
grep -Fq "update-ca-certificates" "${ROLE_DIR}/tasks/main.yml"
grep -Fq "update-ca-trust" "${ROLE_DIR}/tasks/main.yml"
grep -Fq "certctl rehash" "${ROLE_DIR}/tasks/main.yml"
grep -Fq "no_log: true" "${ROLE_DIR}/tasks/main.yml"
grep -Fq "rfc1918_ca_trust_apply | bool" "${ROLE_DIR}/tasks/main.yml"
```

- [ ] **Step 2: Add role defaults**

```yaml
---
rfc1918_ca_trust_enabled: false
rfc1918_ca_trust_apply: false
rfc1918_ca_trust_authority_id: rfc1918_private_ca
rfc1918_ca_trust_cert_pem: "{{ private_certificate_authorities[rfc1918_ca_trust_authority_id].cert_pem | default('') }}"
rfc1918_ca_trust_dest_name: rfc1918-private-ca.crt
rfc1918_ca_trust_gentoo_anchor_dir: /usr/local/share/ca-certificates
rfc1918_ca_trust_rhel_anchor_dir: /etc/pki/ca-trust/source/anchors
rfc1918_ca_trust_freebsd_anchor_dir: /usr/local/share/certs
```

- [ ] **Step 3: Add trust install tasks**

The role must refuse mutation unless both `rfc1918_ca_trust_enabled` and `rfc1918_ca_trust_apply` are true, write the CA cert with mode `0644`, call the correct trust refresh command for Gentoo, Rocky/RHEL, or FreeBSD, and use `no_log: true` on tasks that touch certificate content.

- [ ] **Step 4: Run role tests**

```bash
bash tests/shell/test_rfc1918_ca_trust_role.sh
```

Expected: no output except a final `PASS` line once added.

### Task 3: Service Leaf Certificate Role

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/rfc1918_service_tls/defaults/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/rfc1918_service_tls/tasks/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/rfc1918_service_tls/handlers/main.yml`
- Create: `tests/shell/test_rfc1918_service_tls_role.sh`

- [ ] **Step 1: Write the role test**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROLE_DIR="${ROOT_DIR}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/rfc1918_service_tls"

grep -Fq "rfc1918_service_tls_enabled: false" "${ROLE_DIR}/defaults/main.yml"
grep -Fq "rfc1918_service_tls_apply: false" "${ROLE_DIR}/defaults/main.yml"
grep -Fq "service_tls_certificate_matrix" "${ROLE_DIR}/tasks/main.yml"
grep -Fq "mode: \"0600\"" "${ROLE_DIR}/tasks/main.yml"
grep -Fq "no_log: true" "${ROLE_DIR}/tasks/main.yml"
grep -Fq "openssl x509 -noout" "${ROLE_DIR}/tasks/main.yml"
```

- [ ] **Step 2: Add role defaults**

```yaml
---
rfc1918_service_tls_enabled: false
rfc1918_service_tls_apply: false
rfc1918_service_tls_service_ids: []
rfc1918_service_tls_matrix: "{{ service_tls_certificate_matrix | default({}) }}"
rfc1918_service_tls_secret_namespace: "{{ service_tls_certificate_policy.secret_namespace | default('vault_service_tls_certificates') }}"
```

- [ ] **Step 3: Add file-backed deployment tasks**

For each selected service ID, the role must assert that the matrix entry exists, assert that vault-rendered `fullchain_pem` and `private_key_pem` are non-empty, write cert/chain files as `0644`, write private keys as `0600`, run `openssl x509 -noout -subject -issuer -dates -ext subjectAltName`, and notify the service-specific handler from `reload_commands`.

- [ ] **Step 4: Run role tests**

```bash
bash tests/shell/test_rfc1918_service_tls_role.sh
```

Expected: no output except a final `PASS` line once added.

### Task 4: First Wave Deployment

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/vm-container-services.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/host_vars/obs_sun99_grafana_099066.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/host_vars/obs_sun99_kibana_099067.yml`
- Modify: `docs/wiki/ITIL-ADR-RFC1918-CA-TLS-Deployment.md`

- [ ] **Step 1: Deploy CA trust only**

```bash
ansible-playbook gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/install.yml \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  --limit svc_container_services_safe_move_01,obs_sun99_grafana_099066,obs_sun99_kibana_099067 \
  -e rfc1918_ca_trust_enabled=true \
  -e rfc1918_ca_trust_apply=true
```

Expected: trust anchors installed, services unchanged.

- [ ] **Step 2: Deploy leaf certs for ntfy and rsyslog VIPs**

```bash
ansible-playbook gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/install.yml \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  --limit svc_container_services_safe_move_01 \
  -e rfc1918_service_tls_enabled=true \
  -e rfc1918_service_tls_apply=true \
  -e 'rfc1918_service_tls_service_ids=["ntfy_lan","rsyslog_tls_vip"]'
```

Expected: HAProxy PEM files updated and container-services restarted once.

- [ ] **Step 3: Validate first wave**

```bash
openssl s_client -connect msg-sun99-ntfysys-099096.rfc1918.host:443 -servername msg-sun99-ntfysys-099096.rfc1918.host -verify_return_error </dev/null
curl --fail --silent --show-error https://msg-sun99-ntfysys-099096.rfc1918.host/v1/health
openssl s_client -connect log-sun99-rsyslog-099093.rfc1918.host:6514 -servername log-sun99-rsyslog-099093.rfc1918.host -verify_return_error </dev/null
```

Expected: OpenSSL verifies the RFC1918 private CA chain and ntfy returns healthy JSON.

### Task 5: Device Certificate Import

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/routeros_rfc99_gateway/defaults/main.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/routeros_rfc99_gateway/templates/routeros-rfc99-gateway.rsc.j2`
- Create: `tests/shell/test_routeros_internal_ca_certificate_import.sh`

- [ ] **Step 1: Keep self-signed as fallback**

Add `routeros_rfc99_gateway_certificate_source: self_signed` and keep the current self-signed path for dry-run and emergency fallback.

- [ ] **Step 2: Add internal-CA import mode**

When `routeros_rfc99_gateway_certificate_source: rfc1918_private_ca`, render commands that import the vaulted PKCS#12 certificate, trust the CA certificate, and set both `www-ssl` and `api-ssl` to the imported certificate name.

- [ ] **Step 3: Validate generated RouterOS script before apply**

```bash
bash tests/shell/test_routeros_internal_ca_certificate_import.sh
```

Expected: generated `.rsc` contains PKCS#12 import commands only when the source is `rfc1918_private_ca`, and the self-signed fallback remains covered by `test_routeros_rfc99_gateway_role.sh`.

### Task 6: Closeout Validation And Audit

**Files:**
- Create: `scripts/validate-rfc1918-service-tls.sh`
- Create: `tests/shell/test_validate_rfc1918_service_tls.sh`
- Modify: `docs/ROADMAP-AND-TODO.md`
- Modify: `docs/wiki/Roadmap-and-TODO.md`

- [ ] **Step 1: Add validator**

The validator reads `service_tls_certificates.yml`, iterates selected matrix entries, runs `openssl s_client` with the configured SNI name and port, optionally runs the configured HTTPS health URL, and exits non-zero on chain validation failure, hostname mismatch, or expired certificate.

- [ ] **Step 2: Emit audit**

Write JSONL audit rows to `/var/log/rfc1918-service-tls-audit.jsonl` with keys `timestamp`, `service_id`, `endpoint_fqdn`, `port`, `issuer`, `not_after`, `days_remaining`, and `result`.

- [ ] **Step 3: Notify local ntfy**

Send failures to `https://msg-sun99-ntfysys-099096.rfc1918.host/forge-security` and successes to `https://msg-sun99-ntfysys-099096.rfc1918.host/forge-obs` when `RFC1918_TLS_NOTIFY=true`.

- [ ] **Step 4: Run closeout tests**

```bash
bash tests/shell/test_validate_rfc1918_service_tls.sh
bash tests/shell/run-tests.sh
```

Expected: targeted validator tests pass, then the repository shell suite passes.
