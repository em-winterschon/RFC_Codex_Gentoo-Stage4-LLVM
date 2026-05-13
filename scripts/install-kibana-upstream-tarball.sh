#!/usr/bin/env bash
set -euo pipefail

KIBANA_VERSION="${KIBANA_VERSION:-9.3.1}"
KIBANA_ARCH="${KIBANA_ARCH:-linux-x86_64}"
KIBANA_BASE_URL="${KIBANA_BASE_URL:-https://artifacts.elastic.co/downloads/kibana}"
KIBANA_SHA512="${KIBANA_SHA512:-abe6628dd58cbd2f878d0d158aa9e93c415cf6a39b5812adb8ac9dcfe6b8ec610fd0e802b75a8398c50b243a732aa53547ae253d6bd1a6f579c51c2ffef0499a}"
KIBANA_INSTALL_ROOT="${KIBANA_INSTALL_ROOT:-/opt/kibana}"
KIBANA_SERVICE_USER="${KIBANA_SERVICE_USER:-kibana}"
KIBANA_SERVER_NAME="${KIBANA_SERVER_NAME:-kibana.example.invalid}"
KIBANA_SERVER_HOST="${KIBANA_SERVER_HOST:-0.0.0.0}"
KIBANA_SERVER_PORT="${KIBANA_SERVER_PORT:-5601}"
KIBANA_PUBLIC_BASE_URL="${KIBANA_PUBLIC_BASE_URL:-}"
KIBANA_ELASTICSEARCH_HOSTS="${KIBANA_ELASTICSEARCH_HOSTS:-http://127.0.0.1:9200}"
KIBANA_TIMEZONE="${KIBANA_TIMEZONE:-UTC}"
KIBANA_NODE_OPTIONS="${KIBANA_NODE_OPTIONS:---max-old-space-size=2048}"
KIBANA_CACHE_DIR="${KIBANA_CACHE_DIR:-/var/cache/stage5-artifacts}"

pkg="kibana-${KIBANA_VERSION}-${KIBANA_ARCH}.tar.gz"
pkg_url="${KIBANA_BASE_URL}/${pkg}"
pkg_dir="${KIBANA_INSTALL_ROOT}/kibana-${KIBANA_VERSION}"

json_hosts() {
  python3 - "$@" << 'PY'
import json
import sys

hosts = [item.strip() for item in sys.argv[1].split(",") if item.strip()]
print(json.dumps(hosts))
PY
}

require_root() {
  if [[ "$(id -u)" != 0 ]]; then
    printf 'install-kibana-upstream-tarball: must run as root\n' >&2
    exit 2
  fi
}

ensure_user() {
  if ! getent group "${KIBANA_SERVICE_USER}" > /dev/null; then
    groupadd --system "${KIBANA_SERVICE_USER}"
  fi

  if ! id "${KIBANA_SERVICE_USER}" > /dev/null 2>&1; then
    useradd --system --gid "${KIBANA_SERVICE_USER}" --home-dir /var/lib/kibana --shell /sbin/nologin "${KIBANA_SERVICE_USER}"
  fi
}

install_artifact() {
  mkdir -p "${KIBANA_CACHE_DIR}" "${KIBANA_INSTALL_ROOT}"
  cd "${KIBANA_CACHE_DIR}"

  if [[ ! -s "${pkg}" ]]; then
    curl -fL --retry 5 --retry-delay 2 -O "${pkg_url}"
  fi

  printf '%s  %s\n' "${KIBANA_SHA512}" "${pkg}" | sha512sum -c -

  if [[ ! -d "${pkg_dir}" ]]; then
    tmpdir="$(mktemp -d)"
    tar -xzf "${pkg}" -C "${tmpdir}"
    rm -rf "${pkg_dir}"
    mv "${tmpdir}/kibana-${KIBANA_VERSION}" "${pkg_dir}"
    rmdir "${tmpdir}"
  fi

  ln -sfn "${pkg_dir}" "${KIBANA_INSTALL_ROOT}/current"
  chown -R root:root "${pkg_dir}"
}

render_config() {
  mkdir -p /etc/kibana /var/lib/kibana /var/log/kibana /run/kibana "${KIBANA_INSTALL_ROOT}/current/data"
  chown -R "${KIBANA_SERVICE_USER}:${KIBANA_SERVICE_USER}" /var/lib/kibana /var/log/kibana /run/kibana "${KIBANA_INSTALL_ROOT}/current/data"

  cat > /etc/kibana/kibana.yml << EOF
# Managed by RFC_Codex_Gentoo-Stage4-LLVM.
server.name: "${KIBANA_SERVER_NAME}"
server.host: "${KIBANA_SERVER_HOST}"
server.port: ${KIBANA_SERVER_PORT}
elasticsearch.hosts: $(json_hosts "${KIBANA_ELASTICSEARCH_HOSTS}")
path.data: "/var/lib/kibana"
logging:
  appenders:
    file:
      type: file
      fileName: /var/log/kibana/kibana.log
      layout:
        type: json
  root:
    appenders: [default, file]
    level: info
telemetry.enabled: false
EOF

  if [[ -n "${KIBANA_PUBLIC_BASE_URL}" ]]; then
    printf 'server.publicBaseUrl: "%s"\n' "${KIBANA_PUBLIC_BASE_URL}" >> /etc/kibana/kibana.yml
  fi

  cat > /etc/init.d/kibana << EOF
#!/sbin/openrc-run

name="Kibana"
description="Elastic Kibana web interface"
command="${KIBANA_INSTALL_ROOT}/current/bin/kibana"
command_user="${KIBANA_SERVICE_USER}:${KIBANA_SERVICE_USER}"
directory="${KIBANA_INSTALL_ROOT}/current"
supervisor="supervise-daemon"
pidfile="/run/kibana/kibana.pid"
output_log="/var/log/kibana/kibana-openrc.log"
error_log="/var/log/kibana/kibana-openrc.err"
respawn_delay=10
respawn_period=60
respawn_max=3

export TZ="${KIBANA_TIMEZONE}"
export KBN_PATH_CONF="/etc/kibana"
export NODE_OPTIONS="${KIBANA_NODE_OPTIONS}"

depend() {
  need net
  after firewall
}

start_pre() {
  checkpath -d -m 0755 -o ${KIBANA_SERVICE_USER}:${KIBANA_SERVICE_USER} /run/kibana /var/lib/kibana /var/log/kibana ${KIBANA_INSTALL_ROOT}/current/data
}
EOF
  chmod 0755 /etc/init.d/kibana
}

main() {
  require_root
  ensure_user
  install_artifact
  render_config
  rc-update add kibana default > /dev/null || true
  rc-service kibana restart || rc-service kibana start
}

main "$@"
