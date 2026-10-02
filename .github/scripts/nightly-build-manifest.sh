#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  nightly-build-manifest.sh \
    --inventory <path> \
    --registry-host <registry> \
    --source-tag <tag> \
    --release-tag <tag> \
    --github-release-tag <tag> \
    --replicated-version <version> \
    --channel <channel> \
    --output <path>
EOF
}

inventory=""
registry_host=""
source_tag="latest"
release_tag=""
github_release_tag=""
replicated_version=""
channel=""
output_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory)
      inventory="$2"
      shift 2
      ;;
    --registry-host)
      registry_host="$2"
      shift 2
      ;;
    --source-tag)
      source_tag="$2"
      shift 2
      ;;
    --release-tag)
      release_tag="$2"
      shift 2
      ;;
    --github-release-tag)
      github_release_tag="$2"
      shift 2
      ;;
    --replicated-version)
      replicated_version="$2"
      shift 2
      ;;
    --channel)
      channel="$2"
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

if [[ -z "${inventory}" || -z "${registry_host}" || -z "${release_tag}" || -z "${github_release_tag}" || -z "${replicated_version}" || -z "${channel}" || -z "${output_path}" ]]; then
  usage >&2
  exit 1
fi

if ! command -v crane >/dev/null 2>&1; then
  echo "crane is required but not installed." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not installed." >&2
  exit 1
fi

services_json='[]'

while IFS= read -r service_json; do
  service_name="$(jq -r '.name' <<<"${service_json}")"
  service_repo=""
  service_sha=""
  images_json='[]'

  while IFS= read -r image_json; do
    repository="$(jq -r '.repository' <<<"${image_json}")"
    resolved_from="${registry_host}/${repository}:${source_tag}"
    digest="$(crane digest "${resolved_from}")"
    config_json="$(crane config "${registry_host}/${repository}@${digest}")"
    source_repo="$(jq -r '.config.Labels["org.opencontainers.image.source"] // empty' <<<"${config_json}")"
    git_sha="$(jq -r '.config.Labels["org.opencontainers.image.revision"] // empty' <<<"${config_json}")"

    if [[ -z "${source_repo}" || -z "${git_sha}" ]]; then
      echo "Missing org.opencontainers.image.source or org.opencontainers.image.revision for ${resolved_from}" >&2
      exit 1
    fi

    if [[ -z "${service_repo}" ]]; then
      service_repo="${source_repo}"
      service_sha="${git_sha}"
    elif [[ "${service_repo}" != "${source_repo}" || "${service_sha}" != "${git_sha}" ]]; then
      echo "Resolved images for service ${service_name} do not share the same source repo and git SHA." >&2
      exit 1
    fi

    image_record="$(
      jq -nc \
        --arg repository "${repository}" \
        --arg source_ref "${source_tag}" \
        --arg source_digest "${digest}" \
        --arg nightly_tag "${release_tag}" \
        --arg resolved_from "${resolved_from}" \
        '{
          repository: $repository,
          source_ref: $source_ref,
          source_digest: $source_digest,
          nightly_tag: $nightly_tag,
          resolved_from: $resolved_from
        }'
    )"

    images_json="$(jq -c --argjson record "${image_record}" '. + [$record]' <<<"${images_json}")"
  done < <(jq -c '.images[]' <<<"${service_json}")

  service_record="$(
    jq -nc \
      --arg name "${service_name}" \
      --arg source_repo "${service_repo}" \
      --arg git_sha "${service_sha}" \
      --argjson images "${images_json}" \
      '{
        name: $name,
        source_repo: $source_repo,
        git_sha: $git_sha,
        images: $images
      }'
  )"
  services_json="$(jq -c --argjson record "${service_record}" '. + [$record]' <<<"${services_json}")"
done < <(jq -c '.services[]' "${inventory}")

created_at="$(TZ=Asia/Kolkata date --iso-8601=seconds)"

jq -n \
  --arg release_tag "${release_tag}" \
  --arg github_release_tag "${github_release_tag}" \
  --arg replicated_version "${replicated_version}" \
  --arg channel "${channel}" \
  --arg created_at "${created_at}" \
  --arg registry_host "${registry_host}" \
  --arg source_tag "${source_tag}" \
  --argjson services "${services_json}" \
  '{
    release_tag: $release_tag,
    github_release_tag: $github_release_tag,
    replicated_version: $replicated_version,
    channel: $channel,
    created_at: $created_at,
    source_registry: $registry_host,
    source_tag: $source_tag,
    services: $services
  }' >"${output_path}"
