# gentoo-liveiso-ansible

A rapid-deploy Gentoo installer scaffold intended to be run from a booted Gentoo LiveISO,
either locally with `--connection=local` or remotely against a host booted into the same kind
of LiveISO via root SSH.

## Design goals

- UEFI-first
- OpenRC-first
- Root on ZFS with OpenZFS 2.4 and ZFSBootMenu by default
- LLVM/Clang-oriented make.conf generation
- A small local profile overlay to combine multiple stable Gentoo profile axes
- Reproducible disk provisioning with explicit destructive opt-in

## Why a local profile overlay exists

The desired target profile is effectively:

- amd64
- openrc
- llvm
- split-usr
- no-multilib
- hardened

Gentoo exposes these profile axes, but this scaffold treats the exact combination as a local
profile overlay so that the installer can compose the desired state cleanly and predictably.
The default overlay parents are:

- `gentoo:default/linux/amd64/23.0/llvm`
- `gentoo:default/linux/amd64/23.0/split-usr/no-multilib/hardened`

Adjust `profile_parents` if the upstream profile graph changes.

## Storage model

Supported `storage_layout` values:

- `single-drive`
- `raid-1`
- `raid-10`
- `zfs-mirror`
- `zraid1`
- `zraid2`
- `zraid3`
- `draid`

### Recommendation

For `zfs-2.4 on /`, prefer the native ZFS topologies:

- `single-drive`
- `zfs-mirror`
- `zraid2`
- `draid`

The `raid-1` and `raid-10` layouts intentionally gate execution with
`storage_allow_mdadm_under_zfs=true`, because they place ZFS on top of mdraid.
That can still be useful in some environments, but it is not the default recommendation.

## CPU tuning profiles

Available `portage_cpu_profile` values:

- `amd_ryzen_z1_extreme`
- `amd_epyc_zen4`
- `amd_epyc_zen5`
- `intel_xeon_8370c`
- `intel_core_i9_13900hk`
- `intel_core_ultra_5_125h`
- `intel_xeon_e5_2643v4`

These primarily drive:

- `-march`
- `-mtune`
- `RUSTFLAGS=-C target-cpu=...`
- `LLVM_TARGETS`

GPU-specific Portage settings are intentionally separate via `gpu_stack`.

## Quick start

### Local execution from the LiveISO

```bash
./scripts/bootstrap-liveiso.sh
vim inventories/examples/group_vars/install_targets.yml
ansible-playbook playbooks/install.yml -l liveiso-local --connection=local
```

### Remote execution against a booted LiveISO

```bash
./scripts/bootstrap-liveiso.sh
vim inventories/examples/hosts.yml
vim inventories/examples/group_vars/install_targets.yml
ansible-playbook playbooks/install.yml -l remote-liveiso
```

### Python environment setup helper

Generate the ansible Python setup script:

```bash
./scripts/generate-ansible-python-setup.sh
```

Then run the generated script (defaults to `scripts/setup-ansible-python-env.sh`) to:

- clone/update this repository
- verify Python 3.11+
- bootstrap `pip` if needed
- install `pipenv` if needed
- install this project's `requirements.txt` into a pipenv

You can override defaults when running the generated script, for example:

```bash
REPO_URL=https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM.git BRANCH=main ./scripts/setup-ansible-python-env.sh
```

## Current implementation notes

This repository is a first-cut scaffold, not a finished fully unattended product. The major
flows are present:

- destructive device wipe and GPT partitioning
- UEFI ESP + swap + ZFS root member provisioning
- native ZFS or mdadm-backed storage selection
- latest-stage3 discovery and extraction
- local profile overlay creation
- generated LLVM/Clang make.conf
- basic chroot setup
- package installation for ZFS + dracut + dist-kernel strategy
- prebuilt ZFSBootMenu EFI deployment
- OpenRC service enablement for ZFS, NetworkManager, and sshd

The pieces most likely to need local policy refinement are:

- whether your target make.conf should inherit from an existing house style template
- the exact parent list for the custom profile overlay
- your preferred kernel strategy
- your exact `USE`, `CPU_FLAGS_X86`, and package masks
- any encrypted storage workflow
- multi-ESP synchronization on multi-disk installs
- per-interface network policy beyond enabling NetworkManager

## Suggested next steps

1. Decide whether mdadm-backed layouts should remain supported at all.
2. Add optional LUKS-on-top-of-partition, then ZFS inside LUKS.
3. Add per-host files under `inventories/examples/host_vars/`.
4. Replace the prebuilt ZFSBootMenu download with local image generation if desired.
5. Add a post-install validation play.
