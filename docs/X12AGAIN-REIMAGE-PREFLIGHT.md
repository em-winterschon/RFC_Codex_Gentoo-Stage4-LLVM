# X12AGAIN Reimage Preflight

## No-Mutation Default

Destructive disk mutation is blocked by default. The profile and playbook both
require `x12again_reimage_apply_required=true` plus all live safety gates before
any future install workflow may wipe or repartition X12AGAIN.

The current preflight branch only renders evidence and validates guardrails. It
does not power-cycle, repartition, install, or enroll X12AGAIN.

## Required Live Gates

- `x12again_reimage_backup_verified=true`: off-host backup path and checksum
  manifest are recorded in the change ticket.
- `x12again_reimage_services_offloaded_verified=true`: netboot, identity,
  scheduler, rsyslog, Elasticsearch/Kibana, ntfy, NetBox, and observability stay
  reachable while X12AGAIN is offline.
- `x12again_reimage_emergency_console_verified=true`: serial/OOB or equivalent
  break-glass access has been validated.
- `x12again_reimage_human_change_window_approved=true`: current operator has
  approved the destructive window.

Only after those are true may a separate install playbook honor
`x12again_reimage_apply_required=true`.

## Backout Boundary

The preflight boundary is the last safe checkpoint before disk mutation. If any
gate fails, leave X12AGAIN running or powered off without changing disks. If a
future install fails after mutation, recover from the verified off-host backup
or repeat the same profile install with mutation disabled until root cause is
known.

## Validation

```bash
ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/x12again-reimage-preflight.yml
```

The rendered report is expected to remain `blocked` until the required live
gates are explicitly set true.
