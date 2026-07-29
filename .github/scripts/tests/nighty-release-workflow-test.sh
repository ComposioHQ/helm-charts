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

assert_not_contains() {
  local name="$1"
  local needle="$2"
  if grep -Fq -- "${needle}" "${WORKFLOW}"; then
    echo "FAIL: ${name}: unexpectedly found ${needle}" >&2
    exit 1
  fi
}

assert_step_before() {
  local name="$1"
  local first_id="$2"
  local second_name="$3"
  local first_index second_index

  first_index="$(
    yq -r \
      ".jobs.retag-latest-images.steps | to_entries | map(select(.value.id == \"${first_id}\")) | .[0].key" \
      "${WORKFLOW}"
  )"
  second_index="$(
    yq -r \
      ".jobs.retag-latest-images.steps | to_entries | map(select(.value.name == \"${second_name}\")) | .[0].key" \
      "${WORKFLOW}"
  )"

  if [[ "${first_index}" == "null" || "${second_index}" == "null" || "${first_index}" -ge "${second_index}" ]]; then
    echo "FAIL: ${name}: expected ${first_id} before ${second_name}" >&2
    exit 1
  fi
}

assert_eq "release input type" \
  "$(yq -r '.on.workflow_dispatch.inputs.release_type.type' "${WORKFLOW}")" choice
assert_eq "release input default" \
  "$(yq -r '.on.workflow_dispatch.inputs.release_type.default' "${WORKFLOW}")" standard
assert_eq "release input options" \
  "$(yq -o=json -I=0 '.on.workflow_dispatch.inputs.release_type.options' "${WORKFLOW}")" \
  '["standard","glean"]'
assert_contains "release type concurrency group" \
  "group: nighty-release-\${{ github.event.inputs.release_type || 'standard' }}"
assert_eq "release concurrency cancellation" \
  "$(yq -r '.concurrency.cancel-in-progress' "${WORKFLOW}")" false

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

assert_eq "seed channel name output" \
  "$(yq -r '.jobs.release-config.outputs.seed_channel_name' "${WORKFLOW}")" \
  '${{ steps.config.outputs.seed_channel_name }}'
assert_eq "seed channel id output" \
  "$(yq -r '.jobs.release-config.outputs.seed_channel_id' "${WORKFLOW}")" \
  '${{ steps.config.outputs.seed_channel_id }}'
assert_eq "seed chart output" \
  "$(yq -r '.jobs.release-config.outputs.seed_chart_oci_ref' "${WORKFLOW}")" \
  '${{ steps.config.outputs.seed_chart_oci_ref }}'
assert_eq "version prefix output" \
  "$(yq -r '.jobs.release-config.outputs.version_prefix' "${WORKFLOW}")" \
  '${{ steps.config.outputs.version_prefix }}'

assert_eq "selected seed channel name" \
  "$(yq -r '.jobs.retag-latest-images.steps[] | select(.id == "calculate_release_tag") | .env.SEED_CHANNEL_NAME' "${WORKFLOW}")" \
  '${{ needs.release-config.outputs.seed_channel_name }}'
assert_eq "selected seed channel id" \
  "$(yq -r '.jobs.retag-latest-images.steps[] | select(.id == "calculate_release_tag") | .env.SEED_CHANNEL_ID' "${WORKFLOW}")" \
  '${{ needs.release-config.outputs.seed_channel_id }}'
assert_eq "selected seed chart" \
  "$(yq -r '.jobs.retag-latest-images.steps[] | select(.id == "calculate_release_tag") | .env.SEED_CHART_OCI_REF' "${WORKFLOW}")" \
  '${{ needs.release-config.outputs.seed_chart_oci_ref }}'

assert_eq "release version helper" \
  "$(yq -r '.jobs.retag-latest-images.steps[] | select(.id == "calculate_version") | .run' "${WORKFLOW}")" \
  'bash ./.github/scripts/calculate-release-version.sh'
assert_eq "retag current version output" \
  "$(yq -r '.jobs.retag-latest-images.outputs.current_version' "${WORKFLOW}")" \
  '${{ steps.calculate_version.outputs.current }}'
assert_eq "retag new version output" \
  "$(yq -r '.jobs.retag-latest-images.outputs.new_version' "${WORKFLOW}")" \
  '${{ steps.calculate_version.outputs.new }}'
assert_eq "replicated previous version consumption" \
  "$(yq -r '.jobs.replicated-release.outputs.previous_version' "${WORKFLOW}")" \
  '${{ needs.retag-latest-images.outputs.current_version }}'
assert_eq "replicated new version consumption" \
  "$(yq -r '.jobs.replicated-release.outputs.version' "${WORKFLOW}")" \
  '${{ needs.retag-latest-images.outputs.new_version }}'

assert_step_before "version validation precedes AWS credentials" \
  calculate_version "Determine AWS Assume Role ARN"
assert_not_contains "late inline version calculation" \
  'name: Get and bump version'

echo "nighty-release workflow tests passed"
