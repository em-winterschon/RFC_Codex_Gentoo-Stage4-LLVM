# FreeIPA PDU MCP Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the remaining TLS rollout findings actionable by gating FreeIPA certificate migration, exempting the legacy APC PDU from TLS compliance, and making the MCP control plane inventory-ready.

**Architecture:** Keep secret material in Ansible Vault and operator-private files only. FreeIPA certificate replacement uses a dedicated, opt-in role because Directory Manager credentials can break identity services if mishandled. Legacy power devices move out of the service TLS matrix into an OOB policy, while MCP gets explicit inventory/DNS/readiness metadata before live deployment.

**Tech Stack:** Ansible, Bash validation tests, YAML inventories, FreeIPA `ipa-server-certinstall`, local RFC1918 CA/TLS matrix, Podman-backed MCP service profile.

---

### Task 1: PDU TLS Exemption

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/service_tls_certificates.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/legacy_oob_devices.yml`
- Modify: `docs/RFC1918-CA-TLS-DEPLOYMENT.md`
- Modify: `docs/ANSIBLE-VAULT.md`
- Modify: `tests/shell/test_rfc1918_ca_tls_deployment.sh`

- [ ] Remove `pdu_rfc99_corectrl` from the RFC1918 TLS service matrix.
- [ ] Add `legacy_oob_device_policy` and `legacy_oob_devices.pdu_rfc99_corectrl_ap7901` with `tls_supported: false`.
- [ ] Update TLS docs to list the PDU as TLS-exempt and managed by SNMPv3, serial, and legacy HTTP only.
- [ ] Update tests so the PDU is required in the legacy OOB policy and forbidden from the TLS matrix.

### Task 2: FreeIPA Server Certificate Migration Gate

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/freeipa_server_certificate/defaults/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/freeipa_server_certificate/tasks/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/freeipa-server-cert-migration.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/service_tls_certificates.yml`
- Modify: `docs/ANSIBLE-VAULT.md`
- Create: `tests/shell/test_freeipa_server_certificate_role.sh`

- [ ] Add `pkcs12_base64` and `pkcs12_password` references for `freeipa_ipa01`.
- [ ] Add role defaults that require `freeipa_server_certificate_enabled=true`, `freeipa_server_certificate_apply=true`, and a selected service ID.
- [ ] Assert Directory Manager password and PKCS#12 values are present without logging secrets.
- [ ] Decode the PKCS#12 bundle to a remote temp file, run `ipa-cacert-manage install`, run `ipa-certupdate`, run `ipa-server-certinstall -w -d`, restart FreeIPA, and remove the temp file.
- [ ] Keep KDC/PKINIT replacement disabled by default.
- [ ] Add tests that enforce the gate and secret references.

### Task 3: MCP Control Plane Inventory Readiness

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/local-rfc1918-lab.yml`
- Modify: `docs/MCP-CONTROL-PLANE.md`
- Modify: `tests/shell/test_mcp_control_plane_services.sh`

- [ ] Add `mcp_control_plane_hosts` with `vm_mcp_control_plane` at `172.16.99.68`.
- [ ] Add FQDN and DNS aliases for `mcp-control-plane`, `nginx-ui`, and `mcp-generic`.
- [ ] Track Proxmox placement, profile, TLS service ID, and deployment readiness gates.
- [ ] Add inventory-intake device metadata for NetBox import.
- [ ] Update tests to assert the MCP host and readiness gates exist.

### Task 4: Verification And Publication

**Files:**
- Modify: `tests/shell/run-tests.sh`

- [ ] Add new shell tests to `run-tests.sh`.
- [ ] Run targeted tests for TLS, FreeIPA cert migration, MCP control plane, and legacy OOB policy.
- [ ] Run syntax validation for changed shell scripts.
- [ ] Commit and push the branch after tests pass.
