# X12AGAIN Builder VM Isolation

X12AGAIN is a resource provider and artifact publisher, not a mutable build
workspace. Heavy Portage, stage4/stage5, Path B netboot, and rootfs builds must
run inside disposable builder VMs so stale chroots, bind mounts, package state,
or failed build experiments cannot poison the host.

## Operating Model

- X12AGAIN provides CPU, memory, NVMe storage, networking, and artifact serving.
- Builder VMs perform all chroot, Portage, image-build, rootfs, and netboot
  artifact work.
- Active netboot paths are publish-only targets.
- Build output is written to a staging path first, validated, then promoted to
  the active publish path.
- Failed or stale builder VMs are destroyed and recreated from a clean base
  image or qcow2 backing snapshot.

## Default Layout

| Path | Purpose |
| --- | --- |
| `/var/lib/netboot/path-b` | Active served Path B artifacts only. Do not build here. |
| `/var/lib/netboot/staging/path-b` | Staged netboot artifacts awaiting validation and promotion. |
| `/srv/build-cache/distfiles` | Shared Gentoo distfiles cache. |
| `/srv/build-cache/binpkgs` | Shared binary package cache/repository. |
| `/srv/vm-images/stagebuild-base` | Clean builder VM base image and snapshot inputs. |
| `/srv/vm-images/stagebuild-instances` | Disposable builder VM overlays. |

## Builder VM Resource Class

The default X12AGAIN stage builder VM should be sized for high-throughput local
builds without exhausting host interactivity:

| Resource | Default | Notes |
| --- | --- | --- |
| vCPU | host cores minus reserved host headroom | Keep at least 8 cores free for host and active services. |
| RAM | 128 GiB minimum, 512 GiB preferred | Large enough for Portage parallelism and tmpfs-backed workdirs when useful. |
| Disk | 512 GiB minimum, 2 TiB preferred | Separate fast storage for `/var/tmp/portage`, distfiles, binpkgs, and image outputs. |
| Network | management NIC plus artifact network | Avoid bridging build-only traffic onto unrelated L2 domains. |

## Repo Wrapper

Use the repo wrapper to create and launch disposable builder VMs:

```bash
X12_STAGEBUILD_DRY_RUN=1 gentoo-virt-qemu/x12again-stagebuild-vm.sh --print-env
X12_STAGEBUILD_DRY_RUN=1 gentoo-virt-qemu/x12again-stagebuild-vm.sh --full
gentoo-virt-qemu/x12again-stagebuild-vm.sh --build
gentoo-virt-qemu/x12again-stagebuild-vm.sh --launch
```

For K10 reboot-durable AAA artifact rebuilds, pass the profile definition into
the Path B builder inside the disposable VM:

```bash
PATHB_PROFILE_DEFINITION_FILES="profile-definitions/aaa-domain-client.yml profile-definitions/secure-firstboot-enrollment.yml" \
SSH_AUTHORIZED_KEY_FILE=/root/.ssh/authorized_keys \
PATHB_INSTANCE_NAME=gmktek-k10-stage5 \
PATHB_ROOT=/var/lib/netboot/staging/path-b/gmktek-k10-stage5 \
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/scripts/build-path-b-netboot-artifacts.sh
```

Defaults:

- instance name: `x12again-stagebuild-k10`
- QCOW size: `512 GiB`
- vCPU: `64`
- RAM: `262144 MiB`
- host disk attachment: disabled (`QEMU_ATTACH_HOST_DISKS=0`)
- Portage parallelism: `MAKEOPTS="-j56 -l64"` and `EMERGE_DEFAULT_OPTS`
  configured for binpkg reuse/building
- Cache bind mounts: host `/srv/build-cache/distfiles` and
  `/srv/build-cache/binpkgs` are mounted into the builder chroot at the same
  guest paths so distfiles and built packages persist outside disposable QCOWs
- Root SSH access: the builder must pass `SSH_AUTHORIZED_KEY_FILE` or
  `SSH_AUTHORIZED_KEY` into the Path B script, otherwise rootfs bootstrap stops
  before package mutation begins
- Builder tools: the disposable VM baseline includes `sys-fs/squashfs-tools`
  for Path B rootfs image creation and `dev-python/pyyaml` for profile
  definition parsing
- Portage signing: local binpkg signature enforcement is disabled until the
  internal package-signing key/trust workflow is provisioned
- SSH forwarding: `127.0.0.1:2230`
- serial console: `127.0.0.1:4566`

## Artifact Promotion

Builder VMs must publish through a staging directory and promote atomically:

1. Build into VM-local workspace or `/var/lib/netboot/staging/path-b/<build-id>`.
2. Generate checksums for `vmlinuz`, `initramfs.img`, `initramfs-gz.img`, and
   `rootfs.img`.
3. Verify required files exist and the rootfs contains required profile policy.
4. Rsync to the active path using delayed updates, or promote a symlink to a
   validated build directory.
5. Keep the previous active artifact directory as rollback.

Do not run chroot or Portage build steps directly under `/var/lib/netboot/path-b`.

## K10 Path B Rule

K10 validation depends on a rebuilt Path B rootfs that includes the
`aaa-domain-client` package policy and required SSSD/Samba atoms. The active K10
netboot artifacts must not be replaced until the staged build proves:

- `sys-auth/sssd` is present.
- `net-fs/samba` is present.
- Package USE policy includes `sys-auth/sssd samba`.
- Package USE policy includes `net-fs/samba winbind`.
- `initramfs-gz.img` resolves to the active initramfs artifact.
- The previous active artifacts are preserved for rollback.

## Recovery

If a build root is contaminated by stale bind mounts, use the repo-managed
recovery script before deleting or rebuilding the root. Do not run blind
`rm -rf` against a potentially mounted build root.

```bash
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/scripts/recover-pathb-build-root.sh \
  /var/lib/netboot/path-b/build/gmktek-k10-stage5/rootfs
```

The recovery script unmounts known pseudo-filesystems and removes only top-level
entries on the same filesystem.

## Jenkins Target State

Jenkins should eventually own this workflow:

1. Clone or refresh the repo.
2. Create a disposable builder VM from the clean base image.
3. Attach cache and staging volumes.
4. Run the stage/path build inside the VM.
5. Validate artifacts and E2ET preconditions.
6. Promote artifacts to the active netboot publisher.
7. Destroy the VM on failure or snapshot it only after a clean successful build.
