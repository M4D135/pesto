// Explicit GitHub Actions publication only. The already-tested ZIP bytes are never rebuilt or rewritten.
import {createHash} from 'node:crypto';
import {createReadStream, lstatSync, readFileSync, writeFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

export const repository = 'M4D135/pesto';
const prefix = '/repos/' + repository;
const shaPattern = /^[a-f0-9]{40}$/;
const digestPattern = /^[a-f0-9]{64}$/;
const requireValue = (value, message) => { if (!value) throw new Error(message); };
function regularFile(path, maxBytes = 4 * 1024 ** 3) {
  for (let cursor = resolve(path);; cursor = dirname(cursor)) {
    requireValue(!lstatSync(cursor).isSymbolicLink(), 'A release path contains a link.');
    if (dirname(cursor) === cursor) break;
  }
  const stat = lstatSync(path);
  requireValue(stat.isFile() && stat.size > 0 && stat.size <= maxBytes, 'Invalid release file: ' + path);
  return stat;
}
function json(path) {
  regularFile(path, 1024 * 1024);
  return JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
}
async function identity(path, name) {
  const before = regularFile(path), hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  const after = regularFile(path);
  requireValue(before.size === after.size && before.mtimeMs === after.mtimeMs && before.ino === after.ino,
    'A release file changed while hashing.');
  return {path, name, bytes: after.size, sha256: hash.digest('hex')};
}
export function contextFromEnv(env) {
  requireValue(env.GITHUB_ACTIONS === 'true' && env.GITHUB_REPOSITORY === repository
    && env.GITHUB_EVENT_NAME === 'workflow_dispatch' && env.GITHUB_REF === 'refs/heads/master'
    && env.PESTO_PUBLISH_RELEASE === 'true', 'Release requires an explicit dispatch from M4D135/pesto master.');
  requireValue(shaPattern.test(env.GITHUB_SHA ?? '') && /^[1-9]\d*$/.test(env.GITHUB_RUN_ID ?? '')
    && /^[1-9]\d*$/.test(env.GITHUB_RUN_ATTEMPT ?? '') && env.PESTO_EXPECTED_SOURCE_SHA === env.GITHUB_SHA,
  'Invalid workflow identity or explicitly selected source commit.');
  return {sha: env.GITHUB_SHA, runId: env.GITHUB_RUN_ID, runAttempt: env.GITHUB_RUN_ATTEMPT};
}
const SOCLE_VERSION = '156.0.4314.42';
const SOCLE_RELEASE_URL = 'https://github.com/M4D135/socle-windows/releases/tag/webview2-156.0.4314.42';
const SOCLE_ENGINE_TESTS = [
  'InstallCarriesTheSocleAndRollbackKeepsIt',
  'SocleExactCopyIsAcceptedOutsideThePackIdentity',
  'SocleChangedExtraMissingOrEmptyIsRefused',
  'InstallWithoutSocleNeverCreatesOne',
  'EmbeddedSocleIndexLoadsTheRealRuntimeInventory'
];
export async function prepareRelease(directory, context, version) {
  requireValue(/^2\.\d+\.\d+(?:\.\d+)?$/.test(version), 'Invalid release version.');
  const root = resolve(directory), records = json(join(root, 'evidence/artifacts.json'));
  const sdk = json(join(root, 'evidence/candidate-sdk.json'));
  requireValue(sdk.success === true && sdk.sourceCommit === context.sha && sdk.sdkVersion === '10.0.302'
    && sdk.sourceHead === context.sha && sdk.expectedSdkVersion === '10.0.302' && sdk.rollForward === 'disable', 'Exact Windows SDK proof missing.');
  requireValue(Array.isArray(records), 'Artifact records must be an array.');
  const publishable = records.filter(r => r.channel === 'PROD' && r.edition === 'PROD-LIGHT');
  requireValue(publishable.length === 1, 'Exactly one publishable PROD-LIGHT record is required.');
  const record = publishable[0];
  requireValue(record.sourceCommit === context.sha && record.runId === context.runId && record.runAttempt === context.runAttempt
    && record.version === version && record.distribution === 'official' && record.qualification === 'unqualified'
    && record.adQualified === false && digestPattern.test(record.archiveSha256 ?? '') && digestPattern.test(record.executableSha256 ?? ''),
  'Artifact provenance or qualification does not match this release.');
  requireValue(record.runtimeMode === 'evergreen' && record.runtimeSource === 'evergreen',
    'PROD-LIGHT must declare evergreen runtime mode and source.');
  requireValue(record.nativeRollbackUiQualified === false
    && record.nativeUpdateQualified === true && record.baselineInPlaceUpdateQualified === true
    && record.baselineFormatRefusalQualified === false && record.newInstallationRequiredFromBaseline === false
    && /^2\.\d+\.\d+$/.test(record.uiUpdateFromVersion ?? '') && shaPattern.test(record.uiUpdateFromSourceCommit ?? '')
    && digestPattern.test(record.uiUpdateFromArchiveSha256 ?? '') && shaPattern.test(record.updateBaselineSourceCommit ?? ''),
  'Incomplete PROD-LIGHT update proof.');
  for (const field of ['nativeStartupDemoQualified', 'nativeDemoCoexistenceQualified', 'nativeConfigurationQualified',
    'nativeConfigurationUiQualified', 'nativeUpdatePreparationUiQualified', 'nativeUpdateInstallUiQualified',
    'nativeServiceRollbackAfterUiInstallQualified', 'distinctUpdateBuilds'])
    requireValue(record[field] === true, 'Windows qualification missing: ' + field);
  requireValue(record.socleVersion === SOCLE_VERSION, 'Socle version must be ' + SOCLE_VERSION + '.');
  requireValue(record.socleReleaseUrl === SOCLE_RELEASE_URL, 'Socle release URL differs.');
  requireValue(record.soclePreservationQualified === true, 'Socle preservation not qualified.');
  for (const field of ['socleIndexSha256', 'socleMatchSha256', 'socleRunnerSha256', 'smokeSha256'])
    requireValue(digestPattern.test(record[field] ?? ''), 'Missing or invalid SHA-256: ' + field);
  const engineSocle = json(join(root, 'evidence/engine-socle-tests.json'));
  requireValue(engineSocle.schemaVersion === 1 && engineSocle.kind === 'pesto.engine-socle-tests' && engineSocle.passed === true
    && Array.isArray(engineSocle.tests) && SOCLE_ENGINE_TESTS.every(name => engineSocle.tests.includes(name)),
  'Socle Engine tests did not all pass on the Windows runner.');
  const smokeFile = join(root, 'evidence/prod-light-smoke.json');
  const nativeFile = join(root, 'evidence/native-demo-PROD-LIGHT.json');
  const matchFile = join(root, 'evidence/socle-match.json');
  const runnerFile = join(root, 'evidence/socle-runner.json');
  const smoke = json(smokeFile), native = json(nativeFile);
  const socleMatch = json(matchFile), socleRunner = json(runnerFile);
  requireValue(record.smokeSha256 === (await identity(smokeFile, 'prod-light-smoke.json')).sha256, 'Light receipt changed.');
  requireValue(record.socleMatchSha256 === (await identity(matchFile, 'socle-match.json')).sha256, 'Socle match proof changed.');
  requireValue(record.socleRunnerSha256 === (await identity(runnerFile, 'socle-runner.json')).sha256, 'Socle runner proof changed.');
  requireValue(record.socleIndexSha256 === socleMatch.indexSha256, 'Socle index SHA-256 differs from socle-match proof.');
  requireValue(smoke.nativeProofSha256 === (await identity(nativeFile, 'native-demo-PROD-LIGHT.json')).sha256,
    'Light smoke digest or native proof differs.');
  for (const field of ['sourceCommit', 'runId', 'runAttempt', 'version', 'archiveSha256', 'executableSha256', 'runtimeMode'])
    requireValue(smoke[field] === record[field], 'Light smoke provenance differs: ' + field);
  requireValue(smoke.schemaVersion === 1 && smoke.kind === 'pesto.release-evergreen-smoke' && smoke.packageChannel === 'PROD'
    && smoke.success === true && smoke.ready === true && smoke.closeReturned === true && smoke.adQualification === false
    && smoke.bundledWebView2Absent === true && typeof smoke.browserVersion === 'string'
    && /^[1-9]\d*\.\d+\.\d+\.\d+$/i.test(smoke.browserVersion),
  'Light requires a successful isolated Evergreen smoke bound to the extracted archive.');
  requireValue(native.schemaVersion === 1
    && native.kind === 'pesto.windows-demo-qualification' && native.channel === 'PROD' && native.version === version
    && native.distribution === 'official' && native.executableSha256 === record.executableSha256
    && native.runtimeMode === 'evergreen' && native.runtimeSource === 'evergreen'
    && native.browserVersion === smoke.browserVersion
    && native.success === true && native.ready === true && native.closeReturned === true
    && native.realProfileCreated === false && native.adQualification === false && native.binaryUpdateQualification === false
    && native.coexistence?.success === true, 'Light requires a real successful isolated Evergreen smoke.');
  requireValue(socleMatch.schemaVersion === 1 && socleMatch.kind === 'pesto.socle-match' && socleMatch.success === true
    && socleMatch.version === SOCLE_VERSION, 'Socle match proof is not valid.');
  requireValue(socleRunner.schemaVersion === 1 && socleRunner.kind === 'pesto.socle-runner' && socleRunner.success === true
    && socleRunner.exactCopyValid === true && socleRunner.fingerprintUnchanged === true
    && socleRunner.demoRuntimeSource === 'evergreen' && socleRunner.alteredRefusedCode === 'package.socle',
  'Socle runner proof is not valid.');
  const assets = [];
  const asset = await identity(join(root, 'PROD-LIGHT', 'Pesto_V2_PROD-LIGHT_official.zip'), `Pesto_V2_PRODLIGHT_${version}.zip`);
  requireValue(asset.sha256 === record.archiveSha256, 'ZIP differs from the exact Windows-tested artifact: PROD-LIGHT');
  assets.push(asset);
  assets.push(await identity(join(root, 'Pesto_V2_Windows_evidence.zip'), `Pesto_V2_Windows_evidence_${version}.zip`));
  const tag = 'v' + version;
  const manifest = {schemaVersion: 1, kind: 'pesto.release', repository, version, tag, sourceCommit: context.sha,
    workflowRunId: context.runId, workflowRunAttempt: context.runAttempt, distribution: 'official', qualification: 'unqualified',
    adQualified: false, windows: records, assets: assets.map(({name, bytes, sha256}) => ({name, bytes, sha256}))};
  const manifestPath = join(root, 'release-manifest.json');
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n', {flag: 'wx'});
  assets.push(await identity(manifestPath, 'release-manifest.json'));
  const sumsPath = join(root, 'SHA256SUMS');
  writeFileSync(sumsPath, assets.map(asset => `${asset.sha256}  ${asset.name}`).join('\n') + '\n', {flag: 'wx'});
  assets.push(await identity(sumsPath, 'SHA256SUMS'));
  const body = `Pesto ${version} pour Windows x64 — pack LIGHT seul.\n\n`
    + 'Le runtime WebView2 Evergreen installé sur le poste est utilisé en priorité. S\u2019il est absent, extrayez le pack WebView2 du Socle dans wad\\ : '
    + `[${SOCLE_VERSION}](${SOCLE_RELEASE_URL})\n\n`
    + 'Une installation 2.0.9 PROD exige une nouvelle installation ; vous pouvez recopier son wad\\runtime\\webview2 s\u2019il est identique au Socle.\n\n'
    + `[Sources Git](https://github.com/${repository}/tree/${context.sha}) · [Validation Windows](https://github.com/${repository}/actions/runs/${context.runId}/attempts/${context.runAttempt}).\n\n`
    + 'Le pack LIGHT a passé les essais de mise à jour et de retour arrière. Le pack extrait de son ZIP a démarré et fermé la démonstration avec Evergreen. '
    + 'Les preuves Windows, le manifeste de publication et SHA256SUMS sont joints. Qualification AD réelle en attente.';
  return {...context, version, tag, body, assets};
}
function checkRef(ref, sha) {
  requireValue(ref?.object?.type === 'commit' && ref.object.sha === sha, 'Git reference no longer points to the exact tested commit.');
}
function checkDraft(release, plan) {
  requireValue(Number.isSafeInteger(release?.id) && release.id > 0 && release.tag_name === plan.tag
    && release.target_commitish === plan.sha && release.draft === true && release.prerelease === false,
  'Release is not the owned draft for the exact source commit.');
}
function checkAsset(actual, expected) {
  requireValue(actual?.name === expected.name && actual.state === 'uploaded' && actual.size === expected.bytes
    && actual.digest === 'sha256:' + expected.sha256, 'GitHub asset digest/size/name differs: ' + expected.name);
}
export async function publishRelease(plan, request) {
  const run = await request(`${prefix}/actions/runs/${plan.runId}`);
  requireValue(run.head_sha === plan.sha && run.head_branch === 'master' && run.event === 'workflow_dispatch'
    && run.path === '.github/workflows/pesto-v2.yml' && String(run.run_attempt) === plan.runAttempt,
  'Workflow run does not match the publication context.');
  const jobs = await request(`${prefix}/actions/runs/${plan.runId}/attempts/${plan.runAttempt}/jobs?per_page=100`);
  const windows = jobs.jobs?.filter(job => job.name === 'windows-critical');
  requireValue(windows?.length === 1 && windows[0].status === 'completed' && windows[0].conclusion === 'success',
    'The Windows job for this exact attempt has not succeeded.');
  checkRef(await request(`${prefix}/git/ref/heads/master`), plan.sha);
  const encodedTag = encodeURIComponent(plan.tag);
  requireValue(await request(`${prefix}/git/ref/tags/${encodedTag}`, {allow404: true}) === null,
    'The release tag already exists; nothing is overwritten.');
  requireValue(await request(`${prefix}/releases/tags/${encodedTag}`, {allow404: true}) === null,
    'The release already exists; nothing is overwritten.');
  // Atomically reserve the exact lightweight tag. On failure it and any draft remain inspectable, never replaced/deleted.
  checkRef(await request(`${prefix}/git/refs`, {method: 'POST', json: {ref: 'refs/tags/' + plan.tag, sha: plan.sha}}), plan.sha);
  const draft = await request(`${prefix}/releases`, {method: 'POST', json: {
    tag_name: plan.tag, target_commitish: plan.sha, name: 'Pesto ' + plan.version,
    body: plan.body, draft: true, prerelease: false
  }});
  checkDraft(draft, plan);
  console.log('Draft created: ' + draft.id + '. Any failure preserves the draft and tag for manual inspection.');
  for (const asset of plan.assets) {
    const current = await identity(asset.path, asset.name);
    requireValue(current.sha256 === asset.sha256 && current.bytes === asset.bytes, 'Local release asset changed before upload.');
    checkAsset(await request(`${prefix}/releases/${draft.id}/assets?name=${encodeURIComponent(asset.name)}`,
      {method: 'POST', upload: asset}), asset);
  }
  const uploaded = await request(`${prefix}/releases/${draft.id}/assets?per_page=100`);
  requireValue(Array.isArray(uploaded) && uploaded.length === plan.assets.length, 'Release assets are incomplete or contain an unexpected file.');
  for (const asset of plan.assets) {
    const matches = uploaded.filter(item => item.name === asset.name);
    requireValue(matches.length === 1, 'Duplicate/missing release asset.');
    checkAsset(matches[0], asset);
  }
  checkRef(await request(`${prefix}/git/ref/tags/${encodedTag}`), plan.sha);
  checkRef(await request(`${prefix}/git/ref/heads/master`), plan.sha);
  checkDraft(await request(`${prefix}/releases/${draft.id}`), plan);
  const released = await request(`${prefix}/releases/${draft.id}`, {method: 'PATCH', json: {draft: false, prerelease: false, make_latest: 'true'}});
  requireValue(released.tag_name === plan.tag && released.target_commitish === plan.sha && released.draft === false
    && released.prerelease === false && released.html_url === `https://github.com/${repository}/releases/tag/${plan.tag}`,
  'Publication response is not the expected release; inspect GitHub before retrying.');
  return released.html_url;
}
export function githubClient(token) {
  requireValue(typeof token === 'string' && token.length > 0, 'GITHUB_TOKEN is required.');
  return async (path, options = {}) => {
    requireValue(path.startsWith(prefix + '/'), 'Unexpected repository endpoint.');
    const headers = {'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'Pesto-V2-explicit-release'};
    let body;
    if (options.upload) {
      headers['Content-Type'] = 'application/octet-stream'; headers['Content-Length'] = String(options.upload.bytes);
      body = createReadStream(options.upload.path);
    } else if (options.json) { headers['Content-Type'] = 'application/json'; body = JSON.stringify(options.json); }
    const response = await fetch('https://' + (options.upload ? 'uploads.github.com' : 'api.github.com') + path,
      {method: options.method ?? 'GET', headers, body, redirect: 'error', ...(options.upload ? {duplex: 'half'} : {})});
    if (response.status === 404 && options.allow404) return null;
    requireValue(response.ok, `GitHub ${options.method ?? 'GET'} ${path.split('?')[0]} returned ${response.status}; no automatic retry.`);
    const chunks = []; let bytes = 0;
    for await (const chunk of response.body) {
      bytes += chunk.length; requireValue(bytes <= 4 * 1024 * 1024, 'GitHub JSON response is too large.'); chunks.push(chunk);
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  };
}
if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  try {
    requireValue(process.argv.length === 3, 'Usage: node tools/release/publish-release.mjs <downloaded-release-directory>');
    const context = contextFromEnv(process.env);
    const spec = json(fileURLToPath(new URL('../pack/pack-manifest.json', import.meta.url)));
    const plan = await prepareRelease(process.argv[2], context, spec.version);
    console.log(await publishRelease(plan, githubClient(process.env.GITHUB_TOKEN)));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
