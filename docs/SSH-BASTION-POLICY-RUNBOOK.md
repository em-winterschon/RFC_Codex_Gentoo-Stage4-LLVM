# SSH Bastion Policy Runbook

This runbook covers the host-level SSH client policy and the future R4SE bastion path. It intentionally avoids SELinux requirements and does not require systemd-specific commands.

## Design Decision

Use `/etc/ssh/ssh_config.d/*.conf` for shared OpenSSH client policy and keep per-user `~/.ssh/config` files limited to true user-specific keys or exceptions. OpenSSH applies the first value it sees, so a per-user `ProxyJump`, `ControlPath`, or `ControlMaster` can block the system policy from taking effect. Phase 1 does not rewrite user configs; it adds the shared policy and validates the effective config with `ssh -G`.

The immediate ControlMaster standard is:

```sshconfig
ControlMaster auto
ControlPersist 10m
ControlPath %d/.ssh/controlmasters/%C
```

This avoids the shared `/tmp/.cm-*` socket collision that has already appeared on M70.

## Operator Handoff Requirements

Before Forge applies the bastion role, Operator handles the physical work:

- Rack and power the R4SE.
- Connect the ingress/admin NIC and egress/network NICs.
- Provide IP address, hostname, interface names, and any VLAN or BigNetwork notes.
- Confirm whether the host is Debian/DietPi, Gentoo, or another OS.
- Confirm SSH works with a break-glass local account or root console access.

Forge then handles the automatable work:

- Add or validate inventory facts.
- Enroll or validate FreeIPA/SSSD.
- Apply the bastion `sshd` drop-in.
- Apply client policy to selected clients.
- Validate direct and ProxyJump SSH paths.

## Preflight

Run these before changing a client:

```bash
hostname -f
ssh -V
ssh -G root@agx-rfc99-bunnydev.rfc1918.host | grep -E '^(hostname|user|proxyjump|controlmaster|controlpersist|controlpath) '
```

Check for per-user settings that would override system policy:

```bash
grep -RniE '^\s*(ProxyJump|ControlMaster|ControlPersist|ControlPath)\b' ~/.ssh/config ~/.ssh/*.d 2>/dev/null || true
```

Create a local backup:

```bash
sudo install -d -m 0700 /root/ssh-policy-backup
sudo cp -a /etc/ssh/ssh_config /root/ssh-policy-backup/ssh_config.$(date -u +%Y%m%dT%H%M%SZ)
sudo cp -a /etc/ssh/ssh_config.d /root/ssh-policy-backup/ssh_config.d.$(date -u +%Y%m%dT%H%M%SZ)
```

## Apply Client Policy

Start with ControlMaster only:

```bash
cd /home/forge1/src/RFC_Codex_Gentoo-Stage4-LLVM/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook -i inventories/local-network/hosts.yml playbooks/ssh-client-policy.yml \
  -e ssh_client_policy_hosts=ssh_client_policy_targets \
  -e ssh_client_policy_enabled=true \
  -e ssh_client_policy_apply=true \
  -e ssh_client_policy_manage_controlmaster=true \
  -e ssh_client_policy_manage_bastion_routing=false
```

Validate:

```bash
ssh -G root@agx-rfc99-bunnydev.rfc1918.host | grep -E '^(proxyjump|controlmaster|controlpersist|controlpath) '
test -d ~/.ssh/controlmasters
```

Enable bastion routing only after the R4SE is live and validated:

```bash
ansible-playbook -i inventories/local-network/hosts.yml playbooks/ssh-client-policy.yml \
  -e ssh_client_policy_hosts=ssh_client_policy_targets \
  -e ssh_client_policy_enabled=true \
  -e ssh_client_policy_apply=true \
  -e ssh_client_policy_manage_bastion_routing=true \
  -e ssh_client_policy_bastion_host=r4se-bastion-rfc99.rfc1918.host \
  -e ssh_client_policy_bastion_user=verwalterin
```

Validate:

```bash
ssh -G root@agx-rfc99-bunnydev.rfc1918.host | grep -E '^(proxyjump|controlmaster|controlpersist|controlpath) '
ssh -o BatchMode=yes root@agx-rfc99-bunnydev.rfc1918.host true
```

## Apply R4SE Bastion Role

After the R4SE is reachable and has inventory:

```bash
cd /home/forge1/src/RFC_Codex_Gentoo-Stage4-LLVM/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook -i inventories/local-network/hosts.yml playbooks/ssh-bastion-host.yml \
  -e ssh_bastion_hosts=ssh_bastion_hosts \
  -e ssh_bastion_host_enabled=true \
  -e ssh_bastion_host_apply=true \
  -e ssh_bastion_host_sshd_service_name=ssh
```

Use `ssh_bastion_host_sshd_service_name=sshd` on Gentoo, Rocky, Oracle Linux, or other systems where the SSH service is named `sshd`.

Validate on the bastion:

```bash
sshd -t -f /etc/ssh/sshd_config
sshd -T | grep -E '^(allowtcpforwarding|gatewayports|x11forwarding|allowagentforwarding|passwordauthentication|authorizedkeyscommand) '
getent passwd verwalterin
sss_ssh_authorizedkeys verwalterin >/tmp/verwalterin.keys
```

Validate from a client:

```bash
ssh -J verwalterin@r4se-bastion-rfc99.rfc1918.host root@agx-rfc99-bunnydev.rfc1918.host true
```

## Required Backout Commands

Client backout:

```bash
sudo rm -f /etc/ssh/ssh_config.d/20-yukon-controlmaster.conf
sudo rm -f /etc/ssh/ssh_config.d/30-yukon-bastion-routing.conf
sudo rm -f /etc/ssh/ssh_config.d/40-yukon-host-aliases.conf
ssh -G root@agx-rfc99-bunnydev.rfc1918.host >/tmp/ssh-g-rollback.out
```

If a later migration changed per-user files, restore them explicitly:

```bash
sudo cp -a /root/ssh-policy-backup/home-ssh/<user>/config /home/<user>/.ssh/config
sudo chown <user>:<user> /home/<user>/.ssh/config
sudo chmod 0600 /home/<user>/.ssh/config
```

Bastion host backout:

```bash
sudo rm -f /etc/ssh/sshd_config.d/30-yukon-bastion.conf
sudo sshd -t -f /etc/ssh/sshd_config
sudo service ssh restart || sudo service sshd restart
```

If the role added the Include line and it must be reverted, restore the backed-up main config:

```bash
sudo cp -a /root/ssh-policy-backup/sshd_config.pre-yukon /etc/ssh/sshd_config
sudo sshd -t -f /etc/ssh/sshd_config
sudo service ssh restart || sudo service sshd restart
```

Emergency per-command bypass:

```bash
ssh -o ProxyJump=none -o ControlMaster=no -o ControlPath=none root@agx-rfc99-bunnydev.rfc1918.host true
```

## Notes

- Do not remove direct SSH access until the bastion path has been validated from at least two Forge users and one human operator account.
- Do not store private keys in shared repo content.
- FreeIPA should provide user identity, sudo policy, HBAC, and SSH public keys. The bastion is a route and policy enforcement point, not a replacement for target-host authorization.
- Vault SSH CA or Warpgate can be layered later for short-lived SSH certificates, session recording, and stronger operator audit.
