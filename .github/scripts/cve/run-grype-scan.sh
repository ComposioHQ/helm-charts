#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-cve-reports}"
SCAN_TARGETS_FILE="${SCAN_TARGETS_FILE:-${OUTPUT_DIR}/scan-targets.json}"
GRYPE_BIN="${GRYPE_BIN:-grype}"

if [[ ! -f "${SCAN_TARGETS_FILE}" ]]; then
  echo "Scan targets file not found: ${SCAN_TARGETS_FILE}" >&2
  exit 1
fi

mapfile -t targets < <(jq -c '.[]' "${SCAN_TARGETS_FILE}")
echo '[]' > "${SCAN_TARGETS_FILE}.updated"

for target in "${targets[@]}"; do
  scan_image="$(jq -r '.scan_image' <<<"${target}")"
  safe_name="$(printf '%s' "${scan_image}" | tr -c 'A-Za-z0-9_.-' '_')"
  report_name="${safe_name}.json"
  report_json="${OUTPUT_DIR}/${report_name}"

  echo "Scanning ${scan_image}"
  set +e
  "${GRYPE_BIN}" "registry:${scan_image}" \
    --fail-on high \
    --output json \
    --file "${report_json}"
  grype_rc=$?
  set -e

  updated="$(jq -c \
    --arg report "${report_name}" \
    --argjson grype_exit "${grype_rc}" \
    '. + {report: $report, grype_exit: $grype_exit}' <<<"${target}")"
  jq -c --argjson row "${updated}" '. + [$row]' "${SCAN_TARGETS_FILE}.updated" > "${SCAN_TARGETS_FILE}.tmp"
  mv "${SCAN_TARGETS_FILE}.tmp" "${SCAN_TARGETS_FILE}.updated"
done

mv "${SCAN_TARGETS_FILE}.updated" "${SCAN_TARGETS_FILE}"
