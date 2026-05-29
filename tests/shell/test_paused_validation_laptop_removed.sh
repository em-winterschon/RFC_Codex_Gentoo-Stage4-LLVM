#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
needle="chon""kers"

if rg -n -i "${needle}" "${ROOT_DIR}"; then
  echo "paused validation laptop references must stay removed until re-inventoried" >&2
  exit 1
fi

echo "Paused validation laptop reference checks passed."
