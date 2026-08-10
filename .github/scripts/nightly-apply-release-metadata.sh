#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  nightly-apply-release-metadata.sh \
    --inventory <path> \
    --image-tag <tag> \
    --app-version <version> \
    --values-file <path> \
    --chart-file <path> \
    --k8s-app-file <path> \
    --replicated-manifest-file <path>
EOF
}

inventory=""
image_tag=""
app_version=""
values_file=""
chart_file=""
k8s_app_file=""
replicated_manifest_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory)
      inventory="$2"
      shift 2
      ;;
    --image-tag)
      image_tag="$2"
      shift 2
      ;;
    --app-version)
      app_version="$2"
      shift 2
      ;;
    --values-file)
      values_file="$2"
      shift 2
      ;;
    --chart-file)
      chart_file="$2"
      shift 2
      ;;
    --k8s-app-file)
      k8s_app_file="$2"
      shift 2
      ;;
    --replicated-manifest-file)
      replicated_manifest_file="$2"
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

if [[ -z "${inventory}" || -z "${image_tag}" || -z "${app_version}" || -z "${values_file}" || -z "${chart_file}" || -z "${k8s_app_file}" || -z "${replicated_manifest_file}" ]]; then
  usage >&2
  exit 1
fi

export NIGHTLY_IMAGE_TAG="${image_tag}"
export NIGHTLY_APP_VERSION="${app_version}"

while IFS= read -r path_expr; do
  yq eval -i "${path_expr} = strenv(NIGHTLY_IMAGE_TAG)" "${values_file}"
done < <(jq -r '.services[].images[].values_path' "${inventory}")

yq eval -i '.appVersion = strenv(NIGHTLY_APP_VERSION)' "${chart_file}"
yq eval -i '.version = strenv(NIGHTLY_APP_VERSION)' "${chart_file}"
yq eval -i '.metadata.labels."app.kubernetes.io/version" = strenv(NIGHTLY_APP_VERSION)' "${k8s_app_file}"
yq eval -i '.spec.descriptor.version = strenv(NIGHTLY_APP_VERSION)' "${k8s_app_file}"
yq eval -i '.spec.chart.chartVersion = strenv(NIGHTLY_APP_VERSION)' "${replicated_manifest_file}"
