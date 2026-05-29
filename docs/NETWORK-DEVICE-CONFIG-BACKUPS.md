# Network Device Config Backups

This workflow captures post-change configuration backups for network devices
and stages only Ansible-Vault-encrypted artifacts in git.

## Scope

Current automated device families:

- MikroTik RouterOS routers and switches from the `mikrotik_routeros`
  inventory group over SSH or serial console.
- MikroTik SwOS switches from the `mikrotik_swos` inventory group.
- Manual RouterOS post-change exports under `/root/operator-private/routeros`
  using `post-*.rsc` filenames.

The workflow keeps plaintext exports outside the repo under operator-private
paths, then encrypts selected config artifacts into
`encrypted-backups/network-devices/`.

## One Command

```bash
scripts/backup-network-device-configs.sh --sync-git
```

Default behavior:

1. Runs `playbooks/routeros-state-snapshot.yml` with
   `routeros_snapshot_include_sensitive_export=true`. The playbook uses SSH
   where available and serial console automation for serial-first devices such
   as CCR2004 and CRS354.
2. Runs `playbooks/swos-state-snapshot.yml`, including SwOS `backup.swb`.
3. Encrypts the latest snapshot per host with `ansible-vault encrypt`.
4. Writes encrypted files under `encrypted-backups/network-devices/`.
5. With `--sync-git`, stages, commits, and pushes the encrypted artifact tree.

If the newest RouterOS snapshot contains only failed command outputs, staging
skips it and falls back to the newest snapshot for that host with a successful
config export. This prevents serial-port or SSH transport failures from being
committed as false-positive backups.

For a dry run that never touches devices or writes encrypted files:

```bash
scripts/backup-network-device-configs.sh --skip-collect --dry-run
```

## Plaintext Storage

Plaintext collection remains outside git:

```text
/root/operator-private/routeros/state-snapshots/<inventory-host>/<timestamp>/
/root/operator-private/routeros/<manual-device-name>/post-*.rsc
/root/operator-private/swos/<inventory-host>/<timestamp>/
```

RouterOS artifacts:

- `export-show-sensitive.txt` when supported by the RouterOS version.
- `export-hide-sensitive.txt` as a fallback for older or restricted devices.
- `manifest.json`.

SwOS artifacts:

- `backup.swb`.
- `summary.json`.

## Encrypted Git Storage

Encrypted output is intentionally separate from the main Ansible variable vault:

```text
encrypted-backups/network-devices/routeros/<inventory-host>/<timestamp>/*.vault
encrypted-backups/network-devices/routeros-manual/<manual-device-name>/*.vault
encrypted-backups/network-devices/swos/<inventory-host>/<timestamp>/*.vault
encrypted-backups/network-devices/manifest.json
```

Only `*.vault` files contain device config contents. The unencrypted manifest
stores repo-safe metadata: device type, inventory host, timestamp, source path,
encrypted path, and file sizes.

## Restore

View or decrypt with the standard vault wrapper:

```bash
scripts/with-ansible-vault-env.sh ansible-vault view \
  encrypted-backups/network-devices/routeros/sw_spine_crs309_rfc99/<timestamp>/export-show-sensitive.txt.vault
```

For RouterOS, review the decrypted export before importing. Treat decrypted
`show-sensitive` exports as secrets and keep them out of shell history, logs,
and normal chat output.

## Operational Gate

Run this workflow after every RouterOS or SwOS mutation and before declaring a
network change complete. If live collection cannot run, preserve the
operator-private plaintext snapshot path and use:

```bash
scripts/backup-network-device-configs.sh --skip-collect --git-add --git-commit
```

This lets a serial-console or manually captured post-change snapshot still flow
through the same encrypted git back-channel.
