"""Allowlisted NetBox MCP wrapper scaffold.

The module is importable without FastMCP so repository tests can validate the
tool contract on hosts where the runtime dependency is not installed yet.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Mapping

from rfc1918_mcp_common.audit import write_audit_artifact
from rfc1918_mcp_common.gates import MutationGate
from rfc1918_mcp_common.settings import ServiceSettings

try:  # pragma: no cover - optional runtime dependency
    from fastmcp import FastMCP
except ImportError:  # pragma: no cover - expected in lightweight repo tests
    FastMCP = None  # type: ignore[assignment]


TOOL_MANIFEST = [
    {"name": "netbox_get_device", "mode": "read"},
    {"name": "netbox_get_ip_address", "mode": "read"},
    {"name": "netbox_search_inventory", "mode": "read"},
    {"name": "netbox_validate_dns_ipam", "mode": "read"},
    {"name": "netbox_plan_host_record", "mode": "plan"},
    {"name": "netbox_plan_interface_record", "mode": "plan"},
    {"name": "netbox_plan_service_ip", "mode": "plan"},
    {"name": "netbox_apply_host_record", "mode": "apply"},
    {"name": "netbox_apply_dns_ipam_reconciliation", "mode": "apply"},
]


def _settings(env: Mapping[str, str] | None = None) -> ServiceSettings:
    return ServiceSettings.from_env(env or os.environ, service_default="netbox-mcp")


def get_device(name: str, env: Mapping[str, str] | None = None) -> dict[str, Any]:
    settings = _settings(env)
    return {
        "tool": "netbox_get_device",
        "mutation": False,
        "backend_url": settings.backend_url,
        "name": name,
        "implemented": False,
        "next_step": "wire pynetbox client read path",
    }


def plan_host_record(
    *,
    hostname: str,
    site: str,
    primary_ip: str,
    role: str,
) -> dict[str, Any]:
    return {
        "tool": "netbox_plan_host_record",
        "mutation": False,
        "hostname": hostname,
        "site": site,
        "primary_ip": primary_ip,
        "role": role,
        "proposed_actions": [
            "ensure_device",
            "ensure_primary_interface",
            "ensure_primary_ip",
            "bind_primary_ip_to_device",
        ],
    }


def apply_host_record(
    *,
    plan: dict[str, Any],
    env: Mapping[str, str] | None = None,
    idempotency_key: str,
    audit_dir: Path | None = None,
    audit_comment: str = "apply NetBox host record plan",
) -> dict[str, Any]:
    runtime_env = env or os.environ
    settings = _settings(runtime_env)
    MutationGate.from_env(runtime_env).require(
        "netbox_apply_host_record",
        idempotency_key,
        audit_comment,
    )
    artifact = write_audit_artifact(
        audit_dir or settings.audit_dir,
        service=settings.service_name,
        operation="netbox_apply_host_record",
        idempotency_key=idempotency_key,
        payload={"audit_comment": audit_comment, "plan": plan},
    )
    return {
        "tool": "netbox_apply_host_record",
        "mutation": True,
        "backend_apply_implemented": False,
        "audit_artifact": str(artifact),
        "next_step": "wire pynetbox client mutation path",
    }


def build_mcp() -> Any:
    if FastMCP is None:
        raise RuntimeError("fastmcp is required to run the NetBox MCP server")

    mcp = FastMCP("RFC1918 NetBox MCP")

    @mcp.tool
    def netbox_get_device(name: str) -> dict[str, Any]:
        return get_device(name)

    @mcp.tool
    def netbox_plan_host_record(
        hostname: str,
        site: str,
        primary_ip: str,
        role: str,
    ) -> dict[str, Any]:
        return plan_host_record(
            hostname=hostname,
            site=site,
            primary_ip=primary_ip,
            role=role,
        )

    @mcp.tool
    def netbox_apply_host_record(
        plan: dict[str, Any],
        idempotency_key: str,
        audit_comment: str = "apply NetBox host record plan",
    ) -> dict[str, Any]:
        return apply_host_record(
            plan=plan,
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
        raise SystemExit("fastmcp is required to run the NetBox MCP server")
    mcp.run()
