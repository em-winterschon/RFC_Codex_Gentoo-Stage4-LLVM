#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/validate-agent-rules.py"
HASH_FILE="${REPO_ROOT}/policy/agentsys/AGENTS.md.sha256"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    printf 'FAIL: required file missing: %s\n' "${path}" >&2
    exit 1
  fi
}

require_file "${VALIDATOR}"
require_file "${HASH_FILE}"
require_file "${REPO_ROOT}/AGENTS.md"

python3 "${VALIDATOR}" validate \
  --target "${REPO_ROOT}/AGENTS.md" \
  --expected-sha256-file "${HASH_FILE}" > /dev/null

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

cat > "${tmpdir}/canonical-AGENTS.md" << 'EOF'
# Agent Rules

Canonical test payload.
EOF

cat > "${tmpdir}/stale-AGENTS.md" << 'EOF'
# Agent Rules

Stale test payload.
EOF

python3 "${VALIDATOR}" sync \
  --target "${tmpdir}/stale-AGENTS.md" \
  --source "${tmpdir}/canonical-AGENTS.md" \
  --expected-sha256-file "${tmpdir}/AGENTS.md.sha256" \
  --update-expected-sha256 > /dev/null

cmp -s "${tmpdir}/canonical-AGENTS.md" "${tmpdir}/stale-AGENTS.md"

python3 "${VALIDATOR}" validate \
  --target "${tmpdir}/stale-AGENTS.md" \
  --source "${tmpdir}/canonical-AGENTS.md" \
  --expected-sha256-file "${tmpdir}/AGENTS.md.sha256" > /dev/null

cat > "${tmpdir}/bad-hash" << 'EOF'
0000000000000000000000000000000000000000000000000000000000000000  AGENTS.md
EOF

if python3 "${VALIDATOR}" validate \
  --target "${tmpdir}/stale-AGENTS.md" \
  --expected-sha256-file "${tmpdir}/bad-hash" > /dev/null 2>&1; then
  printf 'FAIL: validator accepted mismatched hash\n' >&2
  exit 1
fi

printf 'PASS: %s\n' "$(basename "$0")"
