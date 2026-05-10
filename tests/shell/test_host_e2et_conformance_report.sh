#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORTER="${REPO_ROOT}/scripts/host_e2et_conformance.py"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected '${needle}'"
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  test -f "${file}" || fail "missing file ${file}"
  grep -q -- "${pattern}" "${file}" || fail "expected '${pattern}' in ${file}"
}

test -f "${REPORTER}"
python3 -m py_compile "${REPORTER}"

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

manifest="${temp_dir}/k10-e2et.json"
json_report="${temp_dir}/report.json"
md_report="${temp_dir}/report.md"
junit_report="${temp_dir}/report.xml"

cat > "${manifest}" << 'EOF'
{
  "run": {
    "id": "k10-aaa-reboot-check",
    "phase": "post-reboot",
    "timestamp": "2026-05-10T02:00:00-07:00"
  },
  "host": {
    "name": "gmktek_nucbox_k10_stage5_candidate",
    "fqdn": "gmktek-k10-stage5.rfc1918.host",
    "profile": "stage4-lox__stage5-workstation-nscde__amd64__gpu-universal-xorg"
  },
  "baseline": {
    "name": "RFC99 workstation AAA reboot durability",
    "target_tier": "p90"
  },
  "gates": [
    {
      "name": "Inventory Gate",
      "weight": 10,
      "hard_required": true,
      "checks": [
        {
          "name": "NetBox and Ansible identity agree",
          "status": "pass",
          "evidence": "K10 inventory host and IPAM are modeled"
        }
      ]
    },
    {
      "name": "Identity Gate",
      "weight": 30,
      "hard_required": true,
      "checks": [
        {
          "name": "SSSD IPA backend persists after reboot",
          "status": "fail",
          "hard_fail": true,
          "evidence": "/usr/lib64/sssd/libsss_ipa.so missing after AP7901 outlet 6 reboot"
        },
        {
          "name": "aaa-domain-client profile assigned",
          "status": "warn",
          "evidence": "profile is assigned in repo but not yet rebuilt into rootfs"
        }
      ]
    },
    {
      "name": "Performance Gate",
      "weight": 10,
      "hard_required": false,
      "checks": [
        {
          "name": "Build benchmark",
          "status": "skip",
          "evidence": "deferred until reboot-durable identity gate passes"
        }
      ]
    }
  ]
}
EOF

if "${REPORTER}" --manifest "${manifest}" --json-output "${json_report}" --markdown-output "${md_report}" --junit-output "${junit_report}" > "${temp_dir}/stdout.json"; then
  fail 'hard-failed K10 E2ET manifest unexpectedly exited 0'
fi

python3 - "${json_report}" << 'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())
assert report["host"]["name"] == "gmktek_nucbox_k10_stage5_candidate"
assert report["e2et_pass"] is False
assert report["recommended_release_state"] == "blocked"
assert report["conformance"]["current_tier"] == "below-p60"
assert report["summary"]["checks_total"] == 4
assert report["summary"]["checks_failed"] == 1
assert report["summary"]["checks_warned"] == 1
assert report["summary"]["checks_skipped"] == 1
assert report["hard_failures"][0]["gate"] == "Identity Gate"
assert "SSSD IPA backend" in report["hard_failures"][0]["check"]
PY

assert_contains "$(cat "${md_report}")" 'RFC99 Host E2ET Conformance Report'
assert_contains "$(cat "${md_report}")" 'gmktek-k10-stage5.rfc1918.host'
assert_contains "$(cat "${md_report}")" 'Identity Gate'
assert_contains "$(cat "${junit_report}")" '<testsuite'
assert_contains "$(cat "${junit_report}")" '<testcase'
assert_contains "$(cat "${junit_report}")" 'SSSD IPA backend persists after reboot'

playbook="${ANSIBLE_ROOT}/playbooks/host-e2et-conformance-report.yml"
sample_manifest="${ANSIBLE_ROOT}/host-e2et-definitions/k10-stage5-aaa-reboot.yml"
assert_file_contains "${playbook}" 'host_e2et_manifest'
assert_file_contains "${playbook}" 'host_e2et_report_dir'
assert_file_contains "${playbook}" 'host_e2et_conformance.py'
assert_file_contains "${sample_manifest}" 'gmktek_nucbox_k10_stage5_candidate'
assert_file_contains "${sample_manifest}" 'aaa-domain-client'
assert_file_contains "${sample_manifest}" 'AP7901 outlet 6'

printf 'PASS: %s\n' "$(basename "$0")"
