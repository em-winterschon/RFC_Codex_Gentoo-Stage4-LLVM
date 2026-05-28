#!/usr/bin/env bash
set -euo pipefail

duration=30
parallel=8
port=55201
json_out=""
allow_lacp_down=0

usage() {
  cat << 'EOF'
Usage: thor-ovs-cross-bridge-iperf.sh [options]

Validate Thor AGX cross-bridge traffic path:

  br-kata0 namespace -> br-kata0 -> CRS354 -> br-podman0 -> br-podman0 namespace

Options:
  --duration SECONDS       iperf3 test duration. Default: 30
  --parallel STREAMS       iperf3 parallel streams. Default: 8
  --port PORT              iperf3 TCP port. Default: 55201
  --json-out PATH          write iperf3 JSON result to PATH instead of stdout
  --allow-lacp-down        run even if OVS LACP members are not enabled
  -h, --help               show this help

The script creates temporary network namespaces and OVS veth ports, then removes
them on exit. It must be run as root on Thor.
EOF
}

while (($#)); do
  case "$1" in
  --duration)
    duration="${2:?missing value for --duration}"
    shift 2
    ;;
  --parallel)
    parallel="${2:?missing value for --parallel}"
    shift 2
    ;;
  --port)
    port="${2:?missing value for --port}"
    shift 2
    ;;
  --json-out)
    json_out="${2:?missing value for --json-out}"
    shift 2
    ;;
  --allow-lacp-down)
    allow_lacp_down=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf 'ERROR: unknown argument: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

for value_name in duration parallel port; do
  value="${!value_name}"
  if ! [[ "${value}" =~ ^[0-9]+$ ]]; then
    printf 'ERROR: %s must be a positive integer: %s\n' "${value_name}" "${value}" >&2
    exit 2
  fi
done

if ((duration < 1 || parallel < 1 || port < 1 || port > 65535)); then
  printf 'ERROR: duration, parallel, and port must be in valid positive ranges\n' >&2
  exit 2
fi

if [[ ${EUID} -ne 0 ]]; then
  printf 'ERROR: must run as root on Thor\n' >&2
  exit 1
fi

for cmd in ip ovs-vsctl ovs-appctl iperf3 ping timeout; do
  command -v "${cmd}" > /dev/null 2>&1 || {
    printf 'ERROR: missing required command: %s\n' "${cmd}" >&2
    exit 1
  }
done

command -v ovs-ofctl > /dev/null 2>&1 || {
  printf 'ERROR: missing required command: ovs-ofctl\n' >&2
  exit 1
}

require_ovs_bridge() {
  local bridge=$1
  ovs-vsctl br-exists "${bridge}" || {
    printf 'ERROR: missing OVS bridge: %s\n' "${bridge}" >&2
    exit 1
  }
}

require_lacp_enabled() {
  local bond=$1
  local output
  output="$(ovs-appctl bond/show "${bond}")"
  if grep -Fq 'may_enable: false' <<< "${output}"; then
    if [[ ${allow_lacp_down} -eq 0 ]]; then
      printf 'ERROR: OVS bond %s has disabled members; CRS354 LACP peer is not ready\n' "${bond}" >&2
      printf 'Use --allow-lacp-down only for negative-path diagnostics.\n' >&2
      exit 1
    fi
  fi
}

require_ovs_bridge br-kata0
require_ovs_bridge br-podman0
require_lacp_enabled bond-kata0
require_lacp_enabled bond-podman0

ns_kata="thor_kata_test"
ns_podman="thor_pod_test"
veth_kata_br="vkata-br"
veth_kata_ns="vkata-ns"
veth_podman_br="vpod-br"
veth_podman_ns="vpod-ns"
mac_kata="02:54:31:fe:00:02"
mac_podman="02:54:31:fe:00:03"
server_log="$(mktemp -t thor-iperf3-server.XXXXXX.log)"
client_log="$(mktemp -t thor-iperf3-client.XXXXXX.log)"
server_pid=""
client_json_tmp=""
client_timeout=$((duration + 20))

cleanup() {
  set +e
  if [[ -n "${server_pid}" ]] && kill -0 "${server_pid}" > /dev/null 2>&1; then
    kill "${server_pid}" > /dev/null 2>&1
    wait "${server_pid}" > /dev/null 2>&1
  fi
  ovs-vsctl --if-exists del-port br-kata0 "${veth_kata_br}" > /dev/null 2>&1
  ovs-vsctl --if-exists del-port br-podman0 "${veth_podman_br}" > /dev/null 2>&1
  ovs-ofctl del-flows br-kata0 "dl_dst=${mac_kata}" > /dev/null 2>&1
  ovs-ofctl del-flows br-podman0 "dl_dst=${mac_podman}" > /dev/null 2>&1
  ip netns del "${ns_kata}" > /dev/null 2>&1
  ip netns del "${ns_podman}" > /dev/null 2>&1
  ip link del "${veth_kata_br}" > /dev/null 2>&1
  ip link del "${veth_podman_br}" > /dev/null 2>&1
  rm -f "${server_log}" "${client_log}"
  if [[ -n "${client_json_tmp}" ]]; then
    rm -f "${client_json_tmp}"
  fi
}
trap cleanup EXIT

cleanup
trap cleanup EXIT

ip netns add "${ns_kata}"
ip netns add "${ns_podman}"

ip link add "${veth_kata_br}" type veth peer name "${veth_kata_ns}"
ip link add "${veth_podman_br}" type veth peer name "${veth_podman_ns}"
ip link set "${veth_kata_ns}" address "${mac_kata}"
ip link set "${veth_podman_ns}" address "${mac_podman}"

ovs-vsctl add-port br-kata0 "${veth_kata_br}"
ovs-vsctl add-port br-podman0 "${veth_podman_br}"
kata_ofport="$(ovs-vsctl get Interface "${veth_kata_br}" ofport)"
podman_ofport="$(ovs-vsctl get Interface "${veth_podman_br}" ofport)"
ovs-ofctl add-flow br-kata0 "priority=200,dl_dst=${mac_kata},actions=output:${kata_ofport}"
ovs-ofctl add-flow br-podman0 "priority=200,dl_dst=${mac_podman},actions=output:${podman_ofport}"
ip link set "${veth_kata_br}" up
ip link set "${veth_podman_br}" up

ip link set "${veth_kata_ns}" netns "${ns_kata}"
ip link set "${veth_podman_ns}" netns "${ns_podman}"

ip -n "${ns_kata}" addr add 172.31.254.2/24 dev "${veth_kata_ns}"
ip -n "${ns_podman}" addr add 172.31.254.3/24 dev "${veth_podman_ns}"
ip -n "${ns_kata}" link set lo up
ip -n "${ns_podman}" link set lo up
ip -n "${ns_kata}" link set "${veth_kata_ns}" up
ip -n "${ns_podman}" link set "${veth_podman_ns}" up

ip netns exec "${ns_podman}" iperf3 -s -1 -p "${port}" > "${server_log}" 2>&1 &
server_pid=$!
sleep 1

ip netns exec "${ns_kata}" ping -c 10 -q 172.31.254.3 >&2

client_json="${json_out}"
if [[ -z "${client_json}" ]]; then
  client_json="$(mktemp -t thor-iperf3-client.XXXXXX.json)"
  client_json_tmp="${client_json}"
fi

iperf_status=0
timeout --kill-after=5 "${client_timeout}" \
  ip netns exec "${ns_kata}" iperf3 -c 172.31.254.3 -p "${port}" -P "${parallel}" -t "${duration}" --json \
  > "${client_json}" 2> "${client_log}" || iperf_status=$?

if [[ ${iperf_status} -ne 0 ]]; then
  printf 'ERROR: iperf3 client exited with status %s; stderr follows:\n' "${iperf_status}" >&2
  sed -n '1,160p' "${client_log}" >&2
  printf 'ERROR: iperf3 client JSON follows:\n' >&2
  sed -n '1,160p' "${client_json}" >&2
  printf 'ERROR: iperf3 server log follows:\n' >&2
  sed -n '1,160p' "${server_log}" >&2
  exit 1
fi

if grep -Fq '"error"' "${client_json}"; then
  printf 'ERROR: iperf3 client reported failure; JSON follows:\n' >&2
  sed -n '1,160p' "${client_json}" >&2
  printf 'ERROR: iperf3 server log follows:\n' >&2
  sed -n '1,160p' "${server_log}" >&2
  exit 1
fi

if [[ -n "${json_out}" ]]; then
  printf 'Wrote iperf3 JSON result to %s\n' "${json_out}" >&2
else
  cat "${client_json}"
fi

wait "${server_pid}" || {
  printf 'ERROR: iperf3 server failed; log follows:\n' >&2
  sed -n '1,120p' "${server_log}" >&2
  exit 1
}
