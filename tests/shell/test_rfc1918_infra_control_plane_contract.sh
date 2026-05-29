#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
CONTRACT="${ANSIBLE_ROOT}/vars/rfc1918_infra_control_plane.yml"
WORKFLOW="${REPO_ROOT}/docs/workflows/rfc1918-infra-control-plane.json"
DOC="${REPO_ROOT}/docs/RFC1918-INFRASTRUCTURE-CONTROL-PLANE.md"
WIKI="${REPO_ROOT}/docs/wiki/RFC1918-Infrastructure-Control-Plane.md"
QNAP_DOC="${REPO_ROOT}/docs/QNAP-SUN99-FLOATING-HOMES-AND-MCP-ASSESSMENT.md"
JENKINS_PROFILE="${ANSIBLE_ROOT}/profile-definitions/vm-jenkins-controller.yml"
JENKINS_TASKS="${ANSIBLE_ROOT}/roles/jenkins_controller/tasks/main.yml"
JENKINS_TEMPLATE="${ANSIBLE_ROOT}/roles/jenkins_controller/templates/rfc1918-infra-job-seed.yml.j2"
PREFLIGHT_MAIN="${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml"
PREFLIGHT_LOAD="${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml"
RUN_TESTS="${REPO_ROOT}/tests/shell/run-tests.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -Fq -- "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

for file in \
  "${CONTRACT}" \
  "${WORKFLOW}" \
  "${DOC}" \
  "${WIKI}" \
  "${QNAP_DOC}" \
  "${JENKINS_PROFILE}" \
  "${JENKINS_TASKS}" \
  "${JENKINS_TEMPLATE}" \
  "${PREFLIGHT_MAIN}" \
  "${PREFLIGHT_LOAD}"; do
  [[ -f "${file}" ]] || fail "missing ${file}"
done

assert_file_contains "${RUN_TESTS}" 'test_rfc1918_infra_control_plane_contract.sh'
assert_file_contains "${CONTRACT}" 'schema: rfc1918.infra-control-plane.v1'
assert_file_contains "${CONTRACT}" 'publish_only_from_ci: true'
assert_file_contains "${CONTRACT}" 'app-misc/rfc99-atlasforge-ca-certs'
assert_file_contains "${CONTRACT}" '/usr/local/share/ca-certificates'
assert_file_contains "${CONTRACT}" 'update-ca-certificates'
assert_file_contains "${CONTRACT}" '/etc/pki/ca-trust/source/anchors'
assert_file_contains "${CONTRACT}" 'update-ca-trust'
assert_file_contains "${CONTRACT}" 'rfc99-yum-hosted'
assert_file_contains "${CONTRACT}" 'plan_public_dns: scripts/plan-hetzner-dns-from-netbox.py'
assert_file_contains "${CONTRACT}" 'render_local_dns: playbooks/coredns-resolver.yml'
assert_file_contains "${CONTRACT}" 'rfc1918.systems'
assert_file_contains "${CONTRACT}" 'vernetzen.io'
assert_file_contains "${CONTRACT}" 'yukon.systems'

assert_file_contains "${WORKFLOW}" 'rfc1918-infra-control-plane'
assert_file_contains "${WORKFLOW}" 'vault-preflight'
assert_file_contains "${WORKFLOW}" 'jenkins-seed-contract-render'
assert_file_contains "${WORKFLOW}" 'slurm-distcc-build-plan'
assert_file_contains "${WORKFLOW}" 'ca-package-publication-plan'
assert_file_contains "${WORKFLOW}" 'nexus-repository-readiness'
assert_file_contains "${WORKFLOW}" 'netbox-dns-dry-run-chain'
assert_file_contains "${WORKFLOW}" 'scripts/with-ansible-vault-env.sh'
assert_file_contains "${WORKFLOW}" 'app-misc/rfc99-atlasforge-ca-certs'
assert_file_contains "${WORKFLOW}" 'scripts/plan-hetzner-dns-from-netbox.py'
assert_file_contains "${WORKFLOW}" 'playbooks/coredns-resolver.yml'

assert_file_contains "${DOC}" 'NetBox remains authoritative'
assert_file_contains "${DOC}" 'Jenkins owns repeatable package builds'
assert_file_contains "${DOC}" 'SLURM owns concurrent execution'
assert_file_contains "${DOC}" 'Nexus is the publication surface'
assert_file_contains "${DOC}" 'eselect repository add rfc99-atlasforge'
assert_file_contains "${DOC}" 'app-misc/rfc99-atlasforge-ca-certs'
assert_file_contains "${DOC}" 'rfc99-atlasforge-ca-certs'
assert_file_contains "${DOC}" 'NetBox change'
assert_file_contains "${DOC}" 'Hetzner DNS plan'
assert_file_contains "${DOC}" 'CoreDNS split-horizon'
assert_file_contains "${WIKI}" 'RFC1918 Infrastructure Control Plane'

assert_file_contains "${QNAP_DOC}" 'Historical note (2026-05-29)'
assert_file_contains "${QNAP_DOC}" 'use `docs/FREEIPA-FORGE-WORKERS-QNAP-HOMES.md`'

assert_file_contains "${JENKINS_PROFILE}" 'job_seed_manifests:'
assert_file_contains "${JENKINS_PROFILE}" 'rfc1918-infra-control-plane'
assert_file_contains "${JENKINS_PROFILE}" 'stage4-stage5-build-via-slurm'
assert_file_contains "${JENKINS_PROFILE}" 'rfc99-atlasforge-ca-certs-gentoo'
assert_file_contains "${JENKINS_PROFILE}" 'rfc99-atlasforge-ca-certs-rpm'
assert_file_contains "${JENKINS_PROFILE}" 'netbox-dns-propagation-plan'
assert_file_contains "${JENKINS_TASKS}" 'Render Jenkins RFC1918 infrastructure job seed manifest'
assert_file_contains "${JENKINS_TASKS}" 'rfc1918-infra-job-seed.yml.j2'
assert_file_contains "${JENKINS_TEMPLATE}" 'schema: rfc1918.jenkins.job-seed-manifest.v1'
assert_file_contains "${PREFLIGHT_MAIN}" 'resolved_profile_slurm_cluster'
assert_file_contains "${PREFLIGHT_LOAD}" 'gentoo_profile_definition.slurm_cluster'

python3 - "${WORKFLOW}" "${CONTRACT}" <<'PY'
import json
import sys
from pathlib import Path
import yaml

workflow = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
contract = yaml.safe_load(Path(sys.argv[2]).read_text(encoding="utf-8"))
if workflow["kind"] != "WorkflowManifest":
    raise SystemExit("workflow kind mismatch")
if len(workflow["stages"]) < 7:
    raise SystemExit("workflow must keep all dry-run control-plane gates")
if not contract["rfc1918_infra_control_plane"]["source_of_truth"]["netbox_authoritative"]:
    raise SystemExit("NetBox must remain authoritative")
if not contract["rfc1918_infra_control_plane"]["repositories"]["hosted"]:
    raise SystemExit("hosted repositories missing")
print("contract-json-yaml-ok")
PY

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
