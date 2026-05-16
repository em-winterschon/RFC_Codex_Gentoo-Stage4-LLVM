# ITIL ADR: RFC1918 CA And TLS Deployment

Status: active implementation.

Adopt the RFC1918 private CA as the common internal trust anchor for LAN
service TLS, observability, management APIs, CheckMK, Proxmox, RouterOS, and
selected OOB or power devices. Leaf certificates are deployed from Ansible Vault
references and never committed as PEM or PKCS#12 material.

Key decisions:

- `rfc1918_private_ca` is the default service certificate authority.
- CA trust deployment is separate from leaf certificate deployment.
- Service and device mutations are disabled by default.
- HAProxy VIP certificates are deployed before native service certificates.
- FreeIPA certificate changes require a dedicated identity change window.
- RouterOS keeps the current self-signed path as a fallback until imported
  internal-CA PKCS#12 certificates are validated.
- Local ntfy receives certificate deployment and expiry alerts.

Priority endpoints:

- `msg-sun99-ntfysys-099096.rfc1918.host`
- `log-sun99-rsyslog-099093.rfc1918.host`
- `obs-sun99-esvip-099092.rfc1918.host`
- `svc-netbox-stage4.rfc1918.host`
- `ipa01.rfc1918.host`
- `obs-sun99-prometheus-099064.rfc1918.host`
- `obs-sun99-vmetrics-099065.rfc1918.host`
- `obs-sun99-grafana-099066.rfc1918.host`
- `obs-sun99-kibana-099067.rfc1918.host`
- `app-sfo200-monitoring-9927.vernetzen.io`
- `mcp-control-plane.rfc1918.host`
- `gw-rfc99-mkccr2004-16g.rfc1918.host`
- `hasslehoff.rfc1918.host`
- `pdu-rfc99-corectrl-p08-099241.rfc1918.host`
- `pdu-rfc99-corectrl-099241.rfc1918.host`

Implementation order:

1. Import or rotate `vault_private_ca_rfc1918_*`.
2. Validate non-secret `service_tls_certificates.yml` matrix.
3. Deploy CA trust anchors to hosts.
4. Deploy HAProxy leaf certificates for ntfy, rsyslog, and Elasticsearch VIPs.
5. Deploy observability, NetBox, and CheckMK service certificates.
6. Deploy Proxmox and RouterOS certificates after console backout validation.
7. Add expiry audit, local ntfy alerts, and CheckMK/Prometheus checks.

Implemented repo controls:

- `rfc1918_ca_trust` role for explicit-gate CA trust-anchor installation.
- `rfc1918_service_tls` role for explicit-gate file-backed leaf certificate
  deployment from `vault_service_tls_certificates`.
- RouterOS `rfc1918_private_ca` certificate-source mode with self-signed
  fallback retained.
- `scripts/validate-rfc1918-service-tls.sh` for OpenSSL validation, JSONL audit,
  health URL checks, and optional local ntfy alerting.

Canonical documents:

- `docs/RFC1918-CA-TLS-DEPLOYMENT.md`
- `docs/superpowers/plans/2026-05-16-rfc1918-ca-tls-deployment.md`
- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/service_tls_certificates.yml`
- `scripts/validate-rfc1918-service-tls.sh`
