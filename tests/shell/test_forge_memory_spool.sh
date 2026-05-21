#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SPOOLER="${REPO_ROOT}/scripts/forge_memory_spool.py"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test -f "${SPOOLER}" || fail "missing ${SPOOLER}"
python3 -m py_compile "${SPOOLER}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

"${SPOOLER}" append-event \
  --spool-root "${tmpdir}" \
  --session-id "session-night-001" \
  --agent-id "forge" \
  --repo "RFC_Codex_Gentoo-Stage4-LLVM" \
  --branch "codex/container-services-delta" \
  --commit "deadbeef" \
  --event-type "session-start" \
  --intent "recover-continuity" \
  --action "normalize-github-issues" \
  --artifact "issue:115" \
  --note "local write-ahead spool smoke test" \
  > "${tmpdir}/append.json"

event_file="${tmpdir}/agents/forge/sessions/session-night-001/events.jsonl"
test -f "${event_file}" || fail "missing event log"

python3 - "${event_file}" "${tmpdir}/append.json" << 'PY'
import json
import sys
from pathlib import Path

event_file = Path(sys.argv[1])
append_result = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
lines = event_file.read_text(encoding="utf-8").splitlines()
assert len(lines) == 1
event = json.loads(lines[0])
assert event["schema"] == "rfc-codex.forge-memory-event.v1"
assert event["session_id"] == "session-night-001"
assert event["agent_id"] == "forge"
assert event["repo"] == "RFC_Codex_Gentoo-Stage4-LLVM"
assert event["branch"] == "codex/container-services-delta"
assert event["commit"] == "deadbeef"
assert event["event_type"] == "session-start"
assert event["intent"] == "recover-continuity"
assert event["actions"] == ["normalize-github-issues"]
assert event["artifacts"] == ["issue:115"]
assert event["notes"] == ["local write-ahead spool smoke test"]
assert event["host"]
assert event["timestamp_utc"].endswith("Z")
assert append_result["event_file"] == str(event_file)
assert append_result["event_count"] == 1
PY

if "${SPOOLER}" append-event \
  --spool-root "${tmpdir}" \
  --session-id "session-night-001" \
  --agent-id "forge" \
  --event-type "bad-secret" \
  --extra-json '{"api_token":"must-not-land-in-memory"}' \
  > "${tmpdir}/secret.stdout" 2> "${tmpdir}/secret.stderr"; then
  fail "secret-looking payload was accepted"
fi
grep -qi 'secret' "${tmpdir}/secret.stderr" || fail "secret rejection did not explain the cause"
! grep -R "must-not-land-in-memory" "${tmpdir}" > /dev/null || fail "secret value leaked into spool"

"${SPOOLER}" closeout \
  --spool-root "${tmpdir}" \
  --session-id "session-night-001" \
  --agent-id "forge" \
  --summary "Nightly continuity checkpoint" \
  > "${tmpdir}/closeout.json"

python3 - "${tmpdir}/closeout.json" "${event_file}" << 'PY'
import hashlib
import json
import sys
from pathlib import Path

closeout = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
event_file = Path(sys.argv[2])
manifest = Path(closeout["manifest_file"])
assert manifest.exists()
data = json.loads(manifest.read_text(encoding="utf-8"))
assert data["schema"] == "rfc-codex.forge-memory-manifest.v1"
assert data["session_id"] == "session-night-001"
assert data["agent_id"] == "forge"
assert data["event_count"] == 1
assert data["event_file"] == str(event_file)
assert data["event_sha256"] == hashlib.sha256(event_file.read_bytes()).hexdigest()
assert data["summary"] == "Nightly continuity checkpoint"
assert data["signature_state"] == "unsigned"
assert data["closed_at_utc"].endswith("Z")
assert closeout["event_count"] == 1
PY

printf 'manifest-signing-test-key' > "${tmpdir}/signing.key"
"${SPOOLER}" closeout \
  --spool-root "${tmpdir}" \
  --session-id "session-signed-001" \
  --agent-id "forge" \
  --summary "Signed continuity checkpoint" \
  --signing-key-file "${tmpdir}/signing.key" \
  --signing-key-id "test-hmac-key" \
  > "${tmpdir}/signed-closeout.json"

python3 - "${tmpdir}/signed-closeout.json" << 'PY'
import hashlib
import hmac
import json
import sys
from pathlib import Path

closeout = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
manifest = Path(closeout["manifest_file"])
data = json.loads(manifest.read_text(encoding="utf-8"))
signature_payload = data["signature_payload"]
expected_signature = hmac.new(
    b"manifest-signing-test-key",
    signature_payload.encode("utf-8"),
    hashlib.sha256,
).hexdigest()

assert data["schema"] == "rfc-codex.forge-memory-manifest.v1"
assert data["session_id"] == "session-signed-001"
assert data["signature_state"] == "signed"
assert data["signature"]["algorithm"] == "hmac-sha256"
assert data["signature"]["key_id"] == "test-hmac-key"
assert data["signature"]["value"] == expected_signature
assert data["signature_payload_sha256"] == hashlib.sha256(
    signature_payload.encode("utf-8")
).hexdigest()
assert "manifest-signing-test-key" not in json.dumps(data)
PY

object_store_root="${tmpdir}/object-store"
"${SPOOLER}" publish-session \
  --spool-root "${tmpdir}" \
  --object-store-root "${object_store_root}" \
  --agent-id "forge" \
  --session-id "session-night-001" \
  --prefix "forge-memory/v1" \
  > "${tmpdir}/publish.json"

python3 - "${tmpdir}/publish.json" "${event_file}" "${tmpdir}/closeout.json" "${object_store_root}" << 'PY'
import hashlib
import json
import sys
from pathlib import Path

publish = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
event_file = Path(sys.argv[2])
closeout = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
object_store_root = Path(sys.argv[4])
closeout_manifest = Path(closeout["manifest_file"])
publish_manifest = Path(publish["publish_manifest_file"])

assert publish["schema"] == "rfc-codex.forge-object-store-publish.v1"
assert publish["session_id"] == "session-night-001"
assert publish["agent_id"] == "forge"
assert publish["backend"] == "filesystem"
assert publish["object_store_root"] == str(object_store_root)
assert publish["prefix"] == "forge-memory/v1"
assert publish["object_count"] == 2
assert publish_manifest.exists()
assert publish_manifest.read_text(encoding="utf-8").endswith("\n")

objects_by_kind = {item["kind"]: item for item in publish["objects"]}
event_object = objects_by_kind["event-log"]
manifest_object = objects_by_kind["closeout-manifest"]

assert event_object["source_file"] == str(event_file)
assert event_object["object_key"] == "forge-memory/v1/agents/forge/sessions/session-night-001/events.jsonl"
assert Path(event_object["object_file"]).read_bytes() == event_file.read_bytes()
assert event_object["sha256"] == hashlib.sha256(event_file.read_bytes()).hexdigest()
assert event_object["size_bytes"] == event_file.stat().st_size

assert manifest_object["source_file"] == str(closeout_manifest)
assert manifest_object["object_key"].startswith("forge-memory/v1/manifests/")
assert manifest_object["object_key"].endswith("/session-night-001.json")
assert Path(manifest_object["object_file"]).read_bytes() == closeout_manifest.read_bytes()
assert manifest_object["sha256"] == hashlib.sha256(closeout_manifest.read_bytes()).hexdigest()
assert manifest_object["size_bytes"] == closeout_manifest.stat().st_size

stored_publish = json.loads(publish_manifest.read_text(encoding="utf-8"))
assert stored_publish == publish
assert "api_token" not in json.dumps(publish).lower()
PY

if "${SPOOLER}" publish-session \
  --spool-root "${tmpdir}" \
  --object-store-root "${object_store_root}" \
  --agent-id "forge" \
  --session-id "session-night-001" \
  --prefix "forge-memory/v1" \
  > "${tmpdir}/publish-again.stdout" 2> "${tmpdir}/publish-again.stderr"; then
  fail "duplicate publish without overwrite was accepted"
fi
grep -qi 'already exists' "${tmpdir}/publish-again.stderr" ||
  fail "duplicate publish rejection did not explain the cause"

"${SPOOLER}" list-sessions \
  --spool-root "${tmpdir}" \
  --agent-id "forge" \
  --limit 5 \
  > "${tmpdir}/sessions.json"

python3 - "${tmpdir}/sessions.json" "${event_file}" << 'PY'
import json
import sys
from pathlib import Path

sessions = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
event_file = Path(sys.argv[2])
assert sessions["agent_id"] == "forge"
assert sessions["session_count"] == 1
assert len(sessions["sessions"]) == 1
session = sessions["sessions"][0]
assert session["session_id"] == "session-night-001"
assert session["event_count"] == 1
assert session["event_file"] == str(event_file)
assert session["last_event_type"] == "session-start"
assert session["last_intent"] == "recover-continuity"
assert session["closed"] is True
assert len(session["manifest_files"]) == 1
assert session["last_timestamp_utc"].endswith("Z")
assert session["event_sha256"]
PY

repo_dir="${tmpdir}/repo"
mkdir -p "${repo_dir}/docs" "${repo_dir}/project-management"
git -C "${repo_dir}" init -q
git -C "${repo_dir}" config user.email forge@example.invalid
git -C "${repo_dir}" config user.name Forge
cat > "${repo_dir}/docs/EOD-STATUS-2026-05-21.md" << 'EOF'
# EOD 2026-05-21

- SLURM closeout completed.
- Forge memory bootstrap remains active.
EOF
cat > "${repo_dir}/project-management/open-issues.json" << 'EOF'
[
  {"number": 115, "title": "MEM-003: Implement Forge cross-machine continuity bootstrap"},
  {"number": 130, "title": "FMT2-007: Validate R630 front-end and RDMA fabric policy on Arista 7060"}
]
EOF
cat > "${repo_dir}/project-management/blockers.json" << 'EOF'
[
  {"id": "object-store-upload", "status": "open"},
  {"id": "manifest-signing", "status": "open"}
]
EOF
git -C "${repo_dir}" add docs project-management
git -C "${repo_dir}" commit -qm "seed continuity inputs"

"${SPOOLER}" bootstrap-session \
  --spool-root "${tmpdir}" \
  --agent-id "forge" \
  --session-id "session-bootstrap-002" \
  --repo-path "${repo_dir}" \
  --intent "resume cross-machine continuity" \
  --issue-state-file "project-management/open-issues.json" \
  --blocker-state-file "project-management/blockers.json" \
  --memory-note "M70 has the active Forge runtime" \
  > "${tmpdir}/bootstrap.json"

bootstrap_event_file="${tmpdir}/agents/forge/sessions/session-bootstrap-002/events.jsonl"
test -f "${bootstrap_event_file}" || fail "missing bootstrap session event log"

python3 - "${tmpdir}/bootstrap.json" "${bootstrap_event_file}" "${repo_dir}" << 'PY'
import json
import subprocess
import sys
from pathlib import Path

bootstrap = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
event_file = Path(sys.argv[2])
repo_dir = Path(sys.argv[3])
lines = event_file.read_text(encoding="utf-8").splitlines()
assert len(lines) == 1
event = json.loads(lines[0])

assert bootstrap["session_id"] == "session-bootstrap-002"
assert bootstrap["event_count"] == 1
assert bootstrap["bootstrap_summary"]["repo"]["branch"] in {"main", "master"}
assert bootstrap["bootstrap_summary"]["repo"]["commit"] == subprocess.check_output(
    ["git", "-C", str(repo_dir), "rev-parse", "HEAD"], text=True
).strip()
assert event["event_type"] == "session-start"
assert event["intent"] == "resume cross-machine continuity"
assert "continuity-bootstrap" in event["actions"]
assert "repo-state" in event["artifacts"]
assert "memory-state" in event["artifacts"]
assert "issue-state" in event["artifacts"]
assert "blocker-state" in event["artifacts"]

extra = event["extra"]
assert extra["bootstrap_schema"] == "rfc-codex.forge-bootstrap-summary.v1"
assert extra["repo"]["dirty"] is False
assert extra["repo"]["path"] == str(repo_dir)
assert extra["latest_memory_notes"] == ["M70 has the active Forge runtime"]
assert extra["latest_documents"][0]["path"] == "docs/EOD-STATUS-2026-05-21.md"
assert extra["issue_state"]["items"][0]["number"] == 115
assert extra["blocker_state"]["items"][0]["id"] == "object-store-upload"
assert extra["recent_sessions"]["total_session_count"] >= 1
assert "api_token" not in json.dumps(extra).lower()
PY

printf 'PASS: %s\n' "$(basename "$0")"
