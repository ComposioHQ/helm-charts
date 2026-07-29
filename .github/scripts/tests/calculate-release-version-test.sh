#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="${SCRIPT_DIR}/calculate-release-version.sh"

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
  [[ "${actual}" == "${expected}" ]] \
    || fail "${key}: expected ${expected:-<empty>}, got ${actual:-<empty>}"
}

assert_version() {
  local name="$1"
  local release_type="$2"
  local current_version="$3"
  local version_prefix="$4"
  local expected_current="$5"
  local expected_new="$6"
  local tmp_dir output_file channel_name

  tmp_dir="$(mktemp -d)"
  output_file="${tmp_dir}/github-output"
  channel_name="Nightly"
  if [[ "${release_type}" == "glean" ]]; then
    channel_name="Glean-Stable"
  fi

  RELEASE_TYPE="${release_type}" \
  RELEASE_CHANNEL_NAME="${channel_name}" \
  CURRENT_VERSION="${current_version}" \
  VERSION_PREFIX="${version_prefix}" \
  GITHUB_OUTPUT="${output_file}" \
  bash "${SCRIPT}" >"${tmp_dir}/stdout" 2>"${tmp_dir}/stderr" \
    || fail "${name}: script exited non-zero"

  assert_output "${output_file}" current "${expected_current}"
  assert_output "${output_file}" new "${expected_new}"
  rm -rf "${tmp_dir}"
}

assert_version_fails() {
  local name="$1"
  local release_type="$2"
  local current_version="$3"
  local version_prefix="$4"
  local expected_error="$5"
  local tmp_dir channel_name

  tmp_dir="$(mktemp -d)"
  channel_name="Nightly"
  if [[ "${release_type}" == "glean" ]]; then
    channel_name="Glean-Stable"
  fi

  if RELEASE_TYPE="${release_type}" \
    RELEASE_CHANNEL_NAME="${channel_name}" \
    CURRENT_VERSION="${current_version}" \
    VERSION_PREFIX="${version_prefix}" \
    bash "${SCRIPT}" >"${tmp_dir}/stdout" 2>"${tmp_dir}/stderr"; then
    fail "${name}: script unexpectedly succeeded"
  fi

  grep -Fq "${expected_error}" "${tmp_dir}/stderr" \
    || fail "${name}: expected error was not emitted"
  rm -rf "${tmp_dir}"
}

assert_version "increments standard version" \
  standard "0.2.140" "" "0.2.140" "0.2.141"
assert_version "bootstraps empty Glean version" \
  glean "" "0.2.87-glean" "" "0.2.87-glean.1"
assert_version "increments existing Glean version" \
  glean "0.2.87-glean.1" "0.2.87-glean" \
  "0.2.87-glean.1" "0.2.87-glean.2"
assert_version "increments a multi-digit Glean sequence" \
  glean "0.2.87-glean.19" "0.2.87-glean" \
  "0.2.87-glean.19" "0.2.87-glean.20"

assert_version_fails "rejects empty standard version" \
  standard "" "" "Nightly channel returned an invalid currentVersion: <empty>"
assert_version_fails "rejects a different Glean family" \
  glean "0.2.88-glean.1" "0.2.87-glean" \
  "Glean-Stable currentVersion must match 0.2.87-glean.x: 0.2.88-glean.1"
assert_version_fails "requires the Glean version prefix" \
  glean "" "" "VERSION_PREFIX is required."

echo "calculate-release-version tests passed"
