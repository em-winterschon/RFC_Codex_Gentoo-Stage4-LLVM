# Network Device Config Backups

Post-change RouterOS and SwOS config backups are captured to
operator-private storage and then encrypted into the repo as Ansible Vault
files.

Run:

```bash
scripts/backup-network-device-configs.sh --sync-git
```

Plaintext remains outside git:

```text
/root/operator-private/routeros/state-snapshots/<host>/<timestamp>/
/root/operator-private/routeros/<manual-device-name>/post-*.rsc
/root/operator-private/swos/<host>/<timestamp>/
```

Encrypted git artifacts live under:

```text
encrypted-backups/network-devices/
```

RouterOS collection uses SSH where available and serial console automation for
serial-first devices. It requests `/export show-sensitive` for encrypted
backups and falls back to `hide-sensitive` if the full export is unavailable.
Manual RouterOS `post-*.rsc` exports are also staged when serial/SSH collection
is unavailable. SwOS stores the raw `backup.swb` file plus decoded summary
metadata. Treat decrypted files as secrets.
