#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  nightly-render-release-notes.sh \
    --current-manifest <path> \
    --output <path> \
    [--baseline-manifest <path>]
EOF
}

current_manifest=""
baseline_manifest=""
output_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --current-manifest)
      current_manifest="$2"
      shift 2
      ;;
    --baseline-manifest)
      baseline_manifest="$2"
      shift 2
      ;;
    --output)
      output_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${current_manifest}" || -z "${output_path}" ]]; then
  usage >&2
  exit 1
fi

short_sha() {
  local value="$1"
  echo "${value:0:7}"
}

current_release_tag="$(jq -r '.release_tag' "${current_manifest}")"
current_version="$(jq -r '.replicated_version' "${current_manifest}")"

{
  echo "# Nightly Snapshot ${current_release_tag}"
  echo
  echo "- Replicated/chart version: \`${current_version}\`"
  echo "- Channel: \`Nightly\`"
  echo

  if [[ -z "${baseline_manifest}" || ! -f "${baseline_manifest}" ]]; then
    echo "No Stable manifest asset was found. This release is using bootstrap notes."
    echo
    echo "## Services"
    while IFS= read -r row; do
      name="$(jq -r '.name' <<<"${row}")"
      repo="$(jq -r '.source_repo' <<<"${row}")"
      sha="$(jq -r '.git_sha' <<<"${row}")"
      echo "- ${name}: \`$(short_sha "${sha}")\` (${repo})"
    done < <(jq -c '.services[]' "${current_manifest}")
    exit 0
  fi

  echo "## Service Changes Since Latest Stable"

  while IFS= read -r row; do
    name="$(jq -r '.name' <<<"${row}")"
    repo="$(jq -r '.source_repo' <<<"${row}")"
    new_sha="$(jq -r '.git_sha' <<<"${row}")"
    baseline_row="$(jq -c --arg name "${name}" '.services[] | select(.name == $name)' "${baseline_manifest}" || true)"

    if [[ -z "${baseline_row}" ]]; then
      echo "- ${name}: new in nightly at \`$(short_sha "${new_sha}")\`"
      continue
    fi

    old_sha="$(jq -r '.git_sha' <<<"${baseline_row}")"
    baseline_repo="$(jq -r '.source_repo' <<<"${baseline_row}")"

    if [[ "${old_sha}" == "${new_sha}" ]]; then
      echo "- ${name}: no change (\`$(short_sha "${new_sha}")\`)"
      continue
    fi

    compare_repo="${repo%.git}"
    if [[ -n "${repo}" && "${repo}" == "${baseline_repo}" && "${compare_repo}" == https://github.com/* ]]; then
      compare_url="${compare_repo}/compare/${old_sha}...${new_sha}"
      echo "- ${name}: \`$(short_sha "${old_sha}")\` -> \`$(short_sha "${new_sha}")\` ([compare](${compare_url}))"
    else
      echo "- ${name}: \`$(short_sha "${old_sha}")\` -> \`$(short_sha "${new_sha}")\`"
    fi
  done < <(jq -c '.services[]' "${current_manifest}")
} >"${output_path}"
