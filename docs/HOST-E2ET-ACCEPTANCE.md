# Host E2ET Acceptance

## RFC99 Host E2ET Acceptance Pipeline

`End to End Testing` / `E2ET` is the host acceptance contract for RFC99
infrastructure. A host passes E2ET only when it can move from source-of-truth
intent to installed, rebooted, validated, scored, documented, and
release-eligible state through the intended automation path.

Live fixes are useful for root-cause isolation, but they are not sufficient for
release confidence. A host with a one-off live fix may be marked
`transient validated`; it must not be marked `E2ET passed` until the fix is
represented in repo-owned profiles, manifests, inventory, docs, and survives a
reboot or reinstall through the target provisioning workflow.

## Remediation Rule

For validation hosts such as K10, prefer the reboot-durable path:

1. Recover the host live only far enough to prove root cause and collect
   evidence.
2. Backport the fix into the repo-owned profile, role, manifest, package list,
   NetBox/IPAM/DNS metadata, and docs.
3. Rebuild or reinstall through the intended iPXE path.
4. Reboot the host.
5. Run the full post-boot acceptance suite.
6. Generate the conformance report and update roadmap state.

One-off host changes are allowed only as diagnostic or emergency recovery
actions. They require a follow-up repo change before the host can advance toward
RC or GA.

## Acceptance Gates

### Inventory Gate

Validates that source-of-truth data matches the physical or virtual host:

- NetBox device or VM record exists.
- Management IP, service IPs, MAC addresses, switch ports, PDU outlet, console
  path, and boot protocol are modeled.
- DNS A/CNAME records and `/etc/hosts` fallback intent match inventory.
- Ansible inventory and host variables point to the same canonical host.

### Out-of-Band Gate

Validates that the host remains recoverable when the installed OS is broken:

- Server BMC, IPMI, Redfish, or vendor-equivalent management endpoint is
  reachable when the platform supports it.
- Serial-over-LAN is enabled by default and validated after firmware, BIOS, or
  maintenance changes.
- Any workflow that temporarily disables SOL must include the restoration and
  validation step before the change is closed.
- Console redirection covers pre-boot, bootloader, kernel, and post-boot
  stages where the hardware supports it.

### Provisioning Gate

Validates the intended install path:

- UEFI iPXE direct boot or PXE chainload to iPXE works as modeled.
- Optional ZFSBootMenu handoff works when required.
- Installer assets are fetched from the expected HTTP/TFTP paths.
- `bootfs` and `rootfs` pools are created, imported, and mounted as expected.
- Install logs and artifact hashes are captured.

### First Boot Gate

Validates the first installed boot after provisioning:

- Kernel command line, serial console, hostname, and FQDN are correct.
- SSH management path works.
- Time sync, rsyslog forwarding, and baseline OpenRC services are active.
- Package profile, Portage settings, and binpkg source match the selected
  Stage4/Stage5 profile.

### Platform Gate

Validates hardware and kernel-visible platform state:

- CPU model, core count, RAM capacity, NUMA topology, and firmware facts are
  captured.
- Disk, NVMe, NVDIMM, Optane, GPU, QAT, NIC, and BMC devices match expected
  inventory when applicable.
- Required kernel modules, firmware, sysfs paths, and CVE mitigations are
  present.
- Unexpected device disappearance or driver binding drift is a hard failure for
  RC/GA validation.

### Network Gate

Validates host connectivity and IPAM conformance:

- Management interface, service interfaces, VLANs, routes, default gateway, and
  DNS are correct.
- Forward and reverse hostname resolution match NetBox/IPAM intent.
- `nmap` or equivalent service-readiness checks pass for required ports.
- Link speed, duplex, LACP, MTU, and RDMA/RoCE expectations are checked where
  applicable.

### Storage Gate

Validates local and remote storage:

- ZFS pools, datasets, snapshots, and boot datasets are healthy.
- NFSv3, NFSv4, NFS over TCP, NFS-RDMA, Ceph, iSER, non-RDMA iSCSI, and sshfs
  mounts are validated when assigned to the profile.
- UID/GID behavior for NFSv4 is checked against centralized identity policy.
- Required data mounts survive reboot.

### Identity Gate

Validates RBAC and AAA:

- FreeIPA, SSSD, PAM, NSS, sudo, SSH authorized-key lookup, and offline cache
  behavior match the host profile.
- UID/GID mappings are stable and match repo-managed identity policy.
- Local break-glass access remains available.
- Network-device or power-device RADIUS/TACACS+ paths are validated separately
  before widening rollout.

### Service Gate

Validates host role behavior:

- Required OpenRC services are enabled and running.
- No unexpected services are failed.
- Role-specific smoke tests and functional tests pass.
- Logs and metrics are emitted to the expected collector endpoints.

### Performance Gate

Validates that the host meets its baseline operating envelope:

- CPU, memory, disk, network, and package-build metrics are captured.
- Distcc, binpkg, GPU, RDMA, or storage benchmarks are included only when the
  host role requires them.
- Results are compared against the most recent accepted baseline for the same
  hardware/profile class.

### Conformance Report

Every E2ET run emits machine-readable and human-readable evidence:

- JSON report for automation.
- Markdown report for docs/wiki.
- Optional JUnit output for Jenkins/GitHub checks.
- Summary score, hard-fail list, warning list, baseline comparison, and
  recommended release state.

## Scoring

E2ET uses hard gates plus weighted scoring. Hard failures override score.

Initial conformance tiers:

- `p60`: host is minimally usable, not a release candidate.
- `p80`: host is acceptable for lab use.
- `p90`: host is an RC candidate.
- `p95`: host is GA-ready for normal infrastructure.
- `p99`: host is suitable as a production-critical or rebuild-template
  reference.

These are conformance tiers, not statistical confidence intervals, until the
repo has enough historical runs to compute real percentile distributions.

## K10 Policy State

K10 is the first bare-metal Stage5 workstation validation host. Its current
state is `transient validated` for AAA: live FreeIPA/SSSD enrollment worked
before reboot, but AP7901 outlet 6 reboot proved the current netboot rootfs does
not persist SSSD or the IPA backend module.

K10 cannot be marked `E2ET passed`, RC-capable, or GA-capable until the rebuilt
rootfs or disk-installed Stage5 profile includes `aaa-domain-client`, survives
reboot, and passes the Identity Gate plus the remaining host acceptance gates.

## Report Tooling

The first repo-native report renderer is:

- `scripts/host_e2et_conformance.py`
- sample manifest:
  `gentoo-liveiso-ansible/host-e2et-definitions/k10-stage5-aaa-reboot.yml`
- Ansible wrapper:
  `gentoo-liveiso-ansible/playbooks/host-e2et-conformance-report.yml`

Render JSON, Markdown, and JUnit artifacts directly:

```bash
scripts/host_e2et_conformance.py \
  --manifest gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/host-e2et-definitions/k10-stage5-aaa-reboot.yml \
  --json-output /tmp/k10-e2et.json \
  --markdown-output /tmp/k10-e2et.md \
  --junit-output /tmp/k10-e2et.xml
```

Or render through Ansible:

```bash
ansible-playbook \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/host-e2et-conformance-report.yml \
  -e host_e2et_report_dir=/tmp/host-e2et
```

The CLI exits `0` only when the manifest meets its target tier and has no hard
failures. It exits `1` for a valid but blocked or under-threshold host, and
`2` for invalid input.
