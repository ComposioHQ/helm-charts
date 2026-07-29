# Release Type and Replicated Channel Design

## Goal

Allow manual runs of `.github/workflows/nighty-release.yml` to select either a
standard release or a Glean release. The selected release type determines the
Replicated channel used as the source of the latest release, the destination
for the new release, and the image-tag calculation.

Scheduled runs remain standard releases.

## Release Configuration

Add a `workflow_dispatch` choice input named `release_type` with these options:

| Release type | Replicated channel | Channel ID | OCI channel path | Default |
| --- | --- | --- | --- | --- |
| `standard` | `Nightly` | `397k1WtPrJ1J56bhb70SfeKGcxL` | `nightly` | Yes |
| `glean` | `Glean-Stable` | `3GwShNBOwcf13Bs7i5pfn3N8TDh` | `glean-stable` | No |

A small configuration job will map the selected release type to its channel
name, channel ID, OCI chart reference, and tag-calculation mode. Scheduled runs,
where no dispatch input exists, will resolve to `standard`.

The OCI references are
`oci://registry.composio.io/composio-rodent/nightly/composio` and
`oci://registry.composio.io/composio-rodent/glean-stable/composio`.

Downstream jobs will consume these outputs instead of repeating release-type
conditionals.

## Tag Calculation

### Standard releases

Standard releases retain the current calendar-tag behavior:

```text
rYYYYMMDD_NN
```

The workflow reads the latest Nightly release and increments `NN` when its
calendar date matches the current date in Asia/Kolkata. Otherwise, it starts at
`01`.

### Glean releases

Glean releases read image tags from the latest Glean-Stable release. The tag is
split into:

```text
<fixed-base>-p<calendar-suffix>
```

For example:

```text
r20260729_01-p20260801_02
```

The fixed base is the portion before `-p`, such as `r20260729_01`. It comes from
the latest Glean-Stable release and does not change during subsequent Glean
release runs.

Only the suffix changes:

```text
pYYYYMMDD_NN
```

When the latest Glean-Stable suffix uses today's Asia/Kolkata date, increment
its sequence. When it uses a different date, start today's sequence at `01`.
When the latest Glean-Stable release contains only a base tag and no `-p`
suffix, preserve that base and create today's suffix at `01`.

The calculation must fail if no valid `rYYYYMMDD_NN` base can be found in the
latest Glean-Stable release. It must not silently construct a Glean tag without
the channel-derived fixed base.

## Selected-Channel Release Flow

The selected channel controls the entire release flow:

1. Resolve the channel by its configured name and verify its ID matches the
   configured channel ID.
2. Pull the latest chart from that channel for image-tag calculation.
3. Read and increment that channel's current Replicated version.
4. Retag the selected source images with the calculated image tag.
5. Update and package the Helm chart.
6. Promote the Replicated release directly to the selected channel.

Standard releases therefore continue to flow through Nightly. Glean releases
flow directly through Glean-Stable.

Branch names, pull-request text, release text, scan identifiers, and Slack
reporting should use the resolved release type or channel where the current
hardcoded Nightly wording would be misleading.

## Error Handling

The workflow will fail before retagging when:

- The release type is unsupported.
- The selected Replicated channel cannot be found.
- The returned channel ID does not match the configured ID.
- The selected channel has no current version.
- The latest channel chart cannot be pulled.
- A Glean release has no valid fixed base tag.

Existing safeguards for conflicting ECR tags, chart rendering, packaging, and
Replicated release creation remain unchanged.

## Verification

Extend `.github/scripts/tests/calculate-nightly-release-tag-test.sh` before
changing the production calculation. Tests will cover:

- Existing standard same-day increment and new-day reset behavior.
- Creating the first Glean suffix from a plain base tag.
- Incrementing a Glean suffix on the same day.
- Resetting the Glean suffix sequence on a new day.
- Keeping the Glean base fixed while the suffix changes.
- Rejecting a Glean calculation with no valid channel-derived base.

Run the focused shell tests, parse the workflow as YAML, run `actionlint` when
available, and execute the repository's relevant Helm lint/render checks.
