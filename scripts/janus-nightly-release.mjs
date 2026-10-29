// Bounded CI operations for Janus. The GitHub run is the publication attempt; ambiguous writes require operator recovery.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

export const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const shaPattern = /^[a-f0-9]{40}$/;
const digestPattern = /^sha256:[a-f0-9]{64}$/;
const idPattern = /^[A-Za-z0-9_-]+$/;
const images = { apollo: ['apollo', 'image'], 'apollo-db-init': ['apollo', 'dbInit', 'image'],
  thermos: ['thermos', 'image'], 'thermos-db-init': ['thermos', 'dbInit', 'image'], mercury: ['mercury', 'image'],
  frontend: ['frontend', 'image'], weaviate: ['weaviate', 'image'], 'thermos-toolkit-registry': ['toolkitRegistry', 'image'] };
export const nextVersion = value => {
  assert(/^\d+\.\d+\.\d+$/.test(value), 'Nightly must have an existing numeric chart version');
  const parts = value.split('.').map(Number); parts[2]++;
  assert(parts.every(Number.isSafeInteger), 'Invalid release version');
  return parts.join('.');
};
export const containedFile = (root, file) => {
  assert(typeof file === 'string' && !path.isAbsolute(file) && !file.split('/').includes('..'), 'Repository-relative file required');
  const actual = fs.realpathSync(path.join(root, file));
  assert(actual.startsWith(fs.realpathSync(root) + path.sep) && fs.statSync(actual).isFile(), 'File escapes checkout');
  return actual;
};
export function validateRecipe(recipe) {
  assert(recipe.schemaVersion === 1 && shaPattern.test(recipe.infrastructureSha), 'Pinned infrastructure source required');
  for (const key of ['appId', 'nightlyChannelId', 'stableChannelId']) assert(idPattern.test(recipe[key]), `Invalid ${key}`);
  assert(recipe.nightlyChannelId !== recipe.stableChannelId, 'Nightly and Stable must be different channels');
  assert(typeof recipe.values === 'string' && typeof recipe.qualification === 'string' && typeof recipe.runnerPublication === 'string', 'Reviewed values, qualification and runner publication files are required');
  const stable = /^oci:\/\/registry\.replicated\.com\/([a-z0-9-]+)\/composio$/.exec(recipe.chartReference);
  assert(stable && recipe.nightlyChartReference === `oci://registry.replicated.com/${stable[1]}/nightly/composio`, 'Stable and Nightly must distribute the same app and chart');
  assert(shaPattern.test(recipe.onpremSha), 'Pin the onprem harness source commit');
  assert(recipe.cvePolicy === 'report' || recipe.cvePolicy === 'block-high-critical', 'Explicit CVE policy is required');
  assert(recipe.imageTags && Object.keys(recipe.imageTags).length === Object.keys(images).length, 'All Composio image sources must be explicit');
  for (const name of Object.keys(images)) assert(/^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$/.test(recipe.imageTags[name]), `Invalid image tag for ${name}`);
  return recipe;
}
export function validatePublication(p) {
  assert(Number.isSafeInteger(p.sequence) && p.sequence > 0 && shaPattern.test(p.helmSha), 'Invalid publication identity');
  assert(sha(p.releaseLock) === p.releaseSha256, 'Release lock checksum differs');
  const lock = JSON.parse(p.releaseLock);
  assert(lock.releaseId === p.releaseId && lock.chart.version === p.version && lock.schemaVersion === 2, 'Release lock identity differs');
  assert(/@sha256:[a-f0-9]{64}$/.test(lock.runner.image), 'Runner image must be pinned');
  return lock;
}
export function promotionDecision(current, candidate) {
  assert(Number.isSafeInteger(current) && current >= 0, 'Stable sequence unavailable');
  assert(Number.isSafeInteger(candidate) && candidate > 0, 'Invalid candidate sequence');
  assert(current <= candidate, 'A newer release is already Stable; this approval cannot roll it back');
  return current === candidate ? 'already-promoted' : 'promote';
}
export function verifyRelease(release, publication, yaml) {
  validatePublication(publication);
  assert(release.sequence === publication.sequence && release.appId === publication.appId && release.isReleaseNotEditable === true, 'Release is missing, mutable or belongs to another app');
  const files = JSON.parse(release.spec);
  const metadata = files.filter(file => file.path === 'release-metadata.yaml');
  assert(metadata.length === 1, 'Release metadata is missing or ambiguous');
  assert(yaml.load(metadata[0].content).data['release.lock.json'] === publication.releaseLock, 'Published release differs from the tested lock');
}
const command = (binary, args, options = {}) => {
  try { return execFileSync(binary, args, { encoding: 'utf8', timeout: 30 * 60_000, maxBuffer: 32 * 1024 * 1024, stdio: ['pipe', 'pipe', 'pipe'], ...options }).trim(); }
  catch { throw new Error(`${path.basename(binary)} operation failed; inspect provider state before retrying publication`); }
};
const write = (file, value) => { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n', { mode: 0o600 }); };
const json = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
export async function vendor(route, token, body, fetch_ = fetch) {
  assert(route.startsWith('/app/') && !route.includes('..'), 'Invalid vendor route');
  const response = await fetch_(`https://api.replicated.com/vendor/v3${route}`, { method: body ? 'POST' : 'GET', redirect: 'error',
    headers: { Authorization: token, Accept: 'application/json', 'Content-Type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(60_000) });
  assert(response.ok, `Replicated returned HTTP ${response.status}; publication outcome may need inspection`);
  return response.json(); // Never retry a mutating request after an ambiguous response.
}
const githubTokens = new Map();
const repositoryToken = repository => {
  const cached = githubTokens.get(repository);
  if (cached && cached.until > Date.now()) return cached.token;
  const permissions = repository === 'helm-charts' ? { actions: 'read', contents: 'write', pull_requests: 'write' } : { actions: 'write', contents: 'read' };
  const value = JSON.parse(command('node', ['automation/.github/scripts/github-app-token.mjs'], { env: { ...process.env,
    GITHUB_APP_CLIENT_ID: process.env.NIGHTLY_GITHUB_APP_CLIENT_ID, GITHUB_APP_PRIVATE_KEY: process.env.NIGHTLY_GITHUB_APP_PRIVATE_KEY,
    GITHUB_APP_OWNER: 'ComposioHQ', GITHUB_APP_REPOSITORIES: repository, GITHUB_APP_PERMISSIONS_JSON: JSON.stringify(permissions) } }));
  assert(value.token && Number.isFinite(Date.parse(value.expires_at)), 'GitHub App token unavailable');
  githubTokens.set(repository, { token: value.token, until: Date.parse(value.expires_at) - 300000 });
  return value.token;
};
const github = async (route, body, method = body ? 'POST' : 'GET') => {
  const response = await fetch(`https://api.github.com/repos/${route}`, { method, redirect: 'error',
    headers: { Authorization: `Bearer ${repositoryToken(route.split('/')[1])}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2026-03-10', 'Content-Type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(30_000) });
  assert(response.ok, `GitHub returned HTTP ${response.status}`); return response.json();
};
// WorkflowJobs can recover dispatch after a lost answer. Publication itself may never be redispatched blindly.
export async function guardAttempt(call = github, env = process.env) {
  assert(env.GITHUB_RUN_ATTEMPT === '1', 'Do not rerun a release job; reconcile its existing publication first');
  for (let page = 1; page <= 100; page++) {
    const result = await call(`${env.GITHUB_REPOSITORY}/actions/workflows/janus-managed-vpc-release.yml/runs?event=workflow_dispatch&per_page=100&page=${page}`);
    assert(Number.isSafeInteger(result.total_count) && Array.isArray(result.workflow_runs), 'Incomplete dispatch history');
    assert(!result.workflow_runs.some(run => run.id < Number(env.GITHUB_RUN_ID) && run.display_title === env.RELEASE_REQUEST_ID),
      'An earlier attempt exists for this request; reconcile its result instead of publishing twice');
    assert(result.workflow_runs.length >= Math.min(100, Math.max(0, result.total_count - (page - 1) * 100)), 'Incomplete dispatch history');
    if (page * 100 >= result.total_count) return;
  }
  throw new Error('Dispatch history exceeds the bounded recovery window');
}
async function reportPublication(publication, source, values, yaml) {
  const branch = `nightly-janus-${publication.version}`;
  command('git', ['checkout', '-b', branch], { cwd: source });
  const chartPath = path.join(source, 'composio/Chart.yaml'), valuesPath = path.join(source, 'composio/values.yaml');
  const chart = yaml.load(fs.readFileSync(chartPath, 'utf8')); chart.version = publication.version; chart.appVersion = publication.version;
  fs.writeFileSync(chartPath, yaml.dump(chart));
  const defaults = yaml.load(fs.readFileSync(valuesPath, 'utf8'));
  for (const keys of Object.values(images)) {
    let target = defaults, actual = values;
    for (const key of keys) { target = target[key] ??= {}; actual = actual[key]; }
    target.imageName = actual.imageName;
  }
  defaults.thermosMiscWorkers.image.imageName = values.thermosMiscWorkers.image.imageName;
  fs.writeFileSync(valuesPath, yaml.dump(defaults));
  for (const file of ['manifests/k8s-app.yaml', 'manifests/composio.yaml']) {
    const doc = yaml.load(fs.readFileSync(path.join(source, file), 'utf8'));
    if (doc.kind === 'HelmChart') doc.spec.chart.chartVersion = publication.version;
    else { doc.spec.descriptor.version = publication.version; doc.metadata.labels['app.kubernetes.io/version'] = publication.version; }
    fs.writeFileSync(path.join(source, file), yaml.dump(doc));
  }
  const files = ['composio/Chart.yaml', 'composio/values.yaml', 'manifests/k8s-app.yaml', 'manifests/composio.yaml'];
  command('git', ['add', ...files], { cwd: source });
  command('git', ['-c', 'user.name=Janus', '-c', 'user.email=janus@users.noreply.github.com', 'commit', '-m', `chore: Nightly release ${publication.version}`], { cwd: source });
  const token = repositoryToken('helm-charts');
  command('git', ['push', 'https://github.com/ComposioHQ/helm-charts.git', `HEAD:refs/heads/${branch}`], { cwd: source,
    env: { ...process.env, GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'http.https://github.com/.extraheader',
      GIT_CONFIG_VALUE_0: `AUTHORIZATION: basic ${Buffer.from(`x-access-token:${token}`).toString('base64')}` } });
  const pr = await github('ComposioHQ/helm-charts/pulls', { base: 'release-stable', head: branch,
    title: `Nightly release ${publication.version}`, body: `Pins the images in Replicated release sequence ${publication.sequence}. Janus deploys this candidate to STS and requires human approval before promoting the same sequence to Stable.\n\nPublication: https://github.com/ComposioHQ/helm-charts/actions/runs/${publication.workflowRunId}` });
  const release = await github('ComposioHQ/helm-charts/releases', { tag_name: `managed-vpc-${publication.version}`, target_commitish: command('git', ['rev-parse', 'HEAD'], { cwd: source }),
    name: publication.version, prerelease: true, body: `Replicated sequence ${publication.sequence}\nTracking PR: ${pr.html_url}\nRelease lock SHA-256: ${publication.releaseSha256}` });
  write('receipts/tracking.json', { pullRequest: pr.html_url, release: release.html_url });
}
export async function main() {
  const payload = JSON.parse(process.env.RELEASE_PAYLOAD ?? '{}');
  assert(['publish', 'test', 'promote'].includes(payload.operation) && payload.operation === process.env.RELEASE_OPERATION, 'Invalid release operation');
  const identity = payload.operation === 'publish' ? payload.preparation : payload.publication;
  assert(identity && shaPattern.test(identity.helmSha) && /^releases\/[a-z0-9][a-z0-9/_-]*\.json$/.test(identity.recipe), 'Invalid source or recipe');
  const source = path.resolve(process.env.RELEASE_SOURCE ?? 'source'), infra = path.resolve(process.env.RELEASE_INFRA ?? 'infrastructure');
  assert(command('git', ['rev-parse', 'HEAD'], { cwd: source }) === identity.helmSha, 'Helm checkout differs from pinned source');
  const recipeBytes = fs.readFileSync(containedFile(source, identity.recipe));
  const recipe = validateRecipe(JSON.parse(recipeBytes));
  if (process.argv[2] === 'configure') {
    fs.appendFileSync(process.env.GITHUB_OUTPUT, `infrastructure_sha=${recipe.infrastructureSha}\n`);
    return;
  }
  assert(command('git', ['rev-parse', 'HEAD'], { cwd: infra }) === recipe.infrastructureSha, 'Infrastructure checkout differs from recipe');
  const require = createRequire(path.join(infra, 'package.json')), yaml = require('js-yaml');
  const token = process.env.REPLICATED_API_TOKEN; assert(token, 'Replicated publishing credential unavailable');
  const channel = async id => {
    const result = await vendor(`/app/${recipe.appId}/channels`, token);
    assert(Array.isArray(result.channels) && (result.totalCount ?? result.channels.length) === result.channels.length, 'Incomplete channel listing');
    const found = result.channels.filter(item => item.id === id);
    assert(found.length === 1, 'Configured channel not found'); return found[0];
  };
  const inspect = async sequence => (await vendor(`/app/${recipe.appId}/release/${sequence}`, token)).release;
  const promote = async (publication, channelId) => {
    await vendor(`/app/${recipe.appId}/release/${publication.sequence}/promote`, token,
      { channelIds: [channelId], versionLabel: publication.version, notifyUsers: false });
    const deadline = Date.now() + 10 * 60_000;
    while (true) {
      const current = await channel(channelId);
      const sequence = Number(current.releaseSequence ?? current.currentReleaseSequence);
      if (sequence === publication.sequence) return;
      assert(Date.now() < deadline, 'Channel promotion was not confirmed'); await sleep(10_000);
    }
  };
  await guardAttempt();
  let publication = payload.publication;
  if (payload.operation === 'publish') {
    assert((await channel(recipe.nightlyChannelId)).name === 'Nightly' && (await channel(recipe.stableChannelId)).name === 'Stable', 'Channel identities differ');
    const nightly = await channel(recipe.nightlyChannelId), version = nextVersion(nightly.currentVersion);
    const releaseId = version, output = path.resolve('release-output');
    const values = yaml.load(fs.readFileSync(containedFile(source, recipe.values), 'utf8'));
    for (const [name, keys] of Object.entries(images)) {
      const response = JSON.parse(command('aws', ['ecr', 'batch-get-image', '--region', 'us-east-1', '--registry-id', '008971668139',
        '--repository-name', `composio-self-host/${name}`, '--image-ids', `imageTag=${recipe.imageTags[name]}`, '--output', 'json']));
      assert(response.images?.length === 1 && !response.failures?.length, `Image unavailable: ${name}`);
      const digest = response.images[0].imageId.imageDigest; assert(digestPattern.test(digest), 'Image digest missing');
      let object = values;
      for (const key of keys) object = object[key] ??= {};
      object.imageName = `proxy.replicated.com/proxy/${recipe.chartReference.split('/')[3]}/008971668139.dkr.ecr.us-east-1.amazonaws.com/composio-self-host/${name}@${digest}`;
      if (name === 'thermos') values.thermosMiscWorkers = { ...values.thermosMiscWorkers, image: { ...values.thermosMiscWorkers?.image, imageName: object.imageName } };
    }
    fs.writeFileSync('release-values.yaml', yaml.dump(values));
    command('node', [path.join(source, 'scripts/package-replicated-release.mjs'), '--version', version, '--release-id', releaseId,
      '--infrastructure-dir', infra, '--values', path.resolve('release-values.yaml'), '--qualification', containedFile(source, recipe.qualification),
      '--runner-publication', containedFile(source, recipe.runnerPublication), '--chart-reference', recipe.chartReference,
      '--alternate-chart-reference', recipe.nightlyChartReference, '--output', output, ...(recipe.runnerImage ? ['--runner-image', recipe.runnerImage] : [])]);
    const lock = json(path.join(output, 'release.lock.json'));
    const releaseLock = fs.readFileSync(path.join(output, 'release.lock.json'), 'utf8');
    // The immutable receipt and package are uploaded even when a later provider operation fails.
    write('receipts/prepared.json', { releaseId, releaseLock, recipeSha256: sha(recipeBytes) });
    const created = JSON.parse(command('replicated', ['release', 'create', '--app', recipe.appId, '--yaml-dir', path.join(output, 'replicated'), '--output', 'json']));
    assert(Number.isSafeInteger(created.sequence) && created.sequence > 0, 'Release creation has no sequence receipt');
    publication = { releaseId, releaseSha256: sha(releaseLock), releaseLock, sequence: created.sequence, appId: recipe.appId,
      nightlyChannelId: recipe.nightlyChannelId, stableChannelId: recipe.stableChannelId, version, previousVersion: nightly.currentVersion,
      helmSha: identity.helmSha, recipe: identity.recipe, recipeSha256: sha(recipeBytes), workflowRunId: Number(process.env.GITHUB_RUN_ID) };
    write('receipts/created.json', publication);
    await promote(publication, recipe.nightlyChannelId);
    verifyRelease(await inspect(publication.sequence), publication, yaml);
    await reportPublication(publication, source, values, yaml);
    write('result/result.json', { operation: 'publish', publication });
    return;
  }
  assert(publication.recipeSha256 === sha(recipeBytes) && publication.appId === recipe.appId && publication.nightlyChannelId === recipe.nightlyChannelId &&
    publication.stableChannelId === recipe.stableChannelId, 'Publication recipe differs');
  const lock = validatePublication(publication);
  verifyRelease(await inspect(publication.sequence), publication, yaml);
  if (payload.operation === 'promote') {
    const stable = await channel(recipe.stableChannelId);
    if (promotionDecision(Number(stable.releaseSequence ?? stable.currentReleaseSequence ?? 0), publication.sequence) === 'promote') await promote(publication, recipe.stableChannelId);
  } else {
    const ecrPassword = command('aws', ['ecr', 'get-login-password', '--region', 'us-east-1']);
    command('docker', ['login', '--username', 'AWS', '--password-stdin', '008971668139.dkr.ecr.us-east-1.amazonaws.com'], { input: ecrPassword });
    fs.mkdirSync('reports', { recursive: true });
    const findings = [];
    for (const [index, image] of lock.images.entries()) {
      assert(/@sha256:[a-f0-9]{64}$/.test(image), 'CVE scan requires immutable images');
      const scanImage = image.replace(/^proxy\.replicated\.com\/proxy\/[^/]+\//, '');
      const report = JSON.parse(command('grype', [scanImage, '-o', 'json']));
      write(`reports/image-${index}.json`, report);
      findings.push(...report.matches.filter(match => ['High', 'Critical'].includes(match.vulnerability.severity)));
    }
    write('reports/cve-summary.json', { highCritical: findings.length, policy: recipe.cvePolicy });
    assert(recipe.cvePolicy !== 'block-high-critical' || findings.length === 0, 'CVE policy blocked qualification');
    const tests = await Promise.allSettled(['', publication.previousVersion].map(async previous => {
      const head = await github('ComposioHQ/onprem-testbed/commits/main');
      assert(head.sha === recipe.onpremSha, 'Harness main differs from the approved test commit');
      const receipt = await github('ComposioHQ/onprem-testbed/actions/workflows/replicated-cmx-harness.yml/dispatches', {
        ref: 'main', inputs: { helm_chart_version: publication.version, upgrade_from_versions: previous, migration_direction: 'upgrade',
          cluster_size: 'xlarge', include_optional_scenarios: 'false',
          harness_env_json: JSON.stringify({ RUN_TRIGGER_TESTS: '1', RUN_POLLING_TRIGGER_TESTS: '1', RUN_WEBHOOK_TRIGGER_TESTS: '1', HELM_OCI_CHART_REF: recipe.nightlyChartReference }) },
      });
      assert(Number.isSafeInteger(receipt.workflow_run_id), 'Harness dispatch has no exact run receipt; inspect before retrying');
      write(`reports/${previous ? 'upgrade' : 'fresh'}-dispatch.json`, receipt);
      const deadline = Date.now() + 5 * 60 * 60_000;
      while (true) {
        const run = await github(`ComposioHQ/onprem-testbed/actions/runs/${receipt.workflow_run_id}/attempts/1`);
        assert(run.head_sha === recipe.onpremSha, 'Harness main moved from the approved test commit');
        if (run.status === 'completed') { assert(run.conclusion === 'success', 'Onprem harness failed'); break; }
        assert(Date.now() < deadline, 'Harness did not finish within five hours'); await sleep(30_000);
      }
    }));
    assert(tests.every(result => result.status === 'fulfilled'), 'One or more qualification harnesses failed or could not be confirmed; inspect the retained dispatch receipts');
  }
  write('result/result.json', { operation: payload.operation, sequence: publication.sequence, releaseSha256: publication.releaseSha256 });
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
