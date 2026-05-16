# RFC1918 CA And TLS Deployment Plan

Status: active implementation.

The RFC1918 private CA is the internal trust anchor for LAN service TLS,
management APIs, observability endpoints, and selected network or OOB device
web/API surfaces. Private key material stays outside git and enters automation
only through Ansible Vault or operator-private source files.

## Decisions

- Keep `rfc1918_private_ca` as the default service TLS authority.
- Store root/intermediate CA material under `vault_private_ca_rfc1918_*`.
- Store leaf certificate material under `vault_service_tls_certificates`.
- Track non-secret service desired state in `service_tls_certificates.yml`.
- Default every mutation to off until an explicit role-level apply variable is
  set.
- Replace runtime self-signed certificates first on HAProxy VIPs, then on
  observability and identity services, then on network and power devices.
- Treat FreeIPA certificate handling as identity-sensitive; deploy trust first
  and change FreeIPA HTTP/LDAP certificates only during a dedicated window.
- Keep RouterOS self-signed generation as an emergency fallback until imported
  PKCS#12 certificates are validated on the CCR2004.

## Rollout Order

1. Import or rotate the private CA vault entries with
   `scripts/import-private-ca-vault.sh`.
2. Materialize and validate the trust anchor on the Ansible controller without
   printing PEM or PKCS#12 content.
3. Deploy the CA trust anchor to Gentoo/OpenRC, Rocky/RHEL, and FreeBSD hosts.
4. Deploy HAProxy leaf certificates for `ntfy_lan`, `rsyslog_tls_vip`, and
   `elasticsearch_sun99_vip`.
5. Deploy service-native or reverse-proxy certificates for NetBox, Prometheus,
   VictoriaMetrics, Grafana, Kibana, and CheckMK.
6. Deploy Proxmox `pveproxy` certificate on Hasslehoff after console and API
   rollback paths are validated.
7. Import certificates into RouterOS and OOB/power devices with device-specific
   mutation gates.
8. Add scheduled expiry monitoring and local ntfy alerts.

## Initial Coverage Matrix

The non-secret matrix lives at:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/service_tls_certificates.yml
```

Initial service IDs:

- `ntfy_lan`
- `rsyslog_tls_vip`
- `elasticsearch_sun99_vip`
- `netbox_stage4`
- `freeipa_ipa01`
- `prometheus_sun99`
- `victoriametrics_sun99`
- `grafana_sun99`
- `kibana_sun99`
- `checkmk_fmt2`
- `mcp_control_plane`
- `routeros_ccr2004_gateway`
- `proxmox_hasslehoff`
- `pdu_rfc99_corectrl`

## Validation

Repo automation artifacts:

- `roles/rfc1918_ca_trust` installs the RFC1918 trust anchor only when
  `rfc1918_ca_trust_enabled=true` and `rfc1918_ca_trust_apply=true`.
- `roles/rfc1918_service_tls` deploys selected file-backed leaf certificates
  only when `rfc1918_service_tls_enabled=true`,
  `rfc1918_service_tls_apply=true`, and service IDs are explicitly selected.
- `roles/routeros_rfc99_gateway` keeps `self_signed` as fallback and adds
  `rfc1918_private_ca` import mode for CA plus PKCS#12 RouterOS certificate
  bundles.
- `playbooks/rfc1918_tls_deploy.yml` applies the CA trust and file-backed
  service TLS roles to selected inventory hosts outside the LiveISO installer
  workflow.
- `scripts/validate-rfc1918-service-tls.sh` provides endpoint validation,
  JSONL audit rows, and optional local ntfy notification.

Every deployed endpoint must pass:

```bash
openssl s_client -connect <fqdn>:<port> -servername <fqdn> -verify_return_error </dev/null
```

HTTP services must also pass a service-specific health or readiness request
with the RFC1918 trust bundle installed on the client. Validation results should
be captured as JSONL audit records and surfaced through local ntfy topics.

## Live Deployment Evidence

2026-05-16 live rollout status:

| Service ID | Endpoint | Port | Result | Notes |
| --- | --- | ---: | --- | --- |
| `ntfy_lan` | `msg-sun99-ntfysys-099096.rfc1918.host` | 443 | pass | HAProxy PEM deployed on the container-services host; `/v1/health` returned healthy. |
| `checkmk_fmt2` | `app-sfo200-monitoring-9927.vernetzen.io` | 443 | pass | Apache/OMD certificate files replaced after `omd update-apache-config vernetzen`; login redirect validated. |
| `netbox_stage4` | `svc-netbox-stage4.rfc1918.host` | 443 | pass | nginx TLS server block added; unauthenticated `/` redirect validated. |
| `proxmox_hasslehoff` | `hasslehoff.rfc1918.host` | 8006 | pass | `pveproxy` cert installed under pmxcfs; unauthenticated Proxmox UI endpoint validated. |

All four endpoints validated with issuer
`O=RFC1918 Internal, CN=RFC1918 Private CA 2026`, hostname verification, and
396 days remaining at validation time. The generated CA and leaf private
material remains outside git under operator-private storage and in Ansible
Vault only.

## Backout

Backout is service-specific:

- HAProxy endpoints keep the previous PEM file with a timestamped suffix before
  replacement and can reload the previous file.
- nginx, Grafana, Kibana, Apache, and Proxmox keep the previous certificate and
  key files with timestamped suffixes before replacement.
- RouterOS keeps self-signed certificate generation in the rendered script until
  imported PKCS#12 material has been validated.
- Device firmware imports require a pre-change configuration backup and a local
  console or serial path before mutation.

## Related Artifacts

- `docs/ANSIBLE-VAULT.md`
- `docs/superpowers/plans/2026-05-16-rfc1918-ca-tls-deployment.md`
- `docs/wiki/ITIL-ADR-RFC1918-CA-TLS-Deployment.md`
- `tests/shell/test_private_ca_vault.sh`
- `tests/shell/test_rfc1918_ca_tls_deployment.sh`
- `tests/shell/test_rfc1918_ca_trust_role.sh`
- `tests/shell/test_rfc1918_service_tls_role.sh`
- `tests/shell/test_routeros_internal_ca_certificate_import.sh`
- `tests/shell/test_validate_rfc1918_service_tls.sh`
