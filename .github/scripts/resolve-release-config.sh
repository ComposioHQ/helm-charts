#!/usr/bin/env bash

set -euo pipefail

release_type="${RELEASE_TYPE:-standard}"

case "${release_type}" in
  standard)
    channel_name="Nightly"
    channel_id="397k1WtPrJ1J56bhb70SfeKGcxL"
    chart_oci_ref="oci://registry.composio.io/composio-rodent/nightly/composio"
    tag_calculation_mode="standard"
    branch_prefix="nightly"
    ;;
  glean)
    channel_name="Glean-Stable"
    channel_id="3GwShNBOwcf13Bs7i5pfn3N8TDh"
    chart_oci_ref="oci://registry.composio.io/composio-rodent/glean-stable/composio"
    tag_calculation_mode="glean"
    branch_prefix="glean"
    ;;
  *)
    echo "Unsupported release type: ${release_type}" >&2
    exit 1
    ;;
esac

write_output() {
  local key="$1"
  local value="$2"

  echo "${key}=${value}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "${GITHUB_OUTPUT}"
  fi
}

write_output release_type "${release_type}"
write_output channel_name "${channel_name}"
write_output channel_id "${channel_id}"
write_output chart_oci_ref "${chart_oci_ref}"
write_output tag_calculation_mode "${tag_calculation_mode}"
write_output branch_prefix "${branch_prefix}"
