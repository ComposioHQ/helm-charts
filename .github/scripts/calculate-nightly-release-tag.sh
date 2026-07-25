#!/usr/bin/env bash

set -euo pipefail

CHART_OCI_REF="${CHART_OCI_REF:-oci://registry.composio.io/composio-rodent/nightly/composio}"
NIGHTLY_CHANNEL_NAME="${NIGHTLY_CHANNEL_NAME:-Nightly}"

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

resolve_nightly_channel() {
  local app_id="$1"
  local channels_json total_count channel_id current_version release_sequence

  channels_json="$(
    curl -fsSLG "https://api.replicated.com/vendor/v3/app/${app_id}/channels" \
      --data-urlencode "channelName=${NIGHTLY_CHANNEL_NAME}" \
      --header "Accept: application/json" \
      --header "Authorization: ${REPLICATED_API_TOKEN}"
  )"

  total_count="$(echo "${channels_json}" | jq -r '.totalCount // (.channels | length)')"
  if [[ "${total_count}" != "1" ]]; then
    echo "${NIGHTLY_CHANNEL_NAME} channel was not found in Replicated channels API response" >&2
    exit 1
  fi

  channel_id="$(echo "${channels_json}" | jq -r '.channels[0].id // .channels[0].channelId // empty')"
  current_version="$(echo "${channels_json}" | jq -r '.channels[0].currentVersion // empty')"
  release_sequence="$(echo "${channels_json}" | jq -r '.channels[0].releaseSequence // .channels[0].currentReleaseSequence // empty')"

  if [[ -z "${current_version}" || "${current_version}" == "null" ]]; then
    echo "${NIGHTLY_CHANNEL_NAME} channel response did not include currentVersion" >&2
    exit 1
  fi

  jq -n \
    --arg id "${channel_id}" \
    --arg currentVersion "${current_version}" \
    --arg releaseSequence "${release_sequence}" \
    '{id: $id, currentVersion: $currentVersion, releaseSequence: $releaseSequence}'
}

pull_nightly_values() {
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

extract_base_calendar_tag() {
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
    | select(test("^r[0-9]{8}_[0-9]{2}$"))
  ' "${values_file}" | sort -u | tail -n1
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

main() {
  local date_ist app_id channel_json channel_id current_version release_sequence values_file base_tag new_tag

  require_cmd jq

  date_ist="${RELEASE_TAG_DATE:-$(TZ=Asia/Kolkata date +%Y%m%d)}"
  app_id=""
  channel_id=""
  current_version=""
  release_sequence=""

  if [[ -n "${NIGHTLY_VALUES_FILE:-}" ]]; then
    values_file="${NIGHTLY_VALUES_FILE}"
  else
    require_cmd curl

    app_id="$(resolve_replicated_app_id)"
    channel_json="$(resolve_nightly_channel "${app_id}")"
    channel_id="$(echo "${channel_json}" | jq -r '.id // empty')"
    current_version="$(echo "${channel_json}" | jq -r '.currentVersion // empty')"
    release_sequence="$(echo "${channel_json}" | jq -r '.releaseSequence // empty')"
    values_file="$(pull_nightly_values "${current_version}")"
  fi

  base_tag="$(extract_base_calendar_tag "${values_file}")"
  new_tag="$(calculate_next_calendar_tag "${base_tag}" "${date_ist}")"

  echo "Replicated app id: ${app_id:-not resolved}"
  echo "Nightly channel id: ${channel_id:-not resolved}"
  echo "Nightly current chart version: ${current_version:-not resolved}"
  echo "Nightly release sequence: ${release_sequence:-not resolved}"
  echo "Base image tag used for increment: ${base_tag:-none}"
  echo "Calculated release tag: ${new_tag}"

  write_output "replicated_app_id" "${app_id}"
  write_output "replicated_channel_id" "${channel_id}"
  write_output "replicated_current_version" "${current_version}"
  write_output "replicated_release_sequence" "${release_sequence}"
  write_output "base_tag" "${base_tag}"
  write_output "release_tag" "${new_tag}"
}

main "$@"
