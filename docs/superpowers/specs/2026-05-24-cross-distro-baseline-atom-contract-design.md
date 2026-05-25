# Cross-Distro Baseline Atom Contract Design

## Purpose

Define a repo-native baseline package and service contract that applies across
Gentoo, RHEL-family systems, Debian-family systems, BSD, Solaris-family systems,
and multiple CPU architectures. The system must let us say "these are our
minimal packages" once, resolve that intent into each platform's native package
names and service controls, and roll changes across the fleet using NetBox as
the authoritative host targeting layer.

## Design Principles

- The repository owns desired baseline policy.
- NetBox owns host identity, lifecycle state, role, site, architecture, OS
  family, and targeting metadata.
- Live hosts provide observed state for drift detection and audit, not desired
  truth.
- Ansible remains the first actuator because it is already integrated, easy to
  review, and works across the target platforms.
- The design must not require SELinux.
- The design must not require systemd; service management must be abstracted per
  OS and init system.
- Plan mode is mandatory and is the default. Apply mode must be explicit.
- Package removals, downgrades, and version changes outside policy must require
  explicit operator approval flags.

## Existing Foundations

The current package baseline system is Gentoo-centric and should be reused, not
discarded.

- Current role taxonomy: `docs/ROLE-PACKAGE-TAXONOMY.md`
- Current Gentoo package list source: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-package-lists/`
- Current Gentoo profile source: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/`
- Current service atom registry: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-service-atoms/stage5-role-service-atoms.yml`
- Current app pin policy: `docs/PACKAGE-VERSION-PINNING.md`
- Current NetBox repo-safe intake flow: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/`

The new contract should make the Gentoo data one platform mapping under a
broader canonical atom system.

## Monorepo Infrastructure Layout

The monorepo should model infrastructure with the same separation of concerns
used by FD.io CSIT: inventory, physical specifications, logical topologies,
environment versioning, runtime settings, reports, and presentation are related
but distinct layers. FD.io's CSIT docs split these concerns across inventory,
testbed specifications, testbed configuration, testbed versioning, logical
topologies, and startup settings. Our repo should follow that pattern while
keeping NetBox authoritative for live entities.

Recommended repo layout:

```text
infra/
  netbox/
    openapi/
    custom-fields/
    validators/
    generated/
  topology/
    physical/
    logical/
    testbeds/
  baseline-atoms/
  host-contracts/
  service-contracts/
  rollout-plans/
  audit-reports/
```

Repository-owned inputs:

- OpenAPI scope definitions for NetBox API clients.
- NetBox custom field and tag schema definitions.
- Validators for required NetBox fields and relationship consistency.
- Baseline atom definitions and platform package mappings.
- Host, service, topology, and rollout contract schemas.
- Plan/apply/audit scripts and Ansible playbooks.
- Generated snapshots from NetBox for review, testing, and offline planning.

NetBox-owned inputs:

- Sites, racks, rack units, devices, VMs, clusters, roles, platforms, and
  lifecycle status.
- Interfaces, MAC addresses, cables, LAGs, VLANs, prefixes, IP addresses, and
  DNS names.
- Power feeds, PDUs, outlets, UPS/ATS relationships, and console/BMC endpoints
  when modeled.
- Device serial numbers, asset tags, model facts, management IPs, and BMC IPs.
- Baseline targeting fields such as policy, cohort, wave, OS family, OS
  version, package backend, init backend, and architecture.

Generated repo artifacts must be treated as build outputs. They are useful for
diff review and reproducible automation, but manual edits to generated NetBox
snapshots are not authoritative. If generated data is wrong, the fix belongs in
NetBox or in the exporter/validator logic.

## Topology Grammar

FD.io CSIT uses stable testbed naming and port naming to encode testbed number,
role, PCIe slot, and port index. We should adopt the grammar concept, but
generate identifiers from NetBox object IDs and normalized host/interface data
instead of relying on hand-maintained text tables.

Recommended entity types:

- `site`: physical or administrative site, such as `sun99`, `rfc99`, `fmt2`.
- `rack`: physical rack identifier.
- `cluster`: logical compute/storage/testbed grouping.
- `host`: physical server, appliance, SBC, or managed VM.
- `role`: host function, such as `sut`, `tg`, `hypervisor`, `storage`,
  `inference`, `builder`, `bastion`, `dns`, `ntp`, `router`, or `switch`.
- `fabric`: network control/data-plane domain.
- `link`: point-to-point, breakout lane, LAG, VLAN trunk, or routed adjacency.
- `endpoint`: host interface, switch port, BMC, serial console, PDU outlet, or
  service VIP.

Recommended generated slug format:

```text
<site>.<cluster>.<role>.<host>.<endpoint>
```

Examples:

- `sun99.m70.forge.m70-forge.bond0`
- `sun99.m70.slurm.m70-canary.eno1`
- `sun99.thor.inference.agx-rfc99-bunnydev.qsfp28-0-lane1`
- `fmt2.nasa.storage.nasa.nfs-kernel-repo`

The slug is for automation readability. NetBox IDs remain the durable object
identity.

## Environment Version Contract

CSIT tracks test environment changes so benchmark anomalies can be separated
from application changes. We need the same idea for fleet operations: host drift
and performance changes must be explainable against a versioned environment
contract.

Each managed host should resolve to an environment version record containing:

- Hardware model, CPU model, CPU topology, RAM topology, accelerator inventory,
  NIC inventory, firmware versions, BIOS/BMC versions, and storage controller
  versions.
- OS family, OS version, kernel version, init backend, package backend, boot
  mode, and root filesystem layout.
- Baseline atom policy and resolved native package/service plan.
- Network fabric membership, interface role, VLAN/LAG/breakout lane mapping,
  routing domain, DNS identity, and management path.
- Storage class, local disks, persistent mounts, NFS/iSCSI/iSER/Ceph/ZFS
  relationships, and backup policy.
- Runtime service contracts for major stacks such as inference, DNS, NTP,
  FreeIPA, RADIUS, NetBox, observability, package repositories, and build
  workers.
- Operator-approved deviations, holds, exemptions, and maintenance windows.

Environment version records should be generated from NetBox plus live audit
facts. They should be stored as reports, not manually curated desired state.

## Canonical Atom Model

Canonical atoms are stable internal capability names. They are not package
manager package names.

Example atom IDs:

- `ssh.server`
- `time.chrony`
- `logging.rsyslog`
- `shell.tmux`
- `shell.zsh`
- `debug.tcpdump`
- `debug.strace`
- `storage.zfs`
- `network.openvpn`
- `network.wireguard`

Each atom definition must include:

- `id`: stable canonical name.
- `summary`: short human description.
- `lifecycle`: `active`, `deprecated`, or `disabled`.
- `required`: whether the atom is mandatory inside a policy.
- `classes`: package, service, config, kernel-module, runtime, or validation.
- `provides`: capabilities this atom satisfies.
- `conflicts`: mutually exclusive atoms or package families.
- `default_services`: expected services, if any.
- `validation`: commands or facts used to prove the atom is present.
- `pin_policy`: unpinned, minimum version, exact version, held version, or
  external lock file.
- `security_notes`: operational security constraints when needed.

## Platform Mapping Model

Platform mappings translate canonical atoms into native package/service facts.

The resolver must key mappings by:

- OS family: `gentoo`, `rhel`, `debian`, `freebsd`, `openbsd`, `netbsd`,
  `solaris`.
- OS version or major version where package names differ.
- Architecture where availability differs.
- Package manager: `emerge`, `dnf`, `yum`, `apt`, `pkg`, `pkg_add`, IPS `pkg`,
  or another explicit backend.
- Init/service manager: `openrc`, `systemd`, BSD rc, SMF, or none.

Each mapping entry must specify:

- Native package names.
- Native service names.
- Whether services should be enabled, started, both, or only validated.
- Supported architectures.
- Unsupported reason when the atom is intentionally unavailable.
- Version or repository pin behavior when applicable.

Unsupported mandatory atoms are hard failures in plan mode.

## Baseline Policies

Policies compose canonical atoms into usable host baselines.

Initial policies:

- `baseline.minimal`: common atoms expected on every managed host.
- `baseline.server`: minimal baseline plus server diagnostics and remote access.
- `baseline.vm`: VM guest agents and virtualization-safe diagnostics.
- `baseline.metal`: bare-metal diagnostics, firmware tools, and hardware facts.
- `baseline.builder`: compiler/build/distributed build tooling.
- `baseline.inference`: GPU/inference host primitives without binding to a
  specific inference service.

Policies may include atom groups but must resolve into an explicit atom list in
the generated plan. This prevents hidden inheritance surprises.

## NetBox Authority Model

NetBox is authoritative for host targeting. Repo inventory is allowed as a
bootstrap, export, dry-run, or break-glass input, but it is not the long-term
authority for fleet membership.

NetBox data may be slaved into the monorepo through exporter scripts, scoped API
clients, and generated Ansible inventory. Those generated artifacts are
downstream consumers of NetBox. Repo validators may reject inconsistent NetBox
exports, but they do not make repo inventory authoritative over NetBox.

Required NetBox data for managed hosts:

- Device or VM name.
- Primary management IP.
- Site.
- Role.
- Lifecycle/status.
- Architecture.
- OS family.
- OS version or major version.
- Baseline policy.
- Management access method and Ansible user.

Recommended NetBox custom fields:

- `baseline_policy`
- `baseline_enabled`
- `baseline_cohort`
- `baseline_wave`
- `os_family`
- `os_version`
- `architecture`
- `package_backend`
- `init_backend`
- `maintenance_window`
- `baseline_exemptions`

Recommended NetBox tags:

- `baseline-managed`
- `baseline-exempt`
- `baseline-canary`
- `baseline-hold`
- `baseline-breakglass`

The resolver must refuse to target a host when required NetBox fields are
missing, contradictory, or unsupported.

## Validation Workflow

Validation has four layers.

1. Repo schema validation:
   - Atom IDs are unique.
   - Policies reference existing active atoms.
   - Platform mappings cover every mandatory atom for supported platforms.
   - Deprecated atoms cannot appear in active policies unless explicitly
     allowed.

2. NetBox data validation:
   - Managed hosts have all required custom fields.
   - OS family, OS version, architecture, package backend, and init backend are
     internally consistent.
   - Interface, cable, power, BMC, DNS, and management-path facts are complete
     for hosts in automation cohorts.
   - Generated repo snapshots match the current NetBox API export.
   - Hosts marked `baseline-exempt` are excluded and reported.
   - Hosts in `baseline-hold` are planned but not applied.

3. Plan validation:
   - Every host resolves to a complete native package/service plan.
   - Unknown packages, unsupported mandatory atoms, and unsafe removals fail the
     plan.
   - Generated plans are deterministic and diffable.

4. Live audit validation:
   - Gather installed package facts and service state.
   - Compare observed state against resolved desired state.
   - Report drift without mutating unless apply mode is explicitly requested.

## Rollout Workflow

The rollout process is:

1. Export target hosts from NetBox.
2. Validate NetBox data quality.
3. Resolve canonical baseline policy into platform-specific plans.
4. Write JSON and Markdown reports.
5. Notify Forge/control-plane/ntfy with plan summary.
6. Apply canary cohort only when requested.
7. Re-audit canaries.
8. Apply later waves only after canary success.
9. Write final result reports.
10. Optionally write NetBox journal entries with plan and apply result links.

Apply mode must support:

- `plan`: validate and report only.
- `check`: ask the platform package manager what would change when supported.
- `apply`: install/enable/start only safe changes.
- `audit`: compare live state to desired state.

Package removals and downgrades are not part of normal apply mode. They require
separate explicit flags so baseline tightening cannot accidentally remove
working host functionality.

## Ansible Actuator Model

The first implementation should use Ansible playbooks and scripts already
consistent with this repository.

Expected new components:

- `baseline-atoms/atoms.yml`
- `baseline-atoms/platform-map.yml`
- `baseline-atoms/policies/minimal.yml`
- `scripts/plan-baseline-atoms.py`
- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/baseline-atoms-plan.yml`
- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/baseline-atoms-apply.yml`
- `tests/shell/test_baseline_atoms_contract.sh`

The playbooks should call the planner first and apply only from the generated
plan artifact. This avoids each playbook inventing different variable syntax,
check behavior, package selection, or targeting logic.

## Reporting

Every plan or apply run must produce:

- Machine-readable JSON plan.
- Human-readable Markdown report.
- NetBox export hash and repo contract hash used by the run.
- Host count by OS family, architecture, site, policy, cohort, and wave.
- Skipped/exempt/held host list.
- Failed validation list.
- Planned package and service changes.
- Unsafe changes requiring explicit approval.
- Environment version deltas relevant to the run.

Reports should be suitable for committing into repo closeout docs when the run
is important enough to preserve.

## Audit Schedule

Recommended cadence:

- On every PR touching atom, policy, platform map, NetBox intake, or inventory
  export code: run schema and fixture validation.
- Daily: validate NetBox managed host metadata and emit drift/quality report.
- Weekly: full live package/service audit across managed hosts, grouped by site
  and cohort.
- Before major fleet work: canary plan/apply/audit cycle.

## Safety Boundaries

- No mutation without an explicit apply flag.
- No removals without an explicit removal flag.
- No downgrades without an explicit downgrade flag.
- No host targeting from incomplete NetBox data.
- No package-manager commands constructed from unvalidated host input.
- No implicit SELinux requirements.
- No implicit systemd requirements.
- No permanent reliance on repo inventory when NetBox has authoritative data.

## Future Extensions

After v1 works through Ansible, the same contract can drive faster actuators:

- Salt minions for high-frequency state enforcement.
- SLURM-backed worker blasts for large parallel plans and audits.
- Forge control-plane task distribution and ntfy progress notifications.
- NetBox journal updates and custom-field drift summaries.
- Package repository promotion gates for Gentoo binpkgs, RPM repos, and APT
  repos.

The contract must remain independent of any one actuator.
