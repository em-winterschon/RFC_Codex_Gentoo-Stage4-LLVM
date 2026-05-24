# SSH Bastion Policy Runbook

This is the wiki-facing mirror of `docs/SSH-BASTION-POLICY-RUNBOOK.md`.

## Summary

YukonSYS standardizes SSH client behavior through `/etc/ssh/ssh_config.d/*.conf` and routes selected access through an R4SE bastion once that host is live. FreeIPA remains the identity and authorization source. Direct break-glass SSH remains available until the bastion path is validated.

## Key Commands

Inspect effective client settings:

```bash
ssh -G root@agx-rfc99-bunnydev.rfc1918.host | grep -E '^(proxyjump|controlmaster|controlpersist|controlpath) '
```

Client backout:

```bash
sudo rm -f /etc/ssh/ssh_config.d/20-yukon-controlmaster.conf
sudo rm -f /etc/ssh/ssh_config.d/30-yukon-bastion-routing.conf
sudo rm -f /etc/ssh/ssh_config.d/40-yukon-host-aliases.conf
```

Bastion backout:

```bash
sudo rm -f /etc/ssh/sshd_config.d/30-yukon-bastion.conf
sudo sshd -t -f /etc/ssh/sshd_config
sudo service ssh restart || sudo service sshd restart
```

Emergency bypass:

```bash
ssh -o ProxyJump=none -o ControlMaster=no -o ControlPath=none root@agx-rfc99-bunnydev.rfc1918.host true
```
