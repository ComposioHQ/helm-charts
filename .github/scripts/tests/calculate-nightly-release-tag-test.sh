#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="${SCRIPT_DIR}/calculate-nightly-release-tag.sh"

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

write_fake_api_tools() {
  local bin_dir="$1"

  mkdir -p "${bin_dir}"
  cat >"${bin_dir}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  *"/vendor/v3/apps"*)
    printf '%s' '{"apps":[{"id":"app-id","slug":"composio-rodent","name":"Composio Rodent"}]}'
    ;;
  *"channelName=Glean-Stable"*)
    printf '%s' '{"totalCount":1,"channels":[{"id":"3GwShNBOwcf13Bs7i5pfn3N8TDh","releaseSequence":0}]}'
    ;;
  *"channelName=Nightly"*)
    if [[ "${FAKE_API_SCENARIO:-bootstrap}" == "bootstrap" ]]; then
      printf '%s' '{"totalCount":1,"channels":[{"id":"397k1WtPrJ1J56bhb70SfeKGcxL","currentVersion":"0.2.140","releaseSequence":238}]}'
    else
      printf '%s' '{"totalCount":1,"channels":[{"id":"397k1WtPrJ1J56bhb70SfeKGcxL","releaseSequence":0}]}'
    fi
    ;;
  *)
    echo "unexpected curl arguments: $*" >&2
    exit 1
    ;;
esac
EOF

  cat >"${bin_dir}/helm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_HELM_LOG}"
untar_dir=""
while (( $# > 0 )); do
  if [[ "$1" == "--untardir" ]]; then
    untar_dir="$2"
    break
  fi
  shift
done

if [[ -z "${untar_dir}" ]]; then
  echo "fake helm did not receive --untardir" >&2
  exit 1
fi

mkdir -p "${untar_dir}/composio"
cat >"${untar_dir}/composio/values.yaml" <<'EOF_VALUES'
apollo:
  image:
    tag: r20260729_04
EOF_VALUES
EOF

  chmod +x "${bin_dir}/curl" "${bin_dir}/helm"
}

assert_empty_glean_uses_nightly_seed() {
  local tmp_dir output_file helm_log

  tmp_dir="$(mktemp -d)"
  output_file="${tmp_dir}/github-output"
  helm_log="${tmp_dir}/helm-log"
  write_fake_api_tools "${tmp_dir}/bin"

  if ! PATH="${tmp_dir}/bin:${PATH}" \
    FAKE_API_SCENARIO=bootstrap \
    FAKE_HELM_LOG="${helm_log}" \
    RELEASE_TAG_DATE=20260730 \
    REPLICATED_APP=composio-rodent \
    REPLICATED_API_TOKEN=test-token \
    RELEASE_CHANNEL_NAME=Glean-Stable \
    RELEASE_CHANNEL_ID=3GwShNBOwcf13Bs7i5pfn3N8TDh \
    CHART_OCI_REF=oci://registry.composio.io/composio-rodent/glean-stable/composio \
    TAG_CALCULATION_MODE=glean \
    SEED_CHANNEL_NAME=Nightly \
    SEED_CHANNEL_ID=397k1WtPrJ1J56bhb70SfeKGcxL \
    SEED_CHART_OCI_REF=oci://registry.composio.io/composio-rodent/nightly/composio \
    GITHUB_OUTPUT="${output_file}" \
    bash "${SCRIPT}" >"${tmp_dir}/stdout" 2>"${tmp_dir}/stderr"; then
    sed 's/^/  /' "${tmp_dir}/stderr" >&2
    fail "empty Glean channel did not bootstrap"
  fi

  assert_output "${output_file}" replicated_current_version ""
  assert_output "${output_file}" release_tag "r20260729_04-p20260730_01"
  grep -Fq \
    'pull oci://registry.composio.io/composio-rodent/nightly/composio --version 0.2.140' \
    "${helm_log}" || fail "empty Glean channel did not pull the Nightly seed chart"

  rm -rf "${tmp_dir}"
}

assert_api_release_tag_fails() {
  local name="$1"
  local mode="$2"
  local channel_name="$3"
  local channel_id="$4"
  local seed_name="$5"
  local seed_id="$6"
  local seed_ref="$7"
  local scenario="$8"
  local expected_error="$9"
  local tmp_dir chart_ref

  tmp_dir="$(mktemp -d)"
  write_fake_api_tools "${tmp_dir}/bin"
  chart_ref="oci://registry.composio.io/composio-rodent/nightly/composio"
  if [[ "${mode}" == "glean" ]]; then
    chart_ref="oci://registry.composio.io/composio-rodent/glean-stable/composio"
  fi

  if PATH="${tmp_dir}/bin:${PATH}" \
    FAKE_API_SCENARIO="${scenario}" \
    FAKE_HELM_LOG="${tmp_dir}/helm-log" \
    RELEASE_TAG_DATE=20260730 \
    REPLICATED_APP=composio-rodent \
    REPLICATED_API_TOKEN=test-token \
    RELEASE_CHANNEL_NAME="${channel_name}" \
    RELEASE_CHANNEL_ID="${channel_id}" \
    CHART_OCI_REF="${chart_ref}" \
    TAG_CALCULATION_MODE="${mode}" \
    SEED_CHANNEL_NAME="${seed_name}" \
    SEED_CHANNEL_ID="${seed_id}" \
    SEED_CHART_OCI_REF="${seed_ref}" \
    bash "${SCRIPT}" >"${tmp_dir}/stdout" 2>"${tmp_dir}/stderr"; then
    fail "${name}: script unexpectedly succeeded"
  fi

  grep -Fq "${expected_error}" "${tmp_dir}/stderr" \
    || fail "${name}: expected error was not emitted"
  rm -rf "${tmp_dir}"
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

assert_release_tag_fails "rejects mixed glean fixed bases" glean \
  "20260801" "Glean tag calculation requires exactly one fixed base tag; found 2." '
apollo:
  image:
    tag: r20260729_01-p20260731_08
mercury:
  image:
    tag: r20260730_01
'

assert_empty_glean_uses_nightly_seed

assert_api_release_tag_fails \
  "empty standard channel remains invalid" \
  standard Nightly 397k1WtPrJ1J56bhb70SfeKGcxL \
  "" "" "" empty-standard \
  "Nightly channel response did not include currentVersion"

assert_api_release_tag_fails \
  "empty Glean seed remains invalid" \
  glean Glean-Stable 3GwShNBOwcf13Bs7i5pfn3N8TDh \
  Nightly 397k1WtPrJ1J56bhb70SfeKGcxL \
  oci://registry.composio.io/composio-rodent/nightly/composio \
  empty-seed \
  "Nightly seed channel response did not include currentVersion"

assert_api_release_tag_fails \
  "mismatched Glean seed channel id is rejected" \
  glean Glean-Stable 3GwShNBOwcf13Bs7i5pfn3N8TDh \
  Nightly wrong-seed-id \
  oci://registry.composio.io/composio-rodent/nightly/composio \
  bootstrap \
  "Nightly channel ID mismatch"

echo "calculate-nightly-release-tag tests passed"
