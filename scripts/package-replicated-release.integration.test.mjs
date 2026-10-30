import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';

const scripts = path.dirname(fileURLToPath(import.meta.url));
const infra = process.env.INFRASTRUCTURE_DIR ?? path.resolve(scripts, '../../infrastructure');
const digest = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');

test('builds one reproducible release binding chart and immutable runner image', { timeout: 180000 }, () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'release-integration-'));
  const run = (binary, args, cwd = root) => {
    const result = spawnSync(binary, args, { cwd, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
    assert.equal(result.status, 0, result.stderr || result.stdout);
    return result.stdout;
  };
  const put = (file, bytes) => {
    fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, bytes);
  };
  try {
    const fixture = path.join(root, 'helm-charts');
    for (const name of ['package-replicated-release.mjs', 'release-archive.py']) put(path.join(fixture, 'scripts', name), fs.readFileSync(path.join(scripts, name)));
    const chart = path.join(fixture, 'composio');
    put(path.join(chart, 'Chart.yaml'), 'apiVersion: v2\nname: composio\nversion: 0.0.1\ndependencies:\n- name: replicated\n  version: 1.19.11\n  repository: file://./charts/replicated\n');
    put(path.join(chart, 'Chart.lock'), 'dependencies:\n- name: replicated\n  repository: file://./charts/replicated\n  version: 1.19.11\ndigest: sha256:fixture\n');
    put(path.join(chart, 'charts/replicated/Chart.yaml'), 'apiVersion: v2\nname: replicated\nversion: 1.19.11\n');
    put(path.join(chart, 'charts/replicated/values.yaml'), '{}\n');
    put(path.join(chart, 'values.yaml'), `global: {}\nimage: registry.example.com/test-only@sha256:${'a'.repeat(64)}\n`);
    put(path.join(chart, 'templates/pod.yaml'), 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: fixture\nspec:\n  containers:\n  - name: app\n    image: {{ .Values.image }}\n');
    put(path.join(fixture, 'manifests/composio.yaml'), 'apiVersion: kots.io/v1beta2\nkind: HelmChart\nmetadata:\n  name: composio\nspec:\n  chart:\n    name: composio\n    chartVersion: 0.0.1\n');
    put(path.join(root, 'qualification.json'), JSON.stringify({ computeModes: ['ec2'], features: ['api', 'authentication'], capabilities: {
      awsWebIdentity: true, mercuryAwsConfiguration: true, managedDependencies: true,
      externalServiceAccounts: true, externalSecrets: true, migrationsOwnedByChart: true } }));
    run('git', ['init', '--quiet', fixture]);
    run('git', ['-C', fixture, '-c', 'user.name=Packager Test', '-c', 'user.email=packager@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '--quiet', '--allow-empty', '-m', 'Local fixture']);
    const publication = { schemaVersion: 1, revision: 'd'.repeat(40),
      image: `000000000000.dkr.ecr.us-east-1.amazonaws.com/test-runner@sha256:${'b'.repeat(64)}`,
      bundle: { schemaVersion: 1, kind: 'ManagedVpcRunnerImage', runnerContractVersion: 2, revision: 'd'.repeat(40), platform: 'linux/amd64',
        infrastructure: { project: 'infra-managed-vpc', sha256: 'c'.repeat(64) } } };
    put(path.join(root, 'publication.json'), JSON.stringify(publication));
    const before = digest(path.join(chart, 'Chart.yaml'));
    const args = [path.join(fixture, 'scripts/package-replicated-release.mjs'), '--version', '1.2.3',
      '--chart-reference', 'oci://registry.replicated.com/composio-rodent/composio',
      '--alternate-chart-reference', 'oci://registry.replicated.com/composio-rodent/nightly/composio',
      '--infrastructure-dir', infra, '--runner-publication', path.join(root, 'publication.json'), '--qualification', path.join(root, 'qualification.json')];
    for (const name of ['first', 'second']) run(process.execPath, [...args, '--output', path.join(root, name)]);
    const first = path.join(root, 'first'), second = path.join(root, 'second');
    assert.equal(digest(path.join(chart, 'Chart.yaml')), before, 'source chart changed');
    assert.equal(fs.readFileSync(path.join(first, 'SHA256SUMS'), 'utf8'), fs.readFileSync(path.join(second, 'SHA256SUMS'), 'utf8'));
    const releaseBytes = fs.readFileSync(path.join(first, 'release.lock.json'));
    const release = JSON.parse(releaseBytes);
    assert.deepEqual(release.chart.alternateReferences, ['oci://registry.replicated.com/composio-rodent/nightly/composio']);
    assert.equal(fs.readFileSync(path.join(first, 'release.lock.sha256'), 'utf8').trim(), digest(path.join(first, 'release.lock.json')));
    assert.equal(release.schemaVersion, 2);
    assert.equal(release.infrastructure.sha256, publication.bundle.infrastructure.sha256);
    assert.equal(release.infrastructure.source, 'runner-image');
    assert.equal(release.infrastructure.url, undefined);
    assert.equal(release.runner.image, `proxy.replicated.com/proxy/composio-rodent/${publication.image}`);
    assert.equal(release.runner.revision, publication.revision);
    assert(!fs.existsSync(path.join(first, 'infrastructure')));
    assert(!fs.existsSync(path.join(first, 'release.candidate.json')));
    run('python3', [path.join(infra, 'stacks/managed-vpc/runner/scripts/archive.py'), path.join(first, 'replicated/composio-1.2.3.tgz'), path.join(root, 'chart')]);
    const require = createRequire(path.join(infra, 'package.json'));
    const runner = path.join(infra, 'stacks/managed-vpc/runner/build/stacks/managed-vpc/runner/src');
    const contract = require(path.join(runner, 'contracts.js'));
    const chartHelper = require(path.join(runner, 'chart.js'));
    const finalChart = path.join(root, 'chart/composio');
    assert.equal(chartHelper.chartContentSha256(finalChart), release.chart.contentSha256);
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(finalChart, 'composio-release.json'))), contract.releaseDescriptor(release));
    contract.validateRelease(release, { releaseId: release.releaseId, runnerImage: release.runner.image }, { installation: { kubernetes: { compute: 'ec2' } },
      application: { values: {}, verification: { checks: [{ feature: 'api' }, { feature: 'authentication' }] } } });
    assert(fs.existsSync(path.join(first, 'bootstrap/template.yaml')));
    assert(!fs.existsSync(path.join(first, 'replicated/composio-infrastructure-1.2.3.tgz')));
    const yaml = require('js-yaml');
    const manifest = yaml.load(fs.readFileSync(path.join(first, 'replicated/release-metadata.yaml'), 'utf8'));
    assert.equal(manifest.metadata.annotations['kots.io/exclude'], 'true');
    assert.equal(manifest.metadata.annotations['kots.io/installer-only'], 'true');
    assert.deepEqual(JSON.parse(manifest.data['release.lock.json']), release);
    const wrongImage = spawnSync(process.execPath, [...args, '--output', path.join(root, 'wrong-image'), '--runner-image', `proxy.replicated.com/proxy/composio-rodent/${publication.image.replace('b'.repeat(64), 'e'.repeat(64))}`], { encoding: 'utf8' });
    assert.notEqual(wrongImage.status, 0);
    assert.match(wrongImage.stderr, /preserve the published/);
    delete publication.bundle.runnerContractVersion;
    put(path.join(root, 'publication.json'), JSON.stringify(publication));
    const oldImage = spawnSync(process.execPath, [...args, '--output', path.join(root, 'old-image')], { encoding: 'utf8' });
    assert.notEqual(oldImage.status, 0);
    assert.match(oldImage.stderr, /publication metadata is invalid/);
    const refused = spawnSync(process.execPath, [...args, '--output', first], { encoding: 'utf8' });
    assert.notEqual(refused.status, 0);
    assert.match(refused.stderr, /already exists/);
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});
