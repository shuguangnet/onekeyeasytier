#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_NETWORK_NAME="hostdzire"
readonly DEFAULT_PEER="tcp://tcc.933999.xyz:11010"
readonly DEFAULT_LISTEN_PORT="11010"
readonly DEFAULT_MTU="1380"
readonly GITHUB_RELEASES_API="https://api.github.com/repos/EasyTier/EasyTier/releases"
readonly INSTALL_DIR="/usr/local/bin"
readonly CONFIG_DIR="/etc/easytier"
readonly CONFIG_FILE="${CONFIG_DIR}/node.toml"
readonly SECRET_FILE_DEFAULT="${CONFIG_DIR}/network.secret"
readonly SERVICE_NAME="easytier"
readonly FIREWALL_HELPER="/usr/local/sbin/easytier-overlay-firewall"

EASYTIER_VERSION=${EASYTIER_VERSION:-latest}
EASYTIER_NETWORK_NAME=${EASYTIER_NETWORK_NAME:-${DEFAULT_NETWORK_NAME}}
EASYTIER_PEER=${EASYTIER_PEER:-${DEFAULT_PEER}}
EASYTIER_IPV4=${EASYTIER_IPV4:-}
EASYTIER_LISTEN_PORT=${EASYTIER_LISTEN_PORT:-${DEFAULT_LISTEN_PORT}}
EASYTIER_MTU=${EASYTIER_MTU:-${DEFAULT_MTU}}
EASYTIER_TRUST_CIDR=${EASYTIER_TRUST_CIDR:-10.126.126.0/24}
EASYTIER_SECRET_FILE=${EASYTIER_SECRET_FILE:-${SECRET_FILE_DEFAULT}}
EASYTIER_SHA256=${EASYTIER_SHA256:-}
EASYTIER_NETWORK_SECRET=${EASYTIER_NETWORK_SECRET:-}
RELEASE_VERSION=""
RELEASE_ARCHIVE_NAME=""
RELEASE_DOWNLOAD_URL=""
RELEASE_SHA256=""

usage() {
  cat <<'EOF'
Install or update this Linux host as an EasyTier node.

Usage:
  curl -fsSL https://raw.githubusercontent.com/shuguangnet/onekeyeasytier/main/install-easytier-node.sh | sudo bash

The default network is hostdzire and the default peer is:
  tcp://tcc.933999.xyz:11010

The installer prompts for the network secret on first use and stores it at
/etc/easytier/network.secret with mode 0600. Re-running the same command uses
the saved secret and updates the node idempotently.

Optional environment variables:
  EASYTIER_NETWORK_NAME   Override the network name.
  EASYTIER_PEER           Override the seed peer URI.
  EASYTIER_IPV4           Static overlay address, for example 10.126.126.20/24.
                          Leave empty to use EasyTier DHCP (the default).
  EASYTIER_SECRET_FILE    Read/save the secret at another root-only path.
  EASYTIER_VERSION        Install a specific release tag instead of latest.
  EASYTIER_SHA256         Optional expected SHA256 for the selected archive.
  EASYTIER_LISTEN_PORT    Local EasyTier TCP/UDP listener port.
  EASYTIER_MTU            Overlay MTU (default 1380).
  EASYTIER_TRUST_CIDR     Allow inbound tun0 traffic from this overlay CIDR.
                          Default: 10.126.126.0/24. Set to "none" to disable.

Non-interactive example with an existing root-only secret file:
  curl -fsSL https://raw.githubusercontent.com/shuguangnet/onekeyeasytier/main/install-easytier-node.sh | \
    sudo EASYTIER_SECRET_FILE=/root/easytier.secret bash
EOF
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

log() {
  echo "[easytier-node] $*"
}

require_root() {
  [ "$(id -u)" -eq 0 ] || fail "run with sudo or as root"
}

validate_value() {
  local label=$1
  local value=$2
  [ -n "${value}" ] || fail "${label} must not be empty"
  case "${value}" in
    *$'\n'*|*$'\r'*) fail "${label} must be a single line" ;;
  esac
}

validate_settings() {
  validate_value "network name" "${EASYTIER_NETWORK_NAME}"
  validate_value "peer URI" "${EASYTIER_PEER}"
  [[ "${EASYTIER_PEER}" =~ ^(tcp|udp|wg|ws|wss):// ]] || fail "unsupported peer URI: ${EASYTIER_PEER}"
  [[ "${EASYTIER_LISTEN_PORT}" =~ ^[0-9]+$ ]] || fail "listener port must be numeric"
  ((EASYTIER_LISTEN_PORT >= 1 && EASYTIER_LISTEN_PORT <= 65535)) || fail "listener port is out of range"
  [[ "${EASYTIER_MTU}" =~ ^[0-9]+$ ]] || fail "MTU must be numeric"
  ((EASYTIER_MTU >= 576 && EASYTIER_MTU <= 9000)) || fail "MTU is out of range"
  if [ "${EASYTIER_VERSION}" != "latest" ]; then
    [[ "${EASYTIER_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?$ ]] || fail "invalid EasyTier version"
  fi
  if [ -n "${EASYTIER_SHA256}" ]; then
    [[ "${EASYTIER_SHA256}" =~ ^[a-fA-F0-9]{64}$ ]] || fail "EASYTIER_SHA256 must contain 64 hexadecimal characters"
  fi
  if [ -n "${EASYTIER_IPV4}" ]; then
    [[ "${EASYTIER_IPV4}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] || fail "EASYTIER_IPV4 must use IPv4/CIDR notation"
  fi
  if [ "${EASYTIER_TRUST_CIDR}" != "none" ]; then
    [[ "${EASYTIER_TRUST_CIDR}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] || fail "EASYTIER_TRUST_CIDR must use IPv4/CIDR notation or be none"
  fi
}

install_dependencies() {
  local missing=()
  local command_name
  for command_name in curl jq unzip sha256sum install; do
    command -v "${command_name}" >/dev/null 2>&1 || missing+=("${command_name}")
  done
  [ "${#missing[@]}" -eq 0 ] && return

  log "installing required packages"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl jq unzip coreutils
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache ca-certificates curl jq unzip coreutils
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y ca-certificates curl jq unzip coreutils
  elif command -v yum >/dev/null 2>&1; then
    yum install -y ca-certificates curl jq unzip coreutils
  else
    fail "install curl, jq, unzip, coreutils, and CA certificates manually"
  fi
}

release_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    armv7l|armv7) echo "armv7" ;;
    *) fail "unsupported architecture: $(uname -m)" ;;
  esac
}

resolve_release() {
  local arch=$1
  local release_url release_json asset_json official_digest

  if [ "${EASYTIER_VERSION}" = "latest" ]; then
    release_url="${GITHUB_RELEASES_API}/latest"
  else
    release_url="${GITHUB_RELEASES_API}/tags/${EASYTIER_VERSION}"
  fi

  log "resolving EasyTier ${EASYTIER_VERSION} release"
  release_json=$(curl -fsSL --retry 3 --retry-delay 2 \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${release_url}") || fail "unable to query EasyTier release metadata"

  RELEASE_VERSION=$(jq -er '.tag_name | select(type == "string")' <<<"${release_json}") || \
    fail "release metadata does not contain a tag"
  [[ "${RELEASE_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?$ ]] || \
    fail "release returned an invalid tag: ${RELEASE_VERSION}"
  RELEASE_ARCHIVE_NAME="easytier-linux-${arch}-${RELEASE_VERSION}.zip"
  asset_json=$(jq -cer --arg name "${RELEASE_ARCHIVE_NAME}" \
    '[.assets[] | select(.name == $name)] | if length == 1 then .[0] else empty end' \
    <<<"${release_json}") || fail "release does not contain ${RELEASE_ARCHIVE_NAME}"
  RELEASE_DOWNLOAD_URL=$(jq -er '.browser_download_url | select(type == "string")' <<<"${asset_json}") || \
    fail "release asset does not contain a download URL"
  official_digest=$(jq -er '.digest | select(type == "string" and startswith("sha256:"))' \
    <<<"${asset_json}") || fail "release asset does not contain a SHA256 digest"
  RELEASE_SHA256=${official_digest#sha256:}
  [[ "${RELEASE_SHA256}" =~ ^[a-fA-F0-9]{64}$ ]] || fail "release asset contains an invalid SHA256 digest"

  if [ -n "${EASYTIER_SHA256}" ] && [ "${EASYTIER_SHA256,,}" != "${RELEASE_SHA256,,}" ]; then
    fail "EASYTIER_SHA256 does not match the digest published by GitHub"
  fi
}

read_network_secret() {
  if [ -n "${EASYTIER_NETWORK_SECRET}" ]; then
    :
  elif [ -f "${EASYTIER_SECRET_FILE}" ]; then
    local secret_mode
    secret_mode=$(stat -c '%a' "${EASYTIER_SECRET_FILE}")
    [ "$((8#${secret_mode} & 8#077))" -eq 0 ] || fail "secret file must be mode 0600: ${EASYTIER_SECRET_FILE}"
    EASYTIER_NETWORK_SECRET=$(tr -d '\r\n' < "${EASYTIER_SECRET_FILE}")
  else
    [ -r /dev/tty ] || fail "no TTY available; provide EASYTIER_SECRET_FILE"
    printf 'EasyTier network secret: ' >/dev/tty
    IFS= read -r -s EASYTIER_NETWORK_SECRET </dev/tty
    printf '\n' >/dev/tty
  fi

  validate_value "network secret" "${EASYTIER_NETWORK_SECRET}"

  if [ ! -f "${EASYTIER_SECRET_FILE}" ]; then
    install -d -m 0700 "$(dirname "${EASYTIER_SECRET_FILE}")"
    umask 077
    printf '%s\n' "${EASYTIER_NETWORK_SECRET}" > "${EASYTIER_SECRET_FILE}"
    chmod 0600 "${EASYTIER_SECRET_FILE}"
  fi
}

toml_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '%s' "${value}"
}

install_release() {
  local arch=$1
  local temp_dir
  temp_dir=$(mktemp -d /tmp/easytier-node.XXXXXX)
  trap 'rm -rf -- "${temp_dir}"' RETURN

  log "downloading EasyTier ${RELEASE_VERSION} for ${arch}"
  curl -fL --retry 3 --retry-delay 2 -o "${temp_dir}/${RELEASE_ARCHIVE_NAME}" "${RELEASE_DOWNLOAD_URL}"
  printf '%s  %s\n' "${RELEASE_SHA256}" "${temp_dir}/${RELEASE_ARCHIVE_NAME}" | sha256sum -c -
  unzip -q "${temp_dir}/${RELEASE_ARCHIVE_NAME}" -d "${temp_dir}/extract"

  local release_dir="${temp_dir}/extract/easytier-linux-${arch}"
  [ -x "${release_dir}/easytier-core" ] || fail "release does not contain easytier-core"
  [ -x "${release_dir}/easytier-cli" ] || fail "release does not contain easytier-cli"
  install -m 0755 "${release_dir}/easytier-core" "${INSTALL_DIR}/easytier-core"
  install -m 0755 "${release_dir}/easytier-cli" "${INSTALL_DIR}/easytier-cli"

  rm -rf -- "${temp_dir}"
  trap - RETURN
}

write_config() {
  local network_name secret peer instance_name
  network_name=$(toml_escape "${EASYTIER_NETWORK_NAME}")
  secret=$(toml_escape "${EASYTIER_NETWORK_SECRET}")
  peer=$(toml_escape "${EASYTIER_PEER}")
  instance_name=$(toml_escape "$(hostname)")

  install -d -m 0700 "${CONFIG_DIR}" /var/lib/easytier
  umask 077
  if [ -n "${EASYTIER_IPV4}" ]; then
    cat > "${CONFIG_FILE}" <<EOF
instance_name = "${instance_name}"
hostname = "${instance_name}"
ipv4 = "${EASYTIER_IPV4}"
dhcp = false
listeners = ["tcp://0.0.0.0:${EASYTIER_LISTEN_PORT}", "udp://0.0.0.0:${EASYTIER_LISTEN_PORT}"]
rpc_portal = "127.0.0.1:15888"

[[peer]]
uri = "${peer}"

[network_identity]
network_name = "${network_name}"
network_secret = "${secret}"

[flags]
default_protocol = "udp"
enable_encryption = true
enable_ipv6 = false
mtu = ${EASYTIER_MTU}
latency_first = false
enable_exit_node = false
no_tun = false
use_smoltcp = false
disable_p2p = false
p2p_only = false
relay_all_peer_rpc = false
disable_tcp_hole_punching = false
disable_udp_hole_punching = false
EOF
  else
    cat > "${CONFIG_FILE}" <<EOF
instance_name = "${instance_name}"
hostname = "${instance_name}"
ipv4 = ""
dhcp = true
listeners = ["tcp://0.0.0.0:${EASYTIER_LISTEN_PORT}", "udp://0.0.0.0:${EASYTIER_LISTEN_PORT}"]
rpc_portal = "127.0.0.1:15888"

[[peer]]
uri = "${peer}"

[network_identity]
network_name = "${network_name}"
network_secret = "${secret}"

[flags]
default_protocol = "udp"
enable_encryption = true
enable_ipv6 = false
mtu = ${EASYTIER_MTU}
latency_first = false
enable_exit_node = false
no_tun = false
use_smoltcp = false
disable_p2p = false
p2p_only = false
relay_all_peer_rpc = false
disable_tcp_hole_punching = false
disable_udp_hole_punching = false
EOF
  fi
  chmod 0600 "${CONFIG_FILE}"
  "${INSTALL_DIR}/easytier-core" -c "${CONFIG_FILE}" --check-config >/dev/null
}

install_firewall_helper() {
  install -d -m 0755 "$(dirname "${FIREWALL_HELPER}")"
  if [ "${EASYTIER_TRUST_CIDR}" = "none" ]; then
    cat > "${FIREWALL_HELPER}" <<'EOF'
#!/bin/sh
exit 0
EOF
  else
    local trust_cidr
    trust_cidr=$(printf '%s' "${EASYTIER_TRUST_CIDR}" | sed 's/[\\&|]/\\&/g')
    cat > "${FIREWALL_HELPER}" <<EOF
#!/bin/sh
set -eu

if command -v iptables >/dev/null 2>&1; then
  iptables -C INPUT -i tun0 -s ${trust_cidr} -j ACCEPT >/dev/null 2>&1 || \
    iptables -I INPUT 1 -i tun0 -s ${trust_cidr} -j ACCEPT
fi
EOF
  fi
  chmod 0755 "${FIREWALL_HELPER}"
}

install_service() {
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=EasyTier private overlay node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/var/lib/easytier
ExecStartPre=${INSTALL_DIR}/easytier-core -c ${CONFIG_FILE} --check-config
ExecStart=${INSTALL_DIR}/easytier-core -c ${CONFIG_FILE}
ExecStartPost=${FIREWALL_HELPER}
Restart=always
RestartSec=3s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now "${SERVICE_NAME}.service"
    systemctl restart "${SERVICE_NAME}.service"
  elif command -v rc-service >/dev/null 2>&1; then
    cat > "/etc/init.d/${SERVICE_NAME}" <<EOF
#!/sbin/openrc-run
description="EasyTier private overlay node"
supervisor=supervise-daemon
command="${INSTALL_DIR}/easytier-core"
command_args="-c ${CONFIG_FILE}"
command_user="root"
pidfile="/run/${SERVICE_NAME}.pid"

start_post() {
  ${FIREWALL_HELPER}
}

depend() {
  need net
  after firewall
}
EOF
    chmod 0755 "/etc/init.d/${SERVICE_NAME}"
    rc-update add "${SERVICE_NAME}" default >/dev/null 2>&1 || true
    rc-service "${SERVICE_NAME}" restart || rc-service "${SERVICE_NAME}" start
  else
    fail "this installer requires systemd or OpenRC"
  fi
}

verify_node() {
  local attempt peer_output node_output
  for attempt in $(seq 1 20); do
    if node_output=$("${INSTALL_DIR}/easytier-cli" -o json node 2>/dev/null) && \
       peer_output=$("${INSTALL_DIR}/easytier-cli" peer 2>/dev/null) && \
       printf '%s\n' "${peer_output}" | grep -Eq '\|[[:space:]]+(p2p|relay)[[:space:]]+\|'; then
      log "node joined successfully"
      printf '%s\n' "${node_output}"
      "${INSTALL_DIR}/easytier-cli" peer
      return
    fi
    sleep 2
  done

  echo "EasyTier service started, but no remote peer was visible after 40 seconds." >&2
  echo "Check DNS, TCP/UDP ${EASYTIER_LISTEN_PORT}, the peer URI, and the network secret." >&2
  if command -v systemctl >/dev/null 2>&1; then
    systemctl status "${SERVICE_NAME}.service" --no-pager -l >&2 || true
  fi
  exit 1
}

main() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
  fi
  [ "$#" -eq 0 ] || fail "unknown argument: $1"

  require_root
  validate_settings
  install_dependencies
  read_network_secret

  local arch
  arch=$(release_arch)
  resolve_release "${arch}"
  install_release "${arch}"
  write_config
  install_firewall_helper
  install_service
  verify_node
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
