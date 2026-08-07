#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="${SCRIPT_DIR}/resolve-release-config.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_output() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(awk -F= -v key="${key}" '$1 == key { print substr($0, index($0, "=") + 1) }' "${file}" | tail -n1)"
  [[ "${actual}" == "${expected}" ]] || fail "${key}: expected ${expected}, got ${actual:-<empty>}"
}

assert_config() {
  local release_type="$1"
  local expected_type="$2"
  local expected_name="$3"
  local expected_id="$4"
  local expected_ref="$5"
  local expected_mode="$6"
  local expected_prefix="$7"
  local expected_version_prefix="$8"
  local tmp_dir output_file

  tmp_dir="$(mktemp -d)"
  output_file="${tmp_dir}/github-output"
  RELEASE_TYPE="${release_type}" GITHUB_OUTPUT="${output_file}" bash "${SCRIPT}"

  assert_output "${output_file}" release_type "${expected_type}"
  assert_output "${output_file}" channel_name "${expected_name}"
  assert_output "${output_file}" channel_id "${expected_id}"
  assert_output "${output_file}" chart_oci_ref "${expected_ref}"
  assert_output "${output_file}" tag_calculation_mode "${expected_mode}"
  assert_output "${output_file}" branch_prefix "${expected_prefix}"
  assert_output "${output_file}" version_prefix "${expected_version_prefix}"
  if grep -Eq '^seed_(channel_name|channel_id|chart_oci_ref)=' "${output_file}"; then
    fail "resolver unexpectedly emitted seed-channel configuration"
  fi
  rm -rf "${tmp_dir}"
}

assert_config "" standard Nightly 397k1WtPrJ1J56bhb70SfeKGcxL \
  oci://registry.composio.io/composio-rodent/nightly/composio standard nightly ""
assert_config standard standard Nightly 397k1WtPrJ1J56bhb70SfeKGcxL \
  oci://registry.composio.io/composio-rodent/nightly/composio standard nightly ""
assert_config glean glean Glean-Stable 3GwShNBOwcf13Bs7i5pfn3N8TDh \
  oci://registry.composio.io/composio-rodent/glean-stable/composio glean glean \
  0.2.87-glean

if RELEASE_TYPE=unsupported bash "${SCRIPT}" >/dev/null 2>&1; then
  fail "unsupported release type should fail"
fi

echo "resolve-release-config tests passed"
