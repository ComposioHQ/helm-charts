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
  {
    collect_rendered_images
    collect_rendered_images --set features.temporal=true
  } | sort -u > "${rendered_images_file}"
else
  collect_rendered_images | sort -u > "${rendered_images_file}"
fi

if [[ ! -s "${rendered_images_file}" ]]; then
  echo "No images were found in rendered Helm manifests." >&2
  echo '[]' > "${scan_targets_file}"
  exit 0
fi

replicated_registry="$(yq -r '.replicated.registry' "${work_chart_dir}/values.yaml")"
replicated_app="$(yq -r '.replicated.app' "${work_chart_dir}/values.yaml")"
replicated_proxy_prefix="${replicated_registry}/proxy/${replicated_app}/${ECR_REGISTRY}"

echo '[]' > "${scan_targets_file}"
while IFS= read -r rendered_image; do
  scan_image="${rendered_image}"
  source="rendered"
  if [[ "${rendered_image}" == "${replicated_proxy_prefix}/"* ]]; then
    scan_image="${ECR_REGISTRY}/${rendered_image#"${replicated_proxy_prefix}/"}"
    source="replicated-proxy"
  fi

  row="$(jq -n \
    --arg image "${rendered_image}" \
    --arg scan_image "${scan_image}" \
    --arg source "${source}" \
    '{image: $image, scan_image: $scan_image, source: $source}')"
  jq -c --argjson row "${row}" '. + [$row]' "${scan_targets_file}" > "${scan_targets_file}.tmp"
  mv "${scan_targets_file}.tmp" "${scan_targets_file}"
done < "${rendered_images_file}"

echo "Rendered image list: ${rendered_images_file}"
echo "Scan targets: ${scan_targets_file}"
