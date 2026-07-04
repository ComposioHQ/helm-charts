import { appendFileSync } from "node:fs";

function normalize(value) {
  return String(value || "").trim();
}

function nonSuccess(outcome) {
  return normalize(outcome) !== "success";
}

export function classifyGrypeWorkflowResult({
  renderOutcome = "",
  scanOutcome = "",
  reportOutcome = "",
  publishOutcome = "",
  scanResult = "",
} = {}) {
  if (nonSuccess(renderOutcome)) {
    return {
      failureReason: "render-failed",
      failureSummary: "Rendering Helm scan targets failed; Grype did not run.",
    };
  }

  if (nonSuccess(scanOutcome)) {
    return {
      failureReason: "scan-execution-failed",
      failureSummary:
        "Running Grype scans failed; Grype scan findings may be incomplete or unavailable.",
    };
  }

  if (nonSuccess(reportOutcome)) {
    return {
      failureReason: "report-build-failed",
      failureSummary:
        "Build Grype report failed; Grype may or may not have found HIGH/CRITICAL vulnerabilities.",
    };
  }

  if (nonSuccess(publishOutcome)) {
    return {
      failureReason: "report-publish-failed",
      failureSummary:
        "Publishing Grype report outputs failed; Grype scan findings may be incomplete or unavailable.",
    };
  }

  if (normalize(scanResult) === "success") {
    return {
      failureReason: "success",
      failureSummary: "",
    };
  }

  if (normalize(scanResult) === "failed") {
    return {
      failureReason: "high-critical-findings",
      failureSummary: "Grype found HIGH or CRITICAL vulnerabilities",
    };
  }

  return {
    failureReason: "missing-scan-result",
    failureSummary:
      "Grype report completed but did not publish a scan result; scan findings may be incomplete or unavailable.",
  };
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (!key.startsWith("--")) {
      throw new Error(`Unexpected argument: ${key}`);
    }
    const value = argv[index + 1];
    if (index + 1 >= argv.length || value.startsWith("--")) {
      throw new Error(`Missing value for ${key}`);
    }
    args[key.slice(2).replaceAll("-", "_")] = value;
    index += 1;
  }
  return args;
}

function githubOutput(result) {
  return [
    `failure_reason=${result.failureReason}`,
    "failure_summary<<__CVE_FAILURE_SUMMARY__",
    result.failureSummary,
    "__CVE_FAILURE_SUMMARY__",
    "",
  ].join("\n");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = parseArgs(process.argv.slice(2));
  const result = classifyGrypeWorkflowResult({
    renderOutcome: args.render_outcome,
    scanOutcome: args.scan_outcome,
    reportOutcome: args.report_outcome,
    publishOutcome: args.publish_outcome,
    scanResult: args.scan_result,
  });
  const output = githubOutput(result);

  if (process.env.GITHUB_OUTPUT) {
    appendFileSync(process.env.GITHUB_OUTPUT, output);
  } else {
    process.stdout.write(output);
  }
}
