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
from dataclasses import dataclass, field
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


@dataclass
class Catalogs:
    labels: list[dict[str, Any]]
    milestones: list[dict[str, Any]]
    issues: list[PlannedIssue]
    project_title: str


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


def roadmap_prefix(roadmap_id: str) -> str:
    return roadmap_id.split("-", 1)[0]


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
                "## Notes",
                notes or "None recorded.",
                "",
                "## Removal Condition",
                "Close this issue when the roadmap item is completed or deliberately removed from the roadmap.",
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
            )
        )
    return issues


def explicit_catalog_issues(config: dict[str, Any]) -> list[PlannedIssue]:
    issues = []
    for item in config.get("issues", []):
        issue_id = item["id"]
        title = item["title"]
        labels = tuple(item.get("labels", ["type:roadmap-task", "status:backlog"]))
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
    issues = explicit_catalog_issues(issue_data)
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
        project_title=args.project_title or settings.get("project_title", "RFC Codex Infrastructure Roadmap"),
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
    for issue in catalogs.issues:
        print(f"  issue: {issue.title}")
        if emit_query_urls:
            print(f"    url: {issue_query_url(repo, issue)}")


def apply_labels(repo: str, labels: list[dict[str, Any]]) -> None:
    existing = {
        item["name"]
        for item in gh_json(["api", f"repos/{repo}/labels", "--paginate"])
    }
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


def existing_issue_titles(repo: str) -> set[str]:
    try:
        data = gh_json(["issue", "list", "--repo", repo, "--state", "all", "--limit", "1000", "--json", "title"])
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


def project_fields(project_number: str, owner: str) -> list[dict[str, Any]]:
    data = gh_json(["project", "field-list", project_number, "--owner", owner, "--format", "json"])
    return list(data.get("fields", []))


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
    data = gh_json(["issue", "list", "--repo", repo, "--state", "all", "--limit", "1000", "--json", "title,url"])
    return {item["title"]: item["url"] for item in data}


def project_item_titles(project_number: str, owner: str) -> set[str]:
    data = gh_json(["project", "item-list", project_number, "--owner", owner, "--format", "json", "--limit", "1000"])
    titles = set()
    for item in data.get("items", []):
        title = item.get("title") or item.get("content", {}).get("title")
        if title:
            titles.add(title)
    return titles


def add_issues_to_project(project_number: str, owner: str, repo: str, issues: list[PlannedIssue]) -> None:
    urls = repo_issues_by_title(repo)
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


def ensure_project(owner: str, repo: str, title: str, issues: list[PlannedIssue]) -> None:
    project_number = create_project(owner, title)
    ensure_project_field(
        project_number,
        owner,
        "Roadmap Status",
        "SINGLE_SELECT",
        ("Backlog", "Ready", "Active", "Blocked", "Review", "Done"),
    )
    ensure_project_field(project_number, owner, "Roadmap ID", "TEXT")
    add_issues_to_project(project_number, owner, repo, issues)


def verify_project_scope(owner: str) -> None:
    try:
        gh_json(["project", "list", "--owner", owner, "--format", "json", "--limit", "1"])
    except subprocess.CalledProcessError as exc:
        raise SystemExit(
            "GitHub Projects v2 creation requires a token with project/read:project scope. "
            "Labels, milestones, and issues can be applied without this scope."
        ) from exc


def apply_catalogs(repo: str, catalogs: Catalogs, create_project_flag: bool) -> None:
    owner = repo.split("/", 1)[0]
    if create_project_flag:
        verify_project_scope(owner)
    apply_labels(repo, catalogs.labels)
    apply_milestones(repo, catalogs.milestones)
    apply_issues(repo, catalogs.issues)
    if create_project_flag:
        ensure_project(owner, repo, catalogs.project_title, catalogs.issues)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, help="GitHub repository in owner/name form.")
    parser.add_argument("--labels", default=str(DEFAULT_LABELS), help="Label catalog path.")
    parser.add_argument("--milestones", default=str(DEFAULT_MILESTONES), help="Milestone catalog path.")
    parser.add_argument("--issues", default=str(DEFAULT_ISSUES), help="Issue seed catalog path.")
    parser.add_argument("--project-title", default=None, help="Project title override.")
    parser.add_argument("--apply", action="store_true", help="Apply GitHub mutations.")
    parser.add_argument("--create-project", action="store_true", help="Create the GitHub Projects v2 board.")
    parser.add_argument("--emit-query-urls", action="store_true", help="Print issue creation query URLs.")
    parser.add_argument("--no-roadmap", action="store_true", help="Do not derive issues from docs/ROADMAP-AND-TODO.md.")
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

    apply_catalogs(args.repo, catalogs, args.create_project)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
