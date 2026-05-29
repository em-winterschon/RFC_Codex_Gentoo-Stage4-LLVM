#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
VALIDATOR="${REPO_ROOT}/scripts/validate_netboot_dns.py"
POLICY="${ANSIBLE_ROOT}/netboot-dns-policy.yml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  grep -Fq "${needle}" "${path}" || fail "expected '${needle}' in ${path}"
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

good_manifest="${tmpdir}/good-netboot.yml"
denied_manifest="${tmpdir}/denied-netboot.yml"
unapproved_manifest="${tmpdir}/unapproved-netboot.yml"

cat > "${good_manifest}" << 'YAML'
---
kind: NetbootImageManifest
network:
  nameserver: 172.16.99.1
cmdline:
  network:
    - nameserver=172.16.99.1
    - nameserver=9.9.9.9
YAML

cat > "${denied_manifest}" << 'YAML'
---
kind: NetbootImageManifest
network:
  nameserver: 172.16.99.63
cmdline:
  network:
    - nameserver=172.16.99.63
YAML

cat > "${unapproved_manifest}" << 'YAML'
---
kind: NetbootImageManifest
network:
  nameserver: 1.1.1.1
cmdline:
  network:
    - nameserver=1.1.1.1
YAML

assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/defaults/main.yml" "netboot_dns_validation_enabled:"
assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" "Validate Path B netboot DNS policy inputs"
assert_file_contains "${ANSIBLE_ROOT}/playbooks/netboot-path-b.yml" "netboot_publishers"
assert_file_contains "${POLICY}" "172.16.99.1"
assert_file_contains "${POLICY}" "172.16.99.63"

python3 "${VALIDATOR}" --policy "${POLICY}" --path "${good_manifest}" > /dev/null
python3 "${VALIDATOR}" --policy "${POLICY}" --path "${ANSIBLE_ROOT}/netboot-image-manifests" > /dev/null
python3 "${VALIDATOR}" --policy "${POLICY}" --value 'nameserver=172.16.99.1 nameserver=9.9.9.9' > /dev/null

if python3 "${VALIDATOR}" --policy "${POLICY}" --path "${denied_manifest}" > /dev/null 2>&1; then
  fail "expected denied FreeIPA DNS address to fail validation"
fi

if python3 "${VALIDATOR}" --policy "${POLICY}" --path "${unapproved_manifest}" > /dev/null 2>&1; then
  fail "expected unapproved DNS address to fail validation"
fi

printf 'PASS: %s\n' "$(basename "$0")"
