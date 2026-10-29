# Replicated image release packaging

The packager produces one Replicated release binding the application Helm chart to
an already published, digest-pinned managed-VPC runner image. Infrastructure and
locked runtime dependencies execute from that image. No separate infrastructure
chart or external archive URL is used. Packaging never pushes, promotes or deploys.

Prerequisites: Node 22+, Python 3, Helm 3, Git and dependencies installed from the
sibling infrastructure repository's lockfiles. The runner image publication must
include `runnerContractVersion: 2`, source revision and infrastructure content hash.

```bash
node scripts/package-replicated-release.mjs \
  --version 0.2.14-managed-vpc-test.2 \
  --runner-publication /path/to/publication.json \
  --chart-reference oci://registry.replicated.com/composio-rodent/managed-vpc-test/composio \
  --values /path/to/public-release-values.yaml \
  --qualification /path/to/qualification.json \
  --output /path/to/new-release-directory
```

Public release values should merge `composio/values-managed-vpc.yaml` with immutable
application, migration and SDK image references. Resolve the selected service tag
(for example `r20260907_02`) to its Linux amd64 digest and set each image's
`imageName`; tags alone cannot produce a qualified deployment lock. The SDK image
uses `replicated.image.digest`. Customer identifiers and credentials are supplied
at execution time, not baked into the chart.

Output contains `replicated/composio-<version>.tgz`, KOTS manifests and excluded
release metadata; local companion `bootstrap/`; `release.lock.json` and its SHA-256;
source/build metadata and `SHA256SUMS`. Without `--qualification`, metadata is a
candidate with no deployment lock. Existing output directories are refused.

The lock and authenticated chart descriptor bind the same image digest, source
revision, embedded infrastructure hash, image inventory, capabilities and features.
Chart hashing excludes only Replicated personalization. The packager preserves the
source checkout and locked chart dependencies, checks reproducibility and the
Replicated release-size limit, and rejects changed image digests or older runners.
Qualification describes the integrations and features actually tested; offline
packaging does not prove a live deployment.

```bash
node --test scripts/package-replicated-release.test.mjs \
  scripts/package-replicated-release.integration.test.mjs
```

Publish the generated `replicated/` directory only through the authorized release
path. The bootstrap approves the runner image, customer configuration, S3 backend
and KMS key. Customer preview and approval precede infrastructure and Helm apply.
Never commit customer licenses, personalized chart archives, stack state or secret
values. Runtime configuration uses exact Secrets Manager ARN/version references.

## Janus nightly executor

`janus-managed-vpc-release.yml` is a dispatch-only executor for Janus. It has three
operations: `publish` creates a candidate in Nightly; `test` scans its pinned
images and runs the existing fresh/upgrade test harness; `promote` moves its exact
Replicated sequence to Stable. Janus owns scheduling, STS deployment, human QA
approval and customer child Runs. This workflow does not create a cron schedule.

Commit a reviewed recipe at `releases/nightly.json` on `release-stable` before use.
For example (replace every example identity and commit with approved values):

```json
{
  "schemaVersion": 1,
  "appId": "APP_ID",
  "nightlyChannelId": "NIGHTLY_CHANNEL_ID",
  "stableChannelId": "STABLE_CHANNEL_ID",
  "infrastructureSha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "onpremSha": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "values": "releases/managed-vpc-values.yaml",
  "qualification": "releases/qualification.json",
  "runnerPublication": "releases/runner-publication.json",
  "chartReference": "oci://registry.replicated.com/composio-rodent/composio",
  "nightlyChartReference": "oci://registry.replicated.com/composio-rodent/nightly/composio",
  "cvePolicy": "report",
  "imageTags": {
    "apollo": "latest", "apollo-db-init": "latest",
    "thermos": "latest", "thermos-db-init": "latest",
    "mercury": "latest", "frontend": "latest",
    "weaviate": "latest", "thermos-toolkit-registry": "latest"
  }
}
```

The selected ECR tags must represent production-qualified images. Tags are resolved
once to digests before packaging; promotion retains them. Public values must pin
non-service images too, including the Replicated SDK, and describe the managed-VPC
feature set. The qualification file records tested integration capabilities, not
invented test results. The runner publication must come from its verified image
build; the infrastructure commit must be merged on `main`. `onpremSha` must match
the reviewed test harness `main` commit before dispatch and in each returned Run.
The `report` CVE policy retains advisory findings like the legacy nightly job;
`block-high-critical` prevents qualification if any high or critical match exists.

The default lock URL serves Stable. `--alternate-chart-reference` records the
Nightly path for the same app and chart before the lock is hashed. STS's pinned
registry credentials select that approved path; the runner verifies the same
chart hash regardless of channel. No secret or customer license goes into the
recipe, tracking PR or release artifacts.

The executor reuses the existing `opra-ci/prd` Doppler identity, Nightly GitHub App,
Replicated publishing credential and Helm ECR read role. Repository tokens are
scoped and refreshed for long tests. Existing App installation access to
`infrastructure` is needed to read the pinned runner source. No IAM grant is part
of this implementation. Restrict workflow dispatch and editing to trusted release
operators: Janus enforces its human gate, while repository administrators retain
their existing publishing authority.

Publication creates a tracking PR and GitHub prerelease. Recovery evidence and
test reports are uploaded even on failure; confirmed receipts are published only
on success. A lost response may have created or promoted a release. Inspect the
exact Run, evidence artifact and Replicated state before recovery. Manual reruns
and duplicate request IDs are rejected instead of publishing again.

The executor serializes its publication and promotion jobs. This does not lock
out other Replicated writers. Drain and disable the legacy `nighty-release.yml`
schedule in a separate reviewed cutover before enabling Janus's schedule; do not
run both against the same channels. The Glean-specific legacy release path is
unchanged. Sandbox publication, STS rollout, rejected/approved promotion and
customer acceptance are required before production activation.
