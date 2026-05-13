"""Audit artifact helpers for infrastructure MCP services."""

from __future__ import annotations

import json
import re
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

_SAFE_NAME = re.compile(r"[^A-Za-z0-9_.-]+")


def _safe_fragment(value: str) -> str:
    return _SAFE_NAME.sub("_", value.strip())[:96] or "unset"


def write_audit_artifact(
    audit_dir: Path,
    *,
    service: str,
    operation: str,
    idempotency_key: str,
    payload: dict[str, Any],
) -> Path:
    audit_dir.mkdir(parents=True, exist_ok=True)
    now = datetime.now(UTC)
    document = {
        "timestamp_utc": now.isoformat(),
        "service": service,
        "operation": operation,
        "idempotency_key": idempotency_key,
        "payload": payload,
    }
    filename = (
        f"{now.strftime('%Y%m%dT%H%M%SZ')}-"
        f"{_safe_fragment(service)}-"
        f"{_safe_fragment(operation)}-"
        f"{_safe_fragment(idempotency_key)}.json"
    )
    path = audit_dir / filename
    path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path
