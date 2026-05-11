#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

validator="${REPO_ROOT}/scripts/validate_secure_firstboot_bundle.py"
renderer="${REPO_ROOT}/scripts/render_secure_firstboot_bundle.py"
package_list="${ANSIBLE_ROOT}/profile-package-lists/stage5-secure-firstboot-enrollment.packages"
profile_definition="${ANSIBLE_ROOT}/profile-definitions/secure-firstboot-enrollment.yml"
profile_metadata="${ANSIBLE_ROOT}/profile-definitions/secure-firstboot-enrollment.metadata.yml"
role_dir="${ANSIBLE_ROOT}/roles/secure_firstboot_enrollment"
role_defaults="${role_dir}/defaults/main.yml"
role_tasks="${role_dir}/tasks/main.yml"
role_script_template="${role_dir}/templates/stage5-firstboot-enroll.sh.j2"
role_init_template="${role_dir}/templates/stage5-firstboot-enroll.initd.j2"
role_confd_template="${role_dir}/templates/stage5-firstboot-enroll.confd.j2"
service_atoms="${ANSIBLE_ROOT}/profile-service-atoms/stage5-role-service-atoms.yml"

test -x "${validator}"
test -x "${renderer}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

future_expiry="$(python3 - <<'PY'
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) + timedelta(hours=2)).replace(microsecond=0).isoformat().replace("+00:00", "Z"))
PY
)"
expired_at="$(python3 - <<'PY'
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) - timedelta(hours=2)).replace(microsecond=0).isoformat().replace("+00:00", "Z"))
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
    > "${tmp_dir}/valid.json"

"${validator}" "${tmp_dir}/valid.json" --expected-fqdn gmktek-k10-stage5.rfc1918.host

if "${renderer}" \
  --fqdn gmktek-k10-stage5.rfc1918.host \
  --realm RFC1918.HOST \
  --domain rfc1918.host \
  --ipa-server ipa01.rfc1918.host \
  --expires-at "${future_expiry}" \
  --otp-env STAGE5_FIRSTBOOT_OTP \
  > "${tmp_dir}/missing-otp.json" 2> "${tmp_dir}/missing-otp.err"; then
  printf 'renderer accepted a missing OTP environment variable\n' >&2
  exit 1
fi
assert_file_contains "${tmp_dir}/missing-otp.err" 'missing OTP environment variable'

python3 - "${tmp_dir}/valid.json" "${tmp_dir}/expired.json" "${expired_at}" <<'PY'
import json
import sys
src, dst, expired_at = sys.argv[1:4]
payload = json.load(open(src, encoding="utf-8"))
payload["expires_at"] = expired_at
json.dump(payload, open(dst, "w", encoding="utf-8"), indent=2, sort_keys=True)
PY

if "${validator}" "${tmp_dir}/expired.json" > "${tmp_dir}/expired.out" 2> "${tmp_dir}/expired.err"; then
  printf 'validator accepted an expired bundle\n' >&2
  exit 1
fi
assert_file_contains "${tmp_dir}/expired.err" 'bundle expired'

python3 - "${tmp_dir}/valid.json" "${tmp_dir}/keytab.json" <<'PY'
import json
import sys
src, dst = sys.argv[1:3]
payload = json.load(open(src, encoding="utf-8"))
payload["krb5_keytab"] = "forbidden"
json.dump(payload, open(dst, "w", encoding="utf-8"), indent=2, sort_keys=True)
PY

if "${validator}" "${tmp_dir}/keytab.json" > "${tmp_dir}/keytab.out" 2> "${tmp_dir}/keytab.err"; then
  printf 'validator accepted keytab material\n' >&2
  exit 1
fi
assert_file_contains "${tmp_dir}/keytab.err" 'forbidden secret field'

test -f "${package_list}"
assert_file_contains "${package_list}" '^app-crypt/age$'
assert_file_contains "${package_list}" '^net-misc/curl$'
assert_file_contains "${package_list}" '^app-misc/jq$'

test -f "${profile_definition}"
assert_file_contains "${profile_definition}" 'secure_firstboot_enrollment:'
assert_file_contains "${profile_definition}" 'method: freeipa-otp-age'
assert_file_contains "${profile_definition}" 'openrc_services_available:'
assert_file_contains "${profile_definition}" 'stage5-firstboot-enroll'

test -f "${profile_metadata}"
assert_file_contains "${profile_metadata}" 'secure-firstboot-enrollment'
assert_file_contains "${profile_metadata}" 'Clevis/Tang'
assert_file_contains "${profile_metadata}" 'Guru'
assert_file_contains "${profile_metadata}" 'Tang-only decryption is not sufficient'

assert_file_contains "${service_atoms}" 'secure-firstboot-enrollment'
assert_file_contains "${service_atoms}" 'app-crypt/age'

test -d "${role_dir}"
test -f "${role_defaults}"
test -f "${role_tasks}"
test -f "${role_script_template}"
test -f "${role_init_template}"
test -f "${role_confd_template}"
assert_file_contains "${role_defaults}" 'secure_firstboot_enrollment_enabled: false'
assert_file_contains "${role_tasks}" 'stage5-firstboot-enroll'
assert_file_contains "${role_script_template}" 'age --decrypt'
assert_file_contains "${role_script_template}" 'validate_secure_firstboot_bundle.py'
assert_file_contains "${role_script_template}" 'STAGE5_FIRSTBOOT_ENROLL_COMMAND'
assert_file_contains "${role_script_template}" '/etc/krb5.keytab'
assert_file_contains "${role_init_template}" 'depend()'
assert_file_contains "${role_confd_template}" 'STAGE5_FIRSTBOOT_ENROLLMENT_ENABLED='

printf 'PASS: %s\n' "$(basename "$0")"
