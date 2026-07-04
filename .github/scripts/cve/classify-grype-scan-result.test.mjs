import assert from "node:assert/strict";
import test from "node:test";

import { classifyGrypeWorkflowResult } from "./classify-grype-scan-result.mjs";

test("classifies report build failures without claiming vulnerabilities were found", () => {
  const result = classifyGrypeWorkflowResult({
    renderOutcome: "success",
    scanOutcome: "success",
    reportOutcome: "failure",
    publishOutcome: "skipped",
    scanResult: "",
  });

  assert.equal(result.failureReason, "report-build-failed");
  assert.match(result.failureSummary, /Build Grype report failed/);
  assert.match(result.failureSummary, /may or may not have found HIGH\/CRITICAL vulnerabilities/);
  assert.doesNotMatch(result.failureSummary, /^Grype found HIGH or CRITICAL vulnerabilities/);
});

test("classifies completed failed reports as blocking HIGH or CRITICAL findings", () => {
  const result = classifyGrypeWorkflowResult({
    renderOutcome: "success",
    scanOutcome: "success",
    reportOutcome: "success",
    publishOutcome: "success",
    scanResult: "failed",
  });

  assert.equal(result.failureReason, "high-critical-findings");
  assert.equal(result.failureSummary, "Grype found HIGH or CRITICAL vulnerabilities");
});
