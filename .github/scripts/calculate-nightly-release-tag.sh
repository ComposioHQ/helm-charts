#!/usr/bin/env bash

set -euo pipefail

CHART_OCI_REF="${CHART_OCI_REF:-oci://registry.composio.io/composio-rodent/nightly/composio}"
RELEASE_CHANNEL_NAME="${RELEASE_CHANNEL_NAME:-${NIGHTLY_CHANNEL_NAME:-Nightly}}"
RELEASE_CHANNEL_ID="${RELEASE_CHANNEL_ID:-}"
TAG_CALCULATION_MODE="${TAG_CALCULATION_MODE:-standard}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_env() {
  if [[ -z "${!1:-}" ]]; then
    echo "$1 is required." >&2
    exit 1
  fi
}

write_output() {
  local key="$1"
  local value="$2"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "${GITHUB_OUTPUT}"
  fi
}

chart_name_from_ref() {
  basename "${CHART_OCI_REF}"
}

resolve_replicated_app_id() {
  local apps_json app_id

  require_env REPLICATED_APP
  require_env REPLICATED_API_TOKEN

  apps_json="$(
    curl -fsSL "https://api.replicated.com/vendor/v3/apps" \
      --header "Accept: application/json" \
      --header "Authorization: ${REPLICATED_API_TOKEN}"
  )"

  app_id="$(
    echo "${apps_json}" | jq -r --arg app "${REPLICATED_APP}" '
      .apps[]
      | select(.id == $app or .slug == $app or .name == $app)
      | .id
    ' | head -n1
  )"

  if [[ -z "${app_id}" || "${app_id}" == "null" ]]; then
    echo "Unable to resolve Replicated app ID for ${REPLICATED_APP}" >&2
    exit 1
  fi

  printf '%s' "${app_id}"
}

resolve_release_channel() {
  local app_id="$1"
  local channels_json total_count channel_id current_version release_sequence

  channels_json="$(
    curl -fsSLG "https://api.replicated.com/vendor/v3/app/${app_id}/channels" \
      --data-urlencode "channelName=${RELEASE_CHANNEL_NAME}" \
      --header "Accept: application/json" \
      --header "Authorization: ${REPLICATED_API_TOKEN}"
  )"

  total_count="$(echo "${channels_json}" | jq -r '.totalCount // (.channels | length)')"
  if [[ "${total_count}" != "1" ]]; then
    echo "${RELEASE_CHANNEL_NAME} channel was not found in Replicated channels API response" >&2
    exit 1
  fi

  channel_id="$(echo "${channels_json}" | jq -r '.channels[0].id // .channels[0].channelId // empty')"
  current_version="$(echo "${channels_json}" | jq -r '.channels[0].currentVersion // empty')"
  release_sequence="$(echo "${channels_json}" | jq -r '.channels[0].releaseSequence // .channels[0].currentReleaseSequence // empty')"

  if [[ -n "${RELEASE_CHANNEL_ID}" && "${channel_id}" != "${RELEASE_CHANNEL_ID}" ]]; then
    echo "${RELEASE_CHANNEL_NAME} channel ID mismatch: expected ${RELEASE_CHANNEL_ID}, got ${channel_id:-<empty>}" >&2
    exit 1
  fi

  if [[ -z "${current_version}" || "${current_version}" == "null" ]]; then
    echo "${RELEASE_CHANNEL_NAME} channel response did not include currentVersion" >&2
    exit 1
  fi

  jq -n \
    --arg id "${channel_id}" \
    --arg currentVersion "${current_version}" \
    --arg releaseSequence "${release_sequence}" \
    '{id: $id, currentVersion: $currentVersion, releaseSequence: $releaseSequence}'
}

pull_release_values() {
  local chart_version="$1"
  local chart_name pull_root chart_dir

  require_cmd helm

  chart_name="$(chart_name_from_ref)"
  pull_root="$(mktemp -d)"

  helm pull "${CHART_OCI_REF}" --version "${chart_version}" --untar --untardir "${pull_root}" >/dev/null

  chart_dir="${pull_root}/${chart_name}"
  if [[ ! -f "${chart_dir}/values.yaml" ]]; then
    echo "Chart pull succeeded but expected values.yaml was missing under ${chart_dir}" >&2
    exit 1
  fi

  printf '%s' "${chart_dir}/values.yaml"
}

extract_image_tags() {
  local values_file="$1"

  require_cmd yq

  yq -r '
    [
      .apollo.image.tag,
      .apollo.dbInit.image.tag,
      .thermos.image.tag,
      .thermos.dbInit.image.tag,
      .thermosMiscWorkers.image.tag,
      .mercury.image.tag,
      .frontend.image.tag,
      .weaviate.image.tag,
      .toolkitRegistry.image.tag
    ]
    | .[]
    | select(. != null)
    | tostring
  ' "${values_file}"
}

extract_base_calendar_tag() {
  local values_file="$1"

  extract_image_tags "${values_file}" \
    | awk '/^r[0-9]{8}_[0-9]{2}$/' \
    | sort -u \
    | tail -n1
}

extract_glean_tags() {
  local values_file="$1"

  extract_image_tags "${values_file}" \
    | awk '/^r[0-9]{8}_[0-9]{2}(-p[0-9]{8}_[0-9]{2})?$/' \
    | sort -u
}

calculate_next_calendar_tag() {
  local base_tag="$1"
  local date_ist="$2"
  local next_nn current_date current_nn

  if [[ "${base_tag}" =~ ^r([0-9]{8})_([0-9]{2})$ ]]; then
    current_date="${BASH_REMATCH[1]}"
    current_nn="${BASH_REMATCH[2]}"

    if [[ "${current_date}" == "${date_ist}" ]]; then
      next_nn="$(printf '%02d' "$((10#${current_nn} + 1))")"
    else
      next_nn="01"
    fi
  else
    next_nn="01"
  fi

  printf 'r%s_%s' "${date_ist}" "${next_nn}"
}

calculate_next_glean_tag() {
  local base_tag="$1"
  local suffix_tag="$2"
  local date_ist="$3"
  local next_nn="01"
  local suffix_date suffix_nn

  if [[ ! "${base_tag}" =~ ^r[0-9]{8}_[0-9]{2}$ ]]; then
    echo "Glean tag calculation requires a valid fixed base tag." >&2
    return 1
  fi

  if [[ "${suffix_tag}" =~ ^p([0-9]{8})_([0-9]{2})$ ]]; then
    suffix_date="${BASH_REMATCH[1]}"
    suffix_nn="${BASH_REMATCH[2]}"
    if [[ "${suffix_date}" == "${date_ist}" ]]; then
      next_nn="$(printf '%02d' "$((10#${suffix_nn} + 1))")"
    fi
  fi

  printf '%s-p%s_%s' "${base_tag}" "${date_ist}" "${next_nn}"
}

main() {
  local date_ist app_id channel_json channel_id current_version release_sequence
  local values_file base_tag suffix_tag new_tag glean_tags

  require_cmd jq

  date_ist="${RELEASE_TAG_DATE:-$(TZ=Asia/Kolkata date +%Y%m%d)}"
  app_id=""
  channel_id=""
  current_version=""
  release_sequence=""
  suffix_tag=""

  if [[ -n "${RELEASE_VALUES_FILE:-}" ]]; then
    values_file="${RELEASE_VALUES_FILE}"
  elif [[ -n "${NIGHTLY_VALUES_FILE:-}" ]]; then
    values_file="${NIGHTLY_VALUES_FILE}"
  else
    require_cmd curl

    app_id="$(resolve_replicated_app_id)"
    channel_json="$(resolve_release_channel "${app_id}")"
    channel_id="$(echo "${channel_json}" | jq -r '.id // empty')"
    current_version="$(echo "${channel_json}" | jq -r '.currentVersion // empty')"
    release_sequence="$(echo "${channel_json}" | jq -r '.releaseSequence // empty')"
    values_file="$(pull_release_values "${current_version}")"
  fi

  case "${TAG_CALCULATION_MODE}" in
    standard)
      base_tag="$(extract_base_calendar_tag "${values_file}")"
      new_tag="$(calculate_next_calendar_tag "${base_tag}" "${date_ist}")"
      ;;
    glean)
      glean_tags="$(extract_glean_tags "${values_file}")"
      base_tag="$(
        printf '%s\n' "${glean_tags}" \
          | sed -E 's/-p[0-9]{8}_[0-9]{2}$//' \
          | awk 'NF' \
          | sort -u \
          | tail -n1
      )"
      suffix_tag="$(
        printf '%s\n' "${glean_tags}" \
          | awk -v prefix="${base_tag}-" 'index($0, prefix) == 1 {
              sub("^" prefix, "", $0)
              print
            }' \
          | sort -u \
          | tail -n1
      )"
      new_tag="$(calculate_next_glean_tag "${base_tag}" "${suffix_tag}" "${date_ist}")"
      ;;
    *)
      echo "Unsupported tag calculation mode: ${TAG_CALCULATION_MODE}" >&2
      exit 1
      ;;
  esac

  echo "Replicated app id: ${app_id:-not resolved}"
  echo "${RELEASE_CHANNEL_NAME} channel id: ${channel_id:-not resolved}"
  echo "${RELEASE_CHANNEL_NAME} current chart version: ${current_version:-not resolved}"
  echo "${RELEASE_CHANNEL_NAME} release sequence: ${release_sequence:-not resolved}"
  echo "Base image tag used for increment: ${base_tag:-none}"
  echo "Suffix image tag used for increment: ${suffix_tag:-none}"
  echo "Calculated release tag: ${new_tag}"

  write_output "replicated_app_id" "${app_id}"
  write_output "replicated_channel_id" "${channel_id}"
  write_output "replicated_current_version" "${current_version}"
  write_output "replicated_release_sequence" "${release_sequence}"
  write_output "base_tag" "${base_tag}"
  write_output "suffix_tag" "${suffix_tag}"
  write_output "release_tag" "${new_tag}"
}

main "$@"
