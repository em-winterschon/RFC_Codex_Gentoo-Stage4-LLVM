# Workstation Package Capture

This workflow captures Gentoo package intent from an existing host before it is
reimaged into the Stage4/Stage5 workstation profile.

## Captured X12AGAIN State

The on-host capture is stored at:

```text
docs/workstation-package-capture/x12again-2026-05-06/
```

Current counts:

```text
completed merges since boot: 104
world atoms: 236
primary candidates: 247
```

The important files are:

- `world.atoms`: the best source for primary user-requested packages.
- `merged-since-boot.atoms`: every package completed by Portage since boot,
  including dependencies.
- `emerge-commands-since-boot.raw`: raw emerge command lines from the log.
- `requested-targets-since-boot.resolved`: rough package targets from those
  commands, resolved through `qlist` where possible.
- `primary-candidates.atoms`: union of `world.atoms` and resolved
  category/package command targets.

## Preferred Capture Command

From this repo on any Gentoo host or live ISO:

```bash
sudo bash scripts/capture-gentoo-emerge-state.sh /tmp/gentoo-emerge-state-$(hostname -s)-$(date +%Y%m%d-%H%M%S)
```

The output directory can then be copied back into
`docs/workstation-package-capture/` for comparison and merge planning.

## Manual Commands

If the helper script is not available, use these commands.

Primary requested applications:

```bash
sudo sort -u /var/lib/portage/world
```

Completed package merges since current boot:

```bash
boot_epoch="$(stat -c %Y /proc/1)"
sudo awk -v boot="${boot_epoch}" '
  $1 + 0 >= boot && /::: completed emerge / {
    atom = $0
    sub(/^.*::: completed emerge \([0-9]+ of [0-9]+\) /, "", atom)
    sub(/ to \/.*/, "", atom)
    print atom
  }
' /var/log/emerge.log | sort -u
```

Raw emerge invocations since current boot:

```bash
boot_epoch="$(stat -c %Y /proc/1)"
sudo awk -v boot="${boot_epoch}" '
  $1 + 0 >= boot && /\*\*\* emerge / {
    line = $0
    sub(/^[0-9]+:[[:space:]]+\*\*\* emerge[[:space:]]+/, "", line)
    print line
  }
' /var/log/emerge.log
```

Installed package atoms for cross-checking:

```bash
qlist -IC | sort -u
```

Full installed package/version inventory:

```bash
qlist -ICv | sort -u
```

## Interpretation

`/var/lib/portage/world` is the closest Gentoo-native answer for "primary
applications intentionally emerged". `/var/log/emerge.log` answers "what got
merged since boot", but that includes dependencies and rebuilds. For the
workstation VM emerge party, use `primary-candidates.atoms` as the initial
review list, then pull from `merged-since-boot.atoms` only when a dependency is
clearly part of the desired workstation baseline.
