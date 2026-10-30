import assert from 'node:assert/strict';
import test from 'node:test';
import { sha, nextVersion, validateRecipe, validatePublication, promotionDecision, verifyRelease, guardAttempt, vendor } from './janus-nightly-release.mjs';
const recipe = { schemaVersion: 1, infrastructureSha: 'a'.repeat(40), onpremSha: 'b'.repeat(40), appId: 'app', nightlyChannelId: 'nightly', stableChannelId: 'stable',
  values: 'releases/values.yaml', qualification: 'releases/qualified.json', runnerPublication: 'releases/runner.json',
  chartReference: 'oci://registry.replicated.com/example/composio', nightlyChartReference: 'oci://registry.replicated.com/example/nightly/composio', cvePolicy: 'report',
  imageTags: Object.fromEntries(['apollo','apollo-db-init','thermos','thermos-db-init','mercury','frontend','weaviate','thermos-toolkit-registry'].map(name => [name, 'latest'])) };
const lock = JSON.stringify({ schemaVersion: 2, releaseId: '1.2.3', chart: { version: '1.2.3' }, runner: { image: `example/runner@sha256:${'c'.repeat(64)}` } });
const publication = { sequence: 42, appId: 'app', releaseId: '1.2.3', version: '1.2.3', releaseLock: lock, releaseSha256: sha(lock), helmSha: 'a'.repeat(40) };
test('Nightly bumps the selected numeric version without changing release identity at promotion', () => {
  assert.equal(nextVersion('0.2.241'), '0.2.242');
  for (const value of ['latest','1.2.3-dev','1.2','']) assert.throws(() => nextVersion(value));
  assert.equal(promotionDecision(41,42),'promote');
  assert.equal(promotionDecision(42,42),'already-promoted');
  assert.throws(() => promotionDecision(43,42), /newer release/);
  assert.throws(() => promotionDecision(NaN,42));
});
test('a recipe pins its tooling sources and separate distribution channels', () => {
  assert.equal(validateRecipe(recipe), recipe);
  for (const change of [{ infrastructureSha: 'main' }, { stableChannelId: 'nightly' }, { nightlyChartReference: 'oci://attacker.example/app/composio' }, { cvePolicy: '' }, { imageTags: {} }])
    assert.throws(() => validateRecipe({ ...recipe, ...change }));
});
test('promotion verifies the exact immutable release spec before changing a channel', () => {
  assert.equal(validatePublication(publication).releaseId, '1.2.3');
  assert.throws(() => validatePublication({ ...publication, releaseLock: lock + ' ' }));
  const release = { sequence: 42, appId: 'app', isReleaseNotEditable: true, spec: JSON.stringify([{ path: 'release-metadata.yaml', content: JSON.stringify({ data: { 'release.lock.json': lock } }) }]) };
  verifyRelease(release, publication, { load: JSON.parse });
  for (const change of [{ sequence: 43 }, { appId: 'other' }, { isReleaseNotEditable: false }, { spec: '[]' }])
    assert.throws(() => verifyRelease({ ...release, ...change }, publication, { load: JSON.parse }));
});
test('duplicate dispatch and manual reruns stop before creating another release', async () => {
  const env = { GITHUB_RUN_ATTEMPT: '1', GITHUB_RUN_ID: '100', GITHUB_REPOSITORY: 'ComposioHQ/helm-charts', RELEASE_REQUEST_ID: 'request' };
  await guardAttempt(async () => ({ total_count: 1, workflow_runs: [{ id: 100, display_title: 'request' }] }), env);
  await assert.rejects(guardAttempt(async () => ({ total_count: 1, workflow_runs: [{ id: 99, display_title: 'request' }] }), env), /earlier attempt/);
  await assert.rejects(guardAttempt(async () => { throw Error('must not call'); }, { ...env, GITHUB_RUN_ATTEMPT: '2' }), /Do not rerun/);
  let pages = 0;
  await assert.rejects(guardAttempt(async () => ({ total_count: 101, workflow_runs: ++pages === 2 ? [{ id: 50, display_title: 'request' }] : Array.from({ length: 100 }, (_, id) => ({ id: id + 101, display_title: 'other' })) }), env), /earlier attempt/);
  assert.equal(pages, 2);
  await assert.rejects(guardAttempt(async () => ({ total_count: 101, workflow_runs: [] }), env), /Incomplete dispatch history/);
});
test('an unknown vendor write is never automatically retried or reported as successful', async () => {
  let calls = 0;
  await assert.rejects(vendor('/app/app/release/42/promote', 'test-token', { channelIds: ['stable'] }, async () => { calls++; throw Error('lost response'); }), /lost response/);
  assert.equal(calls,1);
});
