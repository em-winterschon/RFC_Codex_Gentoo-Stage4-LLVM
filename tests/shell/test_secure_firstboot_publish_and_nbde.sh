#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

assert_file_not_contains() {
  local file=$1
  local pattern=$2
  ! grep -q -- "${pattern}" "${file}" || fail "expected ${file} not to contain ${pattern}"
}

renderer="${REPO_ROOT}/scripts/render_secure_firstboot_bundle.py"
stager="${REPO_ROOT}/scripts/stage_secure_firstboot_bundle.py"
stage_playbook="${ANSIBLE_ROOT}/playbooks/secure-firstboot-bundle-stage.yml"
tang_role="${ANSIBLE_ROOT}/roles/tang_nbde_server"
tang_packages="${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-tang-nbde-server.packages"
clevis_packages="${ANSIBLE_ROOT}/profile-package-lists/stage5-secure-firstboot-nbde-client.packages"
tang_profile="${ANSIBLE_ROOT}/profile-definitions/vm-tang-nbde-server.yml"
tang_metadata="${ANSIBLE_ROOT}/profile-definitions/vm-tang-nbde-server.metadata.yml"
secure_metadata="${ANSIBLE_ROOT}/profile-definitions/secure-firstboot-enrollment.metadata.yml"
service_atoms="${ANSIBLE_ROOT}/profile-service-atoms/stage5-role-service-atoms.yml"

test -x "${stager}"
test -f "${stage_playbook}"
test -f "${tang_packages}"
test -f "${clevis_packages}"
test -f "${tang_profile}"
test -f "${tang_metadata}"
test -d "${tang_role}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

future_expiry="$(python3 - <<'PY'
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) + timedelta(hours=2)).replace(microsecond=0).isoformat().replace("+00:00", "Z"))
PY
)"

STAGE5_FIRSTBOOT_OTP='test-otp-not-for-real-use' \
  "${renderer}" \
    --fqdn gmktek-k10-stage5.rfc1918.host \
    --realm RFC1918.HOST \
    --domain rfc1918.host \
    --ipa-server ipa01.rfc1918.host \
    --expires-at "${future_expiry}" \
    --generation-id k10-e2et-test \
    --otp-env STAGE5_FIRSTBOOT_OTP \
    > "${tmp_dir}/bundle.json"

"${stager}" \
  --bundle "${tmp_dir}/bundle.json" \
  --expected-fqdn gmktek-k10-stage5.rfc1918.host \
  --recipient age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq9q8x7 \
  --output "${tmp_dir}/bundle.json.age" \
  --dry-run \
  --format json > "${tmp_dir}/plan.json"

assert_file_contains "${tmp_dir}/plan.json" '"dry_run": true'
assert_file_contains "${tmp_dir}/plan.json" '"would_write":'
test ! -e "${tmp_dir}/bundle.json.age" || fail "dry-run wrote encrypted bundle"

cat > "${tmp_dir}/fake-age" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out=""
in=""
while (($#)); do
  case "$1" in
    --output)
      out="$2"
      shift 2
      ;;
    --encrypt|--recipient)
      shift
      if [[ "${1:-}" != "" && "$1" != --* ]]; then
        shift
      fi
      ;;
    *)
      in="$1"
      shift
      ;;
  esac
done
printf 'fake-age-encrypted\n' > "${out}"
cat "${in}" >> "${out}"
SH
chmod +x "${tmp_dir}/fake-age"

"${stager}" \
  --bundle "${tmp_dir}/bundle.json" \
  --expected-fqdn gmktek-k10-stage5.rfc1918.host \
  --recipient age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq9q8x7 \
  --output "${tmp_dir}/bundle.json.age" \
  --age-bin "${tmp_dir}/fake-age" \
  --apply \
  --format json > "${tmp_dir}/apply.json"

assert_file_contains "${tmp_dir}/apply.json" '"dry_run": false'
assert_file_contains "${tmp_dir}/bundle.json.age" 'fake-age-encrypted'

if "${stager}" \
  --bundle "${tmp_dir}/bundle.json" \
  --expected-fqdn gmktek-k10-stage5.rfc1918.host \
  --recipient age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq9q8x7 \
  --output "${REPO_ROOT}/forbidden-firstboot-bundle.json.age" \
  --age-bin "${tmp_dir}/fake-age" \
  --apply > "${tmp_dir}/repo-output.out" 2> "${tmp_dir}/repo-output.err"; then
  fail "stager accepted repo output without explicit override"
fi
assert_file_contains "${tmp_dir}/repo-output.err" 'refusing to write encrypted bundle inside repository'

assert_file_contains "${stage_playbook}" 'secure_firstboot_bundle_apply'
assert_file_contains "${stage_playbook}" 'render_secure_firstboot_bundle.py'
assert_file_contains "${stage_playbook}" 'stage_secure_firstboot_bundle.py'
assert_file_contains "${stage_playbook}" 'no_log: true'
assert_file_not_contains "${stage_playbook}" 'krb5.keytab'

assert_file_contains "${tang_packages}" '^app-crypt/tang$'
assert_file_contains "${clevis_packages}" '^app-crypt/clevis$'
assert_file_contains "${clevis_packages}" '^app-crypt/tpm2-tools$'
assert_file_contains "${tang_profile}" 'tang_nbde_server:'
assert_file_contains "${tang_metadata}" 'Tang-only decryption is not sufficient'
assert_file_contains "${secure_metadata}" 'tpm2+tang'
assert_file_contains "${service_atoms}" 'vm-tang-nbde-server'
assert_file_contains "${service_atoms}" 'secure-firstboot-nbde-client'
assert_file_contains "${tang_role}/defaults/main.yml" 'tang_nbde_server_enabled: false'
assert_file_contains "${tang_role}/tasks/main.yml" 'tang_nbde_server_mutation_enabled'
assert_file_contains "${tang_role}/templates/tangd.confd.j2" 'TANGD_LISTEN_URL'
assert_file_contains "${tang_role}/templates/tangd.initd.j2" 'depend()'

printf 'PASS: %s\n' "$(basename "$0")"
