# EOD Status 2026-05-13

## Completed

- Advanced PR `#122`, `codex/m70-forge-admin-provisioning`, for the first M70
  Forge automation-admin host.
- Added the `metal-forge-automation-admin` profile, service atoms, package
  policy, inventory metadata, RouterOS DNS/DHCP desired state, NetBox intake,
  and M70-specific netboot publisher metadata.
- Validated the M70 local SATADOM ESP iPXE chainloader path after firmware did
  not expose a usable UEFI PXE NIC boot entry.
- Reboot-validated the corrected M70 dracut networking command line:
  `bootdev=netboot0`, `ifname=netboot0:00:07:32:78:65:c6`, and static
  `172.16.99.70/24` management networking through `netboot0`.
- Restored M70 reachability after the transient no-ARP state by using AP7901
  outlet 4, now labeled `admin-sun99-forge`.
- Repaired and validated the live M70 FreeIPA/SSSD enrollment path:
  - FreeIPA host object now has the canonical host principal.
  - `ipa-client-live-apply.yml` passes for `admin_sun99_forge_099070`.
  - Hostname/FQDN are set to `admin-sun99-forge-099070.rfc1918.host`.
  - `codex-admin` central SSH key lookup and login validation pass.
  - Host keytab generation is validated on the live rootfs.
- Normalized AP7901 outlet 4 inventory to the control-panel label
  `admin-sun99-forge`, targeting `admin_sun99_forge_099070:power0`.
- Removed the paused validation laptop from active repo inventory, DNS fixtures,
  roadmap, changelog, EOD notes, and wiki mirrors until it is re-inventoried
  later with new IP, switch, and PDU metadata.
- Added `tests/shell/test_paused_validation_laptop_removed.sh` and wired it
  into the full shell harness so stale paused-laptop references stay out of the
  repo.
- Posted the PR update note for commit `73f6e6d` and verified GitHub checks are
  green.

## Verification

- `bash tests/shell/test_m70_forge_admin_provisioning.sh`
  - result: pass
- `bash tests/shell/test_netbox_inventory_intake.sh`
  - result: pass
- `bash tests/shell/test_hetzner_dns_apply_and_hosts_fallback.sh`
  - result: pass
- `bash tests/shell/test_paused_validation_laptop_removed.sh`
  - result: pass
- `bash tests/shell/run-tests.sh`
  - result: `PASS: run-tests.sh`
- `git diff --check`
  - result: pass
- GitHub PR `#122` status:
  - merge state: `CLEAN`
  - checks: `notify`, `pre-commit`, and `shell-tests` all passed for commit
    `73f6e6d`

## Current Gates

- M70 FreeIPA/SSSD is validated only on the live-rootfs path. The persistent
  installed system still needs to render the same hostname, keytab generation,
  SSSD, static networking, and Forge continuity behavior after reboot.
- M70 storage mutation is not safe to run unattended. The SATADOM must remain
  the UEFI/iPXE entry point, while the two NVMe devices become mirrored ZFS
  targets only after a final disk-health check and human change-window approval.
- X12AGAIN remains blocked from reimage until the M70 has restored Forge/Codex
  continuity, validates `/root/.ssh/codex.d/ipmi.d/ipmi-prinzessin` SoL, and
  proves access to Hasslehoff, CCR2004, NetBox, FreeIPA, ntfy, GitHub, and the
  off-host backup target.
- The K10 durable Stage5 path remains blocked on disk install or secure
  first-boot OTP bundle consumption; embedding `/etc/krb5.keytab` or private
  age identities into public HTTP netboot artifacts remains disallowed.
- The first SLURM pilot is online, but scheduler observability, NetBox-derived
  node features, and durable health checks are still follow-up work. X12AGAIN
  must not be admitted as a worker until workstation, hypervisor, RDMA, and E2ET
  gates pass.
- FMT2/BigNetwork live transport remains pending. Do not promote FMT2 records
  into NetBox or Check_MK until the L2 path is validated and evidence is
  captured.
- FastMCP infrastructure wrappers remain scaffolded. NetBox, Proxmox, RouterOS,
  Trac, and internal-infra mutation paths must stay gated behind vaulted
  credentials, idempotency keys, and explicit mutation flags.

## Major Pivots And Errors

- The M70 firmware path did not match the ideal UEFI PXE plan. The accepted
  workaround is SATADOM ESP chainload to the M70-specific iPXE binary until a
  BIOS update or different boot path is proven.
- The M70 live rootfs initially leaked K10 identity and lacked durable SSSD
  state. The live apply now corrects this, but the installed profile must make
  it persistent instead of relying on ad-hoc live-rootfs repair.
- The FreeIPA host object existed without the expected canonical host principal;
  this caused keytab generation failure until the host principal was added.
- The paused validation laptop was removed from active state because carrying
  stale IP, MAC, switch, and PDU metadata would create false automation targets.

## Overnight Work Queue

1. Repo-only M70 hardening:
   - convert live M70 acceptance evidence into a persistent install runbook
   - add disk-health and ZFS layout preflight checks
   - add no-mutation tests around SATADOM/NVMe boundaries
2. Forge continuity prep:
   - define the restore manifest for `/root`, `/opt`, `/var/lib/ansible`,
     `/var/lib/codex`, `/var/lib/forge-memory`, and `/var/lib/git`
   - define post-restore validation for Ansible, vault, GitHub CLI, ntfy,
     NetBox, RouterOS, Hasslehoff, and X12AGAIN SoL
3. X12AGAIN preflight:
   - extend the existing reimage preflight with a concrete service reachability
     matrix
   - keep all destructive gates false
   - do not stop, wipe, or reimage X12AGAIN overnight
4. SLURM pilot follow-up:
   - add scheduler observability targets for Prometheus, VictoriaMetrics,
     Grafana, rsyslog, and Elasticsearch
   - add NetBox/Ansible feature-generation planning for CPU, memory, GPU, RDMA,
     storage locality, and power-control metadata
5. NetBox DCIM deep-modeling:
   - prepare dry-run-only interface, LAG, optics, cable, and power-chain
     modeling for CRS309, CRS354, CSS326, Hasslehoff, QNAP, K10, and M70
   - avoid live NetBox writes unless the plan is reviewed and snapshot-backed
6. FMT2/BigNetwork prep:
   - keep work to runbooks, evidence bundle definitions, and disposable VM
     smoke-test wrappers
   - do not mutate routing or promote FMT2 inventory until the live L2 path is
     up and validated

## Backout Summary

- Latest repo-safe M70 branch commits can be reverted independently:
  - `ee6c913 feat: validate M70 automation admin enrollment`
  - `6ff0aa2 fix: mark M70 shell test executable`
  - `5121605 docs: update M70 PDU outlet label`
  - `73f6e6d docs: remove paused validation laptop inventory`
- No X12AGAIN destructive action was performed by this branch.
- No M70 disk wipe was performed by this branch.
- The paused validation laptop can be reintroduced later as a new intake object
  only after fresh IPAM, switchport, MAC, power, and boot-flow metadata exist.

## Timing

- Report context capture started at `2026-05-13 19:13:55 PDT`.
- Report artifact drafting started at `2026-05-13 19:15:14 PDT`.
- Report verification completed at `2026-05-13 19:18:23 PDT`.
