#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERIAL_SCRIPT="${REPO_ROOT}/scripts/routeros-serial-command.py"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x "${SERIAL_SCRIPT}" ]] || fail "missing executable ${SERIAL_SCRIPT}"
python3 -m py_compile "${SERIAL_SCRIPT}"

python3 - "${SERIAL_SCRIPT}" <<'PY'
import importlib.util
import sys
from pathlib import Path

script = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("routeros_serial_command", script)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

assert module.TERMINAL_ANSWERBACK == b"\x1b[?1;0c"
assert module.needs_terminal_answerback(b"abc\x1bZdef") is True
assert module.needs_terminal_answerback(b"abc") is False

redacted = module.sanitize_transcript("Password: super-secret\nok", "super-secret")
assert "super-secret" not in redacted
assert "<redacted>" in redacted
PY

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
