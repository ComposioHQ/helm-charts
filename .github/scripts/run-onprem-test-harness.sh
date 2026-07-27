#!/usr/bin/env bash
set -euo pipefail

: "${HELM_CHART_VERSION:?HELM_CHART_VERSION is required}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONPREM_REPO="${ONPREM_REPO:-ComposioHQ/onprem-testbed}"
ONPREM_WORKFLOW_FILE="${ONPREM_WORKFLOW_FILE:-replicated-cmx-harness.yml}"
ONPREM_REF="${ONPREM_REF:-main}"
ONPREM_DISPATCH_MODE="${ONPREM_DISPATCH_MODE:-workflow_dispatch}"
HARNESS_NAME="${HARNESS_NAME:-onprem-testbed}"
HARNESS_ENV_JSON="${HARNESS_ENV_JSON:-}"
if [[ -z "${HARNESS_ENV_JSON}" ]]; then
  HARNESS_ENV_JSON="{}"
fi
SCENARIOS="${SCENARIOS:-}"
INCLUDE_OPTIONAL_SCENARIOS="${INCLUDE_OPTIONAL_SCENARIOS:-}"
UPGRADE_FROM_VERSIONS="${UPGRADE_FROM_VERSIONS:-}"
MIGRATION_DIRECTION="${MIGRATION_DIRECTION:-}"
CLUSTER_SIZE="${CLUSTER_SIZE:-}"
CLUSTER_TTL="${CLUSTER_TTL:-}"
GITHUB_APP_OWNER="${GITHUB_APP_OWNER:-ComposioHQ}"
GITHUB_APP_REPOSITORIES="${GITHUB_APP_REPOSITORIES:-helm-charts,onprem-testbed}"
if [[ -z "${GITHUB_APP_PERMISSIONS_JSON:-}" ]]; then
  if [[ "${ONPREM_DISPATCH_MODE}" == "repository_dispatch" ]]; then
    GITHUB_APP_PERMISSIONS_JSON='{"actions":"write","contents":"write"}'
  else
    GITHUB_APP_PERMISSIONS_JSON='{"actions":"write","contents":"read"}'
  fi
fi
GITHUB_APP_TOKEN_EXPIRES_AT_EPOCH="${GITHUB_APP_TOKEN_EXPIRES_AT_EPOCH:-0}"
payload="{}"

append_field() {
  local name="$1"
  local value="$2"
  if [[ -n "${value}" ]]; then
    workflow_args+=(--raw-field "${name}=${value}")
    payload="$(jq -c --arg name "${name}" --arg value "${value}" '. + {($name): $value}' <<<"${payload}")"
  fi
}

mint_github_app_token() {
  local token_json token expires_at
  token_json="$(
    GITHUB_APP_OWNER="${GITHUB_APP_OWNER}" \
    GITHUB_APP_REPOSITORIES="${GITHUB_APP_REPOSITORIES}" \
    GITHUB_APP_PERMISSIONS_JSON="${GITHUB_APP_PERMISSIONS_JSON}" \
    node "${SCRIPT_DIR}/github-app-token.mjs"
  )"
  token="$(jq -r '.token' <<<"${token_json}")"
  expires_at="$(jq -r '.expires_at' <<<"${token_json}")"
  if [[ -z "${token}" || "${token}" == "null" ]]; then
    echo "Unable to mint GitHub App installation token" >&2
    exit 1
  fi
  echo "::add-mask::${token}"
  export GH_TOKEN="${token}"
  GITHUB_APP_TOKEN_EXPIRES_AT_EPOCH="$(
    node -e 'console.log(Math.floor(new Date(process.argv[1]).getTime() / 1000))' "${expires_at}"
  )"
}

ensure_github_token() {
  if [[ -n "${GITHUB_APP_CLIENT_ID:-}" && -n "${GITHUB_APP_PRIVATE_KEY:-}" ]]; then
    local now
    now="$(date -u +%s)"
    if (( now + 300 >= GITHUB_APP_TOKEN_EXPIRES_AT_EPOCH )); then
      mint_github_app_token
    fi
    return
  fi

  if [[ -z "${GH_TOKEN:-}" ]]; then
    echo "GH_TOKEN or GitHub App credentials are required" >&2
    exit 1
  fi
}

dispatch_started="$(date -u +%s)"

workflow_args=(
  workflow run "${ONPREM_WORKFLOW_FILE}"
  --repo "${ONPREM_REPO}"
  --ref "${ONPREM_REF}"
)

append_field "helm_chart_version" "${HELM_CHART_VERSION}"
append_field "scenarios" "${SCENARIOS}"
append_field "include_optional_scenarios" "${INCLUDE_OPTIONAL_SCENARIOS}"
append_field "upgrade_from_versions" "${UPGRADE_FROM_VERSIONS}"
append_field "migration_direction" "${MIGRATION_DIRECTION}"
append_field "cluster_size" "${CLUSTER_SIZE}"
append_field "cluster_ttl" "${CLUSTER_TTL}"
append_field "harness_env_json" "${HARNESS_ENV_JSON}"

echo "Dispatching ${HARNESS_NAME} to ${ONPREM_REPO}/${ONPREM_WORKFLOW_FILE} on ${ONPREM_REF}"
echo "Dispatch mode: ${ONPREM_DISPATCH_MODE}"
echo "Helm chart version: ${HELM_CHART_VERSION}"
echo "Scenarios: ${SCENARIOS:-<default>}"
echo "Upgrade from versions: ${UPGRADE_FROM_VERSIONS:-<none>}"
echo "Cluster size: ${CLUSTER_SIZE:-<workflow default>}"

ensure_github_token
if [[ "${ONPREM_DISPATCH_MODE}" == "repository_dispatch" ]]; then
  if [[ "${ONPREM_REF}" != "main" ]]; then
    echo "repository_dispatch always runs the target repo default branch; set ONPREM_REF=main or use workflow_dispatch" >&2
    exit 1
  fi
  dispatch_payload="$(
    jq -nc \
      --arg event_type "replicated-cmx-harness" \
      --argjson client_payload "${payload}" \
      '{event_type: $event_type, client_payload: $client_payload}'
  )"
  dispatch_output="$(gh api "repos/${ONPREM_REPO}/dispatches" --method POST --input - <<<"${dispatch_payload}")"
  run_event="repository_dispatch"
else
  dispatch_output="$(gh "${workflow_args[@]}")"
  run_event="workflow_dispatch"
fi
printf '%s\n' "${dispatch_output}"

run_id="$(
  sed -nE 's#.*actions/runs/([0-9]+).*#\1#p' <<<"${dispatch_output}" \
    | tail -n1
)"

if [[ -z "${run_id}" ]]; then
  for attempt in {1..60}; do
    ensure_github_token
    runs_json="$(
      gh run list \
        --repo "${ONPREM_REPO}" \
        --workflow "${ONPREM_WORKFLOW_FILE}" \
        --event "${run_event}" \
        --limit 20 \
        --json databaseId,createdAt,url
    )"
    run_id="$(
      jq -r --argjson started "${dispatch_started}" '
        [.[] | select((.createdAt | fromdateiso8601) >= $started)]
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
fi

if [[ -z "${run_id}" ]]; then
  echo "Unable to find onprem-testbed ${run_event} run for chart ${HELM_CHART_VERSION}" >&2
  exit 1
fi

ensure_github_token
run_url="$(gh run view "${run_id}" --repo "${ONPREM_REPO}" --json url --jq '.url')"
echo "Onprem test harness run: ${run_url}"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "run_id=${run_id}"
    echo "run_url=${run_url}"
  } >> "${GITHUB_OUTPUT}"
fi
{
  echo "### ${HARNESS_NAME}"
  echo
  echo "Run: ${run_url}"
  echo "Scenarios: ${SCENARIOS:-<default>}"
  echo "Upgrade from versions: ${UPGRADE_FROM_VERSIONS:-<none>}"
} >> "${GITHUB_STEP_SUMMARY}"

while true; do
  ensure_github_token
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
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "conclusion=${conclusion}" >> "${GITHUB_OUTPUT}"
fi
if [[ "${conclusion}" != "success" ]]; then
  echo "Onprem test harness failed with conclusion '${conclusion}': ${run_url}" >&2
  exit 1
fi
