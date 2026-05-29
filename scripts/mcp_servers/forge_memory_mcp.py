"""Allowlisted Forge memory MCP facade.

The module is importable without FastMCP so repository tests can validate the
tool contract on hosts where the runtime dependency is not installed yet.
"""

from __future__ import annotations

import os
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from rfc1918_mcp_common.audit import write_audit_artifact
from rfc1918_mcp_common.gates import MutationGate
from rfc1918_mcp_common.settings import ServiceSettings

try:  # pragma: no cover - optional runtime dependency
    from fastmcp import FastMCP
except ImportError:  # pragma: no cover - expected in lightweight repo tests
    FastMCP = None  # type: ignore[assignment]

_SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

import forge_memory_spool  # noqa: E402

TOOL_MANIFEST = [
    {"name": "memory_append_event", "mode": "apply"},
    {"name": "memory_get_session_summary", "mode": "read"},
    {"name": "memory_list_recent_sessions", "mode": "read"},
    {"name": "memory_search_artifact_refs", "mode": "read"},
    {"name": "memory_render_eod_context", "mode": "read"},
]


def _settings(env: Mapping[str, str] | None = None) -> ServiceSettings:
    return ServiceSettings.from_env(env or os.environ, service_default="forge-memory-mcp")


def _spool_root(env: Mapping[str, str] | None = None) -> Path:
    runtime_env = env or os.environ
    return Path(runtime_env.get("FORGE_MEMORY_SPOOL_ROOT", "/var/lib/forge-memory/spool"))


def _event_file(spool_root: Path, agent_id: str, session_id: str) -> Path:
    return spool_root / "agents" / agent_id / "sessions" / session_id / "events.jsonl"


def _read_events(spool_root: Path, agent_id: str, session_id: str) -> list[dict[str, Any]]:
    return forge_memory_spool.read_jsonl_events(_event_file(spool_root, agent_id, session_id))


def append_event(
    *,
    session_id: str,
    event_type: str,
    intent: str,
    actions: Sequence[str] | None = None,
    artifacts: Sequence[str] | None = None,
    notes: Sequence[str] | None = None,
    repo: str = "",
    branch: str = "",
    commit: str = "",
    agent_id: str = "forge",
    env: Mapping[str, str] | None = None,
    idempotency_key: str,
    audit_comment: str = "append Forge memory event",
) -> dict[str, Any]:
    runtime_env = env or os.environ
    settings = _settings(runtime_env)
    MutationGate.from_env(runtime_env).require(
        "memory_append_event",
        idempotency_key,
        audit_comment,
    )
    spool_root = _spool_root(runtime_env)
    args = forge_memory_spool.argparse.Namespace(
        spool_root=str(spool_root),
        agent_id=agent_id,
        session_id=session_id,
        repo=repo,
        branch=branch,
        commit=commit,
        event_type=event_type,
        intent=intent,
        action=list(actions or []),
        artifact=list(artifacts or []),
        note=list(notes or []),
        extra_json=None,
    )
    result = forge_memory_spool.append_event(args)
    artifact = write_audit_artifact(
        settings.audit_dir,
        service=settings.service_name,
        operation="memory_append_event",
        idempotency_key=idempotency_key,
        payload={
            "audit_comment": audit_comment,
            "session_id": session_id,
            "agent_id": agent_id,
            "event_type": event_type,
            "intent": intent,
            "actions": list(actions or []),
            "artifacts": list(artifacts or []),
        },
    )
    return {
        "tool": "memory_append_event",
        "mutation": True,
        "spool_result": result,
        "audit_artifact": str(artifact),
    }


def list_recent_sessions(
    *,
    agent_id: str = "forge",
    limit: int = 10,
    env: Mapping[str, str] | None = None,
) -> dict[str, Any]:
    args = forge_memory_spool.argparse.Namespace(
        spool_root=str(_spool_root(env)),
        agent_id=agent_id,
        limit=limit,
    )
    return {
        "tool": "memory_list_recent_sessions",
        "mutation": False,
        "summary": forge_memory_spool.list_sessions(args),
    }


def get_session_summary(
    *,
    session_id: str,
    agent_id: str = "forge",
    env: Mapping[str, str] | None = None,
) -> dict[str, Any]:
    spool_root = _spool_root(env)
    event_path = _event_file(spool_root, agent_id, session_id)
    events = _read_events(spool_root, agent_id, session_id)
    manifest_files = forge_memory_spool.manifest_files_for(spool_root, session_id)
    last_event = events[-1] if events else {}
    return {
        "tool": "memory_get_session_summary",
        "mutation": False,
        "session": {
            "session_id": session_id,
            "agent_id": agent_id,
            "event_file": str(event_path),
            "event_count": len(events),
            "event_sha256": (
                forge_memory_spool.sha256_file(event_path) if event_path.exists() else ""
            ),
            "last_timestamp_utc": str(last_event.get("timestamp_utc", "")),
            "last_event_type": str(last_event.get("event_type", "")),
            "last_intent": str(last_event.get("intent", "")),
            "closed": bool(manifest_files),
            "manifest_files": manifest_files,
        },
    }


def search_artifact_refs(
    query: str,
    *,
    agent_id: str = "forge",
    env: Mapping[str, str] | None = None,
    limit: int = 20,
) -> dict[str, Any]:
    spool_root = _spool_root(env)
    sessions_root = spool_root / "agents" / agent_id / "sessions"
    matches: list[dict[str, Any]] = []
    if sessions_root.exists():
        for event_path in sorted(sessions_root.glob("*/events.jsonl")):
            for event in forge_memory_spool.read_jsonl_events(event_path):
                artifacts = [str(item) for item in event.get("artifacts", [])]
                notes = [str(item) for item in event.get("notes", [])]
                if any(query in item for item in artifacts + notes):
                    matches.append(
                        {
                            "session_id": str(event.get("session_id", event_path.parent.name)),
                            "event_type": str(event.get("event_type", "")),
                            "intent": str(event.get("intent", "")),
                            "artifacts": artifacts,
                            "notes": notes,
                            "event_file": str(event_path),
                        }
                    )
                if len(matches) >= limit:
                    break
            if len(matches) >= limit:
                break
    return {
        "tool": "memory_search_artifact_refs",
        "mutation": False,
        "query": query,
        "match_count": len(matches),
        "matches": matches,
    }


def render_eod_context(
    *,
    agent_id: str = "forge",
    env: Mapping[str, str] | None = None,
    limit: int = 10,
) -> dict[str, Any]:
    sessions = list_recent_sessions(agent_id=agent_id, limit=limit, env=env)["summary"]["sessions"]
    lines = [f"# Forge Memory Context: {agent_id}", ""]
    for session in sessions:
        lines.append(
            f"- `{session['session_id']}`: {session['last_event_type']} - "
            f"{session['last_intent']} ({session['event_count']} events)"
        )
    return {
        "tool": "memory_render_eod_context",
        "mutation": False,
        "markdown": "\n".join(lines) + "\n",
    }


def build_mcp() -> Any:
    if FastMCP is None:
        raise RuntimeError("fastmcp is required to run the Forge memory MCP server")

    mcp = FastMCP("RFC1918 Forge Memory MCP")

    @mcp.tool
    def memory_list_recent_sessions(agent_id: str = "forge", limit: int = 10) -> dict[str, Any]:
        return list_recent_sessions(agent_id=agent_id, limit=limit)

    @mcp.tool
    def memory_get_session_summary(session_id: str, agent_id: str = "forge") -> dict[str, Any]:
        return get_session_summary(session_id=session_id, agent_id=agent_id)

    @mcp.tool
    def memory_search_artifact_refs(
        query: str, agent_id: str = "forge", limit: int = 20
    ) -> dict[str, Any]:
        return search_artifact_refs(query, agent_id=agent_id, limit=limit)

    @mcp.tool
    def memory_render_eod_context(agent_id: str = "forge", limit: int = 10) -> dict[str, Any]:
        return render_eod_context(agent_id=agent_id, limit=limit)

    @mcp.tool
    def memory_append_event(
        session_id: str,
        event_type: str,
        intent: str,
        idempotency_key: str,
        actions: list[str] | None = None,
        artifacts: list[str] | None = None,
        notes: list[str] | None = None,
        audit_comment: str = "append Forge memory event",
    ) -> dict[str, Any]:
        return append_event(
            session_id=session_id,
            event_type=event_type,
            intent=intent,
            actions=actions,
            artifacts=artifacts,
            notes=notes,
            idempotency_key=idempotency_key,
            audit_comment=audit_comment,
        )

    return mcp


if FastMCP is not None:  # pragma: no cover - depends on optional runtime package
    mcp = build_mcp()
else:
    mcp = None


if __name__ == "__main__":  # pragma: no cover - runtime entrypoint
    if mcp is None:
        raise SystemExit("fastmcp is required to run the Forge memory MCP server")
    mcp.run()
