function errorStatus(error) {
  return error.status ?? error.response?.status;
}

async function getOptionalRef({ github, owner, repo, ref }) {
  try {
    const response = await github.rest.git.getRef({ owner, repo, ref });
    return response.data;
  } catch (error) {
    if (errorStatus(error) === 404) {
      return undefined;
    }
    throw error;
  }
}

function verifyImmutableTag({ existingRef, repo, tag, targetSha }) {
  if (existingRef.object.sha !== targetSha) {
    throw new Error(
      `Refusing to move existing ${repo} tag ${tag} from ${existingRef.object.sha} to ${targetSha}`,
    );
  }
}

async function createImmutableReleaseTag({ github, core, owner, repo, tag }) {
  if (!tag) {
    throw new Error("Release tag is required");
  }

  const { data: targetRepository } = await github.rest.repos.get({
    owner,
    repo,
  });
  const defaultBranch = targetRepository.default_branch;
  if (!defaultBranch) {
    throw new Error(`${owner}/${repo} does not have a default branch`);
  }

  const { data: branchRef } = await github.rest.git.getRef({
    owner,
    repo,
    ref: `heads/${defaultBranch}`,
  });
  const targetSha = branchRef.object.sha;
  const tagRef = `tags/${tag}`;
  const existingRef = await getOptionalRef({
    github,
    owner,
    repo,
    ref: tagRef,
  });

  if (existingRef) {
    verifyImmutableTag({ existingRef, repo, tag, targetSha });
    core.info(`${repo} tag ${tag} already points to ${targetSha}.`);
    return { branch: defaultBranch, created: false, sha: targetSha, tag };
  }

  try {
    await github.rest.git.createRef({
      owner,
      repo,
      ref: `refs/${tagRef}`,
      sha: targetSha,
    });
  } catch (error) {
    if (![409, 422].includes(errorStatus(error))) {
      throw error;
    }

    const concurrentRef = await getOptionalRef({
      github,
      owner,
      repo,
      ref: tagRef,
    });
    if (!concurrentRef) {
      throw error;
    }

    verifyImmutableTag({
      existingRef: concurrentRef,
      repo,
      tag,
      targetSha,
    });
    core.info(`${repo} tag ${tag} was concurrently created at ${targetSha}.`);
    return { branch: defaultBranch, created: false, sha: targetSha, tag };
  }

  core.info(`Created ${repo} tag ${tag} at ${targetSha} from ${defaultBranch}.`);
  return { branch: defaultBranch, created: true, sha: targetSha, tag };
}

module.exports = { createImmutableReleaseTag };
