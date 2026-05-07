#!/usr/bin/env python3
"""Export Gentoo build metrics from emerge and builder logs.

This tool turns the current build logs into machine-readable time-series data
and lightweight SVG charts so long-running source builds can be tracked over
time without needing external plotting dependencies.
"""

from __future__ import annotations

# ruff: noqa: E501

import argparse
import csv
import datetime as dt
import html
import json
import math
import pathlib
import re
from collections.abc import Iterable
from dataclasses import dataclass

EMERGE_START_RE = re.compile(
    r"^(?P<ts>\d+):\s+>>> emerge \((?P<index>\d+) of (?P<total>\d+)\) "
    r"(?P<atom>.+?) to (?P<target>\S+)\s*$"
)
EMERGE_PHASE_RE = re.compile(
    r"^(?P<ts>\d+):\s+=== \((?P<index>\d+) of (?P<total>\d+)\) "
    r"(?P<phase>Cleaning|Compiling/Merging|Merging|Post-Build Cleaning) "
    r"\((?P<ebuild>.+?)\)\s*$"
)
EMERGE_COMPLETE_RE = re.compile(
    r"^(?P<ts>\d+):\s+::: completed emerge \((?P<index>\d+) of (?P<total>\d+)\) "
    r"(?P<atom>.+?) to (?P<target>\S+)\s*$"
)
BUILDER_STATUS_RE = re.compile(
    r"^>>> Jobs: (?P<completed>\d+) of (?P<total>\d+) complete"
    r"(?:, (?P<running>\d+) running)?"
    r"(?:, (?P<merge_wait>\d+) merge wait)?"
    r"\s+Load avg: (?P<load1>[\d.]+), (?P<load5>[\d.]+), (?P<load15>[\d.]+)\s*$"
)
BUILDER_EVENT_RE = re.compile(
    r"^>>> (?P<event>Emerging|Installing|Completed) "
    r"\((?P<index>\d+) of (?P<total>\d+)\) (?P<atom>.+?)::\S+\s*$"
)


@dataclass
class EmergeEvent:
    ts: int
    event: str
    index: int
    total: int
    atom: str
    target: str | None = None
    phase: str | None = None


@dataclass
class BuilderSample:
    ts: int
    completed: int
    total: int
    running: int
    merge_wait: int
    load1: float
    load5: float
    load15: float
    current_atom: str | None = None
    current_index: int | None = None


def iso8601(ts: int) -> str:
    return dt.datetime.fromtimestamp(ts, dt.UTC).isoformat()


def parse_emerge_log(path: pathlib.Path) -> list[EmergeEvent]:
    events: list[EmergeEvent] = []
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = EMERGE_START_RE.match(raw_line)
        if match:
            events.append(
                EmergeEvent(
                    ts=int(match["ts"]),
                    event="emerge",
                    index=int(match["index"]),
                    total=int(match["total"]),
                    atom=match["atom"],
                    target=match["target"],
                )
            )
            continue

        match = EMERGE_PHASE_RE.match(raw_line)
        if match:
            events.append(
                EmergeEvent(
                    ts=int(match["ts"]),
                    event="phase",
                    index=int(match["index"]),
                    total=int(match["total"]),
                    atom=match["ebuild"],
                    phase=match["phase"],
                )
            )
            continue

        match = EMERGE_COMPLETE_RE.match(raw_line)
        if match:
            events.append(
                EmergeEvent(
                    ts=int(match["ts"]),
                    event="complete",
                    index=int(match["index"]),
                    total=int(match["total"]),
                    atom=match["atom"],
                    target=match["target"],
                )
            )
    return events


def parse_builder_log(path: pathlib.Path, fallback_ts: int | None) -> list[BuilderSample]:
    current_ts = fallback_ts
    current_atom: str | None = None
    current_index: int | None = None
    samples: list[BuilderSample] = []

    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = raw_line.strip()
        if not stripped:
            continue

        event_match = BUILDER_EVENT_RE.match(stripped)
        if event_match:
            current_atom = event_match["atom"]
            current_index = int(event_match["index"])
            continue

        status_match = BUILDER_STATUS_RE.match(stripped)
        if status_match:
            if current_ts is None:
                current_ts = 0
            else:
                current_ts += 1
            samples.append(
                BuilderSample(
                    ts=current_ts,
                    completed=int(status_match["completed"]),
                    total=int(status_match["total"]),
                    running=int(status_match["running"] or 0),
                    merge_wait=int(status_match["merge_wait"] or 0),
                    load1=float(status_match["load1"]),
                    load5=float(status_match["load5"]),
                    load15=float(status_match["load15"]),
                    current_atom=current_atom,
                    current_index=current_index,
                )
            )
    return samples


def write_emerge_csv(path: pathlib.Path, events: Iterable[EmergeEvent]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["ts", "iso8601_utc", "event", "index", "total", "atom", "target", "phase"])
        for event in events:
            writer.writerow(
                [
                    event.ts,
                    iso8601(event.ts),
                    event.event,
                    event.index,
                    event.total,
                    event.atom,
                    event.target or "",
                    event.phase or "",
                ]
            )


def write_builder_csv(path: pathlib.Path, samples: Iterable[BuilderSample]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "ts",
                "iso8601_utc",
                "completed",
                "total",
                "running",
                "merge_wait",
                "load1",
                "load5",
                "load15",
                "current_index",
                "current_atom",
            ]
        )
        for sample in samples:
            writer.writerow(
                [
                    sample.ts,
                    iso8601(sample.ts),
                    sample.completed,
                    sample.total,
                    sample.running,
                    sample.merge_wait,
                    sample.load1,
                    sample.load5,
                    sample.load15,
                    sample.current_index or "",
                    sample.current_atom or "",
                ]
            )


def summarize(
    emerge_events: list[EmergeEvent], builder_samples: list[BuilderSample]
) -> dict[str, object]:
    started = min((event.ts for event in emerge_events), default=None)
    finished = max((event.ts for event in emerge_events), default=None)
    total = max((event.total for event in emerge_events), default=0)
    completed_events = [event for event in emerge_events if event.event == "complete"]
    completed = max((event.index for event in completed_events), default=0)
    latest_builder = builder_samples[-1] if builder_samples else None

    summary = {
        "started_ts": started,
        "started_iso8601_utc": iso8601(started) if started is not None else None,
        "last_event_ts": finished,
        "last_event_iso8601_utc": iso8601(finished) if finished is not None else None,
        "duration_seconds": (
            (finished - started) if started is not None and finished is not None else None
        ),
        "total_packages": total,
        "completed_packages": completed,
        "completed_percent_by_count": round((completed / total) * 100, 2) if total else 0.0,
        "builder_samples": len(builder_samples),
        "latest_builder": (
            {
                "ts": latest_builder.ts,
                "iso8601_utc": iso8601(latest_builder.ts),
                "completed": latest_builder.completed,
                "total": latest_builder.total,
                "running": latest_builder.running,
                "merge_wait": latest_builder.merge_wait,
                "load1": latest_builder.load1,
                "load5": latest_builder.load5,
                "load15": latest_builder.load15,
                "current_index": latest_builder.current_index,
                "current_atom": latest_builder.current_atom,
            }
            if latest_builder
            else None
        ),
    }
    return summary


def _chart_points(points: list[tuple[float, float]]) -> str:
    return " ".join(f"{x:.2f},{y:.2f}" for x, y in points)


def _axis_labels(title: str, subtitle: str) -> str:
    return (
        f'<text x="32" y="28" font-size="18" font-family="sans-serif">{html.escape(title)}</text>'
        f'<text x="32" y="48" font-size="11" fill="#555" font-family="sans-serif">{html.escape(subtitle)}</text>'
    )


def render_burndown_svg(path: pathlib.Path, completed_events: list[EmergeEvent]) -> None:
    width = 1000
    height = 420
    left = 70
    right = 30
    top = 60
    bottom = 50
    plot_width = width - left - right
    plot_height = height - top - bottom

    if not completed_events:
        path.write_text("<svg xmlns='http://www.w3.org/2000/svg'/>", encoding="utf-8")
        return

    start_ts = completed_events[0].ts
    end_ts = completed_events[-1].ts
    max_total = max(event.total for event in completed_events)
    span = max(end_ts - start_ts, 1)

    points = []
    for event in completed_events:
        x = left + ((event.ts - start_ts) / span) * plot_width
        y = top + plot_height - ((event.index / max_total) * plot_height)
        points.append((x, y))

    grid = []
    for step in range(6):
        y = top + (plot_height / 5) * step
        count = max_total - int((max_total / 5) * step)
        grid.append(
            f"<line x1='{left}' y1='{y:.2f}' x2='{left + plot_width}' y2='{y:.2f}' stroke='#e5e7eb'/>"
            f"<text x='12' y='{y + 4:.2f}' font-size='11' font-family='sans-serif'>{count}</text>"
        )

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}">
  <rect width="100%" height="100%" fill="white"/>
  {_axis_labels("Package Burn-down", f"{completed_events[-1].index} of {max_total} packages completed")}
  {''.join(grid)}
  <line x1="{left}" y1="{top + plot_height}" x2="{left + plot_width}" y2="{top + plot_height}" stroke="#111"/>
  <line x1="{left}" y1="{top}" x2="{left}" y2="{top + plot_height}" stroke="#111"/>
  <polyline fill="none" stroke="#2563eb" stroke-width="2.5" points="{_chart_points(points)}"/>
</svg>
"""
    path.write_text(svg, encoding="utf-8")


def render_load_svg(path: pathlib.Path, samples: list[BuilderSample]) -> None:
    width = 1000
    height = 420
    left = 70
    right = 30
    top = 60
    bottom = 50
    plot_width = width - left - right
    plot_height = height - top - bottom

    if not samples:
        path.write_text("<svg xmlns='http://www.w3.org/2000/svg'/>", encoding="utf-8")
        return

    start_ts = samples[0].ts
    end_ts = samples[-1].ts
    span = max(end_ts - start_ts, 1)
    max_load = max(max(sample.load1, sample.load5, sample.load15) for sample in samples)
    max_load = max(max_load, 1.0)
    max_load = math.ceil(max_load)

    def make_points(attr: str) -> list[tuple[float, float]]:
        result = []
        for sample in samples:
            x = left + ((sample.ts - start_ts) / span) * plot_width
            y = top + plot_height - ((getattr(sample, attr) / max_load) * plot_height)
            result.append((x, y))
        return result

    load1_points = make_points("load1")
    load5_points = make_points("load5")
    load15_points = make_points("load15")
    running_points = []
    max_jobs = max((sample.running + sample.merge_wait for sample in samples), default=1)
    max_jobs = max(max_jobs, 1)
    for sample in samples:
        x = left + ((sample.ts - start_ts) / span) * plot_width
        y = top + plot_height - (((sample.running + sample.merge_wait) / max_jobs) * plot_height)
        running_points.append((x, y))

    grid = []
    for step in range(6):
        y = top + (plot_height / 5) * step
        value = max_load - ((max_load / 5) * step)
        grid.append(
            f"<line x1='{left}' y1='{y:.2f}' x2='{left + plot_width}' y2='{y:.2f}' stroke='#e5e7eb'/>"
            f"<text x='18' y='{y + 4:.2f}' font-size='11' font-family='sans-serif'>{value:.1f}</text>"
        )

    legend = (
        "<g font-size='11' font-family='sans-serif'>"
        "<rect x='720' y='18' width='10' height='10' fill='#dc2626'/>"
        "<text x='736' y='27'>load1</text>"
        "<rect x='790' y='18' width='10' height='10' fill='#2563eb'/>"
        "<text x='806' y='27'>load5</text>"
        "<rect x='860' y='18' width='10' height='10' fill='#16a34a'/>"
        "<text x='876' y='27'>load15</text>"
        "<rect x='930' y='18' width='10' height='10' fill='#7c3aed'/>"
        "<text x='946' y='27'>jobs</text>"
        "</g>"
    )

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}">
  <rect width="100%" height="100%" fill="white"/>
  {_axis_labels("Builder Load and Job Pressure", f"{len(samples)} builder samples")}
  {legend}
  {''.join(grid)}
  <line x1="{left}" y1="{top + plot_height}" x2="{left + plot_width}" y2="{top + plot_height}" stroke="#111"/>
  <line x1="{left}" y1="{top}" x2="{left}" y2="{top + plot_height}" stroke="#111"/>
  <polyline fill="none" stroke="#dc2626" stroke-width="2" points="{_chart_points(load1_points)}"/>
  <polyline fill="none" stroke="#2563eb" stroke-width="2" points="{_chart_points(load5_points)}"/>
  <polyline fill="none" stroke="#16a34a" stroke-width="2" points="{_chart_points(load15_points)}"/>
  <polyline fill="none" stroke="#7c3aed" stroke-width="2" stroke-dasharray="4 3" points="{_chart_points(running_points)}"/>
</svg>
"""
    path.write_text(svg, encoding="utf-8")


def render_html_report(
    path: pathlib.Path,
    summary: dict[str, object],
    burndown_name: str,
    load_name: str,
    emerge_csv_name: str,
    builder_csv_name: str | None,
) -> None:
    latest_builder = summary.get("latest_builder") or {}
    html_text = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Build Metrics Report</title>
  <style>
    body {{ font-family: sans-serif; margin: 24px; color: #111827; }}
    h1, h2 {{ margin-bottom: 0.3rem; }}
    .stats {{ display: grid; grid-template-columns: repeat(4, minmax(180px, 1fr)); gap: 12px; }}
    .card {{ border: 1px solid #d1d5db; border-radius: 8px; padding: 12px; }}
    .label {{ color: #6b7280; font-size: 0.9rem; }}
    img {{ max-width: 100%; border: 1px solid #d1d5db; border-radius: 8px; }}
    code {{ background: #f3f4f6; padding: 2px 4px; border-radius: 4px; }}
  </style>
</head>
<body>
  <h1>Build Metrics Report</h1>
  <p>Generated from <code>emerge.log</code> and builder output.</p>
  <div class="stats">
    <div class="card"><div class="label">Packages</div><div>{summary['completed_packages']} / {summary['total_packages']}</div></div>
    <div class="card"><div class="label">Completed</div><div>{summary['completed_percent_by_count']}%</div></div>
    <div class="card"><div class="label">Duration</div><div>{summary['duration_seconds']}s</div></div>
    <div class="card"><div class="label">Latest Load1</div><div>{latest_builder.get('load1', 'n/a')}</div></div>
  </div>
  <h2>Burn-down</h2>
  <img src="{html.escape(burndown_name)}" alt="Package burn-down chart">
  <h2>Builder Load</h2>
  <img src="{html.escape(load_name)}" alt="Builder load chart">
  <h2>Artifacts</h2>
  <ul>
    <li><a href="{html.escape(emerge_csv_name)}">{html.escape(emerge_csv_name)}</a></li>
    {f"<li><a href='{html.escape(builder_csv_name)}'>{html.escape(builder_csv_name)}</a></li>" if builder_csv_name else ""}
    <li><a href="summary.json">summary.json</a></li>
  </ul>
</body>
</html>
"""
    path.write_text(html_text, encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emerge-log", required=True, help="Path to emerge.log")
    parser.add_argument("--builder-log", help="Path to builder progress log")
    parser.add_argument("--output-dir", required=True, help="Directory for exported files")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    emerge_path = pathlib.Path(args.emerge_log)
    output_dir = pathlib.Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    emerge_events = parse_emerge_log(emerge_path)
    if not emerge_events:
        raise SystemExit(f"no parseable emerge events found in {emerge_path}")

    builder_samples: list[BuilderSample] = []
    if args.builder_log:
        builder_path = pathlib.Path(args.builder_log)
        fallback_ts = emerge_events[0].ts if emerge_events else None
        builder_samples = parse_builder_log(builder_path, fallback_ts)

    summary = summarize(emerge_events, builder_samples)
    emerge_csv_name = "emerge-events.csv"
    builder_csv_name = "builder-samples.csv" if builder_samples else None
    burndown_name = "burndown.svg"
    load_name = "builder-load.svg"

    write_emerge_csv(output_dir / emerge_csv_name, emerge_events)
    if builder_samples:
        write_builder_csv(output_dir / builder_csv_name, builder_samples)

    completed_events = [event for event in emerge_events if event.event == "complete"]
    render_burndown_svg(output_dir / burndown_name, completed_events)
    render_load_svg(output_dir / load_name, builder_samples)

    (output_dir / "summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    render_html_report(
        output_dir / "report.html",
        summary,
        burndown_name,
        load_name,
        emerge_csv_name,
        builder_csv_name,
    )
    print(output_dir / "report.html")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
