#!/usr/bin/env bash

set -euo pipefail

WORKFLOW=".github/workflows/nighty-release.yml"

assert_eq() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL: ${name}: expected ${expected}, got ${actual}" >&2
    exit 1
  fi
}

assert_contains() {
  local name="$1"
  local needle="$2"
  grep -Fq -- "${needle}" "${WORKFLOW}" || {
    echo "FAIL: ${name}: missing ${needle}" >&2
    exit 1
  }
}

assert_eq "release input type" \
  "$(yq -r '.on.workflow_dispatch.inputs.release_type.type' "${WORKFLOW}")" choice
assert_eq "release input default" \
  "$(yq -r '.on.workflow_dispatch.inputs.release_type.default' "${WORKFLOW}")" standard
assert_eq "release input options" \
  "$(yq -o=json -I=0 '.on.workflow_dispatch.inputs.release_type.options' "${WORKFLOW}")" \
  '["standard","glean"]'

assert_contains "config resolver" \
  'bash ./.github/scripts/resolve-release-config.sh'
assert_contains "selected chart" \
  'CHART_OCI_REF: ${{ needs.release-config.outputs.chart_oci_ref }}'
assert_contains "selected channel name" \
  'RELEASE_CHANNEL_NAME: ${{ needs.release-config.outputs.channel_name }}'
assert_contains "selected channel id" \
  'RELEASE_CHANNEL_ID: ${{ needs.release-config.outputs.channel_id }}'
assert_contains "selected tag mode" \
  'TAG_CALCULATION_MODE: ${{ needs.release-config.outputs.tag_calculation_mode }}'
assert_contains "selected promotion" \
  '--promote "${{ needs.release-config.outputs.channel_name }}"'

echo "nighty-release workflow tests passed"
