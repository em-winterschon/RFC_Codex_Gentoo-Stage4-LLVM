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

python3 - "${event_file}" "${tmpdir}/append.json" <<'PY'
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
! grep -R "must-not-land-in-memory" "${tmpdir}" >/dev/null || fail "secret value leaked into spool"

"${SPOOLER}" closeout \
  --spool-root "${tmpdir}" \
  --session-id "session-night-001" \
  --agent-id "forge" \
  --summary "Nightly continuity checkpoint" \
  > "${tmpdir}/closeout.json"

python3 - "${tmpdir}/closeout.json" "${event_file}" <<'PY'
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

printf 'PASS: %s\n' "$(basename "$0")"
