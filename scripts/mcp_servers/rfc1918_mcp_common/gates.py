"""Mutation gates for infrastructure MCP services."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping


class MutationRejected(RuntimeError):
    """Raised when a mutation request does not satisfy safety gates."""


@dataclass(frozen=True)
class MutationGate:
    """Opt-in gate shared by all infrastructure MCP apply operations."""

    allow_mutations: bool = False

    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> "MutationGate":
        value = env.get("MCP_ALLOW_MUTATIONS", "").strip().lower()
        return cls(allow_mutations=value in {"1", "true", "yes", "on"})

    def require(self, operation: str, idempotency_key: str, audit_comment: str) -> None:
        if not self.allow_mutations:
            raise MutationRejected(
                f"{operation} rejected: mutations are disabled; set MCP_ALLOW_MUTATIONS=true"
            )
        if not idempotency_key or not idempotency_key.strip():
            raise MutationRejected(f"{operation} rejected: idempotency key is required")
        if not audit_comment or not audit_comment.strip():
            raise MutationRejected(f"{operation} rejected: audit comment is required")
