import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);
const repoRoot = path.resolve(import.meta.dirname, "../../..");

async function readJson(file) {
  return JSON.parse(await readFile(file, "utf8"));
}

test("render-scan-targets excludes images introduced by the Temporal dependency chart", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "render-scan-targets-test-"));
  try {
    await execFileAsync("bash", [
      path.join(repoRoot, ".github/scripts/cve/render-scan-targets.sh"),
    ], {
      cwd: repoRoot,
      env: {
        ...process.env,
        CHART_DIR: path.join(repoRoot, "composio"),
        OUTPUT_DIR: dir,
        ECR_REGISTRY: "008971668139.dkr.ecr.us-east-1.amazonaws.com",
        RELEASE_TAG: "rtest",
        RENDER_TEMPORAL: "1",
      },
    });

    const scanTargets = await readJson(path.join(dir, "scan-targets.json"));
    const ignoredTargets = await readJson(path.join(dir, "ignored-scan-targets.json"));

    assert.ok(
      scanTargets.some((target) => target.image.includes("composio-self-host/apollo:rtest")),
      "non-Temporal Composio images should remain scan targets",
    );
    assert.equal(
      scanTargets.some((target) => target.image.includes("temporalio/")),
      false,
      "Temporal dependency images should not be scanned or counted in the CVE gate",
    );
    assert.ok(
      ignoredTargets.some((target) => target.image.includes("temporalio/admin-tools")),
      "Temporal dependency images should be recorded as ignored report metadata",
    );
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
