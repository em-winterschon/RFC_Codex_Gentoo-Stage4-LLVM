# CheckMK FMT2 Recovery And Upgrade

The automation entry point is `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/checkmk-recovery-upgrade.yml`.

The workflow is dry-run first. Mutating operations require explicit `checkmk_recovery_allow_*` variables for backup, repo disablement, rsyslog Elasticsearch disablement, internal CA certificate install, OS update, reboot, curated service rediscovery, and CheckMK version upgrade.

Current baseline: Rocky Linux 8.6, CheckMK 2.0.0p22 Raw Edition, site `vernetzen`, and old rsyslog Elasticsearch target `app-sfo200-elastic-9961.vernetzen.io:9200`.

Core rule: do not bulk-accept vanished services. Rediscovery applies only to curated live FMT2 hosts until stale inventory is separated from active infrastructure.
