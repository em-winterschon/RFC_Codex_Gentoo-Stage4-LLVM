#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/service_validator.py"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected '${needle}' in '${haystack}'"
}

test -f "${VALIDATOR}"
python3 -m py_compile "${VALIDATOR}"

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

cat > "${temp_dir}/nmap-open" <<'EOF'
#!/usr/bin/env bash
cat <<'XML'
<?xml version="1.0"?>
<nmaprun>
  <host>
    <address addr="10.9.8.92" addrtype="ipv4"/>
    <ports>
      <port protocol="tcp" portid="9200">
        <state state="open"/>
        <service name="http"/>
      </port>
    </ports>
  </host>
</nmaprun>
XML
EOF

cat > "${temp_dir}/nmap-closed" <<'EOF'
#!/usr/bin/env bash
cat <<'XML'
<?xml version="1.0"?>
<nmaprun>
  <host>
    <address addr="10.9.8.92" addrtype="ipv4"/>
    <ports>
      <port protocol="tcp" portid="9200">
        <state state="closed"/>
      </port>
    </ports>
  </host>
</nmaprun>
XML
EOF

cat > "${temp_dir}/nmap-open-filtered" <<'EOF'
#!/usr/bin/env bash
cat <<'XML'
<?xml version="1.0"?>
<nmaprun>
  <host>
    <address addr="10.9.8.92" addrtype="ipv4"/>
    <ports>
      <port protocol="udp" portid="514">
        <state state="open|filtered"/>
      </port>
    </ports>
  </host>
</nmaprun>
XML
EOF

chmod +x "${temp_dir}/nmap-open" "${temp_dir}/nmap-closed" "${temp_dir}/nmap-open-filtered"

open_output="$("${VALIDATOR}" --nmap-bin "${temp_dir}/nmap-open" --target 10.9.8.92 --port 9200 --protocol tcp --service-name elasticsearch-test --json)"
assert_contains "${open_output}" '"service_name": "elasticsearch-test"'
assert_contains "${open_output}" '"target": "10.9.8.92"'
assert_contains "${open_output}" '"port": 9200'
assert_contains "${open_output}" '"protocol": "tcp"'
assert_contains "${open_output}" '"status": "open"'

if "${VALIDATOR}" --nmap-bin "${temp_dir}/nmap-closed" --target 10.9.8.92 --port 9200 --protocol tcp >/dev/null 2>&1; then
  fail 'closed TCP port unexpectedly passed validation'
fi

if "${VALIDATOR}" --nmap-bin "${temp_dir}/nmap-open-filtered" --target 10.9.8.92 --port 514 --protocol udp >/dev/null 2>&1; then
  fail 'open|filtered UDP port unexpectedly passed without --allow-open-filtered'
fi

udp_output="$("${VALIDATOR}" --nmap-bin "${temp_dir}/nmap-open-filtered" --target 10.9.8.92 --port 514 --protocol udp --allow-open-filtered --json)"
assert_contains "${udp_output}" '"status": "open|filtered"'

printf 'PASS: %s\n' "$(basename "$0")"
