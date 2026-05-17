# EOD Status 2026-05-15

## Completed

- Validated `admin-sun99-forge-099070` to NASA over the M70 OpenVPN path:
  SSH alias `nasa` works from M70, `10.200.99.18` routes through `tun-fmt2`,
  TCP `111` and `2049` are reachable, `showmount` and `rpcinfo` return the
  expected NFS services, and the canonical export mounts with NFSv3/TCP.
- Fixed the NASA NFS write target by keeping the export root locked down and
  creating dedicated squashed-write directories owned by UID/GID `8888`:
  `hasslehoff/config-bundles` and `forge/transfer-stage`. M70 write/read/delete
  probes passed in both directories.
- Updated Hasslehoff backup docs and wiki to make M70 the NFS relay. X12AGAIN
  must not mount NASA NFS; bulky backup artifacts should transit through M70.
- Added M70 automation-admin baseline package atoms for GNU Emacs 30+, `tree`,
  `bash-completion`, `xfsprogs`, `xfsdump`, `eza`, Git, `git-lfs`, and `tig`.
  The profile also owns `/etc/eixrc/00-eixrc` with
  `OVERLAY_CACHE_METHOD="assign"`.
- Extended `scripts/sync-binpkgs-to-repo.sh` with `--local-root` so a mounted
  NFS repository root can receive binpkgs without `sshfs`. This is the safe
  primitive for M70-local NASA NFS publishing and later Jenkins/SLURM hooks.
- Preserved the X1 Gen8 netboot work in the branch: host inventory, DHCP/DNS,
  manifest, and a by-MAC iPXE dispatch artifact for
  `lab-sun99-x1gen8-099082`.
- Adjusted local tmux configuration for Codex multiline input by enabling
  extended keys and CSI-u format. Codex CLI did not expose a supported
  `config.toml` keybinding schema for Shift+Enter.

## Current Gates

- Repo verification passed after the `portage_config_files` schema was wired
  through the profile linter, preflight merge layer, and Portage role renderer:
  `bash tests/shell/run-tests.sh`, `git diff --check`, and focused M70/NFS/binpkg
  tests all exited cleanly.
- NASA NFS transport is viable from M70, but no permanent `/mnt/nasa` mount,
  timer, autofs policy, or backup retention job has been committed yet.
- NASA export root remains intentionally not writable through NFS because of
  `all_squash`; only the UID/GID `8888` subdirectories should be used.
- Secret material for M70-to-NASA SSH, host connection profiles, and base
  passwords still needs Ansible Vault import. Raw private keys must not enter
  git.
- Codex Shift+Enter behavior needs an interactive retest from a new or reloaded
  tmux pane. If tmux extended keys are insufficient, the next layer is a
  Ghostty keybind that emits CSI-u Shift+Enter.
- X12AGAIN remains protected. No reimage, shutdown, disk mutation, or service
  stop is approved until Forge continuity and off-host backup gates pass.

## Recommendations

- Use FreeIPA Web UI as the primary RBAC/AAA web console and `ipa` CLI plus
  `ldapvi` as the operator-side terminal workflow. Keep FreeIPA as source of
  truth for users, groups, SSH public keys, HBAC, sudo rules, hostgroups, and
  service principals. Add Keycloak only as an HTTP/OIDC/SAML federation layer,
  not as the authoritative POSIX identity store.
- Stop copying SSH keys manually once the sync path is stable. Store public key
  intent in the repo-safe identity source, resolve secrets from Ansible Vault,
  write keys to FreeIPA user records, and let SSSD serve
  `sss_ssh_authorizedkeys`.
- Treat inference as three explicit roles: `inference-accelerator` for
  GPU/NPU-aware host or VM tuning, `inference-engine` for Ollama now and
  vLLM/SGLang later, and `inference-webui-api` for Open WebUI and OpenAPI
  compatible front-door access through HAProxy VIPs.

## Backout Summary

- NASA-side directories created today are additive. If they cause policy
  concerns, remove only `hasslehoff/config-bundles` and `forge/transfer-stage`;
  do not loosen the export root.
- The binpkg sync helper remains backward compatible for SSH remote publishing.
  `--local-root` is opt-in and does not affect existing build scripts.
- The local tmux change can be reverted by restoring `default-terminal` to the
  previous value and disabling `extended-keys`; it does not affect repo state.
