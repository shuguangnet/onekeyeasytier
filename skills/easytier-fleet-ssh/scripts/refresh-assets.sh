#!/usr/bin/env bash
set -euo pipefail

asset_dir=${EASYTIER_ASSET_DIR:-/var/lib/easytier-assets}
config_file=${EASYTIER_ASSET_CONFIG:-/etc/easytier-assets/config}
known_hosts=${EASYTIER_KNOWN_HOSTS:-/etc/easytier-assets/known_hosts}
easytier_cli=${EASYTIER_CLI:-/usr/local/bin/easytier-cli}
inventory_file="${asset_dir}/nodes.json"
markdown_file="${asset_dir}/NODES.md"

ssh_user="root"
ssh_port="22"
ssh_identity_file=""
if [ -f "${config_file}" ]; then
  # This file is installed root-owned and mode 0600.
  # shellcheck disable=SC1090
  source "${config_file}"
  ssh_user=${SSH_USER:-${ssh_user}}
  ssh_port=${SSH_PORT:-${ssh_port}}
  ssh_identity_file=${SSH_IDENTITY_FILE:-${ssh_identity_file}}
fi
[[ "${ssh_port}" =~ ^[0-9]+$ ]] || { echo "Invalid SSH_PORT in ${config_file}" >&2; exit 1; }
((ssh_port >= 1 && ssh_port <= 65535)) || { echo "SSH_PORT is out of range" >&2; exit 1; }

for command_name in jq ssh-keygen; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Missing required command: ${command_name}" >&2
    exit 1
  }
done
[ -x "${easytier_cli}" ] || { echo "EasyTier CLI not found: ${easytier_cli}" >&2; exit 1; }

install -d -m 0700 "${asset_dir}" "$(dirname "${known_hosts}")"
touch "${known_hosts}"
chmod 0600 "${known_hosts}"
umask 077

temp_dir=$(mktemp -d "${asset_dir}/.refresh.XXXXXX")
trap 'rm -rf -- "${temp_dir}"' EXIT

if [ -f "${inventory_file}" ]; then
  cp "${inventory_file}" "${temp_dir}/previous.json"
else
  printf '{"nodes":[]}\n' > "${temp_dir}/previous.json"
fi

"${easytier_cli}" -o json peer > "${temp_dir}/current.json"
jq -e 'type == "array"' "${temp_dir}/current.json" >/dev/null
now=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

jq -n \
  --slurpfile previous "${temp_dir}/previous.json" \
  --slurpfile current "${temp_dir}/current.json" \
  --arg now "${now}" \
  --arg ssh_user "${ssh_user}" \
  --argjson ssh_port "${ssh_port}" \
  --arg ssh_identity_file "${ssh_identity_file}" '
  ($previous[0].nodes // []) as $old
  | ($current[0]
      | map(select((.ipv4 // "") != ""))
      | map(select(((.hostname // "") | startswith("PublicServer_")) | not))
      | map({
          alias: (.hostname // .ipv4),
          overlay_ip: .ipv4,
          cidr: (.cidr // ""),
          status: "online",
          local: ((.cost // "") == "Local"),
          connection: (.cost // "unknown"),
          latency_ms: (.lat_ms // "-"),
          loss: (.loss_rate // "-"),
          tunnel: (.tunnel_proto // "-"),
          nat: (.nat_type // "Unknown"),
          version: (.version // "unknown"),
          ssh_user: $ssh_user,
          ssh_port: $ssh_port,
          ssh_identity_file: $ssh_identity_file,
          last_seen: $now
        })) as $live
  | (reduce $old[] as $node ({};
      .[$node.overlay_ip] = ($node + {status: "offline", local: false})))
  | (reduce $live[] as $node (.;
      .[$node.overlay_ip] = ((.[$node.overlay_ip] // {}) + $node)))
  | {
      generated_at: $now,
      source: "easytier-cli peer",
      nodes: ([to_entries[].value] | sort_by(.overlay_ip))
    }
' > "${temp_dir}/nodes.json"

{
  echo "# EasyTier Node Assets"
  echo
  echo "Generated: ${now}"
  echo
  echo '| Alias | Overlay IP | State | Link | Latency | Version | SSH | Last Seen |'
  echo '|---|---|---|---|---:|---|---|---|'
  while IFS=$'\t' read -r alias ip status connection latency version last_seen; do
    trusted="pending"
    host_lookup=${ip}
    if [ "${ssh_port}" != "22" ]; then
      host_lookup="[${ip}]:${ssh_port}"
    fi
    if ssh-keygen -F "${host_lookup}" -f "${known_hosts}" >/dev/null 2>&1; then
      trusted="trusted"
    fi
    alias=${alias//|/\\|}
    printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
      "${alias}" "${ip}" "${status}" "${connection}" "${latency}" \
      "${version}" "${trusted}" "${last_seen}"
  done < <(jq -r '.nodes[] | [.alias,.overlay_ip,.status,.connection,.latency_ms,.version,.last_seen] | @tsv' "${temp_dir}/nodes.json")
} > "${temp_dir}/NODES.md"

install -m 0600 "${temp_dir}/nodes.json" "${inventory_file}"
install -m 0600 "${temp_dir}/NODES.md" "${markdown_file}"
printf '%s\n' "${inventory_file}"
