"""Environment-backed MCP service settings."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ServiceSettings:
    """Shared settings loaded from environment without materializing secrets."""

    service_name: str
    backend_url: str
    token_file: Path | None = None
    audit_dir: Path = Path("/var/log/rfc1918-mcp/audit")

    @classmethod
    def from_env(
        cls,
        env: Mapping[str, str],
        *,
        service_default: str = "rfc1918-mcp",
        backend_url_var: str = "NETBOX_URL",
        token_file_var: str = "NETBOX_TOKEN_FILE",
    ) -> ServiceSettings:
        token_file = env.get(token_file_var, "").strip()
        audit_dir = env.get("MCP_AUDIT_DIR", "").strip()
        return cls(
            service_name=env.get("MCP_SERVICE_NAME", service_default).strip() or service_default,
            backend_url=env.get(backend_url_var, "").strip(),
            token_file=Path(token_file) if token_file else None,
            audit_dir=Path(audit_dir) if audit_dir else Path("/var/log/rfc1918-mcp/audit"),
        )

    def to_safe_dict(self) -> dict[str, str]:
        data = {
            "service_name": self.service_name,
            "backend_url": self.backend_url,
            "audit_dir": str(self.audit_dir),
        }
        if self.token_file is not None:
            data["token_file"] = str(self.token_file)
        return data
