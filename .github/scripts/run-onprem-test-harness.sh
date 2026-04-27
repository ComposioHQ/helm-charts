#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${HELM_CHART_VERSION:?HELM_CHART_VERSION is required}"

ONPREM_REPO="${ONPREM_REPO:-ComposioHQ/onprem-testbed}"
ONPREM_WORKFLOW_FILE="${ONPREM_WORKFLOW_FILE:-replicated-cmx-harness.yml}"
ONPREM_REF="${ONPREM_REF:-main}"
if [[ -z "${HARNESS_ENV_JSON:-}" ]]; then
  HARNESS_ENV_JSON='{"RUN_TRIGGER_TESTS":"1"}'
fi

if ! jq -e . >/dev/null <<<"${HARNESS_ENV_JSON}"; then
  echo "HARNESS_ENV_JSON must be valid JSON: ${HARNESS_ENV_JSON}" >&2
  exit 1
fi

dispatch_started="$(date -u +%s)"
dispatch_inputs="$(
  jq -n \
    --arg helm_chart_version "${HELM_CHART_VERSION}" \
    --arg harness_env_json "${HARNESS_ENV_JSON}" \
    '{
      helm_chart_version: $helm_chart_version,
      harness_env_json: $harness_env_json
    }'
)"

gh workflow run "${ONPREM_WORKFLOW_FILE}" \
  --repo "${ONPREM_REPO}" \
  --ref "${ONPREM_REF}" \
  --json <<<"${dispatch_inputs}"

run_id=""
for attempt in {1..60}; do
  runs_json="$(
    gh run list \
      --repo "${ONPREM_REPO}" \
      --workflow "${ONPREM_WORKFLOW_FILE}" \
      --event workflow_dispatch \
      --limit 20 \
      --json databaseId,createdAt,url
  )"
  run_id="$(
    jq -r --argjson started "${dispatch_started}" '
      [.[] | select((.createdAt | fromdateiso8601) >= ($started - 60))]
      | sort_by(.createdAt)
      | reverse
      | .[0].databaseId // empty
    ' <<<"${runs_json}"
  )"
  if [[ -n "${run_id}" ]]; then
    break
  fi
  echo "Waiting for onprem-testbed workflow run to appear (${attempt}/60)"
  sleep 10
done

if [[ -z "${run_id}" ]]; then
  echo "Unable to find onprem-testbed workflow_dispatch run for chart ${HELM_CHART_VERSION}" >&2
  exit 1
fi

run_url="$(gh run view "${run_id}" --repo "${ONPREM_REPO}" --json url --jq '.url')"
echo "Onprem test harness run: ${run_url}"
{
  echo "### Onprem Test Harness"
  echo
  echo "Run: ${run_url}"
} >> "${GITHUB_STEP_SUMMARY}"

while true; do
  run_json="$(gh run view "${run_id}" --repo "${ONPREM_REPO}" --json status,conclusion,url)"
  status="$(jq -r '.status' <<<"${run_json}")"
  conclusion="$(jq -r '.conclusion // ""' <<<"${run_json}")"
  run_url="$(jq -r '.url' <<<"${run_json}")"

  if [[ "${status}" == "completed" ]]; then
    break
  fi
  echo "Onprem test harness status: ${status}"
  sleep 30
done

echo "Onprem test harness conclusion: ${conclusion}"
if [[ "${conclusion}" != "success" ]]; then
  echo "Onprem test harness failed with conclusion '${conclusion}': ${run_url}" >&2
  exit 1
fi
