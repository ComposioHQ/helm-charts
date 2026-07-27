#!/usr/bin/env bash
set -euo pipefail

good_to_go="YES"
blocker=""
status="SUCCESS"

mark_no() {
  status="FAILURE"
  if [[ "${good_to_go}" == "YES" ]]; then
    good_to_go="NO"
    blocker="$1"
  fi
}

mark_na() {
  status="FAILURE"
  if [[ "${good_to_go}" != "NA" || -z "${blocker}" ]]; then
    good_to_go="NA"
    blocker="$1"
  fi
}

require_success() {
  local label="$1"
  local result="$2"
  if [[ "${result}" != "success" ]]; then
    mark_na "${label} result was ${result}"
  fi
}

require_success "Secret preflight" "${NIGHTLY_SECRETS_RESULT:-unknown}"
require_success "Image retag" "${RETAG_RESULT:-unknown}"

cve_status="${CVE_RESULT:-unknown}"
if [[ "${CVE_RESULT:-unknown}" == "failure" ]]; then
  case "${CVE_FAILURE_REASON:-unknown}" in
    high-critical-findings)
      cve_status="failure (HIGH/CRITICAL findings reported; release continued alert-only)"
      mark_no "Grype found HIGH or CRITICAL vulnerabilities"
      ;;
    report-build-failed)
      cve_status="failure (Build Grype report failed; findings unknown)"
      mark_na "${CVE_FAILURE_SUMMARY:-Build Grype report failed; Grype may or may not have found HIGH/CRITICAL vulnerabilities.}"
      ;;
    render-failed|scan-execution-failed|report-publish-failed|missing-scan-result)
      cve_status="failure (${CVE_FAILURE_SUMMARY:-Grype CVE workflow failed; findings may be incomplete or unavailable.})"
      mark_na "${CVE_FAILURE_SUMMARY:-Grype CVE workflow failed; findings may be incomplete or unavailable.}"
      ;;
    *)
      cve_status="failure (CVE workflow failed before a definitive scan result)"
      mark_na "Grype CVE workflow failed; scan findings may be incomplete or unavailable"
      ;;
  esac
elif [[ "${CVE_RESULT:-unknown}" != "success" ]]; then
  mark_na "Grype CVE scan result was ${CVE_RESULT:-unknown}"
elif [[ "${CVE_SCAN_RESULT:-success}" != "success" ]]; then
  cve_status="${CVE_SCAN_RESULT} (HIGH/CRITICAL findings reported; release continued alert-only)"
  mark_no "Grype found HIGH or CRITICAL vulnerabilities"
else
  cve_status="success"
fi

require_success "Replicated release" "${REPLICATED_RESULT:-unknown}"
require_success "GitHub PR/release" "${PR_RESULT:-unknown}"
require_success "onprem-testbed validation" "${ONPREM_RESULT:-unknown}"

case "${good_to_go}" in
  YES)
    title=":white_check_mark: Nightly release: GOOD TO GO"
    verdict_line="*Good to go:* YES"
    release_blocking_line="*Release blocking:* NO - CVE findings are alert-only."
    ;;
  NO)
    title=":rotating_light: Nightly release: NOT GOOD TO GO"
    verdict_line="*Good to go:* NO - ${blocker}"
    release_blocking_line="*Release blocking:* NO - CVE findings are alert-only."
    ;;
  NA)
    title=":rotating_light: Nightly release: NOT GOOD TO GO"
    verdict_line="*Good to go:* NA - ${blocker}"
    release_blocking_line="*Release blocking:* NA - build/release validation did not complete cleanly."
    ;;
  *)
    title=":rotating_light: Nightly release: NOT GOOD TO GO"
    verdict_line="*Good to go:* NA - release readiness could not be determined"
    release_blocking_line="*Release blocking:* NA - build/release validation did not complete cleanly."
    ;;
esac

{
  if [[ "${good_to_go}" != "YES" && -n "${SLACK_IMPLEMENTATIONS_USERGROUP_ID:-}" ]]; then
    echo "<!subteam^${SLACK_IMPLEMENTATIONS_USERGROUP_ID}|@implementations>"
  fi
  echo "${verdict_line}"
  echo "${release_blocking_line}"
  if [[ "${REPLICATED_RESULT:-unknown}" == "success" ]]; then
    echo "*Release created:* YES"
    echo "- Image release tag: \`${RELEASE_TAG:-unknown}\`"
    echo "- Replicated Nightly version: \`${PREVIOUS_VERSION:-unknown}\` -> \`${NEW_VERSION:-unknown}\`"
    echo "- Nightly branch: \`${RELEASE_BRANCH:-unknown}\`"
  else
    echo "*Release created:* NO"
    echo "- Intended image release tag: \`${RELEASE_TAG:-unknown}\`"
    echo "- Intended Replicated version: \`${PREVIOUS_VERSION:-unknown}\` -> \`${NEW_VERSION:-unknown}\`"
  fi
  echo "*Stages:*"
  echo "- Secret preflight: \`${NIGHTLY_SECRETS_RESULT:-unknown}\`"
  echo "- Image retag: \`${RETAG_RESULT:-unknown}\`"
  echo "- Grype CVE scan: \`${cve_status}\`"
  echo "- Replicated release: \`${REPLICATED_RESULT:-unknown}\`"
  echo "- GitHub PR/release: \`${PR_RESULT:-unknown}\`"
  echo "- onprem-testbed validation (fresh + upgrade + triggers): \`${ONPREM_RESULT:-unknown}\`"
  if [[ -n "${CVE_STATS:-}" ]]; then
    echo "*Grype findings:*"
    printf '%s\n' "${CVE_STATS}"
  fi
  if [[ -n "${CVE_ARTIFACT_NAME:-}" ]]; then
    echo "*Grype artifact:* \`${CVE_ARTIFACT_NAME}\`"
  fi
  if [[ -n "${CVE_ARTIFACT_DOWNLOAD_COMMAND:-}" ]]; then
    echo "*Download Grype reports:*"
    echo "\`\`\`"
    echo "${CVE_ARTIFACT_DOWNLOAD_COMMAND}"
    echo "\`\`\`"
  fi
  links=()
  if [[ -n "${PR_URL:-}" ]]; then
    links+=("<${PR_URL}|PR>")
  fi
  if [[ -n "${RELEASE_URL:-}" ]]; then
    links+=("<${RELEASE_URL}|GitHub release>")
  fi
  links+=("<${RUN_URL:-}|Workflow>")
  printf '*Links:* '
  for index in "${!links[@]}"; do
    if (( index > 0 )); then
      printf ' | '
    fi
    printf '%s' "${links[index]}"
  done
  printf '\n'
} > slack-summary.txt

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "status=${status}"
    echo "title=${title}"
    echo "summary<<__SLACK_SUMMARY__"
    cat slack-summary.txt
    echo "__SLACK_SUMMARY__"
  } >> "${GITHUB_OUTPUT}"
fi
