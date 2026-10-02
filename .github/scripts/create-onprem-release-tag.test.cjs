const assert = require("node:assert/strict");
const test = require("node:test");

const owner = "ComposioHQ";
const repo = "onprem-testbed";
const tag = "0.2.114";
const targetSha = "1111111111111111111111111111111111111111";

function loadSubject() {
  try {
    return require("./create-onprem-release-tag.cjs");
  } catch (error) {
    assert.fail(`Unable to load create-onprem-release-tag.cjs: ${error.message}`);
  }
}

function githubFixture({
  existingTagSha,
  concurrentTagSha,
  concurrentStatus = 422,
} = {}) {
  const refs = new Map([
    ["heads/main", { object: { sha: targetSha } }],
  ]);
  if (existingTagSha) {
    refs.set(`tags/${tag}`, { object: { sha: existingTagSha } });
  }

  let pendingConcurrentTagSha = concurrentTagSha;

  const github = {
    rest: {
      repos: {
        async get(request) {
          assert.deepEqual(request, { owner, repo });
          return { data: { default_branch: "main" } };
        },
      },
      git: {
        async getRef(request) {
          assert.equal(request.owner, owner);
          assert.equal(request.repo, repo);
          const ref = refs.get(request.ref);
          if (!ref) {
            const error = new Error(`Reference ${request.ref} not found`);
            error.status = 404;
            throw error;
          }
          return { data: ref };
        },
        async createRef(request) {
          assert.equal(request.owner, owner);
          assert.equal(request.repo, repo);
          assert.equal(request.ref, `refs/tags/${tag}`);
          assert.equal(request.sha, targetSha);

          if (pendingConcurrentTagSha) {
            refs.set(`tags/${tag}`, {
              object: { sha: pendingConcurrentTagSha },
            });
            pendingConcurrentTagSha = undefined;
            const error = new Error("Reference already exists");
            error.status = concurrentStatus;
            throw error;
          }

          refs.set(`tags/${tag}`, { object: { sha: request.sha } });
          return { data: refs.get(`tags/${tag}`) };
        },
      },
    },
  };

  return { github, refs };
}

const core = { info() {} };

test("creates the chart-version tag at the default-branch HEAD", async () => {
  const { createImmutableReleaseTag } = loadSubject();
  const { github, refs } = githubFixture();

  const result = await createImmutableReleaseTag({
    github,
    core,
    owner,
    repo,
    tag,
  });

  assert.deepEqual(result, {
    branch: "main",
    created: true,
    sha: targetSha,
    tag,
  });
  assert.equal(refs.get(`tags/${tag}`).object.sha, targetSha);
});

test("accepts an existing tag when it already points to the release SHA", async () => {
  const { createImmutableReleaseTag } = loadSubject();
  const { github, refs } = githubFixture({ existingTagSha: targetSha });

  const result = await createImmutableReleaseTag({
    github,
    core,
    owner,
    repo,
    tag,
  });

  assert.deepEqual(result, {
    branch: "main",
    created: false,
    sha: targetSha,
    tag,
  });
  assert.equal(refs.get(`tags/${tag}`).object.sha, targetSha);
});

test("refuses to move an existing tag that points to another SHA", async () => {
  const { createImmutableReleaseTag } = loadSubject();
  const conflictingSha = "2222222222222222222222222222222222222222";
  const { github, refs } = githubFixture({ existingTagSha: conflictingSha });

  await assert.rejects(
    createImmutableReleaseTag({ github, core, owner, repo, tag }),
    /Refusing to move existing onprem-testbed tag 0\.2\.114/,
  );
  assert.equal(refs.get(`tags/${tag}`).object.sha, conflictingSha);
});

for (const concurrentStatus of [409, 422]) {
  test(`accepts a concurrently created tag after HTTP ${concurrentStatus}`, async () => {
    const { createImmutableReleaseTag } = loadSubject();
    const { github, refs } = githubFixture({
      concurrentStatus,
      concurrentTagSha: targetSha,
    });

    const result = await createImmutableReleaseTag({
      github,
      core,
      owner,
      repo,
      tag,
    });

    assert.deepEqual(result, {
      branch: "main",
      created: false,
      sha: targetSha,
      tag,
    });
    assert.equal(refs.get(`tags/${tag}`).object.sha, targetSha);
  });
}

test("rejects a concurrently created tag when it points to another SHA", async () => {
  const { createImmutableReleaseTag } = loadSubject();
  const conflictingSha = "3333333333333333333333333333333333333333";
  const { github, refs } = githubFixture({ concurrentTagSha: conflictingSha });

  await assert.rejects(
    createImmutableReleaseTag({ github, core, owner, repo, tag }),
    /Refusing to move existing onprem-testbed tag 0\.2\.114/,
  );
  assert.equal(refs.get(`tags/${tag}`).object.sha, conflictingSha);
});
