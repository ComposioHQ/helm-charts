#!/usr/bin/env python3
"""Verify ConfigMap rollout behavior with real Helm renders (no cluster needed)."""

import re
import subprocess
import unittest
from pathlib import Path


CHART = Path(__file__).resolve().parents[1]
APOLLO = "apollo/apollo.yaml"
THERMOS = "thermos/thermos.yaml"
MISC_WORKERS = "thermos/thermos-misc-workers.yaml"
FRONTEND = "frontend/frontend.yaml"
MERCURY = "mercury/mercury.yaml"
KNATIVE_MERCURY = "mercury/mercury-service.yaml"
WORKLOADS = {APOLLO, THERMOS, MISC_WORKERS, FRONTEND, MERCURY, KNATIVE_MERCURY}


def render_checksums(*overrides: str) -> dict[str, str]:
    command = ["helm", "template", "rollout-test", str(CHART)]
    for override in (
        "frontend.enabled=true",
        "thermosMiscWorkers.enabled=true",
        "replicated.enabled=false",
        *overrides,
    ):
        command.extend(["--set", override])
    rendered = subprocess.run(command, check=True, capture_output=True, text=True).stdout
    checksums = {}
    for document in re.split(r"(?m)^---\s*$", rendered):
        source = re.search(r"(?m)^# Source: composio/templates/(\S+)$", document)
        if source and source[1] in WORKLOADS:
            checksum = re.search(r'(?m)^\s+checksum/config: "([a-f0-9]{64})"$', document)
            if checksum:
                checksums[source[1]] = checksum[1]
    return checksums


class ConfigMapRolloutTests(unittest.TestCase):
    def test_config_changes_roll_only_consumers_in_both_mercury_modes(self):
        for knative in (False, True):
            with self.subTest(knative=knative):
                mode = f"mercury.useKnative={str(knative).lower()}"
                mercury = KNATIVE_MERCURY if knative else MERCURY
                baseline = render_checksums(mode)
                self.assertEqual(set(baseline), {APOLLO, THERMOS, MISC_WORKERS, FRONTEND, mercury})
                self.assertEqual(baseline[THERMOS], baseline[MISC_WORKERS])
                self.assertEqual(baseline, render_checksums(mode), "Identical renders must be stable")
                self.assertEqual(
                    baseline,
                    render_checksums(mode, "apollo.replicaCount=9", "frontend.replicaCount=9"),
                    "Values outside ConfigMaps must not change config checksums",
                )
                for override, consumers in (
                    ("apollo.singleTenant.maxOrgCount=2", {APOLLO}),
                    ("aws.s3.lambdaBucketName=rollout-test-bucket", {THERMOS, MISC_WORKERS}),
                    ("frontend.env.NODE_ENV=development", {FRONTEND}),
                    ("mercury.fileStorage=base64", {mercury}),
                    ("aws.region=eu-west-1", {APOLLO, THERMOS, MISC_WORKERS, mercury}),
                    ("mercury.aws.region=eu-west-1", {mercury}),
                ):
                    with self.subTest(override=override):
                        updated = render_checksums(mode, override)
                        self.assertEqual(set(updated), set(baseline))
                        changed = {name for name in baseline if updated[name] != baseline[name]}
                        self.assertEqual(changed, consumers)

    def test_disabled_optional_workloads_remain_absent(self):
        for knative in (False, True):
            with self.subTest(knative=knative):
                self.assertEqual(
                    set(render_checksums(
                        f"mercury.useKnative={str(knative).lower()}",
                        "mercury.enabled=false",
                        "frontend.enabled=false",
                        "thermosMiscWorkers.enabled=false",
                    )),
                    {APOLLO, THERMOS},
                )


if __name__ == "__main__":
    unittest.main()
