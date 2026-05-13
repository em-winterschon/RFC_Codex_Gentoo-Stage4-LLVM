#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PYTHONPATH="${REPO_ROOT}/scripts/mcp_servers" python3 - <<'PY'
import json
import os
import tempfile
from pathlib import Path

from rfc1918_mcp_common.audit import write_audit_artifact
from rfc1918_mcp_common.gates import MutationGate, MutationRejected
from rfc1918_mcp_common.settings import ServiceSettings
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
PY

printf 'PASS: %s\n' "$(basename "$0")"
