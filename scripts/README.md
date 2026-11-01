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
