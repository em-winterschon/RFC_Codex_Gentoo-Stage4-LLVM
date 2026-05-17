# X12AGAIN Reimage Preflight

## No-Mutation Default

Destructive disk mutation is blocked by default. The profile and playbook both
require `x12again_reimage_apply_required=true` plus all live safety gates before
any future install workflow may wipe or repartition X12AGAIN.

## Required Live Gates

- `x12again_reimage_backup_verified=true`
- `x12again_reimage_services_offloaded_verified=true`
- `x12again_reimage_emergency_console_verified=true`
- `x12again_reimage_human_change_window_approved=true`

The preflight playbook renders a host E2ET conformance report and should remain
blocked until those gates are true.
