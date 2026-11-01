import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { options, publicValues, merge, renderedImages, qualification, releaseSpecBytes } from './package-replicated-release.mjs';

const temporary = fn => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'release-test-'));
  try { return fn(root); } finally { fs.rmSync(root, { recursive: true, force: true }); }
};
const base = ['--version', '1.2.3', '--runner-publication', '/tmp/test-publication.json'];

test('accepts local packaging options and fixes the release identity', () => {
  const o = options(base);
  assert.equal(o['release-id'], '1.2.3');
  assert.match(o['chart-reference'], /composio-rodent\/unstable\/composio$/);
});

test('image release requires a publication and no external infrastructure URL', () => {
  const o = options(base);
  assert.equal(o['infrastructure-base-url'], undefined);
  assert.throws(() => options(['--version', '1.2.3']), /runner-publication/);
  assert.throws(() => options([...base, '--infrastructure-base-url', 'https://example.com/releases']), /retired/);
  assert(options([...base, '--qualification', '/tmp/qualification.json']));
});

test('rejects publication/deployment switches, duplicate inputs and mutable URLs', () => {
  for (const args of [ [...base, '--push'], [...base, '--version', '2.0.0'],
    ['--version', '../private', '--infrastructure-base-url', 'https://example.com'],
    ['--version', '1.2.3', '--infrastructure-base-url', 'https://user:pass@example.com'],
    ['--version', '1.2.3', '--infrastructure-base-url', 'https://example.com?token=secret'] ]) {
    assert.throws(() => options(args));
  }
});

test('refuses credential values/prototype properties but accepts secret references', () => {
  publicValues({ secret: { name: 'composio-runtime' }, password: { key: 'password' }, token: '' });
  for (const input of [{ apiKey: 'private' }, { url: 'postgres://user:password@db/name' },
    { AWS_SECRET_ACCESS_KEY: 'private' }, JSON.parse('{"__proto__":{"polluted":true}}')]) {
    assert.throws(() => publicValues(input));
  }
  assert.equal({}.polluted, undefined);
});

test('merges public chart overrides without losing unrelated defaults', () => {
  assert.deepEqual(merge({ apollo: { image: { repository: 'apollo', tag: 'old' }, replicas: 2 }, array: [1] },
    { apollo: { image: { tag: 'new' } }, array: [2] }),
  { apollo: { image: { repository: 'apollo', tag: 'new' }, replicas: 2 }, array: [2] });
});

test('image inventory includes hooks, CronJobs, subcharts and init containers', () => {
  assert.deepEqual(renderedImages([
    { kind: 'CronJob', spec: { jobTemplate: { spec: { template: { spec: { containers: [{ image: 'cron@sha256:abc' }], initContainers: [{ image: 'init:tag' }] } } } } } },
    { kind: 'Job', metadata: { annotations: { 'helm.sh/hook': 'pre-install' } }, spec: { template: { spec: { containers: [{ image: 'hook:tag' }, { image: 'init:tag' }] } } } },
  ]), ['cron@sha256:abc', 'hook:tag', 'init:tag']);
});

test('candidate packaging makes no qualification claim', () => {
  const q = qualification(undefined, ['image:latest']);
  assert(Object.values(q.capabilities).every(value => value === false));
});

test('release size accounts for binary base64 expansion and Go JSON escaping', () => temporary(root => {
  fs.writeFileSync(path.join(root, 'app.yaml'), '<resource>');
  fs.writeFileSync(path.join(root, 'chart.tgz'), Buffer.from([0, 1, 2]));
  fs.writeFileSync(path.join(root, 'ignored.json'), 'not part of the CLI release');
  const expected = JSON.stringify([
    { name: 'app.yaml', path: 'app.yaml', content: '<resource>', children: [] },
    { name: 'chart.tgz', path: 'chart.tgz', content: 'AAEC', children: [] },
  ]).replace(/</g, '\\u003c').replace(/>/g, '\\u003e');
  assert.equal(releaseSpecBytes(root), Buffer.byteLength(expected));
}));

test('runner lock requires pins and all qualification claims', () => temporary(root => {
  const file = path.join(root, 'qualification.json');
  const q = { computeModes: ['ec2', 'fargate'], features: ['api', 'authentication'], capabilities: {
    awsWebIdentity: true, mercuryAwsConfiguration: true, managedDependencies: true,
    externalServiceAccounts: true, externalSecrets: true, migrationsOwnedByChart: true, fargate: true } };
  fs.writeFileSync(file, JSON.stringify(q));
  const image = `registry.example.com/app@sha256:${'a'.repeat(64)}`;
  assert.deepEqual(qualification(file, [image]).computeModes, ['ec2', 'fargate']);
  assert.throws(() => qualification(file, ['image:latest']), /@sha256/);
  delete q.capabilities.fargate;
  fs.writeFileSync(file, JSON.stringify(q));
  assert.throws(() => qualification(file, [image]), /Fargate/);
}));

test('archives are deterministic and reject links', () => temporary(root => {
  const source = path.join(root, 'source'); fs.mkdirSync(source);
  fs.writeFileSync(path.join(source, 'file.txt'), 'release bytes\n');
  const helper = fileURLToPath(new URL('./release-archive.py', import.meta.url));
  const pack = file => spawnSync('python3', [helper, source, file]);
  const first = path.join(root, 'first.tgz'), second = path.join(root, 'second.tgz');
  assert.equal(pack(first).status, 0);
  fs.utimesSync(path.join(source, 'file.txt'), new Date(), new Date());
  assert.equal(pack(second).status, 0);
  assert.deepEqual(fs.readFileSync(first), fs.readFileSync(second));
  fs.symlinkSync('/etc/passwd', path.join(source, 'link'));
  assert.notEqual(pack(path.join(root, 'unsafe.tgz')).status, 0);
}));

test('archives match the actual runner content hash and release descriptor', () => temporary(root => {
  const infra = process.env.INFRASTRUCTURE_DIR ?? path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../infrastructure');
  const require = createRequire(path.join(infra, 'package.json'));
  // Use the existing runner build; npm run build in runner/ is the prerequisite.
  const chartHelper = require(path.join(infra, 'stacks/managed-vpc/runner/build/stacks/managed-vpc/runner/src/chart.js'));
  const contract = require(path.join(infra, 'stacks/managed-vpc/runner/build/stacks/managed-vpc/runner/src/contracts.js'));
  const chart = path.join(root, 'composio'); fs.mkdirSync(chart);
  fs.writeFileSync(path.join(chart, 'Chart.yaml'), 'apiVersion: v2\nname: composio\nversion: 1.2.3\n');
  fs.writeFileSync(path.join(chart, 'values.yaml'), 'global:\n  replicated:\n    licenseID: original\n  domain: example.com\n');
  const descriptor = contract.releaseDescriptor({ schemaVersion: 1, releaseId: '1.2.3', chart: { name: 'composio', version: '1.2.3', contentSha256: 'circular' } });
  fs.writeFileSync(path.join(chart, 'composio-release.json'), JSON.stringify(descriptor));
  assert.equal(descriptor.chart.contentSha256, undefined);
  const before = chartHelper.chartContentSha256(chart);
  fs.writeFileSync(path.join(chart, 'values.yaml'), 'global:\n  domain: example.com\n  replicated:\n    licenseID: customer\n');
  assert.equal(chartHelper.chartContentSha256(chart), before);
  fs.writeFileSync(path.join(chart, 'composio-release.json'), JSON.stringify({ ...descriptor, releaseId: '2.0.0' }));
  assert.notEqual(chartHelper.chartContentSha256(chart), before);
}));
