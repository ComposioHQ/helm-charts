# Empty Glean-Stable Channel Bootstrap Design

## Goal

Allow a `glean` run of `.github/workflows/nighty-release.yml` to create the
first Glean-Stable release when that Replicated channel is empty.

The first release must use a Nightly image tag as its fixed base while starting
an independent Glean version sequence at `0.2.87.1`.

## Root Cause

The merged release-tag helper resolves the selected Replicated channel and
requires its API response to contain `currentVersion` before it can pull a
chart or calculate a tag.

An empty Replicated channel is valid but has no `currentVersion`. Glean-Stable
currently has `releaseSequence: 0`, so the helper exits with:

```text
Glean-Stable channel response did not include currentVersion
```

The checked-in chart is not a safe fallback. It currently reports version
`0.2.13` and image tag `r20260501_01`, while the live Nightly channel is at
version `0.2.140`.

## Release Configuration

The release configuration helper will expose optional seed-channel metadata.

For `standard`, seed-channel outputs remain empty.

For `glean`, the seed channel is:

| Field | Value |
| --- | --- |
| Name | `Nightly` |
| Channel ID | `397k1WtPrJ1J56bhb70SfeKGcxL` |
| OCI reference | `oci://registry.composio.io/composio-rodent/nightly/composio` |

Glean also uses the fixed version prefix `0.2.87`.

## Tag Calculation

### Non-empty selected channel

Existing behavior remains unchanged:

- Standard reads the latest Nightly chart and calculates `rYYYYMMDD_NN`.
- Glean reads the latest Glean-Stable chart, keeps its fixed base, and
  increments only `pYYYYMMDD_NN`.

### Empty Glean-Stable channel

When the selected channel is Glean-Stable and has no `currentVersion`:

1. Preserve the selected Glean-Stable channel ID and empty current version.
2. Resolve the configured Nightly seed channel and verify its channel ID.
3. Require Nightly to have a current version.
4. Pull the latest Nightly chart through its OCI reference.
5. Use the Nightly image tag as the fixed Glean base.
6. Calculate the first Glean suffix as `p<current IST date>_01`.

For example, a Nightly image tag of `r20260729_04` produces:

```text
r20260729_04-p20260730_01
```

Nightly supplies only the seed image-tag base. Its version does not become the
Glean version.

## Version Calculation

Version calculation will move from inline workflow shell into a focused,
testable helper.

The release-tag step will continue to output the selected channel's current
version. The workflow will run the version helper immediately afterward,
before configuring AWS or retagging images, and publish both current and new
versions as job outputs. The later Replicated release job will consume those
validated outputs instead of recalculating them.

### Standard

Standard retains the current behavior: require a numeric selected-channel
version and increment its final segment.

```text
0.2.140 -> 0.2.141
```

### Glean

Glean versions must always belong to the `0.2.87.x` family.

- Empty selected-channel version: create `0.2.87.1`.
- Existing `0.2.87.x`: increment only `x`.
- Any other non-empty version: fail before retagging or release creation.

```text
empty -> 0.2.87.1
0.2.87.1 -> 0.2.87.2
```

The workflow will use the selected channel's current version for version
calculation, even when Nightly supplied the initial image-tag base.

## Error Handling

The workflow will still fail when:

- The selected or seed channel ID differs from the configured ID.
- An empty Glean-Stable channel cannot resolve a non-empty Nightly seed.
- A non-empty Glean version is outside `0.2.87.x`.
- The seed chart has no valid fixed calendar image tag.
- A non-empty Glean chart contains no base or multiple fixed bases.

An empty standard/Nightly channel remains an error; only Glean has bootstrap
behavior.

## Verification

Tests will cover:

- Release configuration outputs for the Nightly seed channel and Glean version
  prefix.
- An empty Glean-Stable API response falling back to the latest Nightly chart.
- The bootstrap tag using the Nightly base with suffix sequence `01`.
- Standard version increment behavior.
- Empty Glean version producing `0.2.87.1`.
- Existing Glean version incrementing only the final segment.
- Rejection of Glean versions outside `0.2.87.x`.
- Workflow propagation of seed metadata and use of the version helper.

Existing tag, Slack, workflow, Bash syntax, YAML, Helm lint, and Helm render
checks must remain green.
