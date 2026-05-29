# SSHD Baseline Rollout Runbook

Date: 2026-05-28

## Intent

Distribute the canonical RFC99/SUN99/FMT2 SSHD server configuration through Ansible, with Slurm used only as the concurrency scheduler. Do not run direct per-host `ssh -o ...` commands for rollout work; host connection behavior must come from the operator's SSH client config and Ansible inventory.

Canonical standard baseline hash:

```text
2a045fc24ba3002098ccaa93f31b8d82ae5fde2651e8a82cd34017617543fc15  sshd_config.standard_sssd_no_include
```

The standard baseline owns `/etc/ssh/sshd_config` as a full file, keeps SSSD SSH authorized key lookup inline, and leaves `Include "/etc/ssh/sshd_config.d/*.conf"` commented out to avoid unmanaged drop-in drift. The `installer_recovery_only` variant is gated and must not be used on normal managed live hosts.

## Local Redis cache bootstrap

Run once on the Ansible controller before large host-fact collection:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-galaxy collection install -r requirements.yml
ANSIBLE_CACHE_PLUGIN=memory ansible-playbook -i localhost, playbooks/ansible-redis-cache-local.yml
```

After this, `ansible.cfg` uses `community.general.redis` against `localhost:6379:0:` with an ephemeral Redis config (`save ""`, `appendonly no`).

## Slurm-backed rollout flow

From `gentoo-liveiso-ansible`:

```bash
# 1. Audit current drift and syntax, producing per-host JSON under /tmp/ansible-control-flow.
scripts/slurm-ansible-sshd-rollout.sh audit --run-id sshd-YYYYMMDD-audit

# 2. Apply only to hosts whose audit JSON says managed=true, syntax_ok=true, drift=true.
scripts/slurm-ansible-sshd-rollout.sh apply --run-id sshd-YYYYMMDD-audit --shard-size 10 --max-parallel-shards 4

# 3. Re-audit/verify after apply.
scripts/slurm-ansible-sshd-rollout.sh verify --run-id sshd-YYYYMMDD-verify
```

Use `--limit` for canaries and bounded blast radius. For `apply`, the Slurm wrapper resolves the Ansible limit against the inventory before sharding and applies only the intersection of:

1. drifted, managed, syntax-clean audit records, and
2. hosts matched by the requested `--limit` pattern.

This also applies when `--eligible-hosts-file` is supplied: the file is filtered through the same resolved limit before any Slurm shard is written. If the limit matches no inventory hosts, the wrapper fails before submitting apply jobs. If the limit is valid but no drifted audit host intersects it, the wrapper prints `No eligible hosts to apply` and submits nothing.

Canary example:

```bash
scripts/slurm-ansible-sshd-rollout.sh apply \
  --run-id sshd-YYYYMMDD-audit \
  --limit m70_canary \
  --shard-size 1 \
  --max-parallel-shards 1
```

Use `--dependency afterok:<jobid>` to chain apply after audit or verify after apply.

## Rollback

Each apply backs up the previous remote file under `/var/backups/sshd_config/`. Roll back by passing the host-local backup path:

```bash
scripts/slurm-ansible-sshd-rollout.sh rollback \
  --limit '<host-or-group>' \
  --rollback-source /var/backups/sshd_config/<timestamp>.<host>.sshd_config
```

Rollback uses `sshd -t -f %s` validation before replacing the active config and restarts `sshd` through OpenRC.
