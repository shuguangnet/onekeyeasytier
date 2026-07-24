#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manager="${repo_root}/easytier.sh"
temp_dir=$(mktemp -d)
trap 'rm -rf -- "${temp_dir}"' EXIT

# shellcheck source=../easytier.sh
source "${manager}"

INSTALL_DIR="${temp_dir}/bin"
CONFIG_DIR="${temp_dir}/etc"
DEFAULT_CONFIG_FILE="${CONFIG_DIR}/easytier.toml"
NODE_CONFIG_FILE="${CONFIG_DIR}/node.toml"
CONFIG_FILE="${DEFAULT_CONFIG_FILE}"
SERVICE_FILE="${temp_dir}/easytier.service"
MANAGER_INSTALL_DIR="${temp_dir}/libexec"
MANAGER_INSTALL_PATH="${MANAGER_INSTALL_DIR}/easytier-manager.sh"
ALIAS_PATH="${temp_dir}/bin/et"
EXIT_ROUTE_HELPER="${CONFIG_DIR}/exit-route-helper.sh"
EXIT_ROUTE_PEERS_FILE="${CONFIG_DIR}/exit-route-peers"
EXIT_ROUTE_PREVIOUS_FILE="${CONFIG_DIR}/exit-route-previous-disable-p2p"
EXIT_ROUTE_PREVIOUS_ROUTES_FILE="${CONFIG_DIR}/exit-route-previous-routes"
mkdir -p "${INSTALL_DIR}" "${CONFIG_DIR}"
restart_service() { return 0; }

download_source="${temp_dir}/downloaded-manager.sh"
cp "${manager}" "${download_source}"
curl() {
  local output_file=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-o" ]; then
      output_file=$2
      shift 2
    else
      shift
    fi
  done
  cp "${download_source}" "${output_file}"
}
update_manager_script >/dev/null
cmp -s "${download_source}" "${MANAGER_INSTALL_PATH}"
[ "$(readlink "${ALIAS_PATH}")" = "${MANAGER_INSTALL_PATH}" ]
[ -x "${MANAGER_INSTALL_PATH}" ]
cp "${MANAGER_INSTALL_PATH}" "${temp_dir}/installed-manager.sh"
printf '<html>download failed</html>\n' > "${download_source}"
if update_manager_script >/dev/null 2>&1; then
  echo "Invalid manager download was unexpectedly installed." >&2
  exit 1
fi
cmp -s "${temp_dir}/installed-manager.sh" "${MANAGER_INSTALL_PATH}"

cat > "${INSTALL_DIR}/${CORE_BINARY_NAME}" <<'EOF'
#!/usr/bin/env bash
config_file=
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-c" ]; then
    config_file=$2
    shift 2
  else
    shift
  fi
done
! grep -q 'invalid-config' "${config_file}"
EOF
chmod 0755 "${INSTALL_DIR}/${CORE_BINARY_NAME}"

cat > "${CONFIG_FILE}" <<'EOF'
ipv4 = ""
dhcp = true

[[peer]]
uri = "tcp://seed-1.example:11010"

[[peer]]
uri = "udp://seed-2.example:11010"

[network_identity]
network_name = "example"
network_secret = "secret"

[flags]
mtu = 1380
EOF
chmod 0600 "${CONFIG_FILE}"

update_hostname <<< "macbook-air"
grep -q '^hostname = "macbook-air"$' "${CONFIG_FILE}"
[ "$(get_top_level_toml_string "hostname" "${CONFIG_FILE}")" = "macbook-air" ]
hostname_line=$(grep -n '^hostname = ' "${CONFIG_FILE}" | cut -d: -f1)
first_section_line=$(grep -n '^\[' "${CONFIG_FILE}" | head -n1 | cut -d: -f1)
[ "${hostname_line}" -lt "${first_section_line}" ]

set_top_level_toml_value "exit_nodes" '["10.126.126.2", "10.126.126.3"]' "${CONFIG_FILE}"
[ "$(get_top_level_toml_value "exit_nodes" "${CONFIG_FILE}")" = '["10.126.126.2", "10.126.126.3"]' ]
mapfile -t configured_exit_nodes < <(list_exit_nodes "${CONFIG_FILE}")
[ "${configured_exit_nodes[0]}" = "10.126.126.2" ]
[ "${configured_exit_nodes[1]}" = "10.126.126.3" ]
[ "$(format_exit_nodes_value '10.126.126.2, 10.126.126.3 10.126.126.2')" = '["10.126.126.2", "10.126.126.3"]' ]
if format_exit_nodes_value '10.126.126.2 999.1.1.1' >/dev/null; then
  echo "Invalid exit node address was unexpectedly accepted." >&2
  exit 1
fi
set_top_level_toml_value "exit_nodes" '[]' "${CONFIG_FILE}"
[ -z "$(list_exit_nodes "${CONFIG_FILE}")" ]
set_toml_value "enable_exit_node" "true" "${CONFIG_FILE}"
[ "$(get_toml_value "enable_exit_node" "${CONFIG_FILE}")" = "true" ]
set_toml_value "enable_exit_node" "false" "${CONFIG_FILE}"

[ "$(peer_uri_host 'tcp://seed.example:11010')" = "seed.example" ]
[ "$(peer_uri_host 'wss://203.0.113.20:11012/path')" = "203.0.113.20" ]
set_top_level_toml_value "routes" '["192.168.0.0/16"]' "${CONFIG_FILE}"
resolve_ipv4_host() { printf '%s\n' "203.0.113.10"; }
write_exit_route_state
grep -qx '203.0.113.10' "${EXIT_ROUTE_PEERS_FILE}"
grep -qx 'false' "${EXIT_ROUTE_PREVIOUS_FILE}"
grep -Fqx '["192.168.0.0/16"]' "${EXIT_ROUTE_PREVIOUS_ROUTES_FILE}"
create_exit_route_helper
bash -n "${EXIT_ROUTE_HELPER}"
grep -Fq 'ip route replace "$ip/32"' "${EXIT_ROUTE_HELPER}"
fake_bin="${temp_dir}/fake-bin"
route_log="${temp_dir}/route.log"
mkdir -p "${fake_bin}"
cat > "${fake_bin}/uname" <<'EOF'
#!/usr/bin/env bash
echo "${FAKE_UNAME:-Linux}"
EOF
cat > "${fake_bin}/ip" <<'EOF'
#!/usr/bin/env bash
if [ "$*" = "-4 route show default" ]; then
  echo "default via 192.0.2.1 dev eth0"
else
  printf '%s\n' "$*" >> "${ROUTE_LOG}"
fi
EOF
chmod 0755 "${fake_bin}/uname" "${fake_bin}/ip"
ROUTE_LOG="${route_log}" PATH="${fake_bin}:${PATH}" "${EXIT_ROUTE_HELPER}" prepare
grep -Fq 'route replace 203.0.113.10/32 via 192.0.2.1 dev eth0 metric 5' "${route_log}"
ROUTE_LOG="${route_log}" PATH="${fake_bin}:${PATH}" "${EXIT_ROUTE_HELPER}" cleanup
grep -Fq 'route del 203.0.113.10/32' "${route_log}"
cat > "${fake_bin}/route" <<'EOF'
#!/usr/bin/env bash
if [ "$*" = "-n get default" ]; then
  echo "   gateway: 192.0.2.1"
  echo " interface: en0"
else
  printf '%s\n' "$*" >> "${ROUTE_LOG}"
fi
EOF
chmod 0755 "${fake_bin}/route"
: > "${route_log}"
FAKE_UNAME=Darwin ROUTE_LOG="${route_log}" PATH="${fake_bin}:${PATH}" "${EXIT_ROUTE_HELPER}" prepare
grep -Fq -- '-n add -host 203.0.113.10 192.0.2.1' "${route_log}"
FAKE_UNAME=Darwin ROUTE_LOG="${route_log}" PATH="${fake_bin}:${PATH}" "${EXIT_ROUTE_HELPER}" cleanup
grep -Fq -- '-n delete -host 203.0.113.10' "${route_log}"
OS_TYPE=linux
create_service_file >/dev/null
grep -Fq "ExecStartPre=${EXIT_ROUTE_HELPER} prepare" "${SERVICE_FILE}"
grep -Fq "ExecStopPost=${EXIT_ROUTE_HELPER} cleanup" "${SERVICE_FILE}"
set_top_level_toml_value "routes" '[]' "${CONFIG_FILE}"
rm -f "${EXIT_ROUTE_PEERS_FILE}" "${EXIT_ROUTE_PREVIOUS_FILE}" "${EXIT_ROUTE_PREVIOUS_ROUTES_FILE}"

cp "${CONFIG_FILE}" "${NODE_CONFIG_FILE}"
cat > "${SERVICE_FILE}" <<EOF
[Service]
ExecStart=${INSTALL_DIR}/${CORE_BINARY_NAME} -c ${NODE_CONFIG_FILE}
EOF
CONFIG_FILE="${DEFAULT_CONFIG_FILE}"
select_active_config_file
[ "${CONFIG_FILE}" = "${NODE_CONFIG_FILE}" ]
update_hostname <<< "active-node"
grep -q '^hostname = "active-node"$' "${NODE_CONFIG_FILE}"
grep -q '^hostname = "macbook-air"$' "${DEFAULT_CONFIG_FILE}"

escaped_value='name\with"quote'
set_toml_value "network_name" "\"$(toml_escape "${escaped_value}")\"" "${CONFIG_FILE}"
grep -Fq 'network_name = "name\\with\"quote"' "${CONFIG_FILE}"
set_toml_value "network_name" '"example"' "${CONFIG_FILE}"
! show_config | grep -q 'network_secret = "secret"'
show_config | grep -q 'network_secret = "\*\*\*"'

grep -q $'1\ttcp://seed-1.example:11010' < <(list_peers "${CONFIG_FILE}")
grep -q $'2\tudp://seed-2.example:11010' < <(list_peers "${CONFIG_FILE}")

candidate=$(mktemp)
cp -p "${CONFIG_FILE}" "${candidate}"
update_peer_in_file "${candidate}" 2 "wss://new-seed.example:11012/"
commit_config_file "${candidate}"
grep -q 'uri = "wss://new-seed.example:11012/"' "${CONFIG_FILE}"

cp -p "${CONFIG_FILE}" "${candidate}"
delete_peer_from_file "${candidate}" 1
commit_config_file "${candidate}"
[ "$(list_peers "${CONFIG_FILE}" | wc -l | tr -d ' ')" = "1" ]
! grep -q 'seed-1.example' "${CONFIG_FILE}"

cp -p "${CONFIG_FILE}" "${candidate}"
add_peer_to_file "${candidate}" "tcp://seed-3.example:11010"
commit_config_file "${candidate}"
[ "$(list_peers "${CONFIG_FILE}" | wc -l | tr -d ' ')" = "2" ]

cp -p "${CONFIG_FILE}" "${candidate}"
set_toml_value "network_name" '"invalid-config"' "${candidate}"
if commit_config_file "${candidate}"; then
  echo "Invalid configuration was unexpectedly committed." >&2
  exit 1
fi
grep -q 'network_name = "example"' "${CONFIG_FILE}"

cp -p "${CONFIG_FILE}" "${candidate}"
set_toml_value "network_name" '"restart-failure"' "${candidate}"
restart_service() { return 1; }
if commit_config_file "${candidate}" >/dev/null 2>&1; then
  echo "Configuration with a failed service restart was unexpectedly committed." >&2
  exit 1
fi
grep -q 'network_name = "example"' "${CONFIG_FILE}"
restart_service() { return 0; }

rm -f "${candidate}"
bash -n "${manager}"
echo "Manager checks passed."
