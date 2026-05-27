#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNBOOK="${REPO_ROOT}/docs/THOR-CRS354-LACP-PERF-RUNBOOK.md"
IPERF_SCRIPT="${REPO_ROOT}/scripts/thor-ovs-cross-bridge-iperf.sh"
THOR_READINESS="${REPO_ROOT}/docs/THOR-AGX-INFERENCE-READINESS.md"
CRS354_STANDARD="${REPO_ROOT}/docs/CRS354-DISTRIBUTION-SWITCH-STANDARDIZATION.md"
EVIDENCE="${REPO_ROOT}/docs/evidence/thor-crs354-lacp-mainthread.2026-05-27.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_fixed() {
  local pattern=$1
  local file=$2
  grep -Fq -- "${pattern}" "${file}" || fail "missing text ${pattern} in ${file}"
}

require_absent_fixed() {
  local pattern=$1
  local file=$2
  if grep -Fq -- "${pattern}" "${file}"; then
    fail "unexpected text ${pattern} in ${file}"
  fi
}

require_file "${RUNBOOK}"
require_fixed 'CRS354 management and Thor peer LACP are repaired and applied' "${RUNBOOK}"
require_fixed 'CRS354 serial console: reachable' "${RUNBOOK}"
require_fixed 'CRS354 SSH/HTTP/HTTPS/Winbox TCP from M70: reachable' "${RUNBOOK}"
require_fixed 'mgmt-source-rule' "${RUNBOOK}"
require_fixed 'bond-thor-podman' "${RUNBOOK}"
require_fixed 'bond-thor-kata' "${RUNBOOK}"
require_fixed 'qsfpplus2-1' "${RUNBOOK}"
require_fixed 'qsfpplus2-4' "${RUNBOOK}"
require_fixed 'mode=802.3ad' "${RUNBOOK}"
require_fixed 'lacp-rate=1sec' "${RUNBOOK}"
require_fixed 'link-monitoring=mii' "${RUNBOOK}"
require_fixed 'br-kata0 -> CRS354 qsfpplus2 lanes -> Thor br-podman0' "${RUNBOOK}"
require_fixed './thor-ovs-cross-bridge-iperf.sh --parallel 1 --duration 30' "${RUNBOOK}"
require_fixed './thor-ovs-cross-bridge-iperf.sh --parallel 8 --duration 60' "${RUNBOOK}"
require_fixed 'Do not bind Thor `mgbe*` ports to DPDK' "${RUNBOOK}"
require_fixed 'Docker is not an acceptable implementation detail for this fleet.' "${RUNBOOK}"
require_fixed 'MIG mode: Disabled' "${RUNBOOK}"
require_fixed 'Host vGPU mode: N/A' "${RUNBOOK}"
require_fixed 'vGPU assignment is' "${RUNBOOK}"
require_fixed 'blocked until the NVIDIA vGPU host stack is installed and validated' "${RUNBOOK}"
require_fixed '2026-05-27 Same-Host Hairpin Result' "${RUNBOOK}"
require_fixed 'do not use the same Thor host as both traffic endpoints' "${RUNBOOK}"

require_file "${IPERF_SCRIPT}"
require_fixed 'br-kata0 -> CRS354 -> br-podman0' "${IPERF_SCRIPT}"
require_fixed 'require_lacp_enabled bond-kata0' "${IPERF_SCRIPT}"
require_fixed 'require_lacp_enabled bond-podman0' "${IPERF_SCRIPT}"
require_fixed '--allow-lacp-down' "${IPERF_SCRIPT}"
require_fixed 'port=55201' "${IPERF_SCRIPT}"
require_fixed 'timeout --kill-after=5 "${client_timeout}"' "${IPERF_SCRIPT}"
require_fixed 'duration, parallel, and port must be in valid positive ranges' "${IPERF_SCRIPT}"
require_fixed 'mac_kata="02:54:31:fe:00:02"' "${IPERF_SCRIPT}"
require_fixed 'ovs-ofctl add-flow br-kata0' "${IPERF_SCRIPT}"
require_fixed 'ovs-ofctl add-flow br-podman0' "${IPERF_SCRIPT}"
require_fixed 'ovs-ofctl del-flows br-kata0' "${IPERF_SCRIPT}"
require_fixed 'ip netns add "${ns_kata}"' "${IPERF_SCRIPT}"
require_fixed 'ovs-vsctl add-port br-kata0 "${veth_kata_br}"' "${IPERF_SCRIPT}"
require_fixed 'ovs-vsctl add-port br-podman0 "${veth_podman_br}"' "${IPERF_SCRIPT}"
require_fixed 'iperf3 -s -1 -p "${port}"' "${IPERF_SCRIPT}"
require_fixed 'iperf3 -c 172.31.254.3 -p "${port}"' "${IPERF_SCRIPT}"
require_fixed 'grep -Fq '"'"'"error"'"'"'' "${IPERF_SCRIPT}"
require_absent_fixed 'docker ' "${IPERF_SCRIPT}"

require_file "${THOR_READINESS}"
require_fixed 'docs/THOR-CRS354-LACP-PERF-RUNBOOK.md' "${THOR_READINESS}"
require_fixed 'scripts/thor-ovs-cross-bridge-iperf.sh' "${THOR_READINESS}"
require_fixed 'host-level iperf3 daemon on TCP/5201' "${RUNBOOK}"
require_fixed 'MAC-learning pollution' "${RUNBOOK}"
require_fixed 'Thor bond-podman0:       LACP negotiated' "${THOR_READINESS}"
require_fixed 'Cross-bridge TCP | iperf3 not valid in same-host hairpin topology' "${THOR_READINESS}"

require_file "${CRS354_STANDARD}"
require_fixed 'qsfpplus2-1' "${CRS354_STANDARD}"
require_fixed 'bond-thor-podman' "${CRS354_STANDARD}"
require_fixed 'bond-thor-kata' "${CRS354_STANDARD}"
require_fixed 'br-kata0 -> CRS354 -> br-podman0' "${CRS354_STANDARD}"
require_fixed '2026-05-27 Thor LACP Update' "${CRS354_STANDARD}"
require_fixed 'same-host Thor hairpin path is not a valid throughput acceptance path' "${CRS354_STANDARD}"

require_file "${EVIDENCE}"
require_fixed 'CRS354 Management Fix' "${EVIDENCE}"
require_fixed 'bond-thor-podman: qsfpplus2-1,qsfpplus2-2' "${EVIDENCE}"
require_fixed 'bond-podman0: lacp_status=negotiated' "${EVIDENCE}"
require_fixed 'same-host OVS bridge hairpin' "${EVIDENCE}"
require_fixed '"interrupt - the client has terminated"' "${EVIDENCE}"
require_fixed '`tcpdump` was installed on Thor' "${EVIDENCE}"

printf 'PASS: %s\n' "$(basename "$0")"
