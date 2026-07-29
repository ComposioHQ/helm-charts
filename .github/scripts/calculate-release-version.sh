#!/usr/bin/env bash

set -euo pipefail

release_type="${RELEASE_TYPE:-standard}"
current_version="${CURRENT_VERSION:-}"
version_prefix="${VERSION_PREFIX:-}"
release_channel_name="${RELEASE_CHANNEL_NAME:-Selected}"

write_output() {
  local key="$1"
  local value="$2"

  echo "${key}=${value}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "${GITHUB_OUTPUT}"
  fi
}

case "${release_type}" in
  standard)
    if [[ ! "${current_version}" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
      echo "${release_channel_name} channel returned an invalid currentVersion: ${current_version:-<empty>}" >&2
      exit 1
    fi
    new_version="$(awk -F. '{$NF = $NF + 1} 1' OFS=. <<<"${current_version}")"
    ;;
  glean)
    if [[ -z "${version_prefix}" ]]; then
      echo "VERSION_PREFIX is required." >&2
      exit 1
    fi

    if [[ -z "${current_version}" ]]; then
      new_version="${version_prefix}.1"
    else
      version_prefix_pattern="${version_prefix//./\\.}"
      if [[ ! "${current_version}" =~ ^${version_prefix_pattern}\.([0-9]+)$ ]]; then
        echo "${release_channel_name} currentVersion must match ${version_prefix}.x: ${current_version}" >&2
        exit 1
      fi
      new_version="${version_prefix}.$((10#${BASH_REMATCH[1]} + 1))"
    fi
    ;;
  *)
    echo "Unsupported release type: ${release_type}" >&2
    exit 1
    ;;
esac

write_output current "${current_version}"
write_output new "${new_version}"
