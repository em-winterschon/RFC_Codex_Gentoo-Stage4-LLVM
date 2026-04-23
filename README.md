# RFC_Codex_Gentoo-Stage4-LLVM
An ephemeral repo for Codex use during Gentoo Stage4 builds

Additional host-side QEMU/VFIO helper files live under `gentoo-virt-qemu/`.

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

PR and release validation:
- `.github/workflows/validate.yml` runs the repo validation suite on pull requests and pushes to `main`
- `.github/workflows/notify.yml` sends repository event notifications to ntfy when configured
- the shell validation sequence currently covers shell syntax checks for committed `.sh` files, generator/output parity for the Ansible Python environment helper, and unit tests for `gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
- Python linting and formatting are enforced through `ruff` and `black`
