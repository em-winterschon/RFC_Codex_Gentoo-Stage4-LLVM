#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE_SCRIPT="${REPO_ROOT}/scripts/stage-encrypted-network-config-backups.py"
BACKUP_WRAPPER="${REPO_ROOT}/scripts/backup-network-device-configs.sh"
ROUTEROS_COLLECTOR="${REPO_ROOT}/scripts/collect-mikrotik-routeros-state.py"
ROUTEROS_SERIAL_COLLECTOR="${REPO_ROOT}/scripts/collect-mikrotik-routeros-serial-state.py"
ROUTEROS_PLAYBOOK="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/routeros-state-snapshot.yml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_grep() {
  local pattern=$1
  local file=$2
  grep -q -- "${pattern}" "${file}" || fail "missing pattern '${pattern}' in ${file}"
}

require_file "${STAGE_SCRIPT}"
require_file "${BACKUP_WRAPPER}"
python3 -m py_compile "${STAGE_SCRIPT}" "${ROUTEROS_COLLECTOR}" "${ROUTEROS_SERIAL_COLLECTOR}"
bash -n "${BACKUP_WRAPPER}"

require_grep 'include-sensitive-export' "${ROUTEROS_COLLECTOR}"
require_grep 'include-sensitive-export' "${ROUTEROS_SERIAL_COLLECTOR}"
require_grep 'routeros_snapshot_include_sensitive_export' "${ROUTEROS_PLAYBOOK}"
require_grep 'routeros_snapshot_transport_effective' "${ROUTEROS_PLAYBOOK}"
require_grep 'collect-mikrotik-routeros-serial-state.py' "${ROUTEROS_PLAYBOOK}"
require_grep 'ansible-vault' "${BACKUP_WRAPPER}"
require_grep 'encrypted-backups/network-devices' "${BACKUP_WRAPPER}"
require_grep 'ANSIBLE_STDOUT_CALLBACK' "${BACKUP_WRAPPER}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

routeros_root="${tmpdir}/routeros"
routeros_manual_root="${tmpdir}/routeros-manual"
swos_root="${tmpdir}/swos"
output_root="${tmpdir}/repo/encrypted-backups/network-devices"
fake_vault="${tmpdir}/fake-vault-wrapper.sh"

mkdir -p \
  "${routeros_root}/sw_spine_crs309_rfc99/20260510T211510Z" \
  "${routeros_root}/gw_failed_serial/20260510T211530Z" \
  "${routeros_manual_root}/ccr2004" \
  "${swos_root}/sw_mgmt_css326/20260510T211520Z"

cat > "${routeros_root}/sw_spine_crs309_rfc99/20260510T211510Z/export-show-sensitive.txt" << 'EOF'
/user add name=admin password=secret-password
EOF

cat > "${routeros_root}/sw_spine_crs309_rfc99/20260510T211510Z/export-hide-sensitive.txt" << 'EOF'
/user add name=admin password=""
EOF

cat > "${routeros_root}/sw_spine_crs309_rfc99/20260510T211510Z/manifest.json" << 'EOF'
{
  "host": "172.16.99.8",
  "commands": [
    {"name": "export-show-sensitive", "file": "export-show-sensitive.txt", "returncode": 0},
    {"name": "export-hide-sensitive", "file": "export-hide-sensitive.txt", "returncode": 0}
  ]
}
EOF

cat > "${routeros_root}/gw_failed_serial/20260510T211530Z/export-show-sensitive.txt" << 'EOF'
STDERR:
serial port missing
EOF

cat > "${routeros_root}/gw_failed_serial/20260510T211530Z/manifest.json" << 'EOF'
{
  "host": "172.16.99.1",
  "commands": [
    {"name": "export-show-sensitive", "file": "export-show-sensitive.txt", "returncode": 1}
  ]
}
EOF

cat > "${routeros_manual_root}/ccr2004/post-rsyslog-vip-20260510T211510Z.rsc" << 'EOF'
/ip firewall nat add comment="secret-manual-routeros-config"
EOF

printf 'binary-swos-backup-secret' > "${swos_root}/sw_mgmt_css326/20260510T211520Z/backup.swb"
cat > "${swos_root}/sw_mgmt_css326/20260510T211520Z/summary.json" << 'EOF'
{"host_identity": "sw-mgmt-mkcss326"}
EOF

cat > "${fake_vault}" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "ansible-vault" ]] || exit 2
[[ "$2" == "encrypt" ]] || exit 2
source_file="$3"
[[ "$4" == "--output" ]] || exit 2
dest_file="$5"
{
  printf '$ANSIBLE_VAULT;1.2;AES256\n'
  base64 "${source_file}"
} > "${dest_file}"
EOF
chmod +x "${fake_vault}"

python3 "${STAGE_SCRIPT}" \
  --routeros-root "${routeros_root}" \
  --routeros-manual-root "${routeros_manual_root}" \
  --swos-root "${swos_root}" \
  --output-root "${output_root}" \
  --vault-wrapper "${fake_vault}" \
  --fail-when-empty > "${tmpdir}/stage-output.json"

require_file "${output_root}/routeros/sw_spine_crs309_rfc99/20260510T211510Z/export-show-sensitive.txt.vault"
require_file "${output_root}/routeros/sw_spine_crs309_rfc99/20260510T211510Z/manifest.json.vault"
require_file "${output_root}/routeros-manual/ccr2004/post-rsyslog-vip-20260510T211510Z.rsc.vault"
require_file "${output_root}/swos/sw_mgmt_css326/20260510T211520Z/backup.swb.vault"
require_file "${output_root}/swos/sw_mgmt_css326/20260510T211520Z/summary.json.vault"
require_file "${output_root}/manifest.json"

if [[ -e "${output_root}/routeros/sw_spine_crs309_rfc99/20260510T211510Z/export-hide-sensitive.txt.vault" ]]; then
  fail "hide-sensitive export was staged even though show-sensitive export exists"
fi

if [[ -e "${output_root}/routeros/gw_failed_serial/20260510T211530Z/export-show-sensitive.txt.vault" ]]; then
  fail "failed RouterOS export was staged"
fi

if grep -R 'secret-password\|binary-swos-backup-secret\|secret-manual-routeros-config' "${output_root}" > /dev/null; then
  fail "plaintext secret content leaked into encrypted backup output"
fi

require_grep 'sw_spine_crs309_rfc99' "${output_root}/manifest.json"
require_grep 'sw_mgmt_css326' "${output_root}/manifest.json"
require_grep '\$ANSIBLE_VAULT' "${output_root}/routeros/sw_spine_crs309_rfc99/20260510T211510Z/export-show-sensitive.txt.vault"

NETWORK_CONFIG_BACKUP_ROUTEROS_ROOT="${routeros_root}" \
  NETWORK_CONFIG_BACKUP_ROUTEROS_MANUAL_ROOT="${routeros_manual_root}" \
  NETWORK_CONFIG_BACKUP_SWOS_ROOT="${swos_root}" \
  NETWORK_CONFIG_BACKUP_OUTPUT_ROOT="${tmpdir}/dry-run-output" \
  "${BACKUP_WRAPPER}" --skip-collect --dry-run > "${tmpdir}/wrapper-dry-run.txt"

require_grep 'skipping live collection' "${tmpdir}/wrapper-dry-run.txt"
require_grep 'sw_spine_crs309_rfc99' "${tmpdir}/wrapper-dry-run.txt"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
