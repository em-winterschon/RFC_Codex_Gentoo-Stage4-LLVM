# RFC_Codex_Gentoo-Stage4-LLVM
An ephemeral repo for Codex use during Gentoo Stage4 builds

Additional host-side QEMU/VFIO helper files live under `gentoo-virt-qemu/`.

## Documentation

- [docs/WORKFLOWS.md](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/WORKFLOWS.md)
  human-readable index for the machine-readable workflow manifests
- [docs/wiki](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/wiki)
  versioned source for the GitHub wiki; publish separately after PR approval
- [docs/workflows/codex-approval-watcher-service.json](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/codex-approval-watcher-service.json)
  persistent ntfy approval-watcher install and validation flow
- [docs/workflows/stage4-netboot-path-b.json](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/stage4-netboot-path-b.json)
  Path B iPXE asset publication and operator handoff flow
- [docs/workflows/stage4-routeros-pathb-deployment.json](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/stage4-routeros-pathb-deployment.json)
  RouterOS CHR Path B render/apply workflow for the isolated iPXE lab
- [docs/workflows/stage4-vm-install-and-boot.json](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/stage4-vm-install-and-boot.json)
  Path A LiveISO/QEMU Stage4 build, install, and target-disk boot validation flow
- [docs/workflows/stage4-destination-install-sequences.json](/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/stage4-destination-install-sequences.json)
  Path A staged destination-host Ansible execution flow with a remote-viewable control-flow pipeline

Wiki publication policy:

- edit wiki pages under `docs/wiki/`
- treat the GitHub wiki as a deployment target, not the source of truth
- use `bash scripts/publish-wiki.sh` to refresh the local wiki checkout
- use `bash scripts/publish-wiki.sh --push` only after the relevant PR is approved

## Notifications

This repository now includes ntfy support in three places:

- Ansible controller notifications via:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/callback_plugins/ntfy.py`
- ad hoc Ansible task notifications via:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/action_plugins/ntfy.py`
- GitHub repository event notifications via:
  `.github/workflows/notify.yml`

Local Codex-side notifications can be sent with:

```bash
bash scripts/codex-ntfy.sh info "Codex started work"
bash scripts/codex-ntfy.sh action-required "Need operator input"
```

Codex integration files:

- `scripts/codex_notify_event.py`
  handles Codex `notify` events such as `agent-turn-complete`
- `scripts/codex_ntfy_hook.py`
  handles hook-driven remote approvals and reply prompts over ntfy
- `scripts/codex_notify_with_env.sh`
  sources `CODEX_NTFY_ENV_FILE`, then `~/.codex/ntfy-pub-subs.export.sh`, then `/opt/codex/ntfy-pub-subs.export.sh` before invoking the notify handler
- `scripts/codex_hook_with_env.sh`
  sources `CODEX_NTFY_ENV_FILE`, then `~/.codex/ntfy-pub-subs.export.sh`, then `/opt/codex/ntfy-pub-subs.export.sh` before invoking the hook handler
- `scripts/codex_ntfy_reply_listener.py`
  subscribes to the reply topic and persists normalized replies into a local pending/processed queue
- `scripts/codex_ntfy_reply_listener_with_env.sh`
  sources the ntfy export file before launching the reply listener
- `config/codex-ntfy-policy.json`
  default reply-handling policy that marks each normalized reply kind as `state-driven` or `advisory`
- `.codex/hooks.json`
  repo-local example hook wiring for `PermissionRequest` and `Stop`

To enable the remote-approval flow in a Codex environment:

1. enable Codex hooks in `~/.codex/config.toml`
2. set `notify = ["bash", "/path/to/scripts/codex_notify_with_env.sh"]`
3. configure `CODEX_NTFY_ALERT_TOPIC` and `CODEX_NTFY_REPLY_TOPIC`
4. optionally point `CODEX_NTFY_ENV_FILE` at an export file, or place one at `~/.codex/ntfy-pub-subs.export.sh`

The hook handler accepts replies in these forms:

- `allow <id>`
- `deny <id>`
- `<id>: <free-form answer>`

Preferred reply-processing path:

- run the persistent reply listener service
- let it normalize ntfy reply messages into a local queue under `CODEX_NTFY_REPLY_QUEUE_DIR`
- control whether each reply kind is `state-driven` or `advisory` through `CODEX_NTFY_POLICY_FILE`
- let `scripts/codex_ntfy_hook.py` consume matching replies from that queue first
- fall back to direct ntfy polling only when the queue path is absent or empty

Reply policy defaults:

- `permission_reply`: `state-driven`
- `question_reply`: `state-driven`
- `status_request`: `advisory`
- `unrecognized_reply`: `advisory`

Recommended policy handling:

- keep `permission_reply` and `question_reply` as `state-driven` only if you trust the reply channel
- keep `status_request` and unrecognized content as `advisory`
- override with `CODEX_NTFY_POLICY_FILE=/path/to/ntfy-policy.json` if the host should use a site-local policy instead of the repo default

Archive-derived local operator tools now included:

- `scripts/ntfy_pubsub_tui.py`
  terminal pub/sub client for subscribing to topics and publishing messages
- `scripts/slack_webhook.py`
  optional Slack incoming-webhook bridge for the same operator workflow

Shared environment keys are documented in:

- `ntfy.env.example`

The repository event workflow is designed to send notifications for:

- pushes and commits
- branch and tag create/delete events
- pull request open/edit/sync/merge/draft-state changes
- releases
- completion of the `Validate` workflow

Messages are formatted as RFC 5424-style syslog lines and mapped onto ntfy priorities.

### Local operator tools

Inspect the resolved ntfy pub/sub configuration:

```bash
python3 scripts/ntfy_pubsub_tui.py --print-config
```

Launch the terminal pub/sub client:

```bash
python3 scripts/ntfy_pubsub_tui.py
```

Use the repo-provided wrappers with a live export file:

```bash
export CODEX_NTFY_ENV_FILE=/root/.codex/ntfy-pub-subs.export.sh
bash scripts/codex_notify_with_env.sh --dry-run '{"type":"agent-turn-complete","thread-id":"demo","turn-id":"1","cwd":"/root","input-messages":["ping"],"last-assistant-message":"done"}'
```

Send a Slack webhook message with the optional helper:

```bash
export SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...'
python3 scripts/slack_webhook.py "Codex finished a run" --title "RFC_Codex_Gentoo-Stage4-LLVM"
```

## Validation

Local validation:
- `python -m pip install -r requirements-dev.txt`
- `pre-commit install`
- `pre-commit run --all-files`
- `bash tests/shell/run-tests.sh`
- `bash tests/shell/test_workflow_manifests.sh`

PR and release validation:
- `.github/workflows/validate.yml` runs the repo validation suite on pull requests and pushes to `main`
- `.github/workflows/notify.yml` sends repository event notifications to ntfy when configured
- the shell validation sequence currently covers shell syntax checks for committed `.sh` files, generator/output parity for the Ansible Python environment helper, and unit tests for `gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
- Python linting and formatting are enforced through `ruff` and `black`

## Container Publishing

Container rootfs and image build workflow:

- `docs/CONTAINER-BUILDING.md`

The first supported image publication target is `GHCR`.

Use:

```bash
bash scripts/publish-container-ghcr.sh \
  --local-image localhost/gentoo-stage4-base:latest \
  --image-name gentoo-stage4-base \
  --tag git-$(git rev-parse --short HEAD) \
  --namespace em-winterschon \
  --source-url https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM \
  --description "Gentoo Stage4 LLVM/Clang hardened base container"
```

Authentication:

- `GHCR_TOKEN` in the environment, or
- `--token-file /path/to/token`

Use immutable tags such as `git-<sha>` for validated builds and reserve `latest`
for explicitly promoted images only.

## Stage4 control flow

The Ansible Stage4 subtree now supports staged installer execution plus a structured JSONL
control-flow pipeline that can be tailed remotely during imaging work.

Primary operator entry points:

- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/scripts/run-install-sequence.sh`
- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/scripts/watch-control-flow.py`

The control-flow callback logs playbook, play, task, checkpoint, and final stats events into a
JSONL stream under `/tmp/ansible-control-flow` by default, or an explicit path supplied through
`ANSIBLE_CONTROL_FLOW_PATH`.

## Codex ntfy

- `scripts/codex_notify_with_env.sh` forwards Codex turn-complete notifications to ntfy using `~/.codex/ntfy-pub-subs.export.sh` or `/opt/codex/ntfy-pub-subs.export.sh`
- `scripts/codex_hook_with_env.sh` handles Codex hook-based remote approvals and reply prompts when the runtime emits supported hook events
- `scripts/codex_approval_watcher_with_env.sh` tails `~/.codex/log/codex-tui.log` and sends ntfy alerts for `exec_approval` and `patch_approval` dialogs raised by the sandbox approval layer
- the approval watcher notifies you to approve the action in the Codex UI; remote ntfy replies do not directly satisfy sandbox approval dialogs in this runtime
- `scripts/install_codex_approval_watcher_service.sh` installs the watcher as a persistent OpenRC service
- `scripts/install_codex_ntfy_reply_listener_service.sh` installs the reply listener as a persistent OpenRC service

Persistent setup on Gentoo/OpenRC:
```bash
bash scripts/install_codex_approval_watcher_service.sh
bash scripts/install_codex_ntfy_reply_listener_service.sh
rc-service codex-approval-watcher status
rc-service codex-ntfy-reply-listener status
```

Future-host workflow:
```bash
. /opt/codex/ntfy-pub-subs.export.sh
bash scripts/install_codex_approval_watcher_service.sh
bash scripts/install_codex_ntfy_reply_listener_service.sh
```
