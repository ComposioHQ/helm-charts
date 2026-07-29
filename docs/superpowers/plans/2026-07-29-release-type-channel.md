# Release Type and Replicated Channel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `standard` and `glean` release modes to the nightly workflow so each mode calculates image tags from, versions against, and promotes to its configured Replicated channel.

**Architecture:** A focused shell helper maps `release_type` to immutable channel metadata, and the workflow publishes that metadata as job outputs. The existing tag helper becomes channel-aware and supports either the current calendar tag or a fixed Glean base with an incrementing `pYYYYMMDD_NN` suffix. The workflow consumes one resolved configuration throughout tag calculation, versioning, promotion, validation, and user-visible reporting.

**Tech Stack:** GitHub Actions YAML, Bash, `jq`, `yq`, Helm, Replicated CLI, shell test scripts.

## Global Constraints

- `standard` maps to Nightly channel ID `397k1WtPrJ1J56bhb70SfeKGcxL`.
- `glean` maps to Glean-Stable channel ID `3GwShNBOwcf13Bs7i5pfn3N8TDh`.
- Scheduled runs and manual runs without an explicit selection resolve to `standard`.
- Standard tags remain `rYYYYMMDD_NN`.
- Glean tags are `<fixed-base>-pYYYYMMDD_NN`, for example `r20260729_01-p20260801_02`.
- A Glean tag's fixed base comes from the latest Glean-Stable release and never advances during suffix calculation.
- Glean releases are promoted directly to Glean-Stable.
- Existing source-image overrides, ECR collision checks, CVE scanning, chart packaging, PR creation, and on-prem validation remain active.

---

## File Map

- Create `.github/scripts/resolve-release-config.sh`: map a release type to channel name, channel ID, OCI reference, tag mode, and branch prefix.
- Create `.github/scripts/tests/resolve-release-config-test.sh`: verify both mappings, the default, and unsupported-input rejection.
- Modify `.github/scripts/calculate-nightly-release-tag.sh`: make channel lookup generic, verify channel identity, and calculate Glean suffix tags.
- Modify `.github/scripts/tests/calculate-nightly-release-tag-test.sh`: specify standard and Glean tag behavior before implementation.
- Create `.github/scripts/tests/nighty-release-workflow-test.sh`: enforce the workflow input and selected-channel wiring.
- Modify `.github/workflows/nighty-release.yml`: add the input and route every channel-sensitive step through resolved outputs.
- Modify `.github/scripts/nightly-slack-summary.sh`: identify the selected channel in the report.
- Modify `.github/scripts/tests/nightly-slack-summary-test.sh`: verify the Glean report label while retaining Nightly defaults.

### Task 1: Resolve Release Configuration

**Files:**
- Create: `.github/scripts/resolve-release-config.sh`
- Create: `.github/scripts/tests/resolve-release-config-test.sh`

**Interfaces:**
- Consumes: `RELEASE_TYPE`, with an empty value treated as `standard`; optional `GITHUB_OUTPUT`.
- Produces: `release_type`, `channel_name`, `channel_id`, `chart_oci_ref`, `tag_calculation_mode`, and `branch_prefix` outputs.

- [ ] **Step 1: Write the failing resolver test**

Create `.github/scripts/tests/resolve-release-config-test.sh` with a helper that
runs the resolver into a temporary `GITHUB_OUTPUT` file and asserts all values:

```bash
#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="${SCRIPT_DIR}/resolve-release-config.sh"

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
  [[ "${actual}" == "${expected}" ]] || fail "${key}: expected ${expected}, got ${actual:-<empty>}"
}

assert_config() {
  local release_type="$1"
  local expected_type="$2"
  local expected_name="$3"
  local expected_id="$4"
  local expected_ref="$5"
  local expected_mode="$6"
  local expected_prefix="$7"
  local tmp_dir output_file

  tmp_dir="$(mktemp -d)"
  output_file="${tmp_dir}/github-output"
  RELEASE_TYPE="${release_type}" GITHUB_OUTPUT="${output_file}" bash "${SCRIPT}"

  assert_output "${output_file}" release_type "${expected_type}"
  assert_output "${output_file}" channel_name "${expected_name}"
  assert_output "${output_file}" channel_id "${expected_id}"
  assert_output "${output_file}" chart_oci_ref "${expected_ref}"
  assert_output "${output_file}" tag_calculation_mode "${expected_mode}"
  assert_output "${output_file}" branch_prefix "${expected_prefix}"
  rm -rf "${tmp_dir}"
}

assert_config "" standard Nightly 397k1WtPrJ1J56bhb70SfeKGcxL \
  oci://registry.composio.io/composio-rodent/nightly/composio standard nightly
assert_config standard standard Nightly 397k1WtPrJ1J56bhb70SfeKGcxL \
  oci://registry.composio.io/composio-rodent/nightly/composio standard nightly
assert_config glean glean Glean-Stable 3GwShNBOwcf13Bs7i5pfn3N8TDh \
  oci://registry.composio.io/composio-rodent/glean-stable/composio glean glean

if RELEASE_TYPE=unsupported bash "${SCRIPT}" >/dev/null 2>&1; then
  fail "unsupported release type should fail"
fi

echo "resolve-release-config tests passed"
```

- [ ] **Step 2: Run the resolver test and verify RED**

Run:

```bash
bash .github/scripts/tests/resolve-release-config-test.sh
```

Expected: FAIL because `.github/scripts/resolve-release-config.sh` does not
exist.

- [ ] **Step 3: Implement the resolver**

Create `.github/scripts/resolve-release-config.sh`:

```bash
#!/usr/bin/env bash

set -euo pipefail

release_type="${RELEASE_TYPE:-standard}"

case "${release_type}" in
  standard)
    channel_name="Nightly"
    channel_id="397k1WtPrJ1J56bhb70SfeKGcxL"
    chart_oci_ref="oci://registry.composio.io/composio-rodent/nightly/composio"
    tag_calculation_mode="standard"
    branch_prefix="nightly"
    ;;
  glean)
    channel_name="Glean-Stable"
    channel_id="3GwShNBOwcf13Bs7i5pfn3N8TDh"
    chart_oci_ref="oci://registry.composio.io/composio-rodent/glean-stable/composio"
    tag_calculation_mode="glean"
    branch_prefix="glean"
    ;;
  *)
    echo "Unsupported release type: ${release_type}" >&2
    exit 1
    ;;
esac

write_output() {
  local key="$1"
  local value="$2"
  echo "${key}=${value}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "${GITHUB_OUTPUT}"
  fi
}

write_output release_type "${release_type}"
write_output channel_name "${channel_name}"
write_output channel_id "${channel_id}"
write_output chart_oci_ref "${chart_oci_ref}"
write_output tag_calculation_mode "${tag_calculation_mode}"
write_output branch_prefix "${branch_prefix}"
```

- [ ] **Step 4: Run the resolver test and verify GREEN**

Run:

```bash
bash .github/scripts/tests/resolve-release-config-test.sh
```

Expected: `resolve-release-config tests passed`.

- [ ] **Step 5: Commit the resolver**

```bash
git add .github/scripts/resolve-release-config.sh .github/scripts/tests/resolve-release-config-test.sh
git commit -m "feat(ci): resolve release channel configuration"
```

### Task 2: Calculate Standard and Glean Tags

**Files:**
- Modify: `.github/scripts/calculate-nightly-release-tag.sh:5-203`
- Modify: `.github/scripts/tests/calculate-nightly-release-tag-test.sh:13-73`

**Interfaces:**
- Consumes: `TAG_CALCULATION_MODE=standard|glean`,
  `RELEASE_CHANNEL_NAME`, `RELEASE_CHANNEL_ID`, `CHART_OCI_REF`,
  `RELEASE_VALUES_FILE`, `RELEASE_TAG_DATE`, `REPLICATED_APP`, and
  `REPLICATED_API_TOKEN`.
- Produces: existing Replicated metadata outputs plus `base_tag`,
  `suffix_tag`, and `release_tag`.

- [ ] **Step 1: Extend the tag test helper and add failing Glean cases**

Change `assert_release_tag` to accept `mode` before `date_ist`, set
`TAG_CALCULATION_MODE` and `RELEASE_VALUES_FILE`, and update existing calls to
pass `standard`:

```bash
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
    GITHUB_OUTPUT="${output_file}" \
    bash "${SCRIPT}" >"${tmp_dir}/stdout" 2>"${tmp_dir}/stderr"; then
    echo "stdout:" >&2
    sed 's/^/  /' "${tmp_dir}/stdout" >&2
    echo "stderr:" >&2
    sed 's/^/  /' "${tmp_dir}/stderr" >&2
    fail "${name}: script exited non-zero"
  fi

  actual="$(awk -F= '$1 == "release_tag" { print $2 }' "${output_file}" | tail -n1)"
  [[ "${actual}" == "${expected}" ]] \
    || fail "${name}: expected ${expected}, got ${actual:-<empty>}"
  rm -rf "${tmp_dir}"
}
```

Add these cases:

```bash
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
```

Add `assert_release_tag_fails` and verify Glean mode rejects values containing
only `latest`:

```bash
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
    bash "${SCRIPT}" >"${tmp_dir}/stdout" 2>"${tmp_dir}/stderr"; then
    fail "${name}: script unexpectedly succeeded"
  fi

  grep -Fq "${expected_error}" "${tmp_dir}/stderr" \
    || fail "${name}: expected error was not emitted"
  rm -rf "${tmp_dir}"
}

assert_release_tag_fails "rejects glean values without a fixed base" glean \
  "20260801" "Glean tag calculation requires a valid fixed base tag." '
apollo:
  image:
    tag: latest
'
```

- [ ] **Step 2: Run the tag test and verify RED**

Run:

```bash
bash .github/scripts/tests/calculate-nightly-release-tag-test.sh
```

Expected: FAIL because the current helper ignores `TAG_CALCULATION_MODE` and
cannot emit `-pYYYYMMDD_NN`.

- [ ] **Step 3: Generalize channel lookup and chart pulling**

In `.github/scripts/calculate-nightly-release-tag.sh`:

- Replace `NIGHTLY_CHANNEL_NAME` with
  `RELEASE_CHANNEL_NAME="${RELEASE_CHANNEL_NAME:-Nightly}"`.
- Add `RELEASE_CHANNEL_ID="${RELEASE_CHANNEL_ID:-}"`.
- Add `TAG_CALCULATION_MODE="${TAG_CALCULATION_MODE:-standard}"`.
- Rename `resolve_nightly_channel` to `resolve_release_channel`.
- Query `channelName=${RELEASE_CHANNEL_NAME}`.
- After extracting the returned ID, fail when `RELEASE_CHANNEL_ID` is non-empty
  and does not equal the returned ID.
- Rename `pull_nightly_values` to `pull_release_values`.
- Accept `RELEASE_VALUES_FILE` for local tests, while also honoring
  `NIGHTLY_VALUES_FILE` as a compatibility fallback.

The identity check must be:

```bash
if [[ -n "${RELEASE_CHANNEL_ID}" && "${channel_id}" != "${RELEASE_CHANNEL_ID}" ]]; then
  echo "${RELEASE_CHANNEL_NAME} channel ID mismatch: expected ${RELEASE_CHANNEL_ID}, got ${channel_id:-<empty>}" >&2
  exit 1
fi
```

- [ ] **Step 4: Implement Glean extraction and suffix calculation**

Keep standard extraction restricted to `^r[0-9]{8}_[0-9]{2}$`.

Extract all service image tags once:

```bash
extract_image_tags() {
  local values_file="$1"

  require_cmd yq
  yq -r '
    [
      .apollo.image.tag,
      .apollo.dbInit.image.tag,
      .thermos.image.tag,
      .thermos.dbInit.image.tag,
      .thermosMiscWorkers.image.tag,
      .mercury.image.tag,
      .frontend.image.tag,
      .weaviate.image.tag,
      .toolkitRegistry.image.tag
    ]
    | .[]
    | select(. != null)
    | tostring
  ' "${values_file}"
}
```

Add a Glean extractor that accepts either a plain base or a suffixed tag. Use
`awk` so an empty match set remains a normal empty result rather than a
`pipefail` error:

```bash
extract_glean_tags() {
  local values_file="$1"
  extract_image_tags "${values_file}" \
    | awk '/^r[0-9]{8}_[0-9]{2}(-p[0-9]{8}_[0-9]{2})?$/' \
    | sort -u
}

calculate_next_glean_tag() {
  local base_tag="$1"
  local suffix_tag="$2"
  local date_ist="$3"
  local next_nn="01"

  if [[ ! "${base_tag}" =~ ^r[0-9]{8}_[0-9]{2}$ ]]; then
    echo "Glean tag calculation requires a valid fixed base tag." >&2
    return 1
  fi

  if [[ "${suffix_tag}" =~ ^p([0-9]{8})_([0-9]{2})$ ]] \
    && [[ "${BASH_REMATCH[1]}" == "${date_ist}" ]]; then
    next_nn="$(printf '%02d' "$((10#${BASH_REMATCH[2]} + 1))")"
  fi

  printf '%s-p%s_%s' "${base_tag}" "${date_ist}" "${next_nn}"
}
```

In `main`, select standard or Glean calculation with a `case` statement. For
Glean mode, derive values with:

```bash
glean_tags="$(extract_glean_tags "${values_file}")"
base_tag="$(
  printf '%s\n' "${glean_tags}" \
    | sed -E 's/-p[0-9]{8}_[0-9]{2}$//' \
    | awk 'NF' \
    | sort -u \
    | tail -n1
)"
suffix_tag="$(
  printf '%s\n' "${glean_tags}" \
    | awk -v prefix="${base_tag}-" 'index($0, prefix) == 1 {
        sub("^" prefix, "", $0)
        print
      }' \
    | sort -u \
    | tail -n1
)"
new_tag="$(calculate_next_glean_tag "${base_tag}" "${suffix_tag}" "${date_ist}")"
```

Write `suffix_tag` to `GITHUB_OUTPUT` and reject any unsupported calculation
mode.

- [ ] **Step 5: Run the tag tests and verify GREEN**

Run:

```bash
bash .github/scripts/tests/calculate-nightly-release-tag-test.sh
```

Expected: `calculate-nightly-release-tag tests passed`.

- [ ] **Step 6: Run static shell checks**

Run:

```bash
bash -n .github/scripts/calculate-nightly-release-tag.sh
bash -n .github/scripts/tests/calculate-nightly-release-tag-test.sh
bash -n .github/scripts/resolve-release-config.sh
bash -n .github/scripts/tests/resolve-release-config-test.sh
```

Expected: all commands exit zero.

- [ ] **Step 7: Commit the tag calculation**

```bash
git add .github/scripts/calculate-nightly-release-tag.sh .github/scripts/tests/calculate-nightly-release-tag-test.sh
git commit -m "feat(ci): calculate Glean release image tags"
```

### Task 3: Wire Release Type Through the Workflow

**Files:**
- Create: `.github/scripts/tests/nighty-release-workflow-test.sh`
- Modify: `.github/workflows/nighty-release.yml:7-916`

**Interfaces:**
- Consumes: outputs from `.github/scripts/resolve-release-config.sh` and
  `.github/scripts/calculate-nightly-release-tag.sh`.
- Produces: channel-correct ECR tags, chart version, branch, Replicated
  promotion, PR text, GitHub release text, CVE identifiers, and harness labels.

- [ ] **Step 1: Write the failing workflow contract test**

Create `.github/scripts/tests/nighty-release-workflow-test.sh`. Use `yq` to
assert:

```bash
#!/usr/bin/env bash

set -euo pipefail

WORKFLOW=".github/workflows/nighty-release.yml"

assert_eq() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL: ${name}: expected ${expected}, got ${actual}" >&2
    exit 1
  fi
}

assert_contains() {
  local name="$1"
  local needle="$2"
  grep -Fq -- "${needle}" "${WORKFLOW}" || {
    echo "FAIL: ${name}: missing ${needle}" >&2
    exit 1
  }
}

assert_eq "release input type" \
  "$(yq -r '.on.workflow_dispatch.inputs.release_type.type' "${WORKFLOW}")" choice
assert_eq "release input default" \
  "$(yq -r '.on.workflow_dispatch.inputs.release_type.default' "${WORKFLOW}")" standard
assert_eq "release input options" \
  "$(yq -o=json -I=0 '.on.workflow_dispatch.inputs.release_type.options' "${WORKFLOW}")" \
  '["standard","glean"]'

assert_contains "config resolver" \
  'bash ./.github/scripts/resolve-release-config.sh'
assert_contains "selected chart" \
  'CHART_OCI_REF: ${{ needs.release-config.outputs.chart_oci_ref }}'
assert_contains "selected channel name" \
  'RELEASE_CHANNEL_NAME: ${{ needs.release-config.outputs.channel_name }}'
assert_contains "selected channel id" \
  'RELEASE_CHANNEL_ID: ${{ needs.release-config.outputs.channel_id }}'
assert_contains "selected tag mode" \
  'TAG_CALCULATION_MODE: ${{ needs.release-config.outputs.tag_calculation_mode }}'
assert_contains "selected promotion" \
  '--promote "${{ needs.release-config.outputs.channel_name }}"'

echo "nighty-release workflow tests passed"
```

- [ ] **Step 2: Run the workflow test and verify RED**

Run:

```bash
bash .github/scripts/tests/nighty-release-workflow-test.sh
```

Expected: FAIL because `release_type` and `release-config` are absent.

- [ ] **Step 3: Add the input and configuration job**

Add this input before image-tag inputs:

```yaml
release_type:
  description: "Release path and Replicated channel."
  required: true
  type: choice
  default: standard
  options:
    - standard
    - glean
```

Add a `release-config` job that checks out the repository, runs
`resolve-release-config.sh` with
`RELEASE_TYPE: ${{ github.event.inputs.release_type || 'standard' }}`, and
exports all six resolver outputs:

```yaml
release-config:
  runs-on: ubuntu-latest
  outputs:
    release_type: ${{ steps.config.outputs.release_type }}
    channel_name: ${{ steps.config.outputs.channel_name }}
    channel_id: ${{ steps.config.outputs.channel_id }}
    chart_oci_ref: ${{ steps.config.outputs.chart_oci_ref }}
    tag_calculation_mode: ${{ steps.config.outputs.tag_calculation_mode }}
    branch_prefix: ${{ steps.config.outputs.branch_prefix }}
  steps:
    - name: Checkout code
      uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5

    - name: Resolve release configuration
      id: config
      shell: bash
      env:
        RELEASE_TYPE: ${{ github.event.inputs.release_type || 'standard' }}
      run: bash ./.github/scripts/resolve-release-config.sh
```

- [ ] **Step 4: Make retagging and scanning channel-aware**

- Add `release-config` to `retag-latest-images.needs`.
- Use `needs.release-config.outputs.chart_oci_ref` for registry login and chart
  pull.
- Pass channel name, channel ID, and tag mode to the calculation step.
- Export `replicated_current_version` from the calculation step as
  `retag-latest-images.outputs.current_version`.
- Replace Nightly-only calculation log text with the selected channel name.
- Add `release-config` to `cve-scan.needs`.
- Set `scan_name` to the release type and set `artifact_prefix` to
  `${release_type}-grype-cve-reports`.

- [ ] **Step 5: Make versioning, branching, and promotion channel-aware**

- Add `release-config` to `replicated-release.needs`.
- Build the branch as
  `${branch_prefix}-${release_tag}`.
- Replace the duplicate Replicated channel API lookup in `Get and bump version`
  with the validated `retag-latest-images.outputs.current_version`.
- Keep the existing final numeric-segment increment.
- Use the channel name in the release commit message.
- Pass the selected channel name to `replicated release create --promote`.

- [ ] **Step 6: Make PR, GitHub release, and harness text channel-aware**

- Add `release-config` to `create-nightly-release-pr.needs`,
  `onprem-testbed.needs`, and `notify-nightly-report.needs`.
- In GitHub Script steps, define
  `const channelName = "${{ needs.release-config.outputs.channel_name }}"`.
- Use `${channelName} release ${releaseTag}` as the PR title.
- Say the image tags and manifest versions target `${channelName}` in the PR
  body and GitHub release body.
- Use `${{ needs.release-config.outputs.channel_name }}` in the fresh-install
  and upgrade harness names.
- Keep the existing `nightly-release` PR label because it triggers the existing
  on-prem validation workflow.

- [ ] **Step 7: Run the workflow test and YAML parser**

Run:

```bash
bash .github/scripts/tests/nighty-release-workflow-test.sh
yq eval '.' .github/workflows/nighty-release.yml >/dev/null
```

Expected: the workflow contract test passes and `yq` exits zero.

- [ ] **Step 8: Commit workflow wiring**

```bash
git add .github/workflows/nighty-release.yml .github/scripts/tests/nighty-release-workflow-test.sh
git commit -m "feat(ci): select release channel by release type"
```

### Task 4: Identify the Selected Channel in Slack Reporting

**Files:**
- Modify: `.github/scripts/nightly-slack-summary.sh`
- Modify: `.github/scripts/tests/nightly-slack-summary-test.sh`
- Modify: `.github/workflows/nighty-release.yml:882-908`

**Interfaces:**
- Consumes: optional `RELEASE_CHANNEL_NAME`, defaulting to `Nightly`.
- Produces: channel-specific Slack report title and summary without changing
  result classification.

- [ ] **Step 1: Add a failing Glean reporting assertion**

The test runner already accepts environment overrides after its test name. Add
a successful case:

```bash
glean_dir="$(run_summary glean RELEASE_CHANNEL_NAME=Glean-Stable)"
assert_contains "${glean_dir}/github-output" \
  "title=:white_check_mark: Glean-Stable release: GOOD TO GO"
assert_contains "${glean_dir}/slack-summary.txt" \
  "- Replicated Glean-Stable version: \`0.2.134\` -> \`0.2.135\`"
```

Add `${glean_dir}` to the final cleanup.

- [ ] **Step 2: Run the Slack summary test and verify RED**

Run:

```bash
bash .github/scripts/tests/nightly-slack-summary-test.sh
```

Expected: FAIL because the current title is hardcoded to Nightly.

- [ ] **Step 3: Make the report label channel-aware**

In `.github/scripts/nightly-slack-summary.sh`, add:

```bash
release_channel_name="${RELEASE_CHANNEL_NAME:-Nightly}"
```

Replace `Nightly release` in all four title branches with
`${release_channel_name} release`. Replace `Replicated Nightly version` with
`Replicated ${release_channel_name} version` and `Nightly branch` with
`Release branch`. In the workflow, pass
`RELEASE_CHANNEL_NAME: ${{ needs.release-config.outputs.channel_name }}` to the
`Build Slack summary` step.

- [ ] **Step 4: Run the Slack and workflow tests and verify GREEN**

Run:

```bash
bash .github/scripts/tests/nightly-slack-summary-test.sh
bash .github/scripts/tests/nighty-release-workflow-test.sh
```

Expected: both test scripts pass.

- [ ] **Step 5: Commit report labeling**

```bash
git add .github/scripts/nightly-slack-summary.sh .github/scripts/tests/nightly-slack-summary-test.sh .github/workflows/nighty-release.yml
git commit -m "fix(ci): label release reports by channel"
```

### Task 5: Full Verification

**Files:**
- Verify all files changed in Tasks 1-4.

**Interfaces:**
- Consumes: the complete implementation.
- Produces: evidence that shell behavior, workflow structure, YAML, and Helm
  rendering remain valid.

- [ ] **Step 1: Run all focused shell tests**

```bash
bash .github/scripts/tests/resolve-release-config-test.sh
bash .github/scripts/tests/calculate-nightly-release-tag-test.sh
bash .github/scripts/tests/nighty-release-workflow-test.sh
bash .github/scripts/tests/nightly-slack-summary-test.sh
```

Expected: all four scripts pass.

- [ ] **Step 2: Run syntax checks**

```bash
bash -n .github/scripts/resolve-release-config.sh
bash -n .github/scripts/calculate-nightly-release-tag.sh
bash -n .github/scripts/nightly-slack-summary.sh
bash -n .github/scripts/tests/resolve-release-config-test.sh
bash -n .github/scripts/tests/calculate-nightly-release-tag-test.sh
bash -n .github/scripts/tests/nighty-release-workflow-test.sh
bash -n .github/scripts/tests/nightly-slack-summary-test.sh
yq eval '.' .github/workflows/nighty-release.yml >/dev/null
```

Expected: every command exits zero.

- [ ] **Step 3: Run Helm validation**

```bash
helm lint composio/
helm template composio composio/ --debug >/dev/null
```

Expected: lint succeeds and the chart renders.

- [ ] **Step 4: Run `actionlint` when installed**

```bash
if command -v actionlint >/dev/null 2>&1; then
  actionlint .github/workflows/nighty-release.yml
else
  echo "actionlint is not installed; workflow contract tests and yq parsing were used."
fi
```

Expected: `actionlint` passes, or the command records that it is unavailable.

- [ ] **Step 5: Inspect the final diff**

```bash
git diff --check origin/release-stable...HEAD
git status --short
git log -5 --oneline
```

Expected: no whitespace errors; only the approved spec, plan, workflow, release
helpers, and their tests differ from the original branch.
