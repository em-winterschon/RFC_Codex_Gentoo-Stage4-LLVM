# SSH Bastion Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-user SSH client drift with a host-level, FreeIPA-aware SSH access plane that can route operator and Forge SSH through an R4SE bastion without removing break-glass direct access.

**Architecture:** OpenSSH clients consume shared drop-ins from `/etc/ssh/ssh_config.d`. The R4SE bastion terminates inbound SSH on its admin interface and forwards outbound SSH over RFC99, SUN99, FMT2, VPN, WireGuard, and future BigNetwork paths. FreeIPA remains the identity and authorization source; the bastion does not bypass target-host authorization.

**Tech Stack:** OpenSSH client/server, Ansible roles, FreeIPA/SSSD/PAM/HBAC, optional Vault SSH CA, optional WireGuard/BigNetwork, OpenRC or distro-native service management through Ansible `service`.

---

## Implementation Tasks

- [ ] Add an SSH client policy role that renders `/etc/ssh/ssh_config.d` fragments for safe ControlMaster defaults, host aliases, and opt-in bastion routing.
- [ ] Add an SSH bastion host role that prepares an R4SE-class host for FreeIPA-backed SSH forwarding with conservative `sshd` defaults.
- [ ] Add playbooks for applying the client policy and bastion role independently.
- [ ] Add an operator runbook with preflight checks, apply commands, validation commands, and backout commands.
- [ ] Preserve per-user SSH configs during phase 1; migration to smaller user configs is a later controlled step because OpenSSH uses first-value-wins precedence.
- [ ] Keep direct SSH break-glass paths active until bastion routing is validated from at least two Forge users and one human operator account.
- [ ] Validate with `ssh -G` before and after changes so `ProxyJump`, `ControlPath`, `ControlMaster`, and `ControlPersist` are visible before live use.
- [ ] Add static tests that require explicit apply gates, forbid `/tmp/.cm-*` ControlPath defaults, require rollback documentation, and ensure no systemd-only automation is introduced.

## Rollout Order

- [ ] Operator powers and networks the R4SE, assigns inventory/DNS, and hands the host to Forge.
- [ ] Enroll the R4SE into FreeIPA or confirm SSSD/PAM/HBAC already resolves `verwalterin` and Forge users.
- [ ] Run `ssh-bastion-host.yml` against the R4SE with `ssh_bastion_host_enabled=true` and `ssh_bastion_host_apply=true`.
- [ ] Run `ssh-client-policy.yml` against one non-critical client with only ControlMaster policy enabled.
- [ ] Validate direct SSH and bastion-routed SSH from that client.
- [ ] Expand client policy to Forge users and operator workstations.
- [ ] Only after validation, prune duplicated per-user `~/.ssh/config` entries that conflict with system policy.

## Backout Strategy

- [ ] Client backout removes the YukonSYS client drop-ins from `/etc/ssh/ssh_config.d` and restores any backed-up per-user config if a later migration touched user files.
- [ ] Bastion backout removes the bastion `sshd_config.d` drop-in, restores the backed-up main `sshd_config` if the Include line was added, and restarts the SSH service through Ansible `service`.
- [ ] Routing backout disables bastion path selection by setting `ssh_client_policy_manage_bastion_routing=false` or removing the bastion routing drop-in.
- [ ] Break-glass direct SSH remains available throughout rollout and is the recovery path if ProxyJump breaks.
