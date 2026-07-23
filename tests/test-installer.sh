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
! grep -q 'DEFAULT_VERSION=' "${installer}"
grep -q 'EASYTIER_VERSION=${EASYTIER_VERSION:-latest}' "${installer}"

# shellcheck source=../install-easytier-node.sh
source "${installer}"
release_fixture='{
  "tag_name": "v9.8.7",
  "assets": [
    {
      "name": "easytier-linux-x86_64-v9.8.7.zip",
      "browser_download_url": "https://example.invalid/easytier.zip",
      "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
  ]
}'
curl() { printf '%s\n' "${release_fixture}"; }
EASYTIER_VERSION=latest
EASYTIER_SHA256=
resolve_release x86_64 >/dev/null
[ "${RELEASE_VERSION}" = "v9.8.7" ]
[ "${RELEASE_ARCHIVE_NAME}" = "easytier-linux-x86_64-v9.8.7.zip" ]
[ "${RELEASE_DOWNLOAD_URL}" = "https://example.invalid/easytier.zip" ]
[ "${RELEASE_SHA256}" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ]

if grep -Eq 'network secret must contain at least|#EASYTIER_NETWORK_SECRET.*-(ge|gt)' "${installer}"; then
  echo "A network secret length restriction was found." >&2
  exit 1
fi

if grep -Eq 'network_secret[[:space:]]*=[[:space:]]*"[^$]' "${installer}"; then
  echo "A hard-coded network secret was found." >&2
  exit 1
fi

echo "Installer checks passed."
