#!/usr/bin/env bash
set -euo pipefail

CHART_DIR="${CHART_DIR:-./composio}"
OUTPUT_DIR="${OUTPUT_DIR:-cve-reports}"
RENDER_TEMPORAL="${RENDER_TEMPORAL:-1}"
OVERRIDE_IMAGE_TAGS="${OVERRIDE_IMAGE_TAGS:-}"

if [[ -z "${OVERRIDE_IMAGE_TAGS}" ]]; then
  if [[ -n "${RELEASE_TAG:-}" ]]; then
    OVERRIDE_IMAGE_TAGS="1"
  else
    OVERRIDE_IMAGE_TAGS="0"
  fi
fi

if [[ "${OVERRIDE_IMAGE_TAGS}" == "1" && -z "${RELEASE_TAG:-}" ]]; then
  echo "RELEASE_TAG is required when OVERRIDE_IMAGE_TAGS=1" >&2
  exit 1
fi

if [[ -z "${ECR_REGISTRY:-}" ]]; then
  echo "ECR_REGISTRY is required" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
rendered_images_file="${OUTPUT_DIR}/rendered-images.txt"
scan_targets_file="${OUTPUT_DIR}/scan-targets.json"
ignored_images_file="${OUTPUT_DIR}/ignored-images.txt"
ignored_scan_targets_file="${OUTPUT_DIR}/ignored-scan-targets.json"

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
work_chart_dir="${work_dir}/chart"
cp -R "${CHART_DIR}" "${work_chart_dir}"

cd "${work_chart_dir}"
if [[ "${OVERRIDE_IMAGE_TAGS}" == "1" ]]; then
  yq eval -i '.apollo.image.tag = strenv(RELEASE_TAG)' ./values.yaml
  yq eval -i '.apollo.dbInit.image.tag = strenv(RELEASE_TAG)' ./values.yaml
  yq eval -i '.thermos.image.tag = strenv(RELEASE_TAG)' ./values.yaml
  yq eval -i '.thermos.dbInit.image.tag = strenv(RELEASE_TAG)' ./values.yaml
  yq eval -i '.thermosMiscWorkers.image.tag = strenv(RELEASE_TAG)' ./values.yaml
  yq eval -i '.mercury.image.tag = strenv(RELEASE_TAG)' ./values.yaml
  yq eval -i '.frontend.image.tag = strenv(RELEASE_TAG)' ./values.yaml
  yq eval -i '.weaviate.image.tag = strenv(RELEASE_TAG)' ./values.yaml
  yq eval -i '.toolkitRegistry.image.tag = strenv(RELEASE_TAG)' ./values.yaml
fi
cd - >/dev/null

collect_rendered_images() {
  helm template composio "${work_chart_dir}" "$@" \
    | yq -r '.. | select(tag == "!!map" and has("image")) | .image' \
    | grep -Ev '^(---|null)?$'
}

if [[ "${RENDER_TEMPORAL}" == "1" ]]; then
  base_images_file="${work_dir}/base-images.txt"
  temporal_enabled_images_file="${work_dir}/temporal-enabled-images.txt"
  all_images_file="${work_dir}/all-images.txt"

  collect_rendered_images | sort -u > "${base_images_file}"
  collect_rendered_images --set features.temporal=true | sort -u > "${temporal_enabled_images_file}"

  comm -13 "${base_images_file}" "${temporal_enabled_images_file}" > "${ignored_images_file}"
  cat "${base_images_file}" "${temporal_enabled_images_file}" | sort -u > "${all_images_file}"

  if [[ -s "${ignored_images_file}" ]]; then
    grep -Fvx -f "${ignored_images_file}" "${all_images_file}" > "${rendered_images_file}" || true
  else
    cp "${all_images_file}" "${rendered_images_file}"
  fi
else
  collect_rendered_images | sort -u > "${rendered_images_file}"
  : > "${ignored_images_file}"
fi

if [[ ! -s "${rendered_images_file}" ]]; then
  echo "No images were found in rendered Helm manifests." >&2
  echo '[]' > "${scan_targets_file}"
  echo '[]' > "${ignored_scan_targets_file}"
  exit 0
fi

replicated_registry="$(yq -r '.replicated.registry' "${work_chart_dir}/values.yaml")"
replicated_app="$(yq -r '.replicated.app' "${work_chart_dir}/values.yaml")"
replicated_proxy_prefix="${replicated_registry}/proxy/${replicated_app}/${ECR_REGISTRY}"

target_for_image() {
  local rendered_image="$1"
  local reason="${2:-}"
  local scan_image
  local source

  scan_image="${rendered_image}"
  source="rendered"
  if [[ "${rendered_image}" == "${replicated_proxy_prefix}/"* ]]; then
    scan_image="${ECR_REGISTRY}/${rendered_image#"${replicated_proxy_prefix}/"}"
    source="replicated-proxy"
  fi

  if [[ -n "${reason}" ]]; then
    jq -n \
      --arg image "${rendered_image}" \
      --arg scan_image "${scan_image}" \
      --arg source "${source}" \
      --arg reason "${reason}" \
      '{image: $image, scan_image: $scan_image, source: $source, reason: $reason}'
  else
    jq -n \
      --arg image "${rendered_image}" \
      --arg scan_image "${scan_image}" \
      --arg source "${source}" \
      '{image: $image, scan_image: $scan_image, source: $source}'
  fi
}

append_json_row() {
  local file="$1"
  local row="$2"
  jq -c --argjson row "${row}" '. + [$row]' "${file}" > "${file}.tmp"
  mv "${file}.tmp" "${file}"
}

echo '[]' > "${scan_targets_file}"
while IFS= read -r rendered_image; do
  row="$(target_for_image "${rendered_image}")"
  append_json_row "${scan_targets_file}" "${row}"
done < "${rendered_images_file}"

echo '[]' > "${ignored_scan_targets_file}"
if [[ -s "${ignored_images_file}" ]]; then
  while IFS= read -r rendered_image; do
    row="$(target_for_image \
      "${rendered_image}" \
      "Temporal dependency chart image; excluded from Composio-managed CVE gate")"
    append_json_row "${ignored_scan_targets_file}" "${row}"
  done < "${ignored_images_file}"
fi

echo "Rendered image list: ${rendered_images_file}"
echo "Ignored image list: ${ignored_images_file}"
echo "Ignored scan targets: ${ignored_scan_targets_file}"
echo "Scan targets: ${scan_targets_file}"
