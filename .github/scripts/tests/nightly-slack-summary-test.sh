#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="${SCRIPT_DIR}/nightly-slack-summary.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -F -- "${expected}" "${file}" >/dev/null ||
    fail "expected ${file} to contain: ${expected}"
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -F -- "${unexpected}" "${file}" >/dev/null; then
    fail "did not expect ${file} to contain: ${unexpected}"
  fi
}

run_summary() {
  local name="$1"
  shift
  local tmp_dir="${TMPDIR:-/tmp}/nightly-slack-summary-${name}-$$"
  rm -rf "${tmp_dir}"
  mkdir -p "${tmp_dir}"
  (
    cd "${tmp_dir}"
    env \
      NIGHTLY_SECRETS_RESULT=success \
      RETAG_RESULT=success \
      CVE_RESULT=success \
      CVE_SCAN_RESULT=success \
      CVE_FAILURE_REASON= \
      CVE_FAILURE_SUMMARY= \
      REPLICATED_RESULT=success \
      PR_RESULT=success \
      ONPREM_RESULT=success \
      RELEASE_TAG=r20260727_06 \
      RELEASE_BRANCH=nightly-r20260727_06 \
      PREVIOUS_VERSION=0.2.134 \
      NEW_VERSION=0.2.135 \
      PR_URL=https://github.com/ComposioHQ/helm-charts/pull/999 \
      RELEASE_URL=https://github.com/ComposioHQ/helm-charts/releases/tag/nightly-r20260727_06 \
      CVE_STATS= \
      CVE_ARTIFACT_NAME= \
      CVE_ARTIFACT_DOWNLOAD_COMMAND= \
      RUN_URL=https://github.com/ComposioHQ/helm-charts/actions/runs/1 \
      SLACK_IMPLEMENTATIONS_USERGROUP_ID=S123 \
      GITHUB_OUTPUT="${tmp_dir}/github-output" \
      "$@" \
      bash "${SCRIPT}"
  )
  printf '%s\n' "${tmp_dir}"
}

assert_valid_blocks() {
  local dir="$1"
  jq -e 'type == "array" and length > 0' "${dir}/slack-blocks.json" >/dev/null ||
    fail "expected ${dir}/slack-blocks.json to be a non-empty JSON array"
}

cve_dir="$(run_summary cve CVE_SCAN_RESULT=failed)"
assert_contains "${cve_dir}/slack-summary.txt" "*Good to go:* NO - Grype found HIGH or CRITICAL vulnerabilities"
assert_contains "${cve_dir}/github-output" "status=FAILURE"
assert_valid_blocks "${cve_dir}"

provisional_dir="$(run_summary provisional CVE_SCAN_RESULT=failed CVE_FIXABLE_CVES=0 CVE_UNIQUE_CVES=42)"
assert_contains "${provisional_dir}/github-output" "title=:large_yellow_circle: Nightly release: GOOD TO GO - PROVISIONALLY"
assert_contains "${provisional_dir}/github-output" "status=WARNING"
assert_contains "${provisional_dir}/slack-summary.txt" "*Good to go:* PROVISIONALLY"
assert_not_contains "${provisional_dir}/slack-summary.txt" "<!subteam^S123|@implementations>"
assert_valid_blocks "${provisional_dir}"

fixable_dir="$(run_summary fixable CVE_SCAN_RESULT=failed CVE_FIXABLE_CVES=2 SLACK_ZEN_MEMBER_ID=U999)"
assert_contains "${fixable_dir}/slack-summary.txt" "*Good to go:* NO - Grype found 2 HIGH/CRITICAL CVE(s) with a fix already available"
assert_contains "${fixable_dir}/slack-summary.txt" "<@U999> fix the 2 fixable CVE(s)"
assert_contains "${fixable_dir}/slack-summary.txt" "<!subteam^S123|@implementations>"
assert_contains "${fixable_dir}/github-output" "status=FAILURE"

onprem_dir="$(run_summary onprem ONPREM_RESULT=failure ONPREM_FRESH_RESULT=failure ONPREM_UPGRADE_RESULT=success)"
assert_contains "${onprem_dir}/slack-summary.txt" "onprem-testbed validation FAILED (fresh install: failure, upgrade: success)"
assert_contains "${onprem_dir}/slack-summary.txt" "must not be shipped to customers"
assert_contains "${onprem_dir}/slack-summary.txt" "@zen start an investigation into the onprem-testbed failures"
assert_contains "${onprem_dir}/slack-summary.txt" "<!subteam^S123|@implementations>"
assert_contains "${onprem_dir}/github-output" "status=FAILURE"
assert_valid_blocks "${onprem_dir}"

build_dir="$(run_summary build RETAG_RESULT=failure)"
assert_contains "${build_dir}/slack-summary.txt" "*Good to go:* NA - Image retag result was failure"
assert_not_contains "${build_dir}/slack-summary.txt" "*Good to go:* NO - Image retag result was failure"
assert_contains "${build_dir}/github-output" "status=FAILURE"

report_dir="$(run_summary report CVE_RESULT=failure CVE_FAILURE_REASON=report-build-failed CVE_FAILURE_SUMMARY='Build Grype report failed; Grype may or may not have found HIGH/CRITICAL vulnerabilities.')"
assert_contains "${report_dir}/slack-summary.txt" "*Good to go:* NA - Build Grype report failed; Grype may or may not have found HIGH/CRITICAL vulnerabilities."
assert_not_contains "${report_dir}/slack-summary.txt" "*Good to go:* NO - Build Grype report failed"
assert_contains "${report_dir}/slack-summary.txt" "Build Grype report failed; findings unknown"

glean_dir="$(run_summary glean RELEASE_CHANNEL_NAME=Glean-Stable)"
assert_contains "${glean_dir}/github-output" \
  "title=:white_check_mark: Glean-Stable release: GOOD TO GO"
assert_contains "${glean_dir}/slack-summary.txt" \
  "- Replicated Glean-Stable version: \`0.2.134\` -> \`0.2.135\`"

rm -rf "${cve_dir}" "${provisional_dir}" "${fixable_dir}" "${onprem_dir}" "${build_dir}" "${report_dir}" "${glean_dir}"
echo "nightly-slack-summary tests passed"
