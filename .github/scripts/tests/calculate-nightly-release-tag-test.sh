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
  local date_ist="$2"
  local expected="$3"
  local values_yaml="$4"
  local tmp_dir values_file output_file actual

  tmp_dir="$(mktemp -d)"
  values_file="${tmp_dir}/values.yaml"
  output_file="${tmp_dir}/github-output"

  printf '%s\n' "${values_yaml}" > "${values_file}"

  if ! RELEASE_TAG_DATE="${date_ist}" \
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

assert_release_tag "increments same-day calendar tag" "20260724" "r20260724_04" '
apollo:
  image:
    tag: r20260724_03
'

assert_release_tag "resets sequence for a new calendar day" "20260724" "r20260724_01" '
apollo:
  image:
    tag: r20260723_08
'

assert_release_tag "uses the highest replicated nightly image tag in values" "20260724" "r20260724_10" '
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

assert_release_tag "starts at sequence one when no calendar image tag exists" "20260724" "r20260724_01" '
apollo:
  image:
    tag: latest
'

echo "calculate-nightly-release-tag tests passed"
