# Kernel Config Layering Implementation Plan

## Files

- `tests/shell/test_kernel_config_registry.sh`: regression coverage for registry
  presence and required content.
- `tests/shell/run-tests.sh`: include the new shell test.
- `gentoo-liveiso-ansible/kernel-config/`: kernel map and fragments.
- `gentoo-liveiso-ansible/vars/cpu_profiles.yml`: add CPU tuning policy and
  candidate architecture registry without changing selected live profiles.
- `docs/KERNEL-CONFIG-ARCHITECTURE.md`: gap analysis and implementation design.
- `docs/wiki/Kernel-Config-Architecture.md`: wiki-ready summary.

## Steps

1. Add a failing shell test for the kernel registry.
2. Add the kernel map and required fragments.
3. Add CPU tuning policy metadata and candidate architecture mappings.
4. Add docs and wiki summary.
5. Run the new test, then the shell test suite if runtime permits.
6. Commit the declarative registry once tests pass.
