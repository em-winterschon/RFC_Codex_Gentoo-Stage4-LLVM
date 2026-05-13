# M70 Forge Automation Admin

The first M70 node is reserved as `admin-sun99-forge-099070.rfc1918.host`
(`172.16.99.70`, MAC `00:07:32:78:65:C6`) and uses the
`metal-forge-automation-admin` Stage5 profile.

It is the migration target for Forge/Codex, Ansible, vault workflows, GitHub
CLI, X12AGAIN SoL access through `/root/.ssh/codex.d/ipmi.d/ipmi-prinzessin`,
and restored `/root`, `/opt`, `/var/lib/ansible`, `/var/lib/codex`,
`/var/lib/forge-memory`, and `/var/lib/git` continuity data.

Provisioning is tracked as UEFI PXE to iPXE with static DHCP address
`172.16.99.70`, boot file `m70-forge-ipxe.efi`, and netboot publisher
`172.16.99.88`.
