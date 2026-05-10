#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/syslog_elasticsearch_validator.py"

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
fixture_pid=""
trap 'kill "${fixture_pid:-}" >/dev/null 2>&1 || true; rm -rf "${temp_dir}"' EXIT

cat > "${temp_dir}/fixture.py" << 'PY'
import http.server
import json
import socketserver
import sys
import threading
import time
from pathlib import Path

messages = []
lock = threading.Lock()


class SyslogHandler(socketserver.BaseRequestHandler):
    def handle(self):
        payload = self.request.recv(65535).decode("utf-8", "replace")
        with lock:
            messages.append(payload)


class ElasticsearchHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        body = self.rfile.read(length)
        query = json.loads(body.decode("utf-8"))
        marker = query["query"]["match_phrase"]["message"]
        with lock:
            hits = [
                {"_index": "stage5-syslog", "_source": {"message": message}}
                for message in messages
                if marker in message
            ]
        payload = {"hits": {"total": {"value": len(hits)}, "hits": hits}}
        encoded = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, *args):
        return


class ReusableTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True


ready_path = Path(sys.argv[1])
syslog_server = ReusableTCPServer(("127.0.0.1", 0), SyslogHandler)
elastic_server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), ElasticsearchHandler)

ready_path.write_text(
    json.dumps(
        {
            "syslog_port": syslog_server.server_address[1],
            "elasticsearch_port": elastic_server.server_address[1],
        }
    ),
    encoding="utf-8",
)

threading.Thread(target=syslog_server.serve_forever, daemon=True).start()
threading.Thread(target=elastic_server.serve_forever, daemon=True).start()

while True:
    time.sleep(1)
PY

ready_file="${temp_dir}/ready.json"
python3 "${temp_dir}/fixture.py" "${ready_file}" &
fixture_pid=$!

for _ in $(seq 1 50); do
  [ -s "${ready_file}" ] && break
  sleep 0.1
done
[ -s "${ready_file}" ] || fail "fixture did not become ready"

syslog_port="$(python3 - "${ready_file}" << 'PY'
import json
import sys
print(json.load(open(sys.argv[1]))["syslog_port"])
PY
)"
elasticsearch_port="$(python3 - "${ready_file}" << 'PY'
import json
import sys
print(json.load(open(sys.argv[1]))["elasticsearch_port"])
PY
)"

output="$(
  "${VALIDATOR}" \
    --syslog-target 127.0.0.1 \
    --syslog-port "${syslog_port}" \
    --syslog-protocol tcp \
    --elasticsearch-url "http://127.0.0.1:${elasticsearch_port}" \
    --index-pattern 'stage5-syslog*' \
    --marker "fixture-syslog-elasticsearch-marker" \
    --retries 5 \
    --delay 0.1 \
    --json
)"

assert_contains "${output}" '"success": true'
assert_contains "${output}" '"marker": "fixture-syslog-elasticsearch-marker"'
assert_contains "${output}" '"hits": 1'

printf 'PASS: %s\n' "$(basename "$0")"
