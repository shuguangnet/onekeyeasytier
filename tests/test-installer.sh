#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
installer="${repo_root}/install-easytier-node.sh"

bash -n "${installer}"
help_output=$(bash "${installer}" --help)

grep -q 'shuguangnet/onekeyeasytier' <<<"${help_output}"
grep -q 'EASYTIER_IPV4' <<<"${help_output}"
grep -q 'DEFAULT_NETWORK_NAME="hostdzire"' "${installer}"
grep -q 'DEFAULT_PEER="tcp://tcc.933999.xyz:11010"' "${installer}"
grep -q 'iptables -C INPUT -i tun0' "${installer}"

if grep -Eq 'network_secret[[:space:]]*=[[:space:]]*"[^$]' "${installer}"; then
  echo "A hard-coded network secret was found." >&2
  exit 1
fi

echo "Installer checks passed."
