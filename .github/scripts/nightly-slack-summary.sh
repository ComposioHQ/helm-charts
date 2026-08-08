#!/usr/bin/env bash
set -euo pipefail

good_to_go="YES"
blocker=""
status="SUCCESS"
provisional=0
cve_findings=0
release_channel_name="${RELEASE_CHANNEL_NAME:-Nightly}"
fixable_cves="${CVE_FIXABLE_CVES:-}"
unique_cves="${CVE_UNIQUE_CVES:-}"
onprem_result="${ONPREM_RESULT:-unknown}"
onprem_fresh="${ONPREM_FRESH_RESULT:-unknown}"
onprem_upgrade="${ONPREM_UPGRADE_RESULT:-unknown}"

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
      cve_findings=1
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
  cve_findings=1
else
  cve_status="success"
fi

# CVE findings gate on the fixable count: CVEs with no published fix do not
# block the verdict.
if (( cve_findings )); then
  if [[ "${fixable_cves}" =~ ^[0-9]+$ ]]; then
    if (( fixable_cves > 0 )); then
      mark_no "Grype found ${fixable_cves} HIGH/CRITICAL CVE(s) with a fix already available — they must be patched"
    else
      provisional=1
    fi
  else
    mark_no "Grype found HIGH or CRITICAL vulnerabilities"
  fi
fi

require_success "Replicated release" "${REPLICATED_RESULT:-unknown}"
require_success "GitHub PR/release" "${PR_RESULT:-unknown}"

onprem_explainer="onprem-testbed installs this exact release on a disposable cluster and runs the fresh-install, upgrade, and trigger test suites end to end"
if [[ "${onprem_result}" == "failure" ]]; then
  mark_na "onprem-testbed validation FAILED (fresh install: ${onprem_fresh}, upgrade: ${onprem_upgrade}). ${onprem_explainer} — until it passes, this build is unverified and must not be shipped to customers."
elif [[ "${onprem_result}" != "success" ]]; then
  mark_na "onprem-testbed validation did not run (result: ${onprem_result}). ${onprem_explainer} — without it this build is unverified."
fi

if [[ "${good_to_go}" == "YES" && ${provisional} -eq 1 ]]; then
  good_to_go="PROVISIONAL"
  status="WARNING"
fi

case "${good_to_go}" in
  YES)
    title=":white_check_mark: ${release_channel_name} release: GOOD TO GO"
    verdict_line="*Good to go:* YES"
    release_blocking_line="*Release blocking:* NO - CVE findings are alert-only."
    ;;
  PROVISIONAL)
    title=":large_yellow_circle: ${release_channel_name} release: GOOD TO GO - PROVISIONALLY"
    verdict_line="*Good to go:* PROVISIONALLY - all release and validation stages passed. Grype reported HIGH/CRITICAL CVEs${unique_cves:+ (${unique_cves} unique)}, but none of them have a published fix yet, so there is nothing to patch today. Fixes are re-checked on every scan."
    release_blocking_line="*Release blocking:* NO - CVE findings are alert-only."
    ;;
  NO)
    title=":rotating_light: ${release_channel_name} release: NOT GOOD TO GO"
    verdict_line="*Good to go:* NO - ${blocker}"
    release_blocking_line="*Release blocking:* NO - CVE findings are alert-only."
    ;;
  NA)
    title=":rotating_light: ${release_channel_name} release: NOT GOOD TO GO"
    verdict_line="*Good to go:* NA - ${blocker}"
    release_blocking_line="*Release blocking:* NA - build/release validation did not complete cleanly."
    ;;
  *)
    title=":rotating_light: ${release_channel_name} release: NOT GOOD TO GO"
    verdict_line="*Good to go:* NA - release readiness could not be determined"
    release_blocking_line="*Release blocking:* NA - build/release validation did not complete cleanly."
    ;;
esac

impl_mention="@implementations"
if [[ -n "${SLACK_IMPLEMENTATIONS_USERGROUP_ID:-}" ]]; then
  impl_mention="<!subteam^${SLACK_IMPLEMENTATIONS_USERGROUP_ID}|@implementations>"
fi
zen_mention="@zen"
if [[ -n "${SLACK_ZEN_MEMBER_ID:-}" ]]; then
  zen_mention="<@${SLACK_ZEN_MEMBER_ID}>"
fi

mention_line=""
if [[ "${good_to_go}" == "NO" || "${good_to_go}" == "NA" ]]; then
  mention_line="${impl_mention}"
fi

action_lines=()
if [[ "${onprem_result}" == "failure" ]]; then
  action_lines+=(":mag: ${zen_mention} start an investigation into the onprem-testbed failures in this run, publish a report of the root cause, and tag ${impl_mention} with the findings.")
fi
if (( cve_findings )) && [[ "${fixable_cves}" =~ ^[0-9]+$ ]] && (( fixable_cves > 0 )); then
  action_lines+=(":wrench: ${zen_mention} fix the ${fixable_cves} fixable CVE(s) called out in the Grype findings below.")
fi

stage_icon() {
  case "$1" in
    success) printf ':white_check_mark:' ;;
    failure) printf ':x:' ;;
    skipped) printf ':fast_forward:' ;;
    *) printf ':grey_question:' ;;
  esac
}

stage_line() {
  local result="$1" label="$2"
  local line
  line="$(stage_icon "${result}") ${label}"
  if [[ "${result}" != "success" ]]; then
    line+=" — ${result}"
  fi
  printf '%s' "${line}"
}

if [[ "${cve_status}" == "success" ]]; then
  grype_line=":white_check_mark: Grype CVE scan — no HIGH/CRITICAL findings"
elif (( cve_findings )); then
  grype_line=":warning: Grype CVE scan — HIGH/CRITICAL findings reported (release continued, alert-only)"
else
  grype_line=":x: Grype CVE scan — ${cve_status}"
fi

if [[ "${onprem_result}" == "success" ]]; then
  onprem_line=":white_check_mark: onprem-testbed validation — fresh install + upgrade + trigger tests passed on a real cluster"
elif [[ "${onprem_result}" == "failure" ]]; then
  onprem_line=":x: onprem-testbed validation — FAILED (fresh install: ${onprem_fresh}, upgrade: ${onprem_upgrade}); the release is unverified"
else
  onprem_line="$(stage_icon "${onprem_result}") onprem-testbed validation — ${onprem_result}; the release is unverified"
fi

stage_lines=(
  "$(stage_line "${NIGHTLY_SECRETS_RESULT:-unknown}" "Secret preflight")"
  "$(stage_line "${RETAG_RESULT:-unknown}" "Image retag")"
  "${grype_line}"
  "$(stage_line "${REPLICATED_RESULT:-unknown}" "Replicated release")"
  "$(stage_line "${PR_RESULT:-unknown}" "GitHub PR/release")"
  "${onprem_line}"
)

if [[ "${REPLICATED_RESULT:-unknown}" == "success" ]]; then
  release_created="YES"
  tag_label="Image release tag"
  version_label="Replicated ${release_channel_name} version"
else
  release_created="NO"
  tag_label="Intended image release tag"
  version_label="Intended Replicated version"
fi

{
  if [[ -n "${mention_line}" ]]; then
    echo "${mention_line}"
  fi
  echo "${verdict_line}"
  echo "${release_blocking_line}"
  for line in "${action_lines[@]+"${action_lines[@]}"}"; do
    echo "${line}"
  done
  echo "*Release created:* ${release_created}"
  echo "- ${tag_label}: \`${RELEASE_TAG:-unknown}\`"
  echo "- ${version_label}: \`${PREVIOUS_VERSION:-unknown}\` -> \`${NEW_VERSION:-unknown}\`"
  if [[ "${release_created}" == "YES" ]]; then
    echo "- Release branch: \`${RELEASE_BRANCH:-unknown}\`"
  fi
  echo "*Stages:*"
  for line in "${stage_lines[@]}"; do
    echo "${line}"
  done
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

# --- Slack Block Kit rendering -------------------------------------------
# The same content as slack-summary.txt, laid out as blocks: header, verdict,
# release facts as a field grid, stage checklist, CVE stats, and links.

blocks='[]'

add_block() {
  blocks="$(jq -c --argjson b "$1" '. + [$b]' <<<"${blocks}")"
}

add_header() {
  add_block "$(jq -nc --arg t "$1" '{type: "header", text: {type: "plain_text", text: $t, emoji: true}}')"
}

add_divider() {
  add_block '{"type": "divider"}'
}

add_context() {
  add_block "$(jq -nc --arg t "$1" '{type: "context", elements: [{type: "mrkdwn", text: $t}]}')"
}

# Slack caps section text at 3000 chars; truncate defensively and keep any
# code fence balanced so a huge CVE table cannot invalidate the payload.
add_section() {
  local text="$1"
  if (( ${#text} > 2900 )); then
    text="${text:0:2900}"
    text="${text%$'\n'*}"
    if (( $(grep -c '^```' <<<"${text}") % 2 )); then
      text+=$'\n```'
    fi
    text+=$'\n_…truncated; full details in the Grype artifact._'
  fi
  add_block "$(jq -nc --arg t "${text}" '{type: "section", text: {type: "mrkdwn", text: $t}}')"
}

add_fields() {
  local fields_json='[]'
  local field
  for field in "$@"; do
    fields_json="$(jq -c --arg f "${field}" '. + [{type: "mrkdwn", text: $f}]' <<<"${fields_json}")"
  done
  add_block "$(jq -nc --argjson f "${fields_json}" '{type: "section", fields: $f}')"
}

add_header "${title}"

verdict_block="${verdict_line}"$'\n'"${release_blocking_line}"
if [[ -n "${mention_line}" ]]; then
  verdict_block="${mention_line}"$'\n'"${verdict_block}"
fi
for line in "${action_lines[@]+"${action_lines[@]}"}"; do
  verdict_block+=$'\n'"${line}"
done
add_section "${verdict_block}"

add_divider
release_fields=(
  "*${tag_label}:*"$'\n'"\`${RELEASE_TAG:-unknown}\`"
  "*${version_label}:*"$'\n'"\`${PREVIOUS_VERSION:-unknown}\` → \`${NEW_VERSION:-unknown}\`"
  "*Release created:*"$'\n'"${release_created}"
)
if [[ "${release_created}" == "YES" ]]; then
  release_fields+=("*Release branch:*"$'\n'"\`${RELEASE_BRANCH:-unknown}\`")
fi
add_fields "${release_fields[@]}"

stages_text="*Stages*"
for line in "${stage_lines[@]}"; do
  stages_text+=$'\n'"${line}"
done
add_section "${stages_text}"

if [[ -n "${CVE_STATS:-}" ]]; then
  add_divider
  add_section "*Grype CVE findings*"$'\n'"${CVE_STATS}"
fi
if [[ -n "${CVE_ARTIFACT_NAME:-}" ]]; then
  add_context "Grype artifact: \`${CVE_ARTIFACT_NAME}\`"
fi
if [[ -n "${CVE_ARTIFACT_DOWNLOAD_COMMAND:-}" ]]; then
  add_section "*Download Grype reports:*"$'\n''```'$'\n'"${CVE_ARTIFACT_DOWNLOAD_COMMAND}"$'\n''```'
fi

links_text=""
for index in "${!links[@]}"; do
  if (( index > 0 )); then
    links_text+=" | "
  fi
  links_text+="${links[index]}"
done
add_context "${links_text}"

printf '%s\n' "${blocks}" > slack-blocks.json

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "status=${status}"
    echo "title=${title}"
    echo "summary<<__SLACK_SUMMARY__"
    cat slack-summary.txt
    echo "__SLACK_SUMMARY__"
    echo "blocks<<__SLACK_BLOCKS__"
    cat slack-blocks.json
    echo "__SLACK_BLOCKS__"
  } >> "${GITHUB_OUTPUT}"
fi
