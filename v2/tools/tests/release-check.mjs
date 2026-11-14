// Synthetic release transaction: tiny non-executable files, mocked GitHub only, no token or network.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {appendFileSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {contextFromEnv, prepareRelease, publishRelease, repository} from '../release/publish-release.mjs';

const temporary = mkdtempSync(join(realpathSync(tmpdir()), 'pesto-release-check-'));
const context = {sha: 'a'.repeat(40), runId: '123', runAttempt: '2'};
const env = {GITHUB_ACTIONS: 'true', GITHUB_REPOSITORY: repository, GITHUB_EVENT_NAME: 'workflow_dispatch',
  GITHUB_REF: 'refs/heads/master', PESTO_PUBLISH_RELEASE: 'true', PESTO_EXPECTED_SOURCE_SHA: context.sha,
  GITHUB_SHA: context.sha, GITHUB_RUN_ID: context.runId, GITHUB_RUN_ATTEMPT: context.runAttempt};
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
let checks = 0, sequence = 0;
async function check(name, action) { await action(); checks++; console.log('OK   ' + name); }
function fixture(change = () => {}) {
  const root = join(temporary, String(++sequence)); mkdirSync(join(root, 'evidence'), {recursive: true});
  mkdirSync(join(root, 'PROD-LIGHT'));
  const bytes = Buffer.from('EXPLICIT SYNTHETIC NON-ZIP PROD-LIGHT');
  writeFileSync(join(root, 'PROD-LIGHT', 'Pesto_V2_PROD-LIGHT_official.zip'), bytes);
  const record = {channel: 'PROD', edition: 'PROD-LIGHT', sourceCommit: context.sha, runId: context.runId, runAttempt: context.runAttempt,
    version: '2.0.10', distribution: 'official', qualification: 'unqualified', archiveSha256: hash(bytes), executableSha256: 'b'.repeat(64),
    adQualified: false, runtimeMode: 'evergreen', runtimeSource: 'evergreen',
    nativeRollbackUiQualified: false, nativeStartupDemoQualified: true, nativeDemoCoexistenceQualified: true,
    nativeConfigurationQualified: true, nativeConfigurationUiQualified: true, nativeUpdatePreparationUiQualified: true,
    nativeUpdateInstallUiQualified: true, nativeServiceRollbackAfterUiInstallQualified: true, nativeUpdateQualified: true,
    distinctUpdateBuilds: true, baselineInPlaceUpdateQualified: true, baselineFormatRefusalQualified: false,
    newInstallationRequiredFromBaseline: false, updateBaselineSourceCommit: 'd'.repeat(40),
    uiUpdateFromVersion: '2.0.9', uiUpdateFromSourceCommit: 'e'.repeat(40), uiUpdateFromArchiveSha256: 'c'.repeat(64),
    socleVersion: '156.0.4314.42', socleReleaseUrl: 'https://github.com/M4D135/socle-windows/releases/tag/webview2-156.0.4314.42',
    soclePreservationQualified: true, socleIndexSha256: '1'.repeat(64)};
  const records = [record];
  const sdk = {sourceCommit: context.sha, sourceHead: context.sha, sdkVersion: '10.0.302', expectedSdkVersion: '10.0.302', rollForward: 'disable', success: true};
  const native = {schemaVersion: 1, kind: 'pesto.windows-demo-qualification', channel: 'PROD', version: '2.0.10', distribution: 'official',
    executableSha256: record.executableSha256, runtimeMode: 'evergreen', runtimeSource: 'evergreen', browserVersion: '140.0.100.12',
    ready: true, closeReturned: true, success: true, adQualification: false, binaryUpdateQualification: false, realProfileCreated: false, coexistence: {success: true}};
  const smoke = {schemaVersion: 1, kind: 'pesto.release-evergreen-smoke', packageChannel: 'PROD', version: '2.0.10', sourceCommit: context.sha,
    runId: context.runId, runAttempt: context.runAttempt, archiveSha256: record.archiveSha256, executableSha256: record.executableSha256,
    runtimeMode: 'evergreen', browserVersion: native.browserVersion, ready: true, closeReturned: true, success: true, adQualification: false, bundledWebView2Absent: true};
  const socleMatch = {schemaVersion: 1, kind: 'pesto.socle-match', success: true, version: '156.0.4314.42',
    cabSha256: 'a'.repeat(64), executableSha256: 'b'.repeat(64), indexSha256: record.socleIndexSha256,
    fileCount: 42, bytes: 100000, root: 'wad/runtime/webview2'};
  const socleRunner = {schemaVersion: 1, kind: 'pesto.socle-runner', success: true, exactCopyValid: true,
    fingerprintUnchanged: true, demoRuntimeSource: 'evergreen', alteredRefusedCode: 'package.socle',
    withoutEvergreenQualified: false, withoutEvergreenNote: 'Le démarrage sur le Socle sans Evergreen est qualifié par la recette sur banc, pas sur le runner.'};
  const engineReport = {schemaVersion: 1, kind: 'pesto.engine-socle-tests', passed: true, tests: ['InstallCarriesTheSocleAndRollbackKeepsIt',
    'SocleExactCopyIsAcceptedOutsideThePackIdentity', 'SocleChangedExtraMissingOrEmptyIsRefused', 'InstallWithoutSocleNeverCreatesOne',
    'EmbeddedSocleIndexLoadsTheRealRuntimeInventory']};
  change({records, record, sdk, root, native, smoke, socleMatch, socleRunner, engineReport});
  const nativeBytes = JSON.stringify(native); writeFileSync(join(root, 'evidence/native-demo-PROD-LIGHT.json'), nativeBytes);
  smoke.nativeProofSha256 ??= hash(nativeBytes);
  const smokeBytes = JSON.stringify(smoke); writeFileSync(join(root, 'evidence/prod-light-smoke.json'), smokeBytes);
  record.smokeSha256 ??= hash(smokeBytes);
  record.socleMatchSha256 ??= hash(JSON.stringify(socleMatch));
  record.socleRunnerSha256 ??= hash(JSON.stringify(socleRunner));
  writeFileSync(join(root, 'evidence/socle-match.json'), JSON.stringify(socleMatch));
  writeFileSync(join(root, 'evidence/socle-runner.json'), JSON.stringify(socleRunner));
  writeFileSync(join(root, 'evidence/engine-socle-tests.json'), JSON.stringify(engineReport));
  writeFileSync(join(root, 'evidence/artifacts.json'), '\uFEFF' + JSON.stringify(records));
  writeFileSync(join(root, 'evidence/candidate-sdk.json'), JSON.stringify(sdk));
  writeFileSync(join(root, 'Pesto_V2_Windows_evidence.zip'), 'EXPLICIT SYNTHETIC EVIDENCE');
  return root;
}
function githubMock(plan, override = () => undefined) {
  const state = {calls: [], writes: [], assets: [], tag: null, draft: null, published: false};
  const request = async (path, options = {}) => {
    state.calls.push({path, method: options.method ?? 'GET'});
    if (options.method && options.method !== 'GET') state.writes.push(options.method + ' ' + path);
    const altered = override(path, options, state);
    if (altered !== undefined) return altered;
    if (path.endsWith('/actions/runs/123')) return {head_sha: plan.sha, head_branch: 'master', event: 'workflow_dispatch',
      path: '.github/workflows/pesto-v2.yml', run_attempt: 2};
    if (path.endsWith('/attempts/2/jobs?per_page=100')) return {jobs: [{name: 'windows-critical', status: 'completed', conclusion: 'success'}]};
    if (path.endsWith('/git/ref/heads/master')) return {object: {type: 'commit', sha: plan.sha}};
    if (path.includes('/git/ref/tags/')) return state.tag;
    if (path.includes('/releases/tags/')) return null;
    if (path.endsWith('/git/refs') && options.method === 'POST') {
      assert.equal(options.json.ref, 'refs/tags/' + plan.tag); assert.equal(options.json.sha, plan.sha);
      return state.tag = {object: {type: 'commit', sha: plan.sha}};
    }
    if (path.endsWith('/releases') && options.method === 'POST') {
      assert.equal(options.json.draft, true); assert.equal(options.json.prerelease, false);
      return state.draft = {id: 99, ...options.json};
    }
    if (options.upload) {
      assert.equal(state.draft.draft, true);
      const asset = {name: options.upload.name, size: options.upload.bytes, state: 'uploaded',
        digest: 'sha256:' + hash(readFileSync(options.upload.path))};
      state.assets.push(asset); return asset;
    }
    if (path.endsWith('/releases/99/assets?per_page=100')) return state.assets;
    if (path.endsWith('/releases/99') && options.method === 'PATCH') {
      assert.equal(state.assets.length, 4); assert.equal(options.json.draft, false);
      state.published = true;
      return {...state.draft, draft: false, html_url: `https://github.com/${repository}/releases/tag/${plan.tag}`};
    }
    if (path.endsWith('/releases/99')) return state.draft;
    throw new Error('Unexpected mock endpoint: ' + path);
  };
  return {state, request};
}
try {
  await check('only explicit dispatch, exact SHA and master are admitted', () => assert.deepEqual(contextFromEnv(env), context));
  for (const [key, value] of [['GITHUB_ACTIONS', 'false'], ['GITHUB_REPOSITORY', 'other/pesto'], ['GITHUB_EVENT_NAME', 'push'],
    ['GITHUB_REF', 'refs/heads/feature'], ['PESTO_PUBLISH_RELEASE', 'false'], ['PESTO_EXPECTED_SOURCE_SHA', 'b'.repeat(40)],
    ['GITHUB_SHA', 'bad'], ['GITHUB_RUN_ID', '0'], ['GITHUB_RUN_ATTEMPT', '1x']])
    await check('refuse context ' + key, () => assert.throws(() => contextFromEnv({...env, [key]: value})));
  for (const [name, change] of [
    ['foreign source SHA', ({record}) => { record.sourceCommit = 'b'.repeat(40); }],
    ['another workflow run', ({record}) => { record.runId = '124'; }],
    ['older attempt', ({record}) => { record.runAttempt = '1'; }],
    ['candidate instead of official', ({record}) => { record.distribution = 'candidate'; }],
    ['invented AD qualification', ({record}) => { record.adQualified = true; }],
    ['invented complete qualification', ({record}) => { record.qualification = 'qualified'; }],
    ['invented UI rollback', ({record}) => { record.nativeRollbackUiQualified = true; }],
    ['missing native success', ({record}) => { record.nativeUpdateQualified = false; }],
    ['PROD refuses instead of updating', ({record}) => { record.baselineInPlaceUpdateQualified = false; }],
    ['different light executable', ({record}) => { record.executableSha256 = 'c'.repeat(64); }],
    ['unrelated light source', ({smoke}) => { smoke.sourceCommit = 'd'.repeat(40); }],
    ['unrelated light run', ({smoke}) => { smoke.runId = '456'; }],
    ['unrelated light attempt', ({smoke}) => { smoke.runAttempt = '3'; }],
    ['light contains fixed WebView2', ({smoke}) => { smoke.bundledWebView2Absent = false; }],
    ['light archive replaced', ({root}) => appendFileSync(join(root, 'PROD-LIGHT/Pesto_V2_PROD-LIGHT_official.zip'), 'changed')],
    ['unbound light receipt', ({record}) => { record.smokeSha256 = 'f'.repeat(64); }],
    ['unbound raw smoke', ({smoke}) => { smoke.nativeProofSha256 = 'f'.repeat(64); }],
    ['fixed runtime in record', ({record}) => { record.runtimeMode = 'fixed'; }],
    ['fixed runtime in native', ({native}) => { native.runtimeMode = 'fixed'; }],
    ['unreported browser version', ({native,smoke}) => { native.browserVersion = smoke.browserVersion = 'unknown'; }],
    ['browser version differs from receipt', ({native}) => { native.browserVersion = '110.0.1.2'; }],
    ['smoke not closed', ({native}) => { native.closeReturned = false; }],
    ['smoke claims AD', ({native}) => { native.adQualification = true; }],
    ['unrelated source checkout', ({sdk}) => { sdk.sourceHead = 'd'.repeat(40); }],
    ['wrong version', ({record}) => { record.version = '2.0.1'; }],
    ['missing publishable record', ({records}) => { records.pop(); }],
    ['duplicate publishable record', ({records, record}) => { records.push({...record}); }],
    ['ZIP changed after testing', ({root}) => { appendFileSync(join(root, 'PROD-LIGHT/Pesto_V2_PROD-LIGHT_official.zip'), 'changed'); }],
    ['different SDK', ({sdk}) => { sdk.sdkVersion = '10.0.401'; }],
    ['SDK proof from other source', ({sdk}) => { sdk.sourceCommit = 'b'.repeat(40); }],
    ['socle index SHA wrong', ({record}) => { record.socleIndexSha256 = '9'.repeat(64); }],
    ['socle match SHA wrong', ({record}) => { record.socleMatchSha256 = '9'.repeat(64); }],
    ['socle runner SHA wrong', ({record}) => { record.socleRunnerSha256 = '9'.repeat(64); }],
    ['socle preservation not qualified', ({record}) => { record.soclePreservationQualified = false; }],
    ['socle version wrong', ({record}) => { record.socleVersion = '155.0.0.0'; }],
    ['socle release URL wrong', ({record}) => { record.socleReleaseUrl = 'https://example.com'; }],
    ['engine test missing', ({engineReport}) => { engineReport.tests = engineReport.tests.filter(t => t !== 'InstallCarriesTheSocleAndRollbackKeepsIt'); }],
    ['engine test failed', ({engineReport}) => { engineReport.passed = false; }],
    ['runtimeSource not evergreen', ({record}) => { record.runtimeSource = 'fixed'; }],
    ['native runtimeSource not evergreen', ({native}) => { native.runtimeSource = 'fixed'; }]
  ]) await check('refuse local proof: ' + name, async () => {
    await assert.rejects(prepareRelease(fixture(change), context, '2.0.10'));
  });
  const root = fixture(), plan = await prepareRelease(root, context, '2.0.10');
  await check('four assets bind the untouched ZIP, evidence, manifest and sums', () => {
    assert.equal(plan.assets.length, 4);
    assert.equal(plan.tag, 'v2.0.10');
    const manifest = JSON.parse(readFileSync(join(root, 'release-manifest.json')));
    assert.equal(manifest.sourceCommit, context.sha); assert.equal(manifest.adQualified, false);
    assert.equal(manifest.qualification, 'unqualified');
    for (const asset of plan.assets.slice(0, 3)) assert.ok(readFileSync(join(root, 'SHA256SUMS'), 'utf8').includes(asset.sha256 + '  ' + asset.name));
  });
  await check('single public asset is PRODLIGHT and body mentions Socle link without two-editions phrase', () => {
    assert.deepEqual(plan.assets.slice(0,2).map(asset => asset.name), ['Pesto_V2_PRODLIGHT_2.0.10.zip','Pesto_V2_Windows_evidence_2.0.10.zip']);
    assert.equal(plan.assets[0].name.includes('_PROD_'), false);
    assert.equal(JSON.parse(readFileSync(join(root,'release-manifest.json'))).windows.some(r => r.channel === 'DEV'), false);
    assert.ok(plan.body.includes('pack LIGHT seul'));
    assert.ok(plan.body.includes('Evergreen'));
    assert.ok(plan.body.includes('https://github.com/M4D135/socle-windows/releases/tag/webview2-156.0.4314.42'));
    assert.ok(!plan.body.includes('deux éditions'));
    assert.ok(!plan.body.includes('Les deux éditions'));
    assert.ok(plan.body.includes('nouvelle installation'));
  });
  await check('publication files are CreateNew and never overwritten', () => assert.rejects(prepareRelease(root, context, '2.0.10')));
  await check('successful transaction publishes only after four GitHub digests match', async () => {
    const mock = githubMock(plan); const url = await publishRelease(plan, mock.request);
    assert.equal(url, `https://github.com/${repository}/releases/tag/v2.0.10`); assert.equal(mock.state.published, true);
    assert.equal(mock.state.writes.at(-1), 'PATCH /repos/M4D135/pesto/releases/99');
  });
  for (const [name, override] of [
    ['run source mismatch', path => path.endsWith('/actions/runs/123') ? {head_sha: 'c'.repeat(40)} : undefined],
    ['Windows pending', path => path.includes('/jobs?') ? {jobs: [{name: 'windows-critical', status: 'in_progress', conclusion: null}]} : undefined],
    ['Windows failure', path => path.includes('/jobs?') ? {jobs: [{name: 'windows-critical', status: 'completed', conclusion: 'failure'}]} : undefined],
    ['master advanced', path => path.endsWith('/git/ref/heads/master') ? {object: {type: 'commit', sha: 'c'.repeat(40)}} : undefined],
    ['tag already exists', path => path.includes('/git/ref/tags/') ? {object: {type: 'commit', sha: plan.sha}} : undefined],
    ['release already exists', path => path.includes('/releases/tags/') ? {id: 98, draft: true} : undefined]
  ]) await check('preflight refuses without any GitHub mutation: ' + name, async () => {
    const mock = githubMock(plan, override); await assert.rejects(publishRelease(plan, mock.request));
    assert.equal(mock.state.writes.length, 0);
  });
  for (const [name, override] of [
    ['upload digest missing', (path, options) => options.upload ? {name: options.upload.name, size: options.upload.bytes, state: 'uploaded'} : undefined],
    ['upload digest wrong', (path, options) => options.upload ? {name: options.upload.name, size: options.upload.bytes, state: 'uploaded', digest: 'sha256:' + 'c'.repeat(64)} : undefined],
    ['upload failed', (path, options) => { if (options.upload) throw new Error('explicit upload failure'); }],
    ['remote assets incomplete', path => path.includes('/assets?per_page=') ? [] : undefined],
    ['foreign asset', (path, options, state) => path.includes('/assets?per_page=') ? [...state.assets, {name: 'foreign'}] : undefined],
    ['tag changed before publication', (path, options, state) => path.includes('/git/ref/tags/') && state.tag ? {object: {type: 'commit', sha: 'c'.repeat(40)}} : undefined],
    ['master changed during upload', (path, options, state) => path.endsWith('/git/ref/heads/master') && state.assets.length ? {object: {type: 'commit', sha: 'c'.repeat(40)}} : undefined],
    ['draft changed by another caller', (path, options, state) => path.endsWith('/releases/99') && !options.method ? {...state.draft, target_commitish: 'c'.repeat(40)} : undefined]
  ]) await check('failure retains draft and never publishes: ' + name, async () => {
    const mock = githubMock(plan, override); await assert.rejects(publishRelease(plan, mock.request));
    assert.equal(mock.state.published, false); assert.equal(mock.state.draft.draft, true);
    assert.ok(mock.state.writes.every(write => !write.startsWith('PATCH ') && !write.startsWith('DELETE ')));
  });
  await check('changed local ZIP after preparation is never uploaded or published', async () => {
    const changedRoot = fixture(), changedPlan = await prepareRelease(changedRoot, context, '2.0.10');
    appendFileSync(changedPlan.assets[0].path, 'changed');
    const mock = githubMock(changedPlan); await assert.rejects(publishRelease(changedPlan, mock.request));
    assert.equal(mock.state.assets.length, 0); assert.equal(mock.state.published, false);
  });
  console.log(`\n${checks}/${checks} release checks passed; no GitHub call, Windows execution or AD qualification.`);
} finally { rmSync(temporary, {recursive: true, force: true}); }
