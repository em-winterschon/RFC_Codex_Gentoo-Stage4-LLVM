# Hasslehoff Backup Workflow

This workflow captures Proxmox host configuration from `root@hasslehoff` into
on-host operator-private storage.

## Command

```bash
bash scripts/backup-hasslehoff-config.sh
```

Dry-run:

```bash
HASSLEHOFF_BACKUP_DRY_RUN=1 bash scripts/backup-hasslehoff-config.sh
```

Scheduled wrapper dry-run:

```bash
HASSLEHOFF_BACKUP_DRY_RUN=1 bash scripts/backup-hasslehoff-scheduled.sh
```

Default output:

```text
/root/operator-private/hasslehoff/backups/<UTC timestamp>/
```

Captured data includes:

- `/etc/pve`
- `/etc/network/interfaces`
- `/etc/sysctl.d`
- Proxmox QEMU, LXC, storage, network, disk, and cluster resource JSON from
  `pvesh`
- `qm list`, `pct list`, IP, route, bridge, ZFS, and block-device summaries
- SHA256 checksum for the resulting tarball

## External Scheduled Backup Readiness

Thursday 2026-05-14 objective: prepare Hasslehoff for scheduled external
backups before additional VM migration, gateway, or X12AGAIN reimage work
depends on it.

The current script is only the first layer. It captures host configuration and
Proxmox state into operator-private local storage, but it does not yet provide a
durable off-host copy, VM disk coverage, retention, or restore validation.

## Hasslehoff Backup Policy

The scheduling and coverage decision record lives in
`docs/backup-policies/hasslehoff-backup-policy.yml` and is validated by
`scripts/validate-hasslehoff-backup-policy.py`. It makes the first durable
target explicit as the NASA relay through M70, rejects X12AGAIN as a backup
dependency, and defines the minimum VM/LXC coverage set.

Required first-wave VM/LXC service coverage is NetBox, FreeIPA, observability, syslog/search, netboot publisher, container-services, and workstation validation. Each class requires a daily backup path using `vzdump` or Proxmox Backup Server plus restore validation through disposable restore and offline image inspection.

## Recurring Scheduler Installation

Use
`gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/hasslehoff-backup-scheduler.yml`
to install the recurring root cron job on Hasslehoff. The role is disabled by
default and requires both `hasslehoff_backup_scheduler_enabled=true` and
`hasslehoff_backup_scheduler_apply=true` before writing
`/etc/cron.d/hasslehoff-backup`.

The role installs a small runtime bundle under
`/opt/rfc1918/hasslehoff-backup` instead of requiring a full git checkout on
the Proxmox host. The runtime bundle contains `backup-hasslehoff-config.sh`,
`backup-hasslehoff-scheduled.sh`, `validate-hasslehoff-backup-policy.py`, and
`docs/backup-policies/hasslehoff-backup-policy.yml`.

Before installing a recurring job, run the same role with
`hasslehoff_backup_scheduler_run_preflight=true`. That executes the scheduled
wrapper with `HASSLEHOFF_BACKUP_PREFLIGHT_ONLY=1`, validates
`docs/backup-policies/hasslehoff-backup-policy.yml`, checks wrapper shell
syntax, and rejects any mirror target containing `x12again`, `prinzessin`, or
`172.16.99.108`.

The second-layer scheduled wrapper is:

```bash
bash scripts/backup-hasslehoff-scheduled.sh
```

It runs `scripts/backup-hasslehoff-config.sh`, writes a timestamped
`manifest.json`, uses a lockfile to prevent overlapping runs, and optionally
mirrors the timestamped output to an external target.

Example external mirror:

```bash
HASSLEHOFF_BACKUP_MIRROR_TARGET=backup-node:/srv/backups/hasslehoff \
HASSLEHOFF_BACKUP_MIRROR_VERIFY=1 \
HASSLEHOFF_BACKUP_RESTORE_VERIFY=1 \
HASSLEHOFF_BACKUP_NOTIFY=1 \
bash scripts/backup-hasslehoff-scheduled.sh
```

The wrapper uses `rsync -aH` and does not delete remote data. Set
`HASSLEHOFF_BACKUP_NOTIFY=1` to publish success/failure summaries to local ntfy.
Set `HASSLEHOFF_BACKUP_RESTORE_VERIFY=1` to require manifest readback plus
SHA256 validation from the mirrored target after rsync completes.
Mirror rsync defaults to `HASSLEHOFF_BACKUP_MIRROR_RSYNC_OPTS="--no-owner --no-group"`
so squashed NFS relay targets such as NASA do not fail on ownership changes.
Override that variable only for targets where preserving remote ownership is
known to be supported and required.

Preflight the first external target before scheduling:

```bash
HASSLEHOFF_BACKUP_PREFLIGHT_ONLY=1 \
HASSLEHOFF_BACKUP_MIRROR_TARGET='/mnt/nasa/hasslehoff/config-bundles' \
bash scripts/backup-hasslehoff-scheduled.sh
```

The scheduled wrapper refuses X12AGAIN-dependent mirror targets by name, known
alias, or `172.16.99.108` so an accidental operator default cannot place the
only durable copy back on the host being prepared for reimage. Local retention
is disabled by default; set `HASSLEHOFF_BACKUP_RETENTION_DAYS=<days>` to scan
for expired local backup directories, and add
`HASSLEHOFF_BACKUP_RETENTION_APPLY=1` only when deletion is intentionally
approved.

Target backup layers:

- Config and control-plane state:
  `scripts/backup-hasslehoff-config.sh` captures Proxmox host state before and
  after risky changes, then the resulting timestamped bundle is mirrored to the
  external backup target.
- VM and LXC recoverability:
  selected non-ephemeral service VMs must have `vzdump` or Proxmox Backup
  Server coverage, starting with NetBox, FreeIPA, observability, syslog/search,
  netboot publisher, container-services, and workstation validation VMs.
- Host and ZFS datasets:
  use recursive ZFS snapshots plus `zfs send` to a ZFS-capable external target
  where possible. If the first external target is not ZFS-capable, use
  encrypted `borg` or `restic` repositories until a ZFS receive target exists.
- Restore validation:
  every scheduled backup class must have a restore validation gate. Minimum
  validation is checksum verification plus manifest readback; VM coverage also
  requires periodic restore into a disposable VM or offline image inspection.

Initial external target candidates:

- FMT2 NASA storage controller `kvm-sfo200-nasa-9918.vernetzen.io`
  (`10.200.99.18`) over the temporary M70 OpenVPN transport. On
  2026-05-15, DNS, ICMP, SSH `tcp/22`, and NFS `tcp/2049` validated from
  SUN99, while rsync daemon `tcp/873` was closed or filtered. The X12AGAIN
  operator artifact `/root/operator-private/fmt2-nasa/nasa-nfs-exports`
  records NASA's reference client-facing mapping as
  `/srv/nfs/rfc1918/nasa/chunkers`, allowed for both `172.16.99.0/24` and the
  OpenVPN transit subnet `192.168.132.0/24` with
  `rw,sync,insecure,all_squash,no_subtree_check,sec=sys` and anonymous UID/GID
  `8888`. Live `exportfs -v` currently reports the canonical backing path
  `/opt/storage/local/zfs/ora-sas-mpaths/chunkers/rfc1918.nfs`. Use the M70
  NASA NFS relay pattern for bulky artifacts: mount NASA NFS only on
  `admin-sun99-forge-099070`, then rsync backup data to that mounted path on
  the M70 so the payload transits `tun-fmt2`. X12AGAIN must not mount NASA NFS.
  Do not depend on rsync daemon service.
- R86S/off-host backup node over SSH or mounted storage for immediate
  config-bundle mirroring.
- QNAP TS435XEU after NAS inventory, storage-pool validation, and RBAC/AAA
  integration.
- Future Proxmox Backup Server or ZFS receive target when storage architecture
  stabilizes.

Schedule intent:

- Run config/state backup daily before other automation windows and immediately
  before or after Proxmox/network changes.
- Run selected service-VM backups daily, with lower-frequency full coverage for
  bulky or rebuildable workloads.
- Retain short daily history locally, longer history externally, and define
  retention by service criticality instead of raw VM count.
- Emit success/failure notifications to the local ntfy service and scrape backup
  freshness through observability once exporters/checks are wired.

Readiness gates:

- External backup target is reachable without relying on X12AGAIN.
- Target free space and retention are known before the first full VM run.
- Secrets stay in Ansible Vault or backup-tool repositories; raw backup artifacts are never committed to git.
- The backup process is throttleable so it does not disrupt Hasslehoff VM
  service SLOs or the SUN99 management network.
- Backout is limited to disabling the timer/job and leaving existing backups in
  place; backup enablement must not require destructive host changes.

## FMT2 NASA Mirror Target

The NASA controller is the preferred first durable off-site target while the
FMT2 compatibility VPN is live:

```text
host: kvm-sfo200-nasa-9918.vernetzen.io
ip: 10.200.99.18
role: Dell R730xd storage controller for the FMT2 OpenZFS array
validated: icmp, ssh/tcp22, nfs/tcp2049, showmount export visibility
reference mapping: /srv/nfs/rfc1918/nasa/chunkers
live exportfs path: /opt/storage/local/zfs/ora-sas-mpaths/chunkers/rfc1918.nfs
allowed clients: 172.16.99.0/24 and 192.168.132.0/24
export policy: rw,sync,insecure,all_squash,no_subtree_check,sec=sys,anonuid=8888,anongid=8888
validated 2026-05-15: successful M70 NFSv3 mount over tun-fmt2 plus write/read/delete
not validated: rsync daemon/tcp873
```

## M70 NASA NFS relay

Immediate safe mirror mode is direct `rsync` over SSH from the scheduled
wrapper to the M70 relay, once the M70 has mounted NASA NFS at the selected
local mountpoint:

```bash
HASSLEHOFF_BACKUP_MIRROR_TARGET='root@admin-sun99-forge-099070:/mnt/nasa/hasslehoff/config-bundles' \
HASSLEHOFF_BACKUP_MIRROR_VERIFY=1 \
HASSLEHOFF_BACKUP_RESTORE_VERIFY=1 \
HASSLEHOFF_BACKUP_MIRROR_RSYNC_OPTS='--no-owner --no-group' \
HASSLEHOFF_BACKUP_NOTIFY=1 \
bash scripts/backup-hasslehoff-scheduled.sh
```

If the scheduled wrapper runs directly on M70, use a local mirror target under
the NASA mountpoint instead:

```bash
HASSLEHOFF_BACKUP_MIRROR_TARGET='/mnt/nasa/hasslehoff/config-bundles' \
HASSLEHOFF_BACKUP_MIRROR_VERIFY=1 \
HASSLEHOFF_BACKUP_RESTORE_VERIFY=1 \
HASSLEHOFF_BACKUP_MIRROR_RSYNC_OPTS='--no-owner --no-group' \
HASSLEHOFF_BACKUP_NOTIFY=1 \
bash scripts/backup-hasslehoff-scheduled.sh
```

Use `sshfs` only as an operator convenience mount for inspection or staging. For
scheduled automation, rsync-over-SSH to the M70 relay plus M70-local NFS is the
lower-risk topology because NASA is reachable only through the M70 OpenVPN link.
If NFS is selected for bulk VM artifacts, first validate mount behavior from the
M70 against the reference mapping and the live `exportfs -v` canonical path,
then mount it under a dedicated backup path with explicit timeout, retry, and
stale-mount detection before any destructive retention job.

Live validation on 2026-05-15 mounted the canonical export from M70 with
NFSv3/TCP through `tun-fmt2`. The export root is owned by UID/GID `4096`, while
NASA exports with `all_squash` to UID/GID 8888, so write probes fail at the
export root by design. The dedicated NASA-side directories
`hasslehoff/config-bundles` and `forge/transfer-stage` were created with
UID/GID 8888 and mode `2770`; M70 write/read/delete probes passed in both
directories. Because NASA uses `all_squash`, mirror jobs must not attempt
remote `chown`; the scheduled wrapper's default `--no-owner --no-group` mirror
options are required for this relay topology.

## Emergency Gateway Ethernet WAN Link

Before the CRS309 to CCR2004 swap, prepare a physical Ethernet cable path from
the on-host Codex system directly to the AT&T gateway or to the management L2
that still reaches it. This is the emergency path if the primary gateway is
offline long enough that Codex cannot reach network services.

Emergency objective:

- keep local shell access on the Codex host
- keep Hasslehoff serial access to the CCR2004 available through
  `/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A9888PID-if00-port0`
  (currently observed as `/dev/ttyUSB0`; do not depend on the volatile tty name)
- bypass the failed primary gateway long enough to review, repair, or roll back
  RouterOS

Minimum emergency procedure:

1. Patch the on-host emergency NIC directly to the AT&T gateway L2.
2. Bring up a temporary host IP in the AT&T subnet if DHCP does not work.
3. Confirm the host can reach `192.168.1.254`.
4. Use Hasslehoff serial console to repair or roll back CCR2004:
   `/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A9888PID-if00-port0`.
5. Do not remove the emergency cable until management reachability and default
   gateway behavior are stable through the planned fabric path.
