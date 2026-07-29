#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="${SCRIPT_DIR}/calculate-nightly-release-tag.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_release_tag() {
  local name="$1"
  local mode="$2"
  local date_ist="$3"
  local expected="$4"
  local values_yaml="$5"
  local tmp_dir values_file output_file actual

  tmp_dir="$(mktemp -d)"
  values_file="${tmp_dir}/values.yaml"
  output_file="${tmp_dir}/github-output"

  printf '%s\n' "${values_yaml}" > "${values_file}"

  if ! RELEASE_TAG_DATE="${date_ist}" \
    TAG_CALCULATION_MODE="${mode}" \
    RELEASE_VALUES_FILE="${values_file}" \
    NIGHTLY_VALUES_FILE="${values_file}" \
    GITHUB_OUTPUT="${output_file}" \
    bash "${SCRIPT}" >"${tmp_dir}/stdout" 2>"${tmp_dir}/stderr"; then
    echo "stdout:" >&2
    sed 's/^/  /' "${tmp_dir}/stdout" >&2
    echo "stderr:" >&2
    sed 's/^/  /' "${tmp_dir}/stderr" >&2
    fail "${name}: script exited non-zero"
  fi

  actual="$(awk -F= '$1 == "release_tag" { print $2 }' "${output_file}" | tail -n1)"
  [[ "${actual}" == "${expected}" ]] || fail "${name}: expected ${expected}, got ${actual:-<empty>}"

  rm -rf "${tmp_dir}"
}

assert_release_tag_fails() {
  local name="$1"
  local mode="$2"
  local date_ist="$3"
  local expected_error="$4"
  local values_yaml="$5"
  local tmp_dir values_file

  tmp_dir="$(mktemp -d)"
  values_file="${tmp_dir}/values.yaml"
  printf '%s\n' "${values_yaml}" > "${values_file}"

  if RELEASE_TAG_DATE="${date_ist}" \
    TAG_CALCULATION_MODE="${mode}" \
    RELEASE_VALUES_FILE="${values_file}" \
    NIGHTLY_VALUES_FILE="${values_file}" \
    bash "${SCRIPT}" >"${tmp_dir}/stdout" 2>"${tmp_dir}/stderr"; then
    fail "${name}: script unexpectedly succeeded"
  fi

  grep -Fq "${expected_error}" "${tmp_dir}/stderr" \
    || fail "${name}: expected error was not emitted"
  rm -rf "${tmp_dir}"
}

assert_release_tag "increments same-day calendar tag" standard "20260724" "r20260724_04" '
apollo:
  image:
    tag: r20260724_03
'

assert_release_tag "resets sequence for a new calendar day" standard "20260724" "r20260724_01" '
apollo:
  image:
    tag: r20260723_08
'

assert_release_tag "uses the highest replicated nightly image tag in values" standard "20260724" "r20260724_10" '
apollo:
  image:
    tag: r20260724_03
mercury:
  image:
    tag: r20260724_09
frontend:
  image:
    tag: latest
'

assert_release_tag "starts at sequence one when no calendar image tag exists" standard "20260724" "r20260724_01" '
apollo:
  image:
    tag: latest
'

assert_release_tag "creates first glean suffix from fixed base" glean "20260801" \
  "r20260729_01-p20260801_01" '
apollo:
  image:
    tag: r20260729_01
'

assert_release_tag "increments glean suffix on the same day" glean "20260801" \
  "r20260729_01-p20260801_02" '
apollo:
  image:
    tag: r20260729_01-p20260801_01
'

assert_release_tag "resets glean suffix on a new day" glean "20260801" \
  "r20260729_01-p20260801_01" '
apollo:
  image:
    tag: r20260729_01-p20260731_08
'

assert_release_tag "keeps glean base fixed while suffix advances" glean "20260802" \
  "r20260729_01-p20260802_01" '
apollo:
  image:
    tag: r20260729_01-p20260801_09
mercury:
  image:
    tag: r20260729_01-p20260801_09
'

assert_release_tag_fails "rejects glean values without a fixed base" glean \
  "20260801" "Glean tag calculation requires a valid fixed base tag." '
apollo:
  image:
    tag: latest
'

echo "calculate-nightly-release-tag tests passed"
