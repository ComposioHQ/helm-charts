# Empty Glean-Stable Channel Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Glean release bootstrap an empty Glean-Stable Replicated channel from the latest Nightly chart while starting and maintaining the independent `0.2.87.x` Glean version sequence.

**Architecture:** Extend the release configuration with optional seed-channel metadata, then teach the tag calculator to preserve the selected channel state while pulling chart values from Nightly only when Glean-Stable is empty. Move version selection into a dedicated Bash helper that runs before AWS/ECR mutations, so an empty Glean channel becomes `0.2.87.1` and invalid non-empty Glean versions fail early.

**Tech Stack:** GitHub Actions YAML, Bash with `set -euo pipefail`, Replicated Vendor API, Helm OCI, `jq`, `yq`, shell integration tests.

## Global Constraints

- `standard` continues to use Nightly channel ID `397k1WtPrJ1J56bhb70SfeKGcxL` and OCI reference `oci://registry.composio.io/composio-rodent/nightly/composio`.
- `glean` continues to promote directly to Glean-Stable channel ID `3GwShNBOwcf13Bs7i5pfn3N8TDh`.
- Only an empty Glean-Stable channel may use a seed channel; an empty Nightly channel remains an error.
- The Glean seed source is Nightly channel ID `397k1WtPrJ1J56bhb70SfeKGcxL` at `oci://registry.composio.io/composio-rodent/nightly/composio`.
- Nightly supplies only the fixed image-tag base for the first Glean release; it never supplies the Glean version.
- The first Glean version is exactly `0.2.87.1`.
- Every later Glean version increments only the last segment of `0.2.87.x`; any other non-empty Glean version must fail before AWS credentials or ECR retagging.
- The first Glean tag is `<Nightly fixed tag>-p<current IST date>_01`; later Glean tags keep the same fixed base.
- Preserve unrelated worktree changes and stage only the files listed by each task.

---

### Task 1: Expose Glean seed and version policy

**Files:**
- Modify: `.github/scripts/resolve-release-config.sh:5-43`
- Test: `.github/scripts/tests/resolve-release-config-test.sh:22-50`

**Interfaces:**
- Consumes: `RELEASE_TYPE` with supported values `standard` and `glean`.
- Produces: existing outputs plus `seed_channel_name`, `seed_channel_id`, `seed_chart_oci_ref`, and `version_prefix`.
- Standard produces empty values for all four new outputs.
- Glean produces `Nightly`, `397k1WtPrJ1J56bhb70SfeKGcxL`, `oci://registry.composio.io/composio-rodent/nightly/composio`, and `0.2.87`.

- [ ] **Step 1: Extend the resolver test with the four policy outputs**

Change `assert_config` to accept four more expected values and assert them:

```bash
  local expected_seed_name="$8"
  local expected_seed_id="$9"
  local expected_seed_ref="${10}"
  local expected_version_prefix="${11}"

  assert_output "${output_file}" seed_channel_name "${expected_seed_name}"
  assert_output "${output_file}" seed_channel_id "${expected_seed_id}"
  assert_output "${output_file}" seed_chart_oci_ref "${expected_seed_ref}"
  assert_output "${output_file}" version_prefix "${expected_version_prefix}"
```

Replace the three success cases with:

```bash
assert_config "" standard Nightly 397k1WtPrJ1J56bhb70SfeKGcxL \
  oci://registry.composio.io/composio-rodent/nightly/composio standard nightly \
  "" "" "" ""
assert_config standard standard Nightly 397k1WtPrJ1J56bhb70SfeKGcxL \
  oci://registry.composio.io/composio-rodent/nightly/composio standard nightly \
  "" "" "" ""
assert_config glean glean Glean-Stable 3GwShNBOwcf13Bs7i5pfn3N8TDh \
  oci://registry.composio.io/composio-rodent/glean-stable/composio glean glean \
  Nightly 397k1WtPrJ1J56bhb70SfeKGcxL \
  oci://registry.composio.io/composio-rodent/nightly/composio 0.2.87
```

- [ ] **Step 2: Run the resolver test and verify the new assertion fails**

Run:

```bash
bash .github/scripts/tests/resolve-release-config-test.sh
```

Expected: FAIL on `seed_channel_name` because the resolver does not emit the new metadata yet.

- [ ] **Step 3: Add explicit defaults and the Glean policy to the resolver**

Initialize the optional values before the `case`:

```bash
seed_channel_name=""
seed_channel_id=""
seed_chart_oci_ref=""
version_prefix=""
```

Add these assignments to the `glean)` arm:

```bash
    seed_channel_name="Nightly"
    seed_channel_id="397k1WtPrJ1J56bhb70SfeKGcxL"
    seed_chart_oci_ref="oci://registry.composio.io/composio-rodent/nightly/composio"
    version_prefix="0.2.87"
```

Append these outputs after `branch_prefix`:

```bash
write_output seed_channel_name "${seed_channel_name}"
write_output seed_channel_id "${seed_channel_id}"
write_output seed_chart_oci_ref "${seed_chart_oci_ref}"
write_output version_prefix "${version_prefix}"
```

- [ ] **Step 4: Run the resolver test and Bash syntax check**

Run:

```bash
bash .github/scripts/tests/resolve-release-config-test.sh
bash -n .github/scripts/resolve-release-config.sh .github/scripts/tests/resolve-release-config-test.sh
```

Expected: both commands exit 0 and the test prints `resolve-release-config tests passed`.

- [ ] **Step 5: Commit the release policy metadata**

```bash
git add .github/scripts/resolve-release-config.sh .github/scripts/tests/resolve-release-config-test.sh
git commit -m "ci: expose Glean bootstrap release metadata"
```

---

### Task 2: Bootstrap an empty Glean channel from Nightly chart values

**Files:**
- Modify: `.github/scripts/calculate-nightly-release-tag.sh:5-121`
- Modify: `.github/scripts/calculate-nightly-release-tag.sh:207-289`
- Test: `.github/scripts/tests/calculate-nightly-release-tag-test.sh:13-149`

**Interfaces:**
- Consumes: selected-channel variables `RELEASE_CHANNEL_NAME`, `RELEASE_CHANNEL_ID`, and `CHART_OCI_REF`.
- Consumes when Glean-Stable is empty: `SEED_CHANNEL_NAME`, `SEED_CHANNEL_ID`, and `SEED_CHART_OCI_REF`.
- `resolve_release_channel(app_id, channel_name, expected_channel_id)` returns JSON with `id`, an optionally empty `currentVersion`, and `releaseSequence`.
- `pull_release_values(chart_oci_ref, chart_version)` returns the extracted `values.yaml` path.
- Produces: `replicated_current_version` from the selected channel, which stays empty during bootstrap, plus the calculated `release_tag`.

- [ ] **Step 1: Add an API-level regression test for empty Glean-Stable**

Add this output assertion beside the existing `fail` helper:

```bash
assert_output() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local actual

  actual="$(awk -F= -v key="${key}" '$1 == key { print substr($0, index($0, "=") + 1) }' "${file}" | tail -n1)"
  [[ "${actual}" == "${expected}" ]] \
    || fail "${key}: expected ${expected:-<empty>}, got ${actual:-<empty>}"
}
```

Add `write_fake_api_tools`, which creates a fake `curl`:

```bash
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
```

Add the success helper:

```bash
assert_empty_glean_uses_nightly_seed() {
  local tmp_dir output_file helm_log

  tmp_dir="$(mktemp -d)"
  output_file="${tmp_dir}/github-output"
  helm_log="${tmp_dir}/helm-log"
  write_fake_api_tools "${tmp_dir}/bin"

  PATH="${tmp_dir}/bin:${PATH}" \
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
  bash "${SCRIPT}" >"${tmp_dir}/stdout" 2>"${tmp_dir}/stderr" \
    || fail "empty Glean channel did not bootstrap"

  assert_output "${output_file}" replicated_current_version ""
  assert_output "${output_file}" release_tag "r20260729_04-p20260730_01"
  grep -Fq \
    'pull oci://registry.composio.io/composio-rodent/nightly/composio --version 0.2.140' \
    "${helm_log}" || fail "empty Glean channel did not pull the Nightly seed chart"

  rm -rf "${tmp_dir}"
}
```

Call `assert_empty_glean_uses_nightly_seed` after the existing file-based tag cases.

- [ ] **Step 2: Add negative integration coverage**

Add the failure helper:

```bash
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
```

- [ ] **Step 3: Run the tag test and verify the empty-channel regression fails**

Run:

```bash
bash .github/scripts/tests/calculate-nightly-release-tag-test.sh
```

Expected: FAIL with `Glean-Stable channel response did not include currentVersion`.

- [ ] **Step 4: Parameterize channel resolution and chart pulling**

Add the seed environment variables:

```bash
SEED_CHANNEL_NAME="${SEED_CHANNEL_NAME:-}"
SEED_CHANNEL_ID="${SEED_CHANNEL_ID:-}"
SEED_CHART_OCI_REF="${SEED_CHART_OCI_REF:-}"
```

Change the chart-name helper to consume the reference it is parsing:

```bash
chart_name_from_ref() {
  local chart_oci_ref="$1"
  basename "${chart_oci_ref}"
}
```

Change the channel resolver signature and remove the unconditional `currentVersion` failure:

```bash
resolve_release_channel() {
  local app_id="$1"
  local channel_name="$2"
  local expected_channel_id="$3"
  local channels_json total_count channel_id current_version release_sequence

  channels_json="$(
    curl -fsSLG "https://api.replicated.com/vendor/v3/app/${app_id}/channels" \
      --data-urlencode "channelName=${channel_name}" \
      --header "Accept: application/json" \
      --header "Authorization: ${REPLICATED_API_TOKEN}"
  )"

  total_count="$(echo "${channels_json}" | jq -r '.totalCount // (.channels | length)')"
  if [[ "${total_count}" != "1" ]]; then
    echo "${channel_name} channel was not found in Replicated channels API response" >&2
    exit 1
  fi

  channel_id="$(echo "${channels_json}" | jq -r '.channels[0].id // .channels[0].channelId // empty')"
  current_version="$(echo "${channels_json}" | jq -r '.channels[0].currentVersion // empty')"
  release_sequence="$(echo "${channels_json}" | jq -r '.channels[0].releaseSequence // .channels[0].currentReleaseSequence // empty')"

  if [[ -n "${expected_channel_id}" && "${channel_id}" != "${expected_channel_id}" ]]; then
    echo "${channel_name} channel ID mismatch: expected ${expected_channel_id}, got ${channel_id:-<empty>}" >&2
    exit 1
  fi

  jq -n \
    --arg id "${channel_id}" \
    --arg currentVersion "${current_version}" \
    --arg releaseSequence "${release_sequence}" \
    '{id: $id, currentVersion: $currentVersion, releaseSequence: $releaseSequence}'
}
```

Change `pull_release_values` to accept the source reference:

```bash
pull_release_values() {
  local chart_oci_ref="$1"
  local chart_version="$2"
  local chart_name pull_root chart_dir

  require_cmd helm
  chart_name="$(chart_name_from_ref "${chart_oci_ref}")"
  pull_root="$(mktemp -d)"
  helm pull "${chart_oci_ref}" --version "${chart_version}" --untar --untardir "${pull_root}" >/dev/null

  chart_dir="${pull_root}/${chart_name}"
  if [[ ! -f "${chart_dir}/values.yaml" ]]; then
    echo "Chart pull succeeded but expected values.yaml was missing under ${chart_dir}" >&2
    exit 1
  fi

  printf '%s' "${chart_dir}/values.yaml"
}
```

- [ ] **Step 5: Select Nightly only as the bootstrap chart source**

Extend the `main` local declarations and initialize the source variables so local-file tests remain safe under `set -u`:

```bash
local seed_channel_json values_source_name values_source_version values_source_ref

values_source_name="local file"
values_source_version=""
values_source_ref=""
```

Resolve the selected channel first:

```bash
channel_json="$(
  resolve_release_channel "${app_id}" "${RELEASE_CHANNEL_NAME}" "${RELEASE_CHANNEL_ID}"
)"
channel_id="$(echo "${channel_json}" | jq -r '.id // empty')"
current_version="$(echo "${channel_json}" | jq -r '.currentVersion // empty')"
release_sequence="$(echo "${channel_json}" | jq -r '.releaseSequence // empty')"

values_source_name="${RELEASE_CHANNEL_NAME}"
values_source_version="${current_version}"
values_source_ref="${CHART_OCI_REF}"
```

When the selected `currentVersion` is empty, gate fallback to configured Glean mode and resolve Nightly:

```bash
if [[ -z "${current_version}" || "${current_version}" == "null" ]]; then
  if [[ "${TAG_CALCULATION_MODE}" != "glean" ]]; then
    echo "${RELEASE_CHANNEL_NAME} channel response did not include currentVersion" >&2
    exit 1
  fi

  require_env SEED_CHANNEL_NAME
  require_env SEED_CHANNEL_ID
  require_env SEED_CHART_OCI_REF

  seed_channel_json="$(
    resolve_release_channel "${app_id}" "${SEED_CHANNEL_NAME}" "${SEED_CHANNEL_ID}"
  )"
  values_source_version="$(echo "${seed_channel_json}" | jq -r '.currentVersion // empty')"
  if [[ -z "${values_source_version}" || "${values_source_version}" == "null" ]]; then
    echo "${SEED_CHANNEL_NAME} seed channel response did not include currentVersion" >&2
    exit 1
  fi

  values_source_name="${SEED_CHANNEL_NAME}"
  values_source_ref="${SEED_CHART_OCI_REF}"
fi

values_file="$(pull_release_values "${values_source_ref}" "${values_source_version}")"
```

Log the actual chart source without replacing selected-channel outputs:

```bash
echo "Chart values source: ${values_source_name:-local file} ${values_source_version:-not resolved}"
write_output "replicated_current_version" "${current_version}"
```

- [ ] **Step 6: Run focused and regression tag tests**

Run:

```bash
bash .github/scripts/tests/calculate-nightly-release-tag-test.sh
bash -n .github/scripts/calculate-nightly-release-tag.sh .github/scripts/tests/calculate-nightly-release-tag-test.sh
```

Expected: both commands exit 0; the existing standard/Glean cases and all new empty-channel cases pass.

- [ ] **Step 7: Commit the bootstrap tag behavior**

```bash
git add .github/scripts/calculate-nightly-release-tag.sh .github/scripts/tests/calculate-nightly-release-tag-test.sh
git commit -m "fix(ci): bootstrap empty Glean channel from Nightly"
```

---

### Task 3: Calculate and validate release versions before mutations

**Files:**
- Create: `.github/scripts/calculate-release-version.sh`
- Create: `.github/scripts/tests/calculate-release-version-test.sh`

**Interfaces:**
- Consumes: `RELEASE_TYPE`, `CURRENT_VERSION`, `VERSION_PREFIX`, and optional `RELEASE_CHANNEL_NAME`.
- Produces GitHub outputs `current` and `new`.
- Standard requires a non-empty dotted numeric current version and increments its final segment.
- Glean maps an empty current version to `${VERSION_PREFIX}.1`, increments a matching `${VERSION_PREFIX}.x`, and rejects every other non-empty version.

- [ ] **Step 1: Write the version-helper test**

Create `.github/scripts/tests/calculate-release-version-test.sh` with:

```bash
#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="${SCRIPT_DIR}/calculate-release-version.sh"

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

assert_version() {
  local name="$1"
  local release_type="$2"
  local current_version="$3"
  local version_prefix="$4"
  local expected_current="$5"
  local expected_new="$6"
  local tmp_dir output_file

  tmp_dir="$(mktemp -d)"
  output_file="${tmp_dir}/github-output"
  RELEASE_TYPE="${release_type}" \
  RELEASE_CHANNEL_NAME="$([[ "${release_type}" == "glean" ]] && printf Glean-Stable || printf Nightly)" \
  CURRENT_VERSION="${current_version}" \
  VERSION_PREFIX="${version_prefix}" \
  GITHUB_OUTPUT="${output_file}" \
  bash "${SCRIPT}" >"${tmp_dir}/stdout" 2>"${tmp_dir}/stderr" \
    || fail "${name}: script exited non-zero"

  assert_output "${output_file}" current "${expected_current}"
  assert_output "${output_file}" new "${expected_new}"
  rm -rf "${tmp_dir}"
}

assert_version_fails() {
  local name="$1"
  local release_type="$2"
  local current_version="$3"
  local version_prefix="$4"
  local expected_error="$5"
  local tmp_dir channel_name

  tmp_dir="$(mktemp -d)"
  channel_name="Nightly"
  if [[ "${release_type}" == "glean" ]]; then
    channel_name="Glean-Stable"
  fi

  if RELEASE_TYPE="${release_type}" \
    RELEASE_CHANNEL_NAME="${channel_name}" \
    CURRENT_VERSION="${current_version}" \
    VERSION_PREFIX="${version_prefix}" \
    bash "${SCRIPT}" >"${tmp_dir}/stdout" 2>"${tmp_dir}/stderr"; then
    fail "${name}: script unexpectedly succeeded"
  fi

  grep -Fq "${expected_error}" "${tmp_dir}/stderr" \
    || fail "${name}: expected error was not emitted"
  rm -rf "${tmp_dir}"
}

assert_version "increments standard version" \
  standard "0.2.140" "" "0.2.140" "0.2.141"
assert_version "bootstraps empty Glean version" \
  glean "" "0.2.87" "" "0.2.87.1"
assert_version "increments existing Glean version" \
  glean "0.2.87.1" "0.2.87" "0.2.87.1" "0.2.87.2"
assert_version "increments a multi-digit Glean sequence" \
  glean "0.2.87.19" "0.2.87" "0.2.87.19" "0.2.87.20"
```

Include these failure cases and expected errors:

```bash
assert_version_fails "rejects empty standard version" \
  standard "" "" "Nightly channel returned an invalid currentVersion: <empty>"
assert_version_fails "rejects a different Glean family" \
  glean "0.2.88.1" "0.2.87" "Glean-Stable currentVersion must match 0.2.87.x: 0.2.88.1"
assert_version_fails "requires the Glean version prefix" \
  glean "" "" "VERSION_PREFIX is required."

echo "calculate-release-version tests passed"
```

- [ ] **Step 2: Run the new test and verify it fails because the helper is absent**

Run:

```bash
bash .github/scripts/tests/calculate-release-version-test.sh
```

Expected: FAIL because `.github/scripts/calculate-release-version.sh` does not exist.

- [ ] **Step 3: Implement the focused version helper**

Create `.github/scripts/calculate-release-version.sh`:

```bash
#!/usr/bin/env bash

set -euo pipefail

release_type="${RELEASE_TYPE:-standard}"
current_version="${CURRENT_VERSION:-}"
version_prefix="${VERSION_PREFIX:-}"
release_channel_name="${RELEASE_CHANNEL_NAME:-Selected}"

write_output() {
  local key="$1"
  local value="$2"

  echo "${key}=${value}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "${GITHUB_OUTPUT}"
  fi
}

case "${release_type}" in
  standard)
    if [[ ! "${current_version}" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
      echo "${release_channel_name} channel returned an invalid currentVersion: ${current_version:-<empty>}" >&2
      exit 1
    fi
    new_version="$(awk -F. '{$NF = $NF + 1} 1' OFS=. <<<"${current_version}")"
    ;;
  glean)
    if [[ -z "${version_prefix}" ]]; then
      echo "VERSION_PREFIX is required." >&2
      exit 1
    fi

    if [[ -z "${current_version}" ]]; then
      new_version="${version_prefix}.1"
    else
      version_prefix_pattern="${version_prefix//./\\.}"
      if [[ ! "${current_version}" =~ ^${version_prefix_pattern}\.([0-9]+)$ ]]; then
        echo "${release_channel_name} currentVersion must match ${version_prefix}.x: ${current_version}" >&2
        exit 1
      fi
      new_version="${version_prefix}.$((10#${BASH_REMATCH[1]} + 1))"
    fi
    ;;
  *)
    echo "Unsupported release type: ${release_type}" >&2
    exit 1
    ;;
esac

write_output current "${current_version}"
write_output new "${new_version}"
```

- [ ] **Step 4: Run the version tests and syntax checks**

Run:

```bash
bash .github/scripts/tests/calculate-release-version-test.sh
bash -n .github/scripts/calculate-release-version.sh .github/scripts/tests/calculate-release-version-test.sh
```

Expected: both commands exit 0 and the test prints `calculate-release-version tests passed`.

- [ ] **Step 5: Commit the version policy helper**

```bash
git add .github/scripts/calculate-release-version.sh .github/scripts/tests/calculate-release-version-test.sh
git commit -m "ci: validate release channel version sequences"
```

---

### Task 4: Wire bootstrap metadata and early version validation into the workflow

**Files:**
- Modify: `.github/workflows/nighty-release.yml:74-196`
- Modify: `.github/workflows/nighty-release.yml:357-497`
- Test: `.github/scripts/tests/nighty-release-workflow-test.sh:38-49`

**Interfaces:**
- Consumes Task 1 outputs and passes seed metadata to Task 2.
- Invokes Task 3 immediately after tag calculation and before the AWS role/credentials steps.
- `retag-latest-images` produces `current_version` and `new_version`.
- `replicated-release` consumes those job outputs and does not calculate versions again.

- [ ] **Step 1: Add workflow contract assertions**

Append these assertions to `.github/scripts/tests/nighty-release-workflow-test.sh`:

```bash
assert_contains "seed channel name output" \
  'seed_channel_name: ${{ steps.config.outputs.seed_channel_name }}'
assert_contains "seed channel id output" \
  'seed_channel_id: ${{ steps.config.outputs.seed_channel_id }}'
assert_contains "seed chart output" \
  'seed_chart_oci_ref: ${{ steps.config.outputs.seed_chart_oci_ref }}'
assert_contains "version prefix output" \
  'version_prefix: ${{ steps.config.outputs.version_prefix }}'
assert_contains "selected seed channel name" \
  'SEED_CHANNEL_NAME: ${{ needs.release-config.outputs.seed_channel_name }}'
assert_contains "selected seed channel id" \
  'SEED_CHANNEL_ID: ${{ needs.release-config.outputs.seed_channel_id }}'
assert_contains "selected seed chart" \
  'SEED_CHART_OCI_REF: ${{ needs.release-config.outputs.seed_chart_oci_ref }}'
assert_contains "release version helper" \
  'bash ./.github/scripts/calculate-release-version.sh'
assert_contains "version calculated before AWS" \
  'id: calculate_version'
assert_contains "retag current version output" \
  'current_version: ${{ steps.calculate_version.outputs.current }}'
assert_contains "retag new version output" \
  'new_version: ${{ steps.calculate_version.outputs.new }}'
assert_contains "replicated version consumption" \
  'version: ${{ needs.retag-latest-images.outputs.new_version }}'
```

Add an `assert_not_contains` helper and assert the obsolete step is removed:

```bash
assert_not_contains() {
  local name="$1"
  local needle="$2"
  if grep -Fq -- "${needle}" "${WORKFLOW}"; then
    echo "FAIL: ${name}: unexpectedly found ${needle}" >&2
    exit 1
  fi
}

assert_not_contains "late inline version calculation" \
  'name: Get and bump version'
```

Add an ordering assertion:

```bash
assert_before() {
  local name="$1"
  local first="$2"
  local second="$3"
  local first_line second_line

  first_line="$(grep -nF -- "${first}" "${WORKFLOW}" | head -n1 | cut -d: -f1)"
  second_line="$(grep -nF -- "${second}" "${WORKFLOW}" | head -n1 | cut -d: -f1)"
  if [[ -z "${first_line}" || -z "${second_line}" || "${first_line}" -ge "${second_line}" ]]; then
    echo "FAIL: ${name}: expected ${first} before ${second}" >&2
    exit 1
  fi
}

assert_before "version validation precedes AWS credentials" \
  'id: calculate_version' \
  'name: Determine AWS Assume Role ARN'
```

- [ ] **Step 2: Run the workflow contract test and verify it fails**

Run:

```bash
bash .github/scripts/tests/nighty-release-workflow-test.sh
```

Expected: FAIL on the first missing seed output.

- [ ] **Step 3: Export the release policy from `release-config`**

Add these job outputs:

```yaml
      seed_channel_name: ${{ steps.config.outputs.seed_channel_name }}
      seed_channel_id: ${{ steps.config.outputs.seed_channel_id }}
      seed_chart_oci_ref: ${{ steps.config.outputs.seed_chart_oci_ref }}
      version_prefix: ${{ steps.config.outputs.version_prefix }}
```

Pass the seed inputs to `calculate-nightly-release-tag.sh`:

```yaml
          SEED_CHANNEL_NAME: ${{ needs.release-config.outputs.seed_channel_name }}
          SEED_CHANNEL_ID: ${{ needs.release-config.outputs.seed_channel_id }}
          SEED_CHART_OCI_REF: ${{ needs.release-config.outputs.seed_chart_oci_ref }}
```

- [ ] **Step 4: Calculate the version immediately after the release tag**

Add this step directly after `Calculate release tag from selected Replicated channel` and before `Determine AWS Assume Role ARN`:

```yaml
      - name: Calculate and validate release version
        id: calculate_version
        shell: bash
        env:
          RELEASE_TYPE: ${{ needs.release-config.outputs.release_type }}
          RELEASE_CHANNEL_NAME: ${{ needs.release-config.outputs.channel_name }}
          CURRENT_VERSION: ${{ steps.calculate_release_tag.outputs.replicated_current_version }}
          VERSION_PREFIX: ${{ needs.release-config.outputs.version_prefix }}
        run: bash ./.github/scripts/calculate-release-version.sh
```

Change `retag-latest-images.outputs` to:

```yaml
      current_version: ${{ steps.calculate_version.outputs.current }}
      new_version: ${{ steps.calculate_version.outputs.new }}
```

This ordering is mandatory: invalid `0.2.87.x` state must stop the job before AWS credentials are configured and before any ECR tags are created.

- [ ] **Step 5: Remove late version calculation and consume validated outputs**

Change the `replicated-release` outputs:

```yaml
      previous_version: ${{ needs.retag-latest-images.outputs.current_version }}
      version: ${{ needs.retag-latest-images.outputs.new_version }}
```

Delete the entire `Get and bump version` step. Replace every remaining `${{ steps.version.outputs.new }}` with:

```text
${{ needs.retag-latest-images.outputs.new_version }}
```

The replacements are required in:

- `Update Chart.yaml versions`
- `Update manifest versions`
- `replicated release create --version`

- [ ] **Step 6: Run workflow, YAML, and Bash validation**

Run:

```bash
bash .github/scripts/tests/nighty-release-workflow-test.sh
yq eval '.' .github/workflows/nighty-release.yml >/dev/null
bash -n \
  .github/scripts/resolve-release-config.sh \
  .github/scripts/calculate-nightly-release-tag.sh \
  .github/scripts/calculate-release-version.sh \
  .github/scripts/tests/resolve-release-config-test.sh \
  .github/scripts/tests/calculate-nightly-release-tag-test.sh \
  .github/scripts/tests/calculate-release-version-test.sh \
  .github/scripts/tests/nighty-release-workflow-test.sh
```

Expected: every command exits 0 and the workflow test prints `nighty-release workflow tests passed`.

- [ ] **Step 7: Commit the workflow wiring**

```bash
git add .github/workflows/nighty-release.yml .github/scripts/tests/nighty-release-workflow-test.sh
git commit -m "fix(ci): validate Glean version before image retagging"
```

---

### Task 5: Run the complete release-workflow verification and prepare the focused diff

**Files:**
- Delete before PR: `docs/superpowers/specs/2026-07-29-empty-glean-channel-bootstrap-design.md`
- Delete before PR: `docs/superpowers/plans/2026-07-29-empty-glean-channel-bootstrap.md`
- Verify: `.github/workflows/nighty-release.yml`
- Verify: `.github/scripts/*.sh`
- Verify: `.github/scripts/tests/*.sh`
- Verify: `composio/`

**Interfaces:**
- Consumes the completed scripts and workflow from Tasks 1-4.
- Produces a PR-ready diff containing only the workflow, runtime helpers, and tests.

- [ ] **Step 1: Run every release-workflow shell test**

Run:

```bash
bash .github/scripts/tests/resolve-release-config-test.sh
bash .github/scripts/tests/calculate-nightly-release-tag-test.sh
bash .github/scripts/tests/calculate-release-version-test.sh
bash .github/scripts/tests/nighty-release-workflow-test.sh
bash .github/scripts/tests/nightly-slack-summary-test.sh
```

Expected: all five scripts exit 0 and print their respective `tests passed` messages.

- [ ] **Step 2: Validate all changed Bash and YAML files**

Run:

```bash
bash -n \
  .github/scripts/resolve-release-config.sh \
  .github/scripts/calculate-nightly-release-tag.sh \
  .github/scripts/calculate-release-version.sh \
  .github/scripts/tests/resolve-release-config-test.sh \
  .github/scripts/tests/calculate-nightly-release-tag-test.sh \
  .github/scripts/tests/calculate-release-version-test.sh \
  .github/scripts/tests/nighty-release-workflow-test.sh
yq eval '.' .github/workflows/nighty-release.yml >/dev/null
```

Expected: both commands exit 0 without output.

- [ ] **Step 3: Verify the unchanged chart still lints and renders**

Run:

```bash
helm lint composio
helm template composio composio >/dev/null
```

Expected: lint reports `0 chart(s) failed`; rendering exits 0.

- [ ] **Step 4: Inspect the final behavior-specific diff**

Run:

```bash
git diff --check origin/release-stable...HEAD
git diff --stat origin/release-stable...HEAD
git diff origin/release-stable...HEAD -- \
  .github/workflows/nighty-release.yml \
  .github/scripts/resolve-release-config.sh \
  .github/scripts/calculate-nightly-release-tag.sh \
  .github/scripts/calculate-release-version.sh \
  .github/scripts/tests
```

Confirm the diff proves:

- standard has no seed metadata and keeps its existing tag/version behavior;
- empty Glean preserves an empty selected `currentVersion` but pulls Nightly `values.yaml`;
- bootstrap tag is `<Nightly base>-p<IST date>_01`;
- empty Glean becomes `0.2.87.1`;
- existing `0.2.87.x` increments only `x`;
- invalid Glean versions fail before the AWS steps;
- promotion still uses `${{ needs.release-config.outputs.channel_name }}`.

- [ ] **Step 5: Remove internal planning artifacts from the implementation diff**

Use `apply_patch` to delete:

```text
docs/superpowers/specs/2026-07-29-empty-glean-channel-bootstrap-design.md
docs/superpowers/plans/2026-07-29-empty-glean-channel-bootstrap.md
```

Then commit only those deletions:

```bash
git add \
  docs/superpowers/specs/2026-07-29-empty-glean-channel-bootstrap-design.md \
  docs/superpowers/plans/2026-07-29-empty-glean-channel-bootstrap.md
git commit -m "docs: remove internal Glean bootstrap plans"
```

- [ ] **Step 6: Confirm the PR diff is focused**

Run:

```bash
git status --short
git diff --check origin/release-stable...HEAD
git diff --name-status origin/release-stable...HEAD
```

Expected:

- the worktree is clean;
- `git diff --check` exits 0;
- the final name-status contains only `.github/workflows/nighty-release.yml`, the three runtime scripts, and their test scripts;
- no chart, manifest, packaged chart, secret, or internal planning file is present.
