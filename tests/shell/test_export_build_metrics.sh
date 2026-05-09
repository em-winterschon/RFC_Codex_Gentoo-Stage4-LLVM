#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
EXPORTER="${REPO_ROOT}/scripts/export_build_metrics.py"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q "${pattern}" "${file}" || fail "expected '${pattern}' in ${file}"
}

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

cat > "${temp_dir}/emerge.log" << 'EOF'
1000:  >>> emerge (1 of 2) app-shells/bash-5.2_p37-r1 to /
1001:  === (1 of 2) Compiling/Merging (app-shells/bash-5.2_p37-r1::/var/db/repos/gentoo/app-shells/bash/bash-5.2_p37-r1.ebuild)
1005:  ::: completed emerge (1 of 2) app-shells/bash-5.2_p37-r1 to /
1006:  >>> emerge (2 of 2) sys-devel/gcc-15.2.1_p20260214 to /
1018:  ::: completed emerge (2 of 2) sys-devel/gcc-15.2.1_p20260214 to /
EOF

cat > "${temp_dir}/builder.log" << 'EOF'
>>> Jobs: 0 of 2 complete, 1 running                                Load avg: 1.00, 0.50, 0.25
>>> Emerging (1 of 2) app-shells/bash-5.2_p37-r1::gentoo
>>> Jobs: 1 of 2 complete                                           Load avg: 2.00, 1.00, 0.50
>>> Jobs: 1 of 2 complete, 1 running                                Load avg: 3.00, 1.50, 0.75
>>> Emerging (2 of 2) sys-devel/gcc-15.2.1_p20260214::gentoo
>>> Jobs: 2 of 2 complete                                           Load avg: 4.00, 2.00, 1.00
EOF

python3 "${EXPORTER}" \
  --emerge-log "${temp_dir}/emerge.log" \
  --builder-log "${temp_dir}/builder.log" \
  --output-dir "${temp_dir}/out" \
  > /dev/null

test -f "${temp_dir}/out/report.html" || fail "missing HTML report"
test -f "${temp_dir}/out/summary.json" || fail "missing summary"
test -f "${temp_dir}/out/emerge-events.csv" || fail "missing emerge CSV"
test -f "${temp_dir}/out/builder-samples.csv" || fail "missing builder CSV"
test -f "${temp_dir}/out/burndown.svg" || fail "missing burndown SVG"
test -f "${temp_dir}/out/builder-load.svg" || fail "missing load SVG"

assert_file_contains "${temp_dir}/out/summary.json" '"completed_packages": 2'
assert_file_contains "${temp_dir}/out/summary.json" '"total_packages": 2'
assert_file_contains "${temp_dir}/out/report.html" 'Build Metrics Report'

printf 'PASS: %s\n' "$(basename "$0")"
