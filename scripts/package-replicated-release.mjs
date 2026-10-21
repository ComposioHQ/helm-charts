#!/usr/bin/env node
// Local packaging only: no Replicated, registry, Git, AWS, or Pulumi writes.
import * as fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';

const scripts = path.dirname(fileURLToPath(import.meta.url));
const repo = path.dirname(scripts);
const pins = { '@pulumi/aws': '7.19.0', '@pulumi/pulumi': '3.219.0', '@pulumi/random': '4.19.2' };
const capabilities = ['awsWebIdentity', 'mercuryAwsConfiguration', 'managedDependencies',
  'externalServiceAccounts', 'externalSecrets', 'migrationsOwnedByChart'];
const features = ['api', 'authentication', 'connectedAccounts', 'tools', 'mcp', 'sessions', 'files'];
const imagePattern = /^[a-z0-9][a-z0-9./:_-]+@sha256:[a-f0-9]{64}$/;
const json = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const writeJson = (file, data) => fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
const assert = (condition, message) => { if (!condition) throw new Error(message); };

export function options(args) {
  const result = {};
  const allowed = ['version', 'release-id', 'infrastructure-dir', 'infrastructure-base-url',
    'chart-reference', 'values', 'qualification', 'runner-publication', 'runner-image', 'output', 'help'];
  for (let i = 0; i < args.length; i++) {
    const key = args[i].replace(/^--/, '');
    assert(args[i].startsWith('--') && allowed.includes(key) && !(key in result), `Unknown/duplicate option: ${args[i]}`);
    if (key === 'help') result.help = true;
    else {
      assert(args[i + 1] && !args[i + 1].startsWith('--'), `Missing value: --${key}`);
      result[key] = args[++i];
    }
  }
  if (result.help) return result;
  assert(/^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$/.test(result.version ?? ''), '--version requires a chart SemVer without build metadata');
  result['release-id'] ??= result.version;
  assert(/^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/.test(result['release-id']), 'Invalid release ID');
  if (result['infrastructure-base-url']) {
    const url = new URL(result['infrastructure-base-url']);
    assert(url.protocol === 'https:' && !url.username && !url.password && !url.search && !url.hash,
      '--infrastructure-base-url must be an approved HTTPS publication location without credentials/query/fragment');
    result['infrastructure-base-url'] = url.href.replace(/\/$/, '');
  }
  assert(!result['infrastructure-base-url'], 'External infrastructure archives are retired; supply --runner-publication');
  assert(result['runner-publication'], '--runner-publication must identify the published bundled runner image');
  result['chart-reference'] ??= 'oci://registry.replicated.com/composio-rodent/unstable/composio';
  assert(/^oci:\/\/((registry\.replicated\.com|artifacts\.composio\.io)\/[a-z0-9][a-z0-9/_.-]+|proxy\.replicated\.com\/registry\/[a-z0-9][a-z0-9/_.-]+)\/composio$/.test(result['chart-reference']),
    'Chart reference must match the runner-approved Replicated OCI registry and chart name');
  result['infrastructure-dir'] = path.resolve(result['infrastructure-dir'] ?? path.join(repo, '../infrastructure'));
  result.output = path.resolve(result.output ?? path.join(repo, 'dist/releases', result['release-id']));
  return result;
}

function command(binary, args, settings = {}) {
  const result = spawnSync(binary, args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, ...settings });
  // Tool errors can include rendered values: do not echo their raw output.
  assert(!result.error && result.status === 0, `${path.basename(binary)} ${args[0] ?? ''} failed; check prerequisites and input files`);
  return result.stdout;
}

export function publicValues(value, location = 'values') {
  if (Array.isArray(value)) { value.forEach((item, i) => publicValues(item, `${location}[${i}]`)); return; }
  if (value && typeof value === 'object') for (const [key, item] of Object.entries(value)) {
    assert(!['__proto__', 'constructor', 'prototype'].includes(key), `Unsafe property at ${location}`);
    assert(!/(password|token|apikey|licenseid|dockerconfigjson|privatekey|secretvalue|accesskeyid|secretaccesskey|sessiontoken)$/i.test(key.replace(/[-_]/g, ''))
      || item === '' || item === null || typeof item === 'boolean' || (item && typeof item === 'object'),
    `Use secret references instead of credentials at ${location}.${key}`);
    publicValues(item, `${location}.${key}`);
  }
  if (typeof value === 'string') assert(!/^[a-z]+:\/\/[^/\s]+:[^/\s]+@/i.test(value)
    && !/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(value), `Credential material at ${location}`);
}

export function merge(base, override) {
  for (const [key, value] of Object.entries(override)) {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      base[key] = merge(base[key] && typeof base[key] === 'object' && !Array.isArray(base[key]) ? base[key] : {}, value);
    } else base[key] = value;
  }
  return base;
}

function copyTree(source, destination, skip = new Set(), include = () => true) {
  const info = fs.lstatSync(source);
  assert(!info.isSymbolicLink(), `Links cannot be packaged: ${source}`);
  if (info.isDirectory()) {
    fs.mkdirSync(destination, { recursive: true });
    for (const name of fs.readdirSync(source).sort()) if (!skip.has(name)) copyTree(path.join(source, name), path.join(destination, name), skip, include);
  } else {
    assert(info.isFile() && !source.endsWith('.node'), `Special/native files require a Linux build: ${source}`);
    if (!include(source)) return;
    fs.copyFileSync(source, destination);
    fs.chmodSync(destination, info.mode & 0o111 ? 0o755 : 0o644);
  }
}

export function renderedImages(documents) {
  const images = new Set();
  function visit(value) {
    if (Array.isArray(value)) { value.forEach(visit); return; }
    if (!value || typeof value !== 'object') return;
    for (const [key, item] of Object.entries(value)) {
      if (['containers', 'initContainers', 'ephemeralContainers'].includes(key) && Array.isArray(item)) {
        for (const container of item) {
          assert(typeof container.image === 'string' && container.image.length > 0, 'Rendered container image is missing');
          images.add(container.image);
        }
      }
      visit(item);
    }
  }
  visit(documents);
  assert(images.size, 'Chart rendered no container images');
  return [...images].sort();
}

export function releaseSpecBytes(directory) {
  const files = [], binary = new Set(['.tgz', '.gz', '.woff', '.woff2', '.ttf', '.otf', '.eot', '.svg']);
  const supported = new Set([...binary, '.yaml', '.yml', '.css']);
  function visit(current) {
    for (const entry of fs.readdirSync(current, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const file = path.join(current, entry.name);
      assert(!entry.isSymbolicLink(), 'Release cannot contain links');
      if (entry.isDirectory()) { visit(file); continue; }
      const ext = path.extname(entry.name);
      if (entry.name.startsWith('.') || !supported.has(ext)) continue;
      const bytes = fs.readFileSync(file);
      files.push({ name: entry.name, path: path.relative(directory, file).split(path.sep).join('/'),
        content: binary.has(ext) ? bytes.toString('base64') : bytes.toString('utf8'), children: [] });
    }
  }
  visit(directory);
  // Match the CLI's Go JSON HTML escaping; payload limit is before gzip.
  const encoded = JSON.stringify(files).replace(/[<>&\u2028\u2029]/g, c => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`);
  return Buffer.byteLength(encoded);
}

export function qualification(file, images) {
  if (!file) return { computeModes: ['ec2'], features: ['api', 'authentication'],
    capabilities: Object.fromEntries(capabilities.map(name => [name, false])) };
  const q = json(file);
  assert(Array.isArray(q.computeModes) && q.computeModes.length > 0 && q.computeModes.every(mode => ['ec2', 'fargate'].includes(mode)), 'Invalid qualification computeModes');
  assert(Array.isArray(q.features) && ['api', 'authentication'].every(name => q.features.includes(name))
    && q.features.every(name => features.includes(name)), 'Invalid qualification features');
  const allowed = [...capabilities, 'fargate', 'temporalCloud', 'ingressController'];
  assert(q.capabilities && Object.entries(q.capabilities).every(([key, value]) => allowed.includes(key) && typeof value === 'boolean')
    && capabilities.every(key => q.capabilities[key] === true), 'Qualification must explicitly attest every required integration');
  assert(!q.computeModes.includes('fargate') || q.capabilities.fargate === true, 'Fargate requires explicit qualification');
  assert(images.every(image => imagePattern.test(image)), 'Runner locks require every rendered application, hook and subchart image to use @sha256; supply public --values');
  return { computeModes: [...new Set(q.computeModes)].sort(), features: [...new Set(q.features)].sort(), capabilities: q.capabilities };
}

function sourceInfo(directory) {
  return { commit: command('git', ['-C', directory, 'rev-parse', 'HEAD']).trim(),
    dirty: Boolean(command('git', ['-C', directory, 'status', '--porcelain', '--untracked-files=no']).trim()) };
}

export async function packageRelease(o) {
  const infra = fs.realpathSync(o['infrastructure-dir']);
  const output = o.output;
  assert(!fs.existsSync(output), `Output already exists: ${output}`);
  // Never place output over a source tree. dist/ is the normal output location.
  for (const source of [repo, infra]) assert(output !== source && !source.startsWith(output + path.sep), 'Output overlaps a source repository');
  if (output.startsWith(repo + path.sep)) assert(output.startsWith(path.join(repo, 'dist') + path.sep), 'Outputs inside helm-charts must use dist/');
  assert(!output.startsWith(infra + path.sep), 'Output must be outside the infrastructure repository');
  const load = createRequire(path.join(infra, 'package.json'));
  const yaml = load('js-yaml'), semver = load('semver');
  assert(semver.valid(o.version), 'Invalid chart SemVer');
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'composio-release-'));
  fs.chmodSync(scratch, 0o700);
  const work = path.join(scratch, 'release');
  fs.mkdirSync(work);
  const archive = (source, destination, prefix = '') => command('python3', [path.join(scripts, 'release-archive.py'), source, destination, prefix]);
  const extract = (source, destination) => command('python3', [path.join(infra, 'stacks/managed-vpc/runner/scripts/archive.py'), source, destination]);
  const tsc = path.join(infra, 'node_modules/typescript/bin/tsc');
  const yamlRead = file => yaml.load(fs.readFileSync(file, 'utf8'), { schema: yaml.JSON_SCHEMA });
  const yamlWrite = (file, value) => fs.writeFileSync(file, yaml.dump(value, { noRefs: true, lineWidth: -1, sortKeys: false }));
  try {
    assert(command('helm', ['version', '--short']).startsWith('v3.'), 'Helm 3 is required');
    console.log('Loading immutable runner publication and compiling release contract helpers...');
    const publication = json(path.resolve(o['runner-publication']));
    assert(imagePattern.test(publication.image) && /^[a-f0-9]{40}$/.test(publication.revision), 'Invalid runner publication');
    const bundle = publication.bundle;
    assert(bundle?.kind === 'ManagedVpcRunnerImage' && bundle.schemaVersion === 1 && bundle.runnerContractVersion === 2 && bundle.revision === publication.revision
      && bundle.platform === 'linux/amd64' && bundle.infrastructure?.project === 'infra-managed-vpc'
      && /^[a-f0-9]{64}$/.test(bundle.infrastructure.sha256), 'Bundled infrastructure publication metadata is invalid');
    const app = o['chart-reference'].replace(/^oci:\/\/(?:proxy\.replicated\.com\/registry\/|[^/]+\/)/, '').split('/')[0];
    const runnerImage = o['runner-image'] ?? `proxy.replicated.com/proxy/${app}/${publication.image}`;
    assert(imagePattern.test(runnerImage) && (runnerImage === publication.image || runnerImage === `proxy.replicated.com/proxy/${app}/${publication.image}`),
      'Runner proxy reference must preserve the published repository and digest');
    command(process.execPath, [tsc, '--project', path.join(infra, 'stacks/managed-vpc/runner/tsconfig.json'), '--outDir', path.join(scratch, 'runner-build')]);
    const cli = path.join(scratch, 'runner-build/stacks/managed-vpc/runner/src/cli.js');
    const helperEnv = { ...process.env, NODE_PATH: [path.join(infra, 'stacks/managed-vpc/runner/node_modules'), path.join(infra, 'node_modules')].join(path.delimiter) };
    const helper = (name, file) => command(process.execPath, ['-e', 'require(process.argv[1]).main()', cli, name, file], { env: helperEnv }).trim();
    const sources = { helm: sourceInfo(repo), infrastructure: sourceInfo(infra) };
    const chart = path.join(scratch, 'chart');
    fs.mkdirSync(chart);
    for (const name of ['Chart.yaml', 'Chart.lock', 'values.yaml', 'values.schema.json', '.helmignore', 'templates', 'charts', 'crds', 'files', 'LICENSE']) {
      const source = path.join(repo, 'composio', name);
      if (fs.existsSync(source)) copyTree(source, path.join(chart, name), new Set(['.helm_ls_cache', '.git', '.DS_Store']));
    }
    const metadata = yamlRead(path.join(chart, 'Chart.yaml'));
    assert(metadata.name === 'composio', 'Chart name must match the runner contract');
    assert(metadata.dependencies?.some(d => d.name === 'replicated'), 'Replicated SDK dependency is missing');
    assert(fs.existsSync(path.join(chart, 'Chart.lock')), 'Locked chart dependencies are required');
    const locked = yamlRead(path.join(chart, 'Chart.lock'));
    const dependencyPins = deps => deps.map(({ name, version, repository }) => ({ name, version, repository }));
    assert(JSON.stringify(dependencyPins(locked.dependencies)) === JSON.stringify(dependencyPins(metadata.dependencies)),
      'Chart dependencies differ from Chart.lock; prepare locked dependencies first');
    // A file:// source directory plus its cached tgz makes Helm emit duplicates.
    for (const dep of metadata.dependencies) {
      const directory = path.join(chart, 'charts', dep.alias ?? dep.name);
      const cached = path.join(chart, 'charts', `${dep.name}-${dep.version}.tgz`);
      if (fs.existsSync(directory) && fs.existsSync(cached)) {
        assert(dep.repository.startsWith('file://'), `Ambiguous packaged and unpacked dependency: ${dep.name}`);
        const installed = yamlRead(path.join(directory, 'Chart.yaml'));
        assert(installed.name === dep.name && installed.version === dep.version, `Unpacked dependency differs from lock: ${dep.name}`);
        fs.unlinkSync(cached);
      }
    }
    metadata.version = o.version; metadata.appVersion = o.version;
    yamlWrite(path.join(chart, 'Chart.yaml'), metadata);
    const values = yamlRead(path.join(chart, 'values.yaml'));
    if (o.values) {
      const override = yamlRead(path.resolve(o.values));
      assert(override && typeof override === 'object' && !Array.isArray(override), '--values must contain a mapping');
      publicValues(override);
      merge(values, override);
    }
    assert(values.global?.replicated === undefined, 'Customer Replicated personalization cannot be packaged');
    yamlWrite(path.join(chart, 'values.yaml'), values);
    command('helm', ['dependency', 'list', chart]); // List only; never download/update dependencies.
    command('helm', ['lint', chart, '--strict', '--set', 'global.disableK8SecretCheck=true']);
    const render = () => yaml.loadAll(command('helm', ['template', 'composio', chart, '--namespace', 'composio',
      '--include-crds', '--set', 'global.disableK8SecretCheck=true']), { schema: yaml.JSON_SCHEMA }).filter(Boolean);
    const images = renderedImages(render());
    const q = qualification(o.qualification, images);
    if (o.qualification) {
      const validation = path.join(scratch, 'chart-validation.json');
      writeJson(validation, { documents: render(), images, computeModes: q.computeModes,
        namespace: values.namespace?.name ?? 'composio',
        accounts: Object.fromEntries(['apollo', 'thermos', 'mercury'].map(name => [name, values[name]?.serviceAccount?.name ?? `composio-${name}`])) });
      command(process.execPath, ['-e', `const fs=require('node:fs'); const {validateManifests}=require(process.argv[1]);
        const v=JSON.parse(fs.readFileSync(process.argv[2]));
        for(const compute of v.computeModes) validateManifests(v.documents,
          {installation:{kubernetes:{compute},workloads:{namespace:v.namespace,serviceAccounts:v.accounts}},application:{secrets:[]}},
          {images:v.images,capabilities:{}});`, path.join(scratch, 'runner-build/stacks/managed-vpc/runner/src/chart.js'), validation], { env: helperEnv });
    }

    const release = { schemaVersion: 2, releaseId: o['release-id'], smokeTestOnly: false,
      toolchain: { pulumi: pins['@pulumi/pulumi'], awsProvider: pins['@pulumi/aws'], randomProvider: pins['@pulumi/random'], nodeMajor: 22 },
      runner: { image: runnerImage, revision: publication.revision },
      infrastructure: { source: 'runner-image', sha256: bundle.infrastructure.sha256, project: 'infra-managed-vpc' },
      chart: { reference: o['chart-reference'], name: 'composio', version: o.version, contentSha256: '0'.repeat(64) }, images, ...q };
    const candidate = path.join(scratch, 'candidate.json');
    writeJson(candidate, release);
    fs.writeFileSync(path.join(chart, 'composio-release.json'), helper('release-descriptor', candidate) + '\n');

    // Helm rewrites chart/dependency metadata. Hash the final extracted package.
    const packaged = path.join(scratch, 'packaged');
    fs.mkdirSync(packaged);
    command('helm', ['package', chart, '--destination', packaged]);
    const rawChart = path.join(packaged, `composio-${o.version}.tgz`);
    const unpacked = path.join(scratch, 'extracted');
    extract(rawChart, unpacked);
    const finalChart = path.join(unpacked, 'composio');
    // Normalize Helm's timestamped dependency archives before hashing them.
    function normalizeDependencies(directory) {
      for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
        const file = path.join(directory, entry.name);
        if (entry.isDirectory()) normalizeDependencies(file);
        else if (entry.name.endsWith('.tgz')) {
          const temp = path.join(scratch, `dependency-${sha(file)}`);
          extract(file, temp);
          normalizeDependencies(temp);
          fs.unlinkSync(file);
          archive(temp, file);
          fs.rmSync(temp, { recursive: true });
        }
      }
    }
    normalizeDependencies(finalChart);
    release.chart.contentSha256 = helper('chart-content-sha256', finalChart);

    const replicated = path.join(work, 'replicated');
    fs.mkdirSync(replicated);
    const finalArchive = path.join(replicated, `composio-${o.version}.tgz`);
    archive(finalChart, finalArchive, 'composio');
    const finalImages = renderedImages(yaml.loadAll(command('helm', ['template', 'composio', finalArchive, '--namespace', 'composio',
      '--include-crds', '--set', 'global.disableK8SecretCheck=true']), { schema: yaml.JSON_SCHEMA }).filter(Boolean));
    assert(JSON.stringify(finalImages) === JSON.stringify(images), 'Packaged chart image inventory differs from staged render');
    // Preserve KOTS manifests, but never include historical chart packages.
    for (const name of fs.readdirSync(path.join(repo, 'manifests')).sort()) {
      if (!/\.ya?ml$/.test(name)) continue;
      const manifest = yamlRead(path.join(repo, 'manifests', name));
      if (manifest.kind === 'HelmChart' && manifest.spec?.chart?.name === 'composio') {
        manifest.spec.chart.chartVersion = o.version;
        // Release defaults live in the packaged chart; KOTS only adds personalization.
        manifest.spec.values = { replicated: { isEmbeddedCluster: 'repl{{ eq Distribution "embedded-cluster"}}', enabled: true, imagePullSecrets: [{ name: '{{repl ImagePullSecretName }}' }] },
          global: { imagePullSecrets: [{ name: '{{repl ImagePullSecretName }}' }] } };
      }
      if (manifest.kind === 'Application' && manifest.apiVersion?.startsWith('app.k8s.io/')) {
        manifest.metadata.labels['app.kubernetes.io/version'] = o.version;
        manifest.spec.descriptor.version = o.version;
      }
      yamlWrite(path.join(replicated, name), manifest);
    }
    const helmCharts = fs.readdirSync(replicated).filter(n => /\.ya?ml$/.test(n)).map(n => yamlRead(path.join(replicated, n)))
      .filter(d => d.kind === 'HelmChart' && d.spec?.chart?.name === 'composio');
    assert(helmCharts.length === 1, 'Replicated release requires exactly one matching HelmChart manifest');

    // Bootstrap is a companion, never part of a Helm release's Kubernetes objects.
    const bootstrap = path.join(work, 'bootstrap'); fs.mkdirSync(bootstrap);
    for (const name of ['template.yaml', 'preflight.py', 'permission-inventory.json', 'customer-permissions.md', 'security.guard', 'README.md']) {
      copyTree(path.join(infra, 'stacks/managed-vpc/bootstrap/aws', name), path.join(bootstrap, name));
    }
    // The one release binds the application chart to its immutable runner image.
    // No infrastructure chart, runtime dependency archive or external download URL.
    const lockName = o.qualification ? 'release.lock.json' : 'release.candidate.json';
    writeJson(path.join(work, lockName), release);
    yamlWrite(path.join(replicated, 'release-metadata.yaml'), { apiVersion: 'v1', kind: 'ConfigMap',
      metadata: { name: 'composio-release-metadata', annotations: { 'kots.io/exclude': 'true', 'kots.io/installer-only': 'true' } },
      data: { [lockName]: JSON.stringify(release, null, 2) + '\n' } });
    if (o.qualification) fs.writeFileSync(path.join(work, 'release.lock.sha256'), sha(fs.readFileSync(path.join(work, lockName))) + '\n');
    const specBytes = releaseSpecBytes(replicated);
    assert(specBytes <= 16 * 1024 * 1024, `Replicated release spec is ${specBytes} bytes; maximum is 16777216. Reduce build-only files before publication.`);
    writeJson(path.join(work, 'build-info.json'), { schemaVersion: 1, mode: o.qualification ? 'runner-lock' : 'candidate',
      sources, runner: release.runner, infrastructure: release.infrastructure, chartArchiveSha256: sha(fs.readFileSync(finalArchive)),
      releaseSpecBytes: specBytes, infrastructureTransport: 'bundled-runner-image',
      pinnedImages: images.every(image => imagePattern.test(image)),
      qualification: o.qualification ? 'Publisher attestation supplied; deployment verification is still required' : 'Not qualified; no runner deployment lock generated' });
    const sums = [];
    function checksums(directory) {
      for (const name of fs.readdirSync(directory).sort()) {
        const file = path.join(directory, name);
        if (fs.statSync(file).isDirectory()) checksums(file);
        else sums.push(`${sha(fs.readFileSync(file))}  ${path.relative(work, file).split(path.sep).join('/')}`);
      }
    }
    checksums(work);
    fs.writeFileSync(path.join(work, 'SHA256SUMS'), sums.join('\n') + '\n');
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.cpSync(work, output, { recursive: true, errorOnExist: true, force: false });
    console.log(`Local release: ${output}\nReplicated input: ${path.join(output, 'replicated')}\nMetadata: ${lockName}\nNothing uploaded, pushed, published or deployed.`);
    return output;
  } finally { fs.rmSync(scratch, { recursive: true, force: true }); }
}

if (process.argv[1] && fs.existsSync(process.argv[1]) && import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href) {
  try {
    const parsed = options(process.argv.slice(2));
    if (parsed.help) console.log(`Usage: node scripts/package-replicated-release.mjs --version 0.2.14 \\\n  [options]

Options:
  --infrastructure-dir PATH  Infrastructure checkout (default: ../infrastructure)
  --release-id ID            Release identity (default: chart version)
  --chart-reference OCI     Future Replicated OCI reference (default: composio-rodent/unstable/composio)
  --values PATH             Public chart defaults/image pins; never customer credentials
  --runner-publication PATH  Required publication.json from the tested deployment runner image\n  --runner-image IMAGE       Optional direct ECR or Replicated proxy reference preserving that digest
  --qualification PATH      Explicit integration attestation; generates a strict runner lock
  --output PATH             New output directory (default: dist/releases/RELEASE_ID)

Infrastructure executes from the immutable runner image referenced by this single Replicated release.\nThe bootstrap package is included as a local companion; no separate infrastructure release is generated.
Without --qualification, builds a local candidate with no deployable runner lock.
Only installed locked dependencies are used. Nothing is pushed or uploaded.`);
    else await packageRelease(parsed);
  } catch (error) { console.error(`Packaging failed: ${error.message}`); process.exitCode = 1; }
}
