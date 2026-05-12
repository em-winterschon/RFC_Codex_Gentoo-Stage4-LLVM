#!/usr/bin/env python3
"""Seed GitHub project-management objects from repo catalogs.

The command is dry-run by default. GitHub mutations require --apply.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.parse
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError as exc:  # pragma: no cover - Ansible hosts should have PyYAML.
    raise SystemExit("PyYAML is required to read project-management catalogs") from exc


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LABELS = REPO_ROOT / "project-management" / "labels.yml"
DEFAULT_MILESTONES = REPO_ROOT / "project-management" / "milestones.yml"
DEFAULT_ISSUES = REPO_ROOT / "project-management" / "issue-seed.yml"


@dataclass(frozen=True)
class PlannedIssue:
    title: str
    body: str
    labels: tuple[str, ...]
    milestone: str | None
    roadmap_id: str | None = None
    source: str = "catalog"
    status: str | None = None
    depends_on: tuple[str, ...] = ()
    parent_id: str | None = None
    issue_type: str = "task"


@dataclass
class Catalogs:
    labels: list[dict[str, Any]]
    milestones: list[dict[str, Any]]
    issues: list[PlannedIssue]
    project_title: str


@dataclass(frozen=True)
class IssueRecord:
    number: int
    title: str
    url: str
    body: str
    labels: tuple[str, ...]
    state: str


def load_yaml(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    return data or {}


def normalize_status(status: str) -> str:
    normalized = status.strip().lower().replace(" ", "-")
    if normalized in {"planned", "pending", "scaffolded"}:
        return "backlog"
    if normalized in {"complete", "completed"}:
        return "done"
    if normalized in {"active", "ready", "blocked", "review", "done", "backlog"}:
        return normalized
    return "backlog"


def status_from_labels(labels: tuple[str, ...], default: str = "backlog") -> str:
    for label in labels:
        if label.startswith("status:"):
            return normalize_status(label.split(":", 1)[1])
    return normalize_status(default)


def roadmap_prefix(roadmap_id: str) -> str:
    return roadmap_id.split("-", 1)[0]


def extract_roadmap_refs(text: str) -> tuple[str, ...]:
    if not text or text.strip().lower() in {"none", "none recorded.", "n/a", "-"}:
        return ()
    refs = []
    for match in re.findall(r"\b[A-Z0-9]+-[0-9]+\b", text):
        if match not in refs:
            refs.append(match)
    return tuple(refs)


def epic_id_for_milestone(title: str) -> str:
    normalized = re.sub(r"[^A-Z0-9]+", "-", title.upper()).strip("-")
    return f"EPIC-{normalized}"


def parse_markdown_table_row(line: str) -> list[str]:
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    return [re.sub(r"`([^`]+)`", r"\1", cell).strip() for cell in cells]


def parse_roadmap_issues(config: dict[str, Any]) -> list[PlannedIssue]:
    source = config.get("roadmap_source", "docs/ROADMAP-AND-TODO.md")
    roadmap_path = REPO_ROOT / source
    if not roadmap_path.exists():
        return []

    excluded = {str(item).strip().lower() for item in config.get("exclude_statuses", [])}
    prefix_milestones = config.get("prefix_milestones", {})
    prefix_areas = config.get("prefix_areas", {})

    issues: list[PlannedIssue] = []
    for raw_line in roadmap_path.read_text(encoding="utf-8").splitlines():
        if not raw_line.startswith("| `"):
            continue
        cells = parse_markdown_table_row(raw_line)
        if len(cells) < 5:
            continue
        roadmap_id, status, task, depends_on, notes = cells[:5]
        if not re.match(r"^[A-Z0-9]+-[0-9]+$", roadmap_id):
            continue
        if status.strip().lower() in excluded:
            continue

        prefix = roadmap_prefix(roadmap_id)
        normalized_status = normalize_status(status)
        area = prefix_areas.get(prefix, "critical-path")
        milestone = prefix_milestones.get(prefix, "Critical Path")
        labels = (
            "type:roadmap-task",
            f"area:{area}",
            f"status:{normalized_status}",
            "priority:normal",
        )
        dependencies = extract_roadmap_refs(depends_on)
        if dependencies:
            labels = (*labels, "rel:depends-on")
            if normalized_status == "blocked":
                labels = (*labels, "rel:blocked-by")
        body = "\n".join(
            [
                f"Roadmap ID: `{roadmap_id}`",
                "",
                f"Source: `{source}`",
                "",
                "## Objective",
                task,
                "",
                "## Current Status",
                status,
                "",
                "## Dependencies",
                depends_on or "None recorded.",
                "",
                "## Dependency Links",
                (
                    "Dependency links are resolved by "
                    "`scripts/github_project_seed.py --apply --sync-relationships` "
                    "after issues exist."
                ),
                "",
                "## Notes",
                notes or "None recorded.",
                "",
                "## Removal Condition",
                (
                    "Close this issue when the roadmap item is completed or "
                    "deliberately removed from the roadmap."
                ),
            ]
        )
        issues.append(
            PlannedIssue(
                title=f"[{roadmap_id}] {task}",
                body=body,
                labels=labels,
                milestone=milestone,
                roadmap_id=roadmap_id,
                source="roadmap",
                status=normalized_status,
                depends_on=dependencies,
                parent_id=epic_id_for_milestone(milestone),
                issue_type="task",
            )
        )
    return issues


def explicit_catalog_issues(config: dict[str, Any]) -> list[PlannedIssue]:
    issues = []
    for item in config.get("issues", []):
        issue_id = item["id"]
        title = item["title"]
        labels = tuple(item.get("labels", ["type:roadmap-task", "status:backlog"]))
        status = normalize_status(item.get("status") or status_from_labels(labels, "ready"))
        body = str(item.get("body", "")).strip()
        if issue_id and not title.startswith(f"[{issue_id}]"):
            title = f"[{issue_id}] {title}"
        issues.append(
            PlannedIssue(
                title=title,
                body=body,
                labels=labels,
                milestone=item.get("milestone"),
                roadmap_id=issue_id,
                source="catalog",
                status=status,
                depends_on=tuple(item.get("depends_on", [])),
                parent_id=item.get("parent_id"),
                issue_type=item.get("issue_type", "task"),
            )
        )
    return issues


def epic_issues(milestones: list[dict[str, Any]]) -> list[PlannedIssue]:
    issues = []
    for milestone in milestones:
        title = milestone["title"]
        epic_id = epic_id_for_milestone(title)
        body = "\n".join(
            [
                f"Roadmap ID: `{epic_id}`",
                "",
                "## Epic Scope",
                milestone.get("description", f"Track roadmap work for {title}."),
                "",
                "## Child Issues",
                (
                    "Child issues are linked by milestone, project board fields, "
                    "dependency references, and native GitHub sub-issue relationships "
                    "when the API accepts them."
                ),
                "",
                "## Removal Condition",
                (
                    "Close this epic when all child roadmap issues in this milestone "
                    "are completed or intentionally moved."
                ),
            ]
        )
        issues.append(
            PlannedIssue(
                title=f"[EPIC] {title}",
                body=body,
                labels=("type:epic", "status:active", "priority:normal"),
                milestone=title,
                roadmap_id=epic_id,
                source="epic",
                status="active",
                issue_type="epic",
            )
        )
    return issues


def load_catalogs(args: argparse.Namespace) -> Catalogs:
    label_data = load_yaml(Path(args.labels))
    milestone_data = load_yaml(Path(args.milestones))
    issue_data = load_yaml(Path(args.issues))
    settings = issue_data.get("settings", {})

    labels = list(label_data.get("labels", []))
    milestones = list(milestone_data.get("milestones", []))
    issues = epic_issues(milestones)
    issues.extend(explicit_catalog_issues(issue_data))
    if not args.no_roadmap:
        issues.extend(parse_roadmap_issues(settings))

    seen_titles: set[str] = set()
    deduped: list[PlannedIssue] = []
    for issue in issues:
        if issue.title in seen_titles:
            continue
        seen_titles.add(issue.title)
        deduped.append(issue)

    return Catalogs(
        labels=labels,
        milestones=milestones,
        issues=deduped,
        project_title=args.project_title
        or settings.get("project_title", "RFC Codex Infrastructure Roadmap"),
    )


def gh_json(args: list[str]) -> Any:
    result = subprocess.run(["gh", *args], check=True, text=True, stdout=subprocess.PIPE)
    if not result.stdout.strip():
        return None
    return json.loads(result.stdout)


def gh_run(args: list[str]) -> None:
    subprocess.run(["gh", *args], check=True, text=True)


def gh_json_optional(args: list[str]) -> Any | None:
    try:
        return gh_json(args)
    except subprocess.CalledProcessError:
        return None


def url_quote(value: str) -> str:
    return urllib.parse.quote(value, safe="")


def issue_query_url(repo: str, issue: PlannedIssue) -> str:
    params = {
        "template": "roadmap_task.yml",
        "title": issue.title,
        "body": issue.body,
        "labels": ",".join(issue.labels),
    }
    if issue.milestone:
        params["milestone"] = issue.milestone
    return f"https://github.com/{repo}/issues/new?{urllib.parse.urlencode(params)}"


def print_plan(repo: str, catalogs: Catalogs, emit_query_urls: bool) -> None:
    print("DRY-RUN: no GitHub mutations will be performed")
    print(f"repo: {repo}")
    print(f"project: {catalogs.project_title}")
    print(f"labels: {len(catalogs.labels)}")
    for label in catalogs.labels:
        print(f"  label: {label['name']}")
    print(f"milestones: {len(catalogs.milestones)}")
    for milestone in catalogs.milestones:
        print(f"  milestone: {milestone['title']}")
    print(f"issues: {len(catalogs.issues)}")
    print(f"epics: {sum(1 for issue in catalogs.issues if issue.issue_type == 'epic')}")
    print(f"relationship edges: {sum(len(issue.depends_on) for issue in catalogs.issues)}")
    for issue in catalogs.issues:
        prefix = "epic" if issue.issue_type == "epic" else "issue"
        print(f"  {prefix}: {issue.title}")
        if emit_query_urls:
            print(f"    url: {issue_query_url(repo, issue)}")


def apply_labels(repo: str, labels: list[dict[str, Any]]) -> None:
    existing = {item["name"] for item in gh_json(["api", f"repos/{repo}/labels", "--paginate"])}
    for label in labels:
        name = label["name"]
        color = str(label["color"]).lstrip("#")
        description = str(label.get("description", ""))
        if name in existing:
            gh_run(
                [
                    "api",
                    "--method",
                    "PATCH",
                    f"repos/{repo}/labels/{url_quote(name)}",
                    "-f",
                    f"new_name={name}",
                    "-f",
                    f"color={color}",
                    "-f",
                    f"description={description}",
                    "--silent",
                ]
            )
            print(f"updated label: {name}")
        else:
            gh_run(
                [
                    "api",
                    "--method",
                    "POST",
                    f"repos/{repo}/labels",
                    "-f",
                    f"name={name}",
                    "-f",
                    f"color={color}",
                    "-f",
                    f"description={description}",
                    "--silent",
                ]
            )
            print(f"created label: {name}")


def apply_milestones(repo: str, milestones: list[dict[str, Any]]) -> None:
    existing = {
        item["title"]: item["number"]
        for item in gh_json(["api", f"repos/{repo}/milestones?state=all&per_page=100"])
    }
    for milestone in milestones:
        title = milestone["title"]
        fields = [
            "-f",
            f"title={title}",
            "-f",
            f"description={milestone.get('description', '')}",
            "-f",
            f"state={milestone.get('state', 'open')}",
        ]
        if milestone.get("due_on"):
            fields.extend(["-f", f"due_on={milestone['due_on']}"])
        if title in existing:
            gh_run(
                [
                    "api",
                    "--method",
                    "PATCH",
                    f"repos/{repo}/milestones/{existing[title]}",
                    *fields,
                    "--silent",
                ]
            )
            print(f"updated milestone: {title}")
        else:
            gh_run(
                [
                    "api",
                    "--method",
                    "POST",
                    f"repos/{repo}/milestones",
                    *fields,
                    "--silent",
                ]
            )
            print(f"created milestone: {title}")


def fetch_issue_records(repo: str) -> list[IssueRecord]:
    data = gh_json(
        [
            "issue",
            "list",
            "--repo",
            repo,
            "--state",
            "all",
            "--limit",
            "1000",
            "--json",
            "number,title,url,body,labels,state",
        ]
    )
    records = []
    for item in data:
        records.append(
            IssueRecord(
                number=int(item["number"]),
                title=item["title"],
                url=item["url"],
                body=item.get("body") or "",
                labels=tuple(label["name"] for label in item.get("labels", [])),
                state=item.get("state", "OPEN"),
            )
        )
    return records


def issue_records_by_title(repo: str) -> dict[str, IssueRecord]:
    return {record.title: record for record in fetch_issue_records(repo)}


def issue_records_by_roadmap_id(repo: str) -> dict[str, IssueRecord]:
    records = {}
    for record in fetch_issue_records(repo):
        match = re.match(r"^\[([A-Z0-9-]+)\]", record.title)
        if match:
            records[match.group(1)] = record
        if record.title.startswith("[EPIC] "):
            records[epic_id_for_milestone(record.title.removeprefix("[EPIC] "))] = record
    return records


def existing_issue_titles(repo: str) -> set[str]:
    try:
        data = gh_json(
            [
                "issue",
                "list",
                "--repo",
                repo,
                "--state",
                "all",
                "--limit",
                "1000",
                "--json",
                "title",
            ]
        )
    except subprocess.CalledProcessError:
        data = gh_json(["api", f"repos/{repo}/issues?state=all&per_page=100"])
    return {item["title"] for item in data}


def apply_issues(repo: str, issues: list[PlannedIssue]) -> None:
    existing = existing_issue_titles(repo)
    for issue in issues:
        if issue.title in existing:
            print(f"skipped existing issue: {issue.title}")
            continue
        cmd = [
            "issue",
            "create",
            "--repo",
            repo,
            "--title",
            issue.title,
            "--body",
            issue.body,
        ]
        for label in issue.labels:
            cmd.extend(["--label", label])
        if issue.milestone:
            cmd.extend(["--milestone", issue.milestone])
        gh_run(cmd)
        print(f"created issue: {issue.title}")


def dependency_section(issue: PlannedIssue, records_by_id: dict[str, IssueRecord]) -> str:
    if not issue.depends_on:
        return "## Dependency Links\nNone recorded."
    lines = ["## Dependency Links"]
    for dep_id in issue.depends_on:
        record = records_by_id.get(dep_id)
        if record:
            lines.append(f"- depends on #{record.number} (`{dep_id}`)")
        else:
            lines.append(f"- unresolved dependency `{dep_id}`")
    return "\n".join(lines)


def replace_markdown_section(body: str, heading: str, replacement: str) -> str:
    pattern = re.compile(rf"^## {re.escape(heading)}\n.*?(?=^## |\Z)", re.MULTILINE | re.DOTALL)
    if pattern.search(body):
        return pattern.sub(replacement.rstrip() + "\n\n", body).rstrip()
    return (body.rstrip() + "\n\n" + replacement.rstrip()).rstrip()


def resolve_dependency_numbers(
    issue: PlannedIssue, records_by_id: dict[str, IssueRecord]
) -> tuple[int, ...]:
    numbers = []
    for dep_id in issue.depends_on:
        record = records_by_id.get(dep_id)
        if record and record.number not in numbers:
            numbers.append(record.number)
    return tuple(numbers)


def update_issue_body_for_relationships(
    repo: str, issue: PlannedIssue, record: IssueRecord, records_by_id: dict[str, IssueRecord]
) -> None:
    new_body = replace_markdown_section(
        record.body, "Dependency Links", dependency_section(issue, records_by_id)
    )
    if new_body == record.body:
        return
    gh_run(["issue", "edit", str(record.number), "--repo", repo, "--body", new_body])
    print(f"updated relationship body: {issue.title}")


def apply_native_dependency(repo: str, blocked_by_number: int, blocking_number: int) -> bool:
    # GitHub's issue relationship endpoints are newer than the classic Issues API.
    # Keep failures non-fatal because the body links and project fields are durable.
    result = subprocess.run(
        [
            "gh",
            "api",
            "--method",
            "POST",
            f"repos/{repo}/issues/{blocked_by_number}/dependencies/blocked_by",
            "-F",
            f"blocking_issue_id={blocking_number}",
            "--silent",
        ],
        text=True,
        capture_output=True,
    )
    if result.returncode == 0:
        print(f"linked native dependency: #{blocked_by_number} blocked by #{blocking_number}")
        return True
    if "already" not in result.stderr.lower() and "exists" not in result.stderr.lower():
        print(
            f"skipped native dependency #{blocked_by_number} -> "
            f"#{blocking_number}: {result.stderr.strip()}",
            file=sys.stderr,
        )
    return False


def apply_native_sub_issue(repo: str, parent_number: int, child_number: int) -> bool:
    result = subprocess.run(
        [
            "gh",
            "api",
            "--method",
            "POST",
            f"repos/{repo}/issues/{parent_number}/sub_issues",
            "-F",
            f"sub_issue_id={child_number}",
            "--silent",
        ],
        text=True,
        capture_output=True,
    )
    if result.returncode == 0:
        print(f"linked native sub-issue: #{parent_number} -> #{child_number}")
        return True
    if "already" not in result.stderr.lower() and "exists" not in result.stderr.lower():
        print(
            f"skipped native sub-issue #{parent_number} -> "
            f"#{child_number}: {result.stderr.strip()}",
            file=sys.stderr,
        )
    return False


def apply_issue_relationships(repo: str, issues: list[PlannedIssue], native_links: bool) -> None:
    records_by_title = issue_records_by_title(repo)
    records_by_id = issue_records_by_roadmap_id(repo)
    for issue in issues:
        record = records_by_title.get(issue.title)
        if not record:
            continue
        update_issue_body_for_relationships(repo, issue, record, records_by_id)
        if native_links:
            for dep_number in resolve_dependency_numbers(issue, records_by_id):
                apply_native_dependency(repo, record.number, dep_number)
            parent = records_by_id.get(issue.parent_id or "")
            if parent and issue.issue_type != "epic":
                apply_native_sub_issue(repo, parent.number, record.number)


def project_fields(project_number: str, owner: str) -> list[dict[str, Any]]:
    data = gh_json(["project", "field-list", project_number, "--owner", owner, "--format", "json"])
    return list(data.get("fields", []))


def project_field_by_name(project_number: str, owner: str, name: str) -> dict[str, Any] | None:
    for field_obj in project_fields(project_number, owner):
        if field_obj["name"] == name:
            return field_obj
    return None


def ensure_project_field(
    project_number: str,
    owner: str,
    name: str,
    data_type: str,
    options: tuple[str, ...] = (),
) -> None:
    existing = {field["name"] for field in project_fields(project_number, owner)}
    if name in existing:
        print(f"skipped existing project field: {name}")
        return

    cmd = [
        "project",
        "field-create",
        project_number,
        "--owner",
        owner,
        "--name",
        name,
        "--data-type",
        data_type,
    ]
    if options:
        cmd.extend(["--single-select-options", ",".join(options)])
    gh_run(cmd)
    print(f"created project field: {name}")


def repo_issues_by_title(repo: str) -> dict[str, str]:
    data = gh_json(
        [
            "issue",
            "list",
            "--repo",
            repo,
            "--state",
            "all",
            "--limit",
            "1000",
            "--json",
            "title,url",
        ]
    )
    return {item["title"]: item["url"] for item in data}


def repo_issue_urls_by_title(repo: str) -> dict[str, str]:
    return repo_issues_by_title(repo)


def project_item_titles(project_number: str, owner: str) -> set[str]:
    data = gh_json(
        [
            "project",
            "item-list",
            project_number,
            "--owner",
            owner,
            "--format",
            "json",
            "--limit",
            "1000",
        ]
    )
    titles = set()
    for item in data.get("items", []):
        title = item.get("title") or item.get("content", {}).get("title")
        if title:
            titles.add(title)
    return titles


def project_items_by_title(project_number: str, owner: str) -> dict[str, dict[str, Any]]:
    data = gh_json(
        [
            "project",
            "item-list",
            project_number,
            "--owner",
            owner,
            "--format",
            "json",
            "--limit",
            "1000",
        ]
    )
    items = {}
    for item in data.get("items", []):
        title = item.get("title") or item.get("content", {}).get("title")
        if title:
            items[title] = item
    return items


def add_issues_to_project(
    project_number: str, owner: str, repo: str, issues: list[PlannedIssue]
) -> None:
    urls = repo_issue_urls_by_title(repo)
    existing_titles = project_item_titles(project_number, owner)
    for issue in issues:
        if issue.title in existing_titles:
            print(f"skipped existing project item: {issue.title}")
            continue
        url = urls.get(issue.title)
        if not url:
            print(f"skipped missing issue for project item: {issue.title}", file=sys.stderr)
            continue
        gh_run(["project", "item-add", project_number, "--owner", owner, "--url", url])
        print(f"added project item: {issue.title}")


def roadmap_status_label(status: str | None) -> str:
    status = normalize_status(status or "backlog")
    return {
        "backlog": "Backlog",
        "ready": "Ready",
        "active": "Active",
        "blocked": "Blocked",
        "review": "Review",
        "done": "Done",
    }.get(status, "Backlog")


def kanban_status_label(status: str | None, issue_state: str | None = None) -> str:
    if str(issue_state or "").upper() == "CLOSED":
        return "Complete"
    status = normalize_status(status or "backlog")
    return {
        "backlog": "Backlog",
        "ready": "Scoping",
        "active": "In-Progress",
        "blocked": "Blocked",
        "review": "Review-Ready",
        "done": "Complete",
    }.get(status, "Backlog")


def roadmap_status_from_kanban(kanban_status: str) -> str:
    return {
        "Backlog": "Backlog",
        "Scoping": "Ready",
        "In-Progress": "Active",
        "Blocked": "Blocked",
        "Review-Ready": "Review",
        "Complete": "Done",
    }[kanban_status]


def single_select_option_id(field_obj: dict[str, Any], option_name: str) -> str | None:
    for option in field_obj.get("options", []):
        if option["name"] == option_name:
            return option["id"]
    return None


def update_project_item_fields(
    project_number: str, owner: str, repo: str, issues: list[PlannedIssue]
) -> None:
    project = gh_json(["project", "view", project_number, "--owner", owner, "--format", "json"])
    project_id = project["id"]
    roadmap_id_field = project_field_by_name(project_number, owner, "Roadmap ID")
    roadmap_status_field = project_field_by_name(project_number, owner, "Roadmap Status")
    kanban_status_field = project_field_by_name(project_number, owner, "Kanban Status")
    if not roadmap_id_field or not roadmap_status_field:
        print("skipped project field sync: missing Roadmap ID or Roadmap Status", file=sys.stderr)
        return
    items = project_items_by_title(project_number, owner)
    records_by_title = issue_records_by_title(repo)
    for issue in issues:
        item = items.get(issue.title)
        if not item:
            continue
        issue_state = records_by_title.get(issue.title).state if issue.title in records_by_title else None
        if issue.roadmap_id:
            gh_run(
                [
                    "project",
                    "item-edit",
                    "--id",
                    item["id"],
                    "--project-id",
                    project_id,
                    "--field-id",
                    roadmap_id_field["id"],
                    "--text",
                    issue.roadmap_id,
                    "--format",
                    "json",
                ]
            )
        kanban_status = kanban_status_label(issue.status, issue_state)
        option_id = single_select_option_id(roadmap_status_field, roadmap_status_from_kanban(kanban_status))
        if option_id:
            gh_run(
                [
                    "project",
                    "item-edit",
                    "--id",
                    item["id"],
                    "--project-id",
                    project_id,
                    "--field-id",
                    roadmap_status_field["id"],
                    "--single-select-option-id",
                    option_id,
                    "--format",
                    "json",
                ]
            )
        if kanban_status_field:
            option_id = single_select_option_id(kanban_status_field, kanban_status)
            if option_id:
                gh_run(
                    [
                        "project",
                        "item-edit",
                        "--id",
                        item["id"],
                        "--project-id",
                        project_id,
                        "--field-id",
                        kanban_status_field["id"],
                        "--single-select-option-id",
                        option_id,
                        "--format",
                        "json",
                    ]
                )
        print(f"updated project fields: {issue.title}")
def create_project(owner: str, title: str) -> str:
    projects = gh_json(["project", "list", "--owner", owner, "--format", "json", "--limit", "100"])
    for project in projects.get("projects", []):
        if project.get("title") == title:
            print(f"skipped existing project: {title} #{project['number']}")
            return str(project["number"])

    created = gh_json(["project", "create", "--owner", owner, "--title", title, "--format", "json"])
    number = str(created["number"])
    print(f"created project: {title} #{number}")
    return number


def ensure_project(
    owner: str, repo: str, title: str, issues: list[PlannedIssue], sync_fields: bool
) -> None:
    project_number = create_project(owner, title)
    ensure_project_field(
        project_number,
        owner,
        "Roadmap Status",
        "SINGLE_SELECT",
        ("Backlog", "Ready", "Active", "Blocked", "Review", "Done"),
    )
    ensure_project_field(
        project_number,
        owner,
        "Kanban Status",
        "SINGLE_SELECT",
        ("Backlog", "Scoping", "In-Progress", "Blocked", "Review-Ready", "Complete"),
    )
    ensure_project_field(project_number, owner, "Roadmap ID", "TEXT")
    add_issues_to_project(project_number, owner, repo, issues)
    if sync_fields:
        update_project_item_fields(project_number, owner, repo, issues)


def verify_project_scope(owner: str) -> None:
    try:
        gh_json(["project", "list", "--owner", owner, "--format", "json", "--limit", "1"])
    except subprocess.CalledProcessError as exc:
        raise SystemExit(
            "GitHub Projects v2 creation requires a token with project/read:project scope. "
            "Labels, milestones, and issues can be applied without this scope."
        ) from exc


def apply_catalogs(
    repo: str,
    catalogs: Catalogs,
    create_project_flag: bool,
    sync_relationships: bool,
    sync_project_fields: bool,
    native_links: bool,
) -> None:
    owner = repo.split("/", 1)[0]
    if create_project_flag:
        verify_project_scope(owner)
    apply_labels(repo, catalogs.labels)
    apply_milestones(repo, catalogs.milestones)
    apply_issues(repo, catalogs.issues)
    if sync_relationships:
        apply_issue_relationships(repo, catalogs.issues, native_links)
    if create_project_flag:
        ensure_project(owner, repo, catalogs.project_title, catalogs.issues, sync_project_fields)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, help="GitHub repository in owner/name form.")
    parser.add_argument("--labels", default=str(DEFAULT_LABELS), help="Label catalog path.")
    parser.add_argument(
        "--milestones", default=str(DEFAULT_MILESTONES), help="Milestone catalog path."
    )
    parser.add_argument("--issues", default=str(DEFAULT_ISSUES), help="Issue seed catalog path.")
    parser.add_argument("--project-title", default=None, help="Project title override.")
    parser.add_argument("--apply", action="store_true", help="Apply GitHub mutations.")
    parser.add_argument(
        "--create-project", action="store_true", help="Create the GitHub Projects v2 board."
    )
    parser.add_argument(
        "--sync-relationships",
        action="store_true",
        help="Update issue bodies and optional native issue relationships.",
    )
    parser.add_argument(
        "--native-issue-links",
        action="store_true",
        help="Attempt native GitHub dependency and sub-issue API links.",
    )
    parser.add_argument(
        "--sync-project-fields",
        action="store_true",
        help="Populate Roadmap ID and Roadmap Status project fields.",
    )
    parser.add_argument(
        "--emit-query-urls", action="store_true", help="Print issue creation query URLs."
    )
    parser.add_argument(
        "--no-roadmap",
        action="store_true",
        help="Do not derive issues from docs/ROADMAP-AND-TODO.md.",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.create_project and not args.apply:
        print("--create-project requires --apply", file=sys.stderr)
        return 2
    if args.apply and not os.environ.get("GH_TOKEN") and not os.environ.get("GITHUB_TOKEN"):
        print("--apply requires GH_TOKEN or GITHUB_TOKEN in the environment", file=sys.stderr)
        return 2

    catalogs = load_catalogs(args)
    if not args.apply:
        print_plan(args.repo, catalogs, args.emit_query_urls)
        return 0

    apply_catalogs(
        args.repo,
        catalogs,
        args.create_project,
        args.sync_relationships,
        args.sync_project_fields,
        args.native_issue_links,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
