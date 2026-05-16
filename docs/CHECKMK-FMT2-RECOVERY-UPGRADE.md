# CheckMK FMT2 Recovery And Upgrade

This workflow makes the FMT2 CheckMK VM recoverable before it is upgraded. It is dry-run by default: the role gathers state, inventories risky components, writes an update plan, and refuses mutations unless an explicit `checkmk_recovery_allow_*` gate is set.

Observed baseline on 2026-05-16:

- Host: `app-sfo200-monitoring-9927.vernetzen.io`.
- OS: Rocky Linux 8.6.
- Site: `vernetzen`.
- CheckMK 2.0.0p22 Raw Edition is active, with older 2.0.0 packages also present.
- Old rsyslog forwarding targets `app-sfo200-elastic-9961.vernetzen.io:9200`; that endpoint was reachable for SSH and agents after the VM powered on, but Elasticsearch 9200 was not ready during assessment.
- The `ripe-atlas-probe` repo was previously blocking DNF operations and should stay disabled unless its repository trust path is repaired.
- The local Apache certificate is expired and should be replaced with an internal CA signed certificate.

Run preflight and plan-only checks:

```bash
ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/checkmk-recovery-upgrade.yml \
  --limit app-sfo200-monitoring-9927
```

Mutation gates:

- `checkmk_recovery_allow_backup=true` creates `omd backup` and configuration bundle archives.
- `checkmk_recovery_allow_repo_disable=true` disables known-broken repos such as `ripe-atlas-probe`.
- `checkmk_recovery_allow_rsyslog_elastic_disable=true` disables the old rsyslog Elasticsearch output only if the socket probe still fails.
- `checkmk_recovery_allow_cert_install=true` installs internal CA and Apache TLS material from controller-side vault-managed paths.
- `checkmk_recovery_allow_os_update=true` applies Rocky package updates after `dnf update --assumeno` has been reviewed.
- `checkmk_recovery_allow_reboot=true` reboots the VM and validates `omd status`.
- `checkmk_recovery_allow_discovery_apply=true` applies rediscovery only for the curated live FMT2 host list.
- `checkmk_recovery_allow_checkmk_upgrade=true` installs a staged CheckMK RPM and runs `omd -f -V <target-version> update`.
- `checkmk_recovery_upgrade_target_version` must match the installed OMD target version, for example `2.0.0p39.cre`.

Operational policy:

- Take a hypervisor snapshot before any OS or CheckMK version mutation.
- Run `checkmk_recovery_allow_backup=true` before package updates, reboot, rediscovery apply, or CheckMK version upgrade.
- Upgrade Rocky 8 packages first, validate, then handle CheckMK major/minor upgrade as a separate change.
- Do not bulk-accept vanished services across all hosts. Use curated live host rediscovery first: CheckMK pair, Elastic, Prometheus, NASA, routers, switches, and PDUs.
- Replace expired HTTPS certificates with internal CA signed material before relying on HTTPS UI or API health checks.
- If the old rsyslog to Elasticsearch path remains broken, disable it and migrate syslog traffic to the stable RFC99 rsyslog VIP and Elasticsearch ingestion plan.
