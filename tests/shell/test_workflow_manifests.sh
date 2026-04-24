#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

python3 - <<'PY' "${REPO_ROOT}"
import json
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
workflow_dir = repo_root / "docs" / "workflows"
files = sorted(workflow_dir.glob("*.json"))
if not files:
    raise SystemExit("no workflow manifests found")

required_top = {"apiVersion", "kind", "metadata", "variables", "stages"}
required_stage = {"id", "summary", "cwd", "command", "expectedExitCodes"}

for path in files:
    payload = json.loads(path.read_text(encoding="utf-8"))
    missing_top = required_top - payload.keys()
    if missing_top:
        raise SystemExit(f"{path}: missing top-level keys: {sorted(missing_top)}")
    if payload["kind"] != "WorkflowManifest":
        raise SystemExit(f"{path}: unexpected kind {payload['kind']!r}")
    if not isinstance(payload["variables"], list):
        raise SystemExit(f"{path}: variables must be a list")
    if not isinstance(payload["stages"], list) or not payload["stages"]:
        raise SystemExit(f"{path}: stages must be a non-empty list")
    for stage in payload["stages"]:
        missing_stage = required_stage - stage.keys()
        if missing_stage:
            raise SystemExit(f"{path}: stage missing keys {sorted(missing_stage)}")
        if not isinstance(stage["command"], list) or not stage["command"]:
            raise SystemExit(f"{path}: stage {stage['id']} command must be a non-empty list")
        if not isinstance(stage["expectedExitCodes"], list) or not all(isinstance(code, int) for code in stage["expectedExitCodes"]):
            raise SystemExit(f"{path}: stage {stage['id']} expectedExitCodes must be a list of ints")

print("PASS: test_workflow_manifests.sh")
PY
