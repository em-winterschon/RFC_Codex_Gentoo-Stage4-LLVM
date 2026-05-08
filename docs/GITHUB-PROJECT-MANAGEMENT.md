# GitHub Project Management

This repository uses GitHub Issues, Milestones, and Projects v2 as the NOW()
project-management layer while Trac and custom MCP integration remain under
evaluation.

GitHub Actions are intentionally out of scope for this workflow. All seeding is
local and operator-triggered through `scripts/github_project_seed.py`.

## Source Files

- `.github/ISSUE_TEMPLATE/roadmap_task.yml`
- `.github/ISSUE_TEMPLATE/change_control.yml`
- `.github/ISSUE_TEMPLATE/service_role.yml`
- `.github/ISSUE_TEMPLATE/blocker.yml`
- `project-management/labels.yml`
- `project-management/milestones.yml`
- `project-management/issue-seed.yml`
- `docs/ROADMAP-AND-TODO.md`

The seed script derives issues from `docs/ROADMAP-AND-TODO.md` by default and
skips completed roadmap rows. Explicit bootstrap issues live in
`project-management/issue-seed.yml`.

## GitHub Query URLs

GitHub issue creation URLs can preselect templates, labels, milestone, title,
and body through query parameters.

Roadmap task example:

```text
https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM/issues/new?template=roadmap_task.yml&labels=type%3Aroadmap-task%2Cstatus%3Aready&milestone=Workstation%20Stage5
```

Change-control example:

```text
https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM/issues/new?template=change_control.yml&labels=type%3Achange-control%2Cstatus%3Aready&milestone=NetBox%2FIPAM%2FDCIM
```

Blocker example:

```text
https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM/issues/new?template=blocker.yml&labels=type%3Ablocker%2Cstatus%3Ablocked%2Cpriority%3Acritical
```

The template chooser also exposes these links through
`.github/ISSUE_TEMPLATE/config.yml`.

## Dry Run

Use dry-run mode before any GitHub mutation:

```bash
python3 scripts/github_project_seed.py \
  --repo em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM \
  --emit-query-urls
```

Dry-run output lists labels, milestones, derived issues, explicit seed issues,
and optional issue query URLs.

## Apply

Apply requires `GH_TOKEN` or `GITHUB_TOKEN` in the environment:

```bash
GH_TOKEN="$(cat /root/.ssh/codex.d/tokens/FORGE_TOKEN)" \
  python3 scripts/github_project_seed.py \
  --repo em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM \
  --apply
```

The apply path is idempotent:

- existing labels are updated
- existing milestones are updated
- issues with matching titles are skipped
- missing issues are created

Current live seed status:

- labels and milestones are applied
- open roadmap/catalog issues are applied
- Projects v2 board `RFC Codex Infrastructure Roadmap` is created at
  `https://github.com/users/em-winterschon/projects/1`
- the board contains the seeded roadmap/catalog issues and the custom
  `Roadmap Status` plus `Roadmap ID` fields

## Project Board

Creating a GitHub Projects v2 board requires a token with the `project` scope.
Depending on token type, GitHub CLI may report the missing permission as
`read:project`. Use this only after labels, milestones, and issues dry-run
cleanly:

```bash
GH_TOKEN="$(cat /root/.ssh/codex.d/tokens/FORGE_TOKEN)" \
  python3 scripts/github_project_seed.py \
  --repo em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM \
  --apply \
  --create-project
```

The project is named `RFC Codex Infrastructure Roadmap` unless overridden with
`--project-title`. GitHub creates a reserved `Status` field automatically; the
script creates `Roadmap Status` and `Roadmap ID` fields for repo-specific
Kanban and burn-down style tracking, then adds seeded issues to the project.

If the token is missing project permissions, the script exits before performing
any project mutation and prints a scope-specific error.

## Milestone Model

GitHub does not provide selectable milestone templates in the same way it
provides issue templates. This repository treats `project-management/milestones.yml`
as the milestone template catalog and applies it with the seed script.

The initial milestones are aligned to the current roadmap lanes:

- Critical Path
- Container Services
- NetBox/IPAM/DCIM
- RouterOS Network
- Identity/RBAC/AAA
- Observability
- Logging/Search
- Builder Farm
- Workstation Stage5
- FMT2 Recovery
- DNS Automation
- MCP/Trac Control Plane
- Repository Proxy
- LLM/RAG Services

## Operational Rules

- Keep `docs/ROADMAP-AND-TODO.md` as the human-readable source.
- Use GitHub issues as the execution board and external collaboration layer.
- Do not create GitHub Actions for project management unless explicitly approved.
- Do not put secrets, token values, credentials, or private host passwords in issues.
- Use issue labels and milestones for status and lane tracking; use NetBox for
  durable IPAM/DCIM source-of-truth.
