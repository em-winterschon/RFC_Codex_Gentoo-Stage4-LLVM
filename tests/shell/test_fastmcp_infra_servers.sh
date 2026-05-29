#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PYTHONPATH="${REPO_ROOT}/scripts/mcp_servers" python3 - << 'PY'
import json
import os
import tempfile
from pathlib import Path

from rfc1918_mcp_common.audit import write_audit_artifact
from rfc1918_mcp_common.gates import MutationGate, MutationRejected
from rfc1918_mcp_common.settings import ServiceSettings
import forge_memory_mcp
import netbox_mcp


disabled = MutationGate.from_env({})
try:
    disabled.require("netbox_apply_host_record", "idem-001", "test apply")
except MutationRejected as exc:
    assert "disabled" in str(exc)
else:
    raise AssertionError("disabled mutation gate did not reject apply")

enabled = MutationGate.from_env({"MCP_ALLOW_MUTATIONS": "true"})
try:
    enabled.require("netbox_apply_host_record", "", "test apply")
except MutationRejected as exc:
    assert "idempotency" in str(exc)
else:
    raise AssertionError("enabled mutation gate allowed missing idempotency key")

settings = ServiceSettings.from_env(
    {
        "MCP_SERVICE_NAME": "netbox-mcp",
        "NETBOX_URL": "https://netbox.rfc1918.host",
        "NETBOX_TOKEN_FILE": "/run/secrets/netbox-token",
    }
)
safe_settings = settings.to_safe_dict()
assert safe_settings["service_name"] == "netbox-mcp"
assert safe_settings["token_file"] == "/run/secrets/netbox-token"
assert "token_value" not in safe_settings

with tempfile.TemporaryDirectory() as tmpdir:
    artifact = write_audit_artifact(
        Path(tmpdir),
        service="netbox-mcp",
        operation="netbox_apply_host_record",
        idempotency_key="idem-002",
        payload={"hostname": "host-a.rfc1918.host"},
    )
    assert artifact.exists()
    data = json.loads(artifact.read_text(encoding="utf-8"))
    assert data["service"] == "netbox-mcp"
    assert data["idempotency_key"] == "idem-002"

tool_names = {tool["name"] for tool in netbox_mcp.TOOL_MANIFEST}
assert "netbox_get_device" in tool_names
assert "netbox_plan_host_record" in tool_names
assert "netbox_apply_host_record" in tool_names
assert not any("shell" in name or "exec" in name for name in tool_names)

plan = netbox_mcp.plan_host_record(
    hostname="host-a.rfc1918.host",
    site="SUN99",
    primary_ip="172.16.99.123/24",
    role="workstation",
)
assert plan["mutation"] is False
assert plan["hostname"] == "host-a.rfc1918.host"
assert plan["primary_ip"] == "172.16.99.123/24"
assert plan["proposed_actions"] == [
    "ensure_device",
    "ensure_primary_interface",
    "ensure_primary_ip",
    "bind_primary_ip_to_device",
]

try:
    netbox_mcp.apply_host_record(
        plan=plan,
        env=os.environ,
        idempotency_key="",
        audit_dir=Path(tempfile.gettempdir()),
    )
except MutationRejected:
    pass
else:
    raise AssertionError("NetBox apply did not require mutation gate")

forge_tools = {tool["name"]: tool["mode"] for tool in forge_memory_mcp.TOOL_MANIFEST}
assert forge_tools["memory_append_event"] == "apply"
assert forge_tools["memory_get_session_summary"] == "read"
assert forge_tools["memory_list_recent_sessions"] == "read"
assert forge_tools["memory_search_artifact_refs"] == "read"
assert forge_tools["memory_render_eod_context"] == "read"
assert not any("shell" in name or "exec" in name for name in forge_tools)

with tempfile.TemporaryDirectory() as tmpdir:
    spool_root = Path(tmpdir) / "spool"
    audit_dir = Path(tmpdir) / "audit"
    env = {
        "MCP_SERVICE_NAME": "forge-memory-mcp",
        "FORGE_MEMORY_SPOOL_ROOT": str(spool_root),
        "MCP_AUDIT_DIR": str(audit_dir),
    }
    try:
        forge_memory_mcp.append_event(
            session_id="session-mcp-001",
            event_type="checkpoint",
            intent="mcp facade mutation gate test",
            actions=["attempt-write"],
            artifacts=["issue:115"],
            notes=["blocked write"],
            env=env,
            idempotency_key="",
        )
    except MutationRejected:
        pass
    else:
        raise AssertionError("Forge memory append did not require mutation gate")

    write_result = forge_memory_mcp.append_event(
        session_id="session-mcp-001",
        event_type="checkpoint",
        intent="mcp facade append",
        actions=["write-memory-event"],
        artifacts=["issue:115"],
        notes=["allowed write"],
        env={**env, "MCP_ALLOW_MUTATIONS": "true"},
        idempotency_key="idem-forge-memory-001",
        audit_comment="append Forge memory event from MCP facade",
    )
    assert write_result["tool"] == "memory_append_event"
    assert write_result["mutation"] is True
    assert write_result["spool_result"]["event_count"] == 1
    assert Path(write_result["spool_result"]["event_file"]).exists()
    assert Path(write_result["audit_artifact"]).exists()

    sessions = forge_memory_mcp.list_recent_sessions(agent_id="forge", limit=5, env=env)
    assert sessions["tool"] == "memory_list_recent_sessions"
    assert sessions["mutation"] is False
    assert sessions["summary"]["session_count"] == 1

    session_summary = forge_memory_mcp.get_session_summary(
        session_id="session-mcp-001",
        agent_id="forge",
        env=env,
    )
    assert session_summary["tool"] == "memory_get_session_summary"
    assert session_summary["session"]["event_count"] == 1
    assert session_summary["session"]["last_intent"] == "mcp facade append"

    search = forge_memory_mcp.search_artifact_refs("issue:115", agent_id="forge", env=env)
    assert search["tool"] == "memory_search_artifact_refs"
    assert search["match_count"] == 1
    assert search["matches"][0]["session_id"] == "session-mcp-001"

    eod = forge_memory_mcp.render_eod_context(agent_id="forge", env=env, limit=3)
    assert eod["tool"] == "memory_render_eod_context"
    assert "session-mcp-001" in eod["markdown"]
    assert "mcp facade append" in eod["markdown"]
PY

printf 'PASS: %s\n' "$(basename "$0")"
