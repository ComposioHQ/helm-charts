#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: generate-release-changelog.sh <from_identifier> <to_identifier> [output_file]

Identifiers can be any of:
- a git ref that contains composio/Chart.yaml and composio/values.yaml
- a Helm chart version present in git history
- a Helm chart version published at CHART_OCI_REF
- the special identifier WORKTREE for the current checked-out files

The generated markdown includes:
- the OCI image tag delta from composio/values.yaml
- the current helm-charts repo changes when chart versions map to git commits
- source repository and revision metadata from image labels when accessible
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

set_meta() {
  local prefix="$1"
  local key="$2"
  local value="$3"
  printf -v "${prefix}_${key}" '%s' "${value}"
}

get_meta() {
  local prefix="$1"
  local key="$2"
  local var_name="${prefix}_${key}"
  printf '%s' "${!var_name:-}"
}

safe_name() {
  echo "$1" | tr -c 'A-Za-z0-9._-' '_'
}

chart_name_from_ref() {
  basename "${CHART_OCI_REF}"
}

copy_release_files_from_git() {
  local ref="$1"
  local prefix="$2"

  git show "${ref}:composio/Chart.yaml" > "${TMPDIR_PATH}/${prefix}-Chart.yaml"
  git show "${ref}:composio/values.yaml" > "${TMPDIR_PATH}/${prefix}-values.yaml"
}

resolve_from_git_ref() {
  local identifier="$1"
  local prefix="$2"
  local chart_version app_version commit_sha commit_date

  if ! git rev-parse --verify "${identifier}^{commit}" >/dev/null 2>&1; then
    return 1
  fi

  if ! git show "${identifier}:composio/values.yaml" >/dev/null 2>&1; then
    return 1
  fi

  copy_release_files_from_git "${identifier}" "${prefix}"

  chart_version="$(yq -r '.version // ""' "${TMPDIR_PATH}/${prefix}-Chart.yaml")"
  app_version="$(yq -r '.appVersion // ""' "${TMPDIR_PATH}/${prefix}-Chart.yaml")"
  commit_sha="$(git rev-parse "${identifier}^{commit}")"
  commit_date="$(git log -1 --date=short --format=%cd "${identifier}")"

  set_meta "${prefix}" identifier "${identifier}"
  set_meta "${prefix}" source_kind "git-ref"
  set_meta "${prefix}" source_ref "${commit_sha}"
  set_meta "${prefix}" source_date "${commit_date}"
  set_meta "${prefix}" chart_version "${chart_version}"
  set_meta "${prefix}" app_version "${app_version}"

  return 0
}

find_commit_for_chart_version() {
  local wanted_version="$1"
  local commit chart_version

  while IFS= read -r commit; do
    chart_version="$(git show "${commit}:composio/Chart.yaml" 2>/dev/null | yq -r '.version // ""' 2>/dev/null || true)"
    if [[ "${chart_version}" == "${wanted_version}" ]]; then
      echo "${commit}"
      return 0
    fi
  done < <(git log --all --format='%H' -- composio/Chart.yaml | awk '!seen[$0]++')

  return 1
}

resolve_from_git_chart_version() {
  local version="$1"
  local prefix="$2"
  local commit app_version commit_date

  if ! commit="$(find_commit_for_chart_version "${version}")"; then
    return 1
  fi

  copy_release_files_from_git "${commit}" "${prefix}"

  app_version="$(yq -r '.appVersion // ""' "${TMPDIR_PATH}/${prefix}-Chart.yaml")"
  commit_date="$(git log -1 --date=short --format=%cd "${commit}")"

  set_meta "${prefix}" identifier "${version}"
  set_meta "${prefix}" source_kind "git-chart-version"
  set_meta "${prefix}" source_ref "${commit}"
  set_meta "${prefix}" source_date "${commit_date}"
  set_meta "${prefix}" chart_version "${version}"
  set_meta "${prefix}" app_version "${app_version}"

  return 0
}

resolve_from_chart_oci() {
  local version="$1"
  local prefix="$2"
  local pull_root chart_dir chart_name app_version helm_pull_log

  require_cmd helm

  pull_root="${TMPDIR_PATH}/chart-$(safe_name "${version}")"
  helm_pull_log="${TMPDIR_PATH}/helm-pull-$(safe_name "${version}").log"
  chart_name="$(chart_name_from_ref)"
  rm -rf "${pull_root}"
  mkdir -p "${pull_root}"

  if ! helm pull "${CHART_OCI_REF}" --version "${version}" --untar --untardir "${pull_root}" >"${helm_pull_log}" 2>&1; then
    cat >&2 <<EOF
Failed to resolve chart version ${version}.
Checked git history and then tried pulling ${CHART_OCI_REF}:${version}.
If the chart is private, run helm registry login before generating the changelog.
EOF
    if [[ -s "${helm_pull_log}" ]]; then
      echo "Helm pull output:" >&2
      sed 's/^/  /' "${helm_pull_log}" >&2
    fi
    exit 1
  fi

  chart_dir="${pull_root}/${chart_name}"
  if [[ ! -f "${chart_dir}/Chart.yaml" || ! -f "${chart_dir}/values.yaml" ]]; then
    echo "Chart pull succeeded but expected files were missing under ${chart_dir}" >&2
    exit 1
  fi

  cp "${chart_dir}/Chart.yaml" "${TMPDIR_PATH}/${prefix}-Chart.yaml"
  cp "${chart_dir}/values.yaml" "${TMPDIR_PATH}/${prefix}-values.yaml"

  app_version="$(yq -r '.appVersion // ""' "${TMPDIR_PATH}/${prefix}-Chart.yaml")"

  set_meta "${prefix}" identifier "${version}"
  set_meta "${prefix}" source_kind "chart-oci"
  set_meta "${prefix}" source_ref "${CHART_OCI_REF}@${version}"
  set_meta "${prefix}" source_date ""
  set_meta "${prefix}" chart_version "${version}"
  set_meta "${prefix}" app_version "${app_version}"

  return 0
}

resolve_from_worktree() {
  local identifier="$1"
  local prefix="$2"
  local chart_version app_version

  if [[ "${identifier}" != "WORKTREE" ]]; then
    return 1
  fi

  if [[ ! -f "composio/Chart.yaml" || ! -f "composio/values.yaml" ]]; then
    echo "WORKTREE resolution requires composio/Chart.yaml and composio/values.yaml in the current checkout." >&2
    exit 1
  fi

  cp "composio/Chart.yaml" "${TMPDIR_PATH}/${prefix}-Chart.yaml"
  cp "composio/values.yaml" "${TMPDIR_PATH}/${prefix}-values.yaml"

  chart_version="$(yq -r '.version // ""' "${TMPDIR_PATH}/${prefix}-Chart.yaml")"
  app_version="$(yq -r '.appVersion // ""' "${TMPDIR_PATH}/${prefix}-Chart.yaml")"

  set_meta "${prefix}" identifier "${identifier}"
  set_meta "${prefix}" source_kind "worktree"
  set_meta "${prefix}" source_ref "WORKTREE"
  set_meta "${prefix}" source_date ""
  set_meta "${prefix}" chart_version "${chart_version}"
  set_meta "${prefix}" app_version "${app_version}"

  return 0
}

resolve_identifier() {
  local identifier="$1"
  local prefix="$2"

  if resolve_from_worktree "${identifier}" "${prefix}"; then
    return 0
  fi

  if resolve_from_git_ref "${identifier}" "${prefix}"; then
    return 0
  fi

  if resolve_from_git_chart_version "${identifier}" "${prefix}"; then
    return 0
  fi

  resolve_from_chart_oci "${identifier}" "${prefix}"
}

normalize_source_repo() {
  local source="$1"

  source="${source#https://github.com/}"
  source="${source#http://github.com/}"
  source="${source#ssh://git@github.com/}"
  source="${source#git@github.com:}"
  source="${source#git://github.com/}"
  source="${source#github.com/}"
  source="${source%.git}"
  source="${source#/}"

  if [[ "${source}" == */* ]]; then
    printf '%s' "${source}"
  fi
}

ecr_fetch_image_config_json() {
  local registry="$1"
  local repository="$2"
  local tag="$3"
  local registry_id region image_json manifest_json manifest_media_type child_digest config_digest download_url

  if [[ ! "${registry}" =~ ^([0-9]{12})\.dkr\.ecr\.([a-z0-9-]+)\.amazonaws\.com$ ]]; then
    return 1
  fi

  registry_id="${BASH_REMATCH[1]}"
  region="${BASH_REMATCH[2]}"

  image_json="$(
    aws ecr batch-get-image \
      --region "${region}" \
      --registry-id "${registry_id}" \
      --repository-name "${repository}" \
      --image-ids imageTag="${tag}" \
      --accepted-media-types \
        application/vnd.oci.image.manifest.v1+json \
        application/vnd.oci.image.index.v1+json \
        application/vnd.docker.distribution.manifest.v2+json \
        application/vnd.docker.distribution.manifest.list.v2+json \
      --output json \
      2>/dev/null
  )" || return 1

  manifest_json="$(jq -er '.images[0].imageManifest | fromjson' <<<"${image_json}" 2>/dev/null)" || return 1
  manifest_media_type="$(jq -r '.images[0].imageManifestMediaType // empty' <<<"${image_json}")"

  if [[ "${manifest_media_type}" == *"image.index"* || "${manifest_media_type}" == *"manifest.list"* ]]; then
    child_digest="$(jq -r '.manifests[0].digest // empty' <<<"${manifest_json}")"
    [[ -n "${child_digest}" ]] || return 1

    image_json="$(
      aws ecr batch-get-image \
        --region "${region}" \
        --registry-id "${registry_id}" \
        --repository-name "${repository}" \
        --image-ids imageDigest="${child_digest}" \
        --accepted-media-types \
          application/vnd.oci.image.manifest.v1+json \
          application/vnd.docker.distribution.manifest.v2+json \
        --output json \
        2>/dev/null
    )" || return 1

    manifest_json="$(jq -er '.images[0].imageManifest | fromjson' <<<"${image_json}" 2>/dev/null)" || return 1
  fi

  config_digest="$(jq -r '.config.digest // empty' <<<"${manifest_json}")"
  [[ -n "${config_digest}" ]] || return 1

  download_url="$(
    aws ecr get-download-url-for-layer \
      --region "${region}" \
      --registry-id "${registry_id}" \
      --repository-name "${repository}" \
      --layer-digest "${config_digest}" \
      --output json \
      2>/dev/null \
    | jq -r '.downloadUrl // empty'
  )" || return 1

  [[ -n "${download_url}" ]] || return 1
  curl -fsSL "${download_url}"
}

lookup_image_label_metadata_json() {
  local registry="$1"
  local repository="$2"
  local tag="$3"
  local fallback_source_repo="$4"
  local source_repo="${fallback_source_repo}"
  local source_label=""
  local revision=""
  local metadata_origin="fallback-map"
  local metadata_status="unavailable"
  local config_json normalized_source

  if [[ -z "${repository}" || -z "${tag}" ]]; then
    jq -cn \
      --arg source_repo "${source_repo}" \
      --arg source_label "${source_label}" \
      --arg revision "${revision}" \
      --arg metadata_origin "${metadata_origin}" \
      --arg metadata_status "missing-image-reference" \
      '{
        source_repo: $source_repo,
        source_label: $source_label,
        revision: $revision,
        metadata_origin: $metadata_origin,
        metadata_status: $metadata_status
      }'
    return 0
  fi

  if [[ "${ENABLE_IMAGE_LABEL_LOOKUP:-1}" != "1" ]]; then
    metadata_status="lookup-disabled"
  elif ! command -v aws >/dev/null 2>&1; then
    metadata_status="aws-cli-missing"
  elif ! config_json="$(ecr_fetch_image_config_json "${registry}" "${repository}" "${tag}")"; then
    metadata_status="lookup-failed"
  else
    source_label="$(jq -r '.config.Labels["org.opencontainers.image.source"] // ""' <<<"${config_json}")"
    revision="$(jq -r '.config.Labels["org.opencontainers.image.revision"] // ""' <<<"${config_json}")"
    normalized_source="$(normalize_source_repo "${source_label}")"

    if [[ -n "${normalized_source}" ]]; then
      source_repo="${normalized_source}"
    fi

    if [[ -n "${source_label}" || -n "${revision}" ]]; then
      metadata_origin="image-label"
    fi

    metadata_status="ok"
  fi

  jq -cn \
    --arg source_repo "${source_repo}" \
    --arg source_label "${source_label}" \
    --arg revision "${revision}" \
    --arg metadata_origin "${metadata_origin}" \
    --arg metadata_status "${metadata_status}" \
    '{
      source_repo: $source_repo,
      source_label: $source_label,
      revision: $revision,
      metadata_origin: $metadata_origin,
      metadata_status: $metadata_status
    }'
}

extract_images_json() {
  local file="$1"

  yq -o=json '
    {
      "apollo": {
        "registry": (.global.registry.name // ""),
        "repository": (.apollo.image.repository // ""),
        "tag": (.apollo.image.tag // ""),
        "fallback_source_repo": "ComposioHQ/apollo"
      },
      "apollo-db-init": {
        "registry": (.global.registry.name // ""),
        "repository": (.apollo.dbInit.image.repository // ""),
        "tag": (.apollo.dbInit.image.tag // ""),
        "fallback_source_repo": "ComposioHQ/apollo"
      },
      "thermos": {
        "registry": (.global.registry.name // ""),
        "repository": (.thermos.image.repository // ""),
        "tag": (.thermos.image.tag // ""),
        "fallback_source_repo": "ComposioHQ/hermes"
      },
      "thermos-db-init": {
        "registry": (.global.registry.name // ""),
        "repository": (.thermos.dbInit.image.repository // ""),
        "tag": (.thermos.dbInit.image.tag // ""),
        "fallback_source_repo": "ComposioHQ/hermes"
      },
      "mercury": {
        "registry": (.global.registry.name // ""),
        "repository": (.mercury.image.repository // ""),
        "tag": (.mercury.image.tag // ""),
        "fallback_source_repo": "ComposioHQ/mercury"
      },
      "weaviate": {
        "registry": (.global.registry.name // ""),
        "repository": (.weaviate.image.repository // ""),
        "tag": (.weaviate.image.tag // ""),
        "fallback_source_repo": ""
      }
    }
  ' "${file}"
}

enrich_images_json() {
  local images_json="$1"
  local result_json="$images_json"
  local component_json name registry repository tag fallback_source_repo metadata_json

  while IFS= read -r component_json; do
    name="$(jq -r '.name' <<<"${component_json}")"
    registry="$(jq -r '.registry // ""' <<<"${component_json}")"
    repository="$(jq -r '.repository // ""' <<<"${component_json}")"
    tag="$(jq -r '.tag // ""' <<<"${component_json}")"
    fallback_source_repo="$(jq -r '.fallback_source_repo // ""' <<<"${component_json}")"

    metadata_json="$(lookup_image_label_metadata_json "${registry}" "${repository}" "${tag}" "${fallback_source_repo}")"

    result_json="$(
      jq -c \
        --arg name "${name}" \
        --argjson metadata "${metadata_json}" \
        '.[$name] += $metadata' \
        <<<"${result_json}"
    )"
  done < <(jq -c 'to_entries[] | {name: .key} + .value' <<<"${images_json}")

  printf '%s' "${result_json}"
}

github_compare_request() {
  local repo="$1"
  local base="$2"
  local head="$3"
  local url="https://api.github.com/repos/${repo}/compare/${base}...${head}"
  local body_file status
  local token="${CHANGELOG_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}"

  body_file="$(mktemp "${TMPDIR_PATH}/compare-XXXXXX.json")"

  if [[ -n "${token}" ]]; then
    status="$(curl -sS -L \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${token}" \
      -o "${body_file}" \
      -w '%{http_code}' \
      "${url}")"
  else
    status="$(curl -sS -L \
      -H "Accept: application/vnd.github+json" \
      -o "${body_file}" \
      -w '%{http_code}' \
      "${url}")"
  fi

  if [[ "${status}" != "200" ]]; then
    rm -f "${body_file}"
    return 1
  fi

  cat "${body_file}"
  rm -f "${body_file}"
}

append_helm_charts_section() {
  local from_kind to_kind from_ref to_ref compare_url commit_count

  from_kind="$(get_meta FROM source_kind)"
  to_kind="$(get_meta TO source_kind)"
  from_ref="$(get_meta FROM source_ref)"
  to_ref="$(get_meta TO source_ref)"

  echo "## Source Repository Changes" >> "${output_file}"
  echo >> "${output_file}"
  echo "### ComposioHQ/helm-charts" >> "${output_file}"
  echo >> "${output_file}"
  echo "- Chart versions: \`$(get_meta FROM chart_version)\` -> \`$(get_meta TO chart_version)\`" >> "${output_file}"

  if [[ "${to_kind}" == "worktree" ]]; then
    if [[ "${from_kind}" == "chart-oci" ]]; then
      echo "- Base release was resolved from OCI and the target is the current working tree, so no helm-charts git commit range could be determined." >> "${output_file}"
      echo >> "${output_file}"
      return 0
    fi

    echo "- Compared against the current working tree state, so no committed helm-charts range is attached for the target side." >> "${output_file}"
    echo "- Base git ref: \`${from_ref:0:7}\`" >> "${output_file}"
    echo >> "${output_file}"
    echo '```diff' >> "${output_file}"
    git diff --stat "${from_ref}" -- \
      composio/Chart.yaml \
      composio/values.yaml \
      manifests/k8s-app.yaml \
      manifests/composio.yaml >> "${output_file}" || true
    echo '```' >> "${output_file}"
    echo >> "${output_file}"
    return 0
  fi

  if [[ "${from_kind}" == "chart-oci" || "${to_kind}" == "chart-oci" ]]; then
    echo "- One or both chart versions were resolved from OCI only, so no helm-charts git commit range could be determined." >> "${output_file}"
    echo >> "${output_file}"
    return 0
  fi

  compare_url="https://github.com/ComposioHQ/helm-charts/compare/${from_ref}...${to_ref}"
  commit_count="$(git rev-list --count "${from_ref}..${to_ref}")"

  echo "- Git refs: \`${from_ref:0:7}\` -> \`${to_ref:0:7}\`" >> "${output_file}"
  echo "- Compare: [ComposioHQ/helm-charts ${from_ref:0:7}...${to_ref:0:7}](${compare_url})" >> "${output_file}"
  echo "- Commits: ${commit_count}" >> "${output_file}"
  echo >> "${output_file}"

  if [[ "${commit_count}" == "0" ]]; then
    echo "_No commits reported for this chart range._" >> "${output_file}"
    echo >> "${output_file}"
    return 0
  fi

  git log --first-parent --reverse --pretty=format:'- %s (`%h`)' "${from_ref}..${to_ref}" >> "${output_file}"
  echo >> "${output_file}"
  echo >> "${output_file}"
}

append_repo_sections() {
  local image_diff_json="$1"
  local repo_groups_json group_json repo compare_url base_revision head_revision compare_json
  local components image_refs total_commits compare_commits files_changed
  local revision_components total_components

  repo_groups_json="$(
    jq '
      [
        .[]
        | select(.changed and (.source_repo // "") != "")
      ]
      | group_by(.source_repo)
      | map({
          source_repo: .[0].source_repo,
          components: (map(.name) | unique),
          image_refs: (map(.image_ref) | unique),
          from_tags: (map(.from_tag) | map(select(length > 0)) | unique),
          to_tags: (map(.to_tag) | map(select(length > 0)) | unique),
          from_revisions: (map(.from_revision) | map(select(length > 0)) | unique),
          to_revisions: (map(.to_revision) | map(select(length > 0)) | unique),
          metadata_origins: (map(.metadata_origin) | unique),
          revision_components: ([.[] | select((.from_revision // "") != "" and (.to_revision // "") != "")] | length),
          total_components: length
        })
    ' <<<"${image_diff_json}"
  )"

  if [[ "$(jq 'length' <<<"${repo_groups_json}")" == "0" ]]; then
    echo "_No mapped source repo changes detected._" >> "${output_file}"
    echo >> "${output_file}"
    return 0
  fi

  while IFS= read -r group_json; do
    repo="$(jq -r '.source_repo' <<<"${group_json}")"
    components="$(jq -r '.components | join(", ")' <<<"${group_json}")"
    image_refs="$(jq -r '.image_refs | join(", ")' <<<"${group_json}")"
    revision_components="$(jq -r '.revision_components' <<<"${group_json}")"
    total_components="$(jq -r '.total_components' <<<"${group_json}")"

    echo "### ${repo}" >> "${output_file}"
    echo >> "${output_file}"
    echo "- Components: \`${components}\`" >> "${output_file}"
    echo "- Images: \`${image_refs}\`" >> "${output_file}"

    if [[ "$(jq '.from_tags | length' <<<"${group_json}")" == "1" && "$(jq '.to_tags | length' <<<"${group_json}")" == "1" ]]; then
      echo "- OCI tags: \`$(jq -r '.from_tags[0]' <<<"${group_json}")\` -> \`$(jq -r '.to_tags[0]' <<<"${group_json}")\`" >> "${output_file}"
    else
      echo "- OCI tags: mixed across components" >> "${output_file}"
    fi

    echo "- Revision metadata resolved for ${revision_components}/${total_components} changed components" >> "${output_file}"

    if [[ "$(jq '.from_revisions | length' <<<"${group_json}")" != "1" || "$(jq '.to_revisions | length' <<<"${group_json}")" != "1" ]]; then
      echo "- Revision labels were missing or inconsistent across components, so repo compare is omitted." >> "${output_file}"
      echo >> "${output_file}"
      continue
    fi

    base_revision="$(jq -r '.from_revisions[0]' <<<"${group_json}")"
    head_revision="$(jq -r '.to_revisions[0]' <<<"${group_json}")"
    compare_url="https://github.com/${repo}/compare/${base_revision}...${head_revision}"

    echo "- Revisions: \`${base_revision:0:12}\` -> \`${head_revision:0:12}\`" >> "${output_file}"
    echo "- Compare: [${repo} ${base_revision:0:12}...${head_revision:0:12}](${compare_url})" >> "${output_file}"

    if [[ "${SKIP_GITHUB_COMPARE:-0}" == "1" ]]; then
      echo "- Compare API skipped via \`SKIP_GITHUB_COMPARE=1\`." >> "${output_file}"
      echo >> "${output_file}"
      continue
    fi

    if ! compare_json="$(github_compare_request "${repo}" "${base_revision}" "${head_revision}")"; then
      echo "- Unable to load compare data. Check repo access and revision availability." >> "${output_file}"
      echo >> "${output_file}"
      continue
    fi

    total_commits="$(jq -r '.total_commits // (.commits | length)' <<<"${compare_json}")"
    compare_commits="$(jq -r '.commits | length' <<<"${compare_json}")"
    files_changed="$(jq -r '.files | length' <<<"${compare_json}")"

    echo "- Commits: ${total_commits}" >> "${output_file}"
    echo "- Files changed: ${files_changed}" >> "${output_file}"
    if [[ "${total_commits}" != "${compare_commits}" ]]; then
      echo "- GitHub compare returned ${compare_commits} commit objects out of ${total_commits} total commits." >> "${output_file}"
    fi
    echo >> "${output_file}"

    if [[ "${compare_commits}" == "0" ]]; then
      echo "_No commits reported for this revision range._" >> "${output_file}"
      echo >> "${output_file}"
      continue
    fi

    jq -r '
      .commits[]
      | "- "
        + (.commit.message | split("\n")[0])
        + " (`"
        + (.sha[0:7])
        + "`)"
    ' <<<"${compare_json}" >> "${output_file}"
    echo >> "${output_file}"
  done < <(jq -c '.[]' <<<"${repo_groups_json}")
}

append_unmapped_components_section() {
  local image_diff_json="$1"
  local unmapped_json

  unmapped_json="$(jq '[.[] | select(.changed and (.source_repo // "") == "")]' <<<"${image_diff_json}")"

  if [[ "$(jq 'length' <<<"${unmapped_json}")" == "0" ]]; then
    return 0
  fi

  echo "## Unmapped Components" >> "${output_file}"
  echo >> "${output_file}"
  echo "These OCI tags changed, but no source repo could be derived for them." >> "${output_file}"
  echo >> "${output_file}"
  echo "| Component | Image | From tag | To tag | From revision | To revision | Metadata status |" >> "${output_file}"
  echo "| --- | --- | --- | --- | --- | --- | --- |" >> "${output_file}"
  jq -r '
    .[]
    | "| "
      + .name
      + " | "
      + .image_ref
      + " | "
      + (if .from_tag == "" then "-" else .from_tag end)
      + " | "
      + (if .to_tag == "" then "-" else .to_tag end)
      + " | "
      + (if .from_revision == "" then "-" else .from_revision[0:12] end)
      + " | "
      + (if .to_revision == "" then "-" else .to_revision[0:12] end)
      + " | "
      + (.metadata_status // "-")
      + " |"
  ' <<<"${unmapped_json}" >> "${output_file}"
  echo >> "${output_file}"
}

from_identifier="${1:-}"
to_identifier="${2:-}"
output_file="${3:-release-changelog.md}"

if [[ -z "${from_identifier}" || -z "${to_identifier}" ]]; then
  usage
  exit 1
fi

CHART_OCI_REF="${CHART_OCI_REF:-oci://registry.composio.io/composio-rodent/nightly/composio}"

require_cmd git
require_cmd curl
require_cmd jq
require_cmd yq

TMPDIR_PATH="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_PATH}"' EXIT

resolve_identifier "${from_identifier}" "FROM"
resolve_identifier "${to_identifier}" "TO"

from_images_json="$(extract_images_json "${TMPDIR_PATH}/FROM-values.yaml")"
to_images_json="$(extract_images_json "${TMPDIR_PATH}/TO-values.yaml")"
from_images_json="$(enrich_images_json "${from_images_json}")"
to_images_json="$(enrich_images_json "${to_images_json}")"

image_diff_json="$(
  jq -cn \
    --argjson from "${from_images_json}" \
    --argjson to "${to_images_json}" '
      [
        ($to | keys_unsorted[]) as $name
        | {
            name: $name,
            registry: ($to[$name].registry // $from[$name].registry // ""),
            repository: ($to[$name].repository // $from[$name].repository // ""),
            image_ref: (
              if ($to[$name].registry // $from[$name].registry // "") == "" then
                ($to[$name].repository // $from[$name].repository // "")
              else
                ($to[$name].registry // $from[$name].registry // "")
                + "/"
                + ($to[$name].repository // $from[$name].repository // "")
              end
            ),
            source_repo: ($to[$name].source_repo // $from[$name].source_repo // ""),
            from_tag: ($from[$name].tag // ""),
            to_tag: ($to[$name].tag // ""),
            from_revision: ($from[$name].revision // ""),
            to_revision: ($to[$name].revision // ""),
            metadata_origin: (
              if ($to[$name].metadata_origin // "") != "" and ($to[$name].metadata_origin // "") != "fallback-map" then
                ($to[$name].metadata_origin // "")
              else
                ($from[$name].metadata_origin // $to[$name].metadata_origin // "")
              end
            ),
            metadata_status: (
              [
                ($from[$name].metadata_status // ""),
                ($to[$name].metadata_status // "")
              ]
              | map(select(length > 0))
              | unique
              | join(",")
            ),
            changed: (($from[$name].tag // "") != ($to[$name].tag // ""))
          }
      ]
    '
)"

from_unique_tag_count="$(jq -r '[.[].from_tag | select(length > 0)] | unique | length' <<<"${image_diff_json}")"
to_unique_tag_count="$(jq -r '[.[].to_tag | select(length > 0)] | unique | length' <<<"${image_diff_json}")"
from_release_oci_tag="$(jq -r '[.[].from_tag | select(length > 0)] | unique | if length == 1 then .[0] else "" end' <<<"${image_diff_json}")"
to_release_oci_tag="$(jq -r '[.[].to_tag | select(length > 0)] | unique | if length == 1 then .[0] else "" end' <<<"${image_diff_json}")"
changed_components_count="$(jq -r '[.[] | select(.changed)] | length' <<<"${image_diff_json}")"
revision_resolved_count="$(jq -r '[.[] | select(.changed and (.from_revision // "") != "" and (.to_revision // "") != "")] | length' <<<"${image_diff_json}")"

{
  echo "# Release changelog"
  echo
  echo "## Inputs"
  echo
  echo "- From input: \`${from_identifier}\`"
  echo "- To input: \`${to_identifier}\`"
  echo "- Chart OCI ref fallback: \`${CHART_OCI_REF}\`"
  echo
  echo "## Resolved Chart Versions"
  echo
  echo "- From: chart \`$(get_meta FROM chart_version)\`, app \`$(get_meta FROM app_version)\`, source \`$(get_meta FROM source_kind)\` -> \`$(get_meta FROM source_ref)\`"
  if [[ -n "$(get_meta FROM source_date)" ]]; then
    echo "- From source date: $(get_meta FROM source_date)"
  fi
  echo "- To: chart \`$(get_meta TO chart_version)\`, app \`$(get_meta TO app_version)\`, source \`$(get_meta TO source_kind)\` -> \`$(get_meta TO source_ref)\`"
  if [[ -n "$(get_meta TO source_date)" ]]; then
    echo "- To source date: $(get_meta TO source_date)"
  fi
  echo
  echo "## OCI Image Tags"
  echo
  if [[ "${from_unique_tag_count}" == "1" && "${to_unique_tag_count}" == "1" ]]; then
    echo "- Release OCI tag: \`${from_release_oci_tag}\` -> \`${to_release_oci_tag}\`"
  else
    echo "- Releases use mixed OCI tags. See the per-component table below."
  fi
  echo "- Components changed: ${changed_components_count}"
  echo "- Revision labels resolved for ${revision_resolved_count}/${changed_components_count} changed components"
  echo
  echo "| Component | Image | Source repo | From tag | To tag | From revision | To revision | Metadata |"
  echo "| --- | --- | --- | --- | --- | --- | --- | --- |"
  jq -r '
    .[]
    | [
        .name,
        .image_ref,
        (if .source_repo == "" then "-" else .source_repo end),
        (if .from_tag == "" then "-" else .from_tag end),
        (if .to_tag == "" then "-" else .to_tag end),
        (if .from_revision == "" then "-" else .from_revision[0:12] end),
        (if .to_revision == "" then "-" else .to_revision[0:12] end),
        (if .metadata_origin == "" then "-" else .metadata_origin end)
      ]
    | "| " + join(" | ") + " |"
  ' <<<"${image_diff_json}"
  echo
} > "${output_file}"

append_helm_charts_section
append_repo_sections "${image_diff_json}"
append_unmapped_components_section "${image_diff_json}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "output_file=${output_file}"
    echo "changed_components=${changed_components_count}"
    echo "revision_resolved_components=${revision_resolved_count}"
    echo "from_chart_version=$(get_meta FROM chart_version)"
    echo "to_chart_version=$(get_meta TO chart_version)"
    echo "from_source_kind=$(get_meta FROM source_kind)"
    echo "to_source_kind=$(get_meta TO source_kind)"
    if [[ -n "${from_release_oci_tag}" ]]; then
      echo "from_oci_tag=${from_release_oci_tag}"
    fi
    if [[ -n "${to_release_oci_tag}" ]]; then
      echo "to_oci_tag=${to_release_oci_tag}"
    fi
  } >> "${GITHUB_OUTPUT}"
fi

echo "Wrote changelog to ${output_file}"
