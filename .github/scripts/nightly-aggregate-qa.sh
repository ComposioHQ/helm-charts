#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  nightly-aggregate-qa.sh \
    --input-dir <path> \
    --release-tag <tag> \
    --replicated-version <version> \
    --output-markdown <path> \
    --output-json <path>
EOF
}

input_dir=""
release_tag=""
replicated_version=""
output_markdown=""
output_json=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input-dir)
      input_dir="$2"
      shift 2
      ;;
    --release-tag)
      release_tag="$2"
      shift 2
      ;;
    --replicated-version)
      replicated_version="$2"
      shift 2
      ;;
    --output-markdown)
      output_markdown="$2"
      shift 2
      ;;
    --output-json)
      output_json="$2"
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

if [[ -z "${input_dir}" || -z "${release_tag}" || -z "${replicated_version}" || -z "${output_markdown}" || -z "${output_json}" ]]; then
  usage >&2
  exit 1
fi

mapfile -t result_files < <(find "${input_dir}" -type f -name '*.json' | sort)

if [[ "${#result_files[@]}" -eq 0 ]]; then
  jq -n '[]' >"${output_json}"
else
  jq -s 'map(select(type == "object")) | sort_by(.distribution, .mode, .source_version)' "${result_files[@]}" >"${output_json}"
fi

total_count="$(jq 'length' "${output_json}")"
passed_count="$(jq '[.[] | select(.job_status == "success")] | length' "${output_json}")"
failed_count="$(jq '[.[] | select(.job_status != "success")] | length' "${output_json}")"

{
  echo "# QA Report"
  echo
  echo "- Nightly image tag: \`${release_tag}\`"
  echo "- Replicated/chart version: \`${replicated_version}\`"
  echo "- Validation jobs: \`${total_count}\`"
  echo "- Passed: \`${passed_count}\`"
  echo "- Failed: \`${failed_count}\`"
  echo
  echo "## Fresh Installs"
  echo
  echo "| Distribution | Kubernetes | Status | Cluster ID |"
  echo "| --- | --- | --- | --- |"
  while IFS= read -r row; do
    distribution="$(jq -r '.distribution' <<<"${row}")"
    cluster_version="$(jq -r '.cluster_version // ""' <<<"${row}")"
    status="$(jq -r '.job_status' <<<"${row}")"
    cluster_id="$(jq -r '.cluster_id // ""' <<<"${row}")"
    echo "| ${distribution} | ${cluster_version} | ${status} | ${cluster_id} |"
  done < <(jq -c '.[] | select(.mode == "fresh")' "${output_json}")
  echo
  echo "## Upgrades"
  echo
  echo "| Distribution | From | To | Kubernetes | Status | Cluster ID |"
  echo "| --- | --- | --- | --- | --- | --- |"
  while IFS= read -r row; do
    distribution="$(jq -r '.distribution' <<<"${row}")"
    source_version="$(jq -r '.source_version // ""' <<<"${row}")"
    target_version="$(jq -r '.target_version // ""' <<<"${row}")"
    cluster_version="$(jq -r '.cluster_version // ""' <<<"${row}")"
    status="$(jq -r '.job_status' <<<"${row}")"
    cluster_id="$(jq -r '.cluster_id // ""' <<<"${row}")"
    echo "| ${distribution} | ${source_version} | ${target_version} | ${cluster_version} | ${status} | ${cluster_id} |"
  done < <(jq -c '.[] | select(.mode == "upgrade")' "${output_json}")
} >"${output_markdown}"
