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

## Captured Microbox State

The microbox capture imported from `/tmp/microbox.gentoo-state-capture.tar` is
stored at:

```text
docs/workstation-package-capture/microbox-2026-05-06/
```

Current counts:

```text
completed merges since boot: 4
world atoms: 247
primary candidates: 247
```

Microbox was running the regular Gentoo `amd64/23.0/desktop/plasma` live ISO,
not the LLVM/Clang profile. Its package list is therefore useful as user intent,
but Plasma, SDDM, and Wayland-adjacent atoms are filtered before any Stage4 LOX
workstation review list is accepted.

## Combined Stage4 LOX Review

The generated review set is stored at:

```text
docs/workstation-package-capture/stage4-lox-workstation-review-2026-05-06/
```

Canonical target ID:

```text
stage4-lox__stage5-workstation-nscde__amd64__gpu-universal-xorg
```

Current generated counts:

```text
shared primary candidates: 222
X12AGAIN-only primary candidates: 25
microbox-only primary candidates: 25
union primary candidates: 272
Wayland/Plasma rejects: 2
review candidates after rejects: 270
```

`stage5-workstation-review-candidates.atoms` remains a review input, not an
active emerge target. Active workstation package policy stays curated in:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-package-lists/stage5-virtual-host-workstation-nscde.packages
```

## Former LLVM/Clang Hosts

Two former etc-keeper Portage archives were inspected for tuning references:

- `/tmp/gentoo-portage-legiongo.tar`
- `/tmp/gentoo-portage-susse.tar`

Sanitized notes are tracked at:

```text
docs/workstation-package-capture/former-portage-policy/
```

The raw archives are not imported. The `susse` archive contains GnuPG/private
key material under `/etc/portage/gnupg`, so only policy summaries and selected
advisory atoms are committed.

Useful policy carried forward:

- LLVM/Clang toolchain, OpenRC, Xorg, `-systemd`, and explicit `-wayland`.
- `VIDEO_CARDS` policy covering Intel, AMDGPU, radeonsi, fbdev, and vesa.
- Mesa, QEMU, GTK, Chromium/libva, and media package policy that disables
  Wayland where Gentoo exposes a USE flag.
- Binpkg generation with `--buildpkg=y`, `--with-bdeps=y`,
  `--complete-graph=y`, and `--binpkg-respect-use=y`.

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

## Regeneration

Regenerate the combined review set with:

```bash
bash scripts/generate-workstation-package-review.sh \
  docs/workstation-package-capture/x12again-2026-05-06 \
  docs/workstation-package-capture/microbox-2026-05-06 \
  docs/workstation-package-capture/stage4-lox-workstation-review-2026-05-06
```
