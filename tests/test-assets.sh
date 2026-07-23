#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
refresh_script="${repo_root}/skills/easytier-fleet-ssh/scripts/refresh-assets.sh"
ssh_helper="${repo_root}/skills/easytier-fleet-ssh/scripts/et-ssh"
temp_dir=$(mktemp -d)
trap 'rm -rf -- "${temp_dir}"' EXIT

mkdir -p "${temp_dir}/bin" "${temp_dir}/assets" "${temp_dir}/etc"
cat > "${temp_dir}/bin/easytier-cli" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[
  {"cidr":"10.126.126.1/24","ipv4":"10.126.126.1","hostname":"seed-01","cost":"Local","lat_ms":"-","loss_rate":"-","tunnel_proto":"-","nat_type":"NoPat","version":"2.6.4"},
  {"cidr":"10.126.126.2/24","ipv4":"10.126.126.2","hostname":"worker-01","cost":"p2p","lat_ms":"36.10","loss_rate":"0.0%","tunnel_proto":"tcp","nat_type":"PortRestricted","version":"2.6.4"},
  {"cidr":"","ipv4":"","hostname":"PublicServer_seed-01","cost":"p2p","lat_ms":"1.00","loss_rate":"0.0%","tunnel_proto":"tcp","nat_type":"Unknown","version":"2.6.4"}
]
JSON
EOF
chmod 0755 "${temp_dir}/bin/easytier-cli"

cat > "${temp_dir}/etc/config" <<'EOF'
SSH_USER=root
SSH_PORT=22
SSH_IDENTITY_FILE=
EOF

EASYTIER_ASSET_DIR="${temp_dir}/assets" \
EASYTIER_ASSET_CONFIG="${temp_dir}/etc/config" \
EASYTIER_KNOWN_HOSTS="${temp_dir}/etc/known_hosts" \
EASYTIER_CLI="${temp_dir}/bin/easytier-cli" \
  bash "${refresh_script}" >/dev/null

jq -e '.nodes | length == 2' "${temp_dir}/assets/nodes.json" >/dev/null
jq -e '.nodes[] | select(.alias == "worker-01" and .overlay_ip == "10.126.126.2" and .status == "online")' \
  "${temp_dir}/assets/nodes.json" >/dev/null
grep -q 'worker-01' "${temp_dir}/assets/NODES.md"

cat > "${temp_dir}/bin/easytier-cli" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[
  {"cidr":"10.126.126.1/24","ipv4":"10.126.126.1","hostname":"seed-01","cost":"Local","lat_ms":"-","loss_rate":"-","tunnel_proto":"-","nat_type":"NoPat","version":"2.6.4"}
]
JSON
EOF
chmod 0755 "${temp_dir}/bin/easytier-cli"

EASYTIER_ASSET_DIR="${temp_dir}/assets" \
EASYTIER_ASSET_CONFIG="${temp_dir}/etc/config" \
EASYTIER_KNOWN_HOSTS="${temp_dir}/etc/known_hosts" \
EASYTIER_CLI="${temp_dir}/bin/easytier-cli" \
  bash "${refresh_script}" >/dev/null
jq -e '.nodes[] | select(.alias == "worker-01" and .status == "offline")' \
  "${temp_dir}/assets/nodes.json" >/dev/null

list_output=$(EASYTIER_ASSET_DIR="${temp_dir}/assets" \
  EASYTIER_MARKDOWN_FILE="${temp_dir}/assets/NODES.md" \
  EASYTIER_KNOWN_HOSTS="${temp_dir}/etc/known_hosts" \
  EASYTIER_REFRESH_COMMAND=/bin/true \
  bash "${ssh_helper}" list)
grep -q 'worker-01' <<<"${list_output}"

if EASYTIER_ASSET_DIR="${temp_dir}/assets" \
  EASYTIER_INVENTORY_FILE="${temp_dir}/assets/nodes.json" \
  EASYTIER_KNOWN_HOSTS="${temp_dir}/etc/known_hosts" \
  EASYTIER_REFRESH_COMMAND=/bin/true \
  EASYTIER_SSH_AUDIT_FILE="${temp_dir}/audit.jsonl" \
  bash "${ssh_helper}" connect seed-01 >"${temp_dir}/connect.out" 2>"${temp_dir}/connect.err"; then
  echo "Untrusted SSH target was unexpectedly accepted." >&2
  exit 1
fi
grep -q 'SSH host key is not trusted' "${temp_dir}/connect.err"

bash -n "${refresh_script}"
bash -n "${ssh_helper}"
echo "Asset checks passed."
