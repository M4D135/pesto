// Synthetic files only; no real GitHub run, token, publication or network.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {appendFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, renameSync,
  rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {sealLabHandoff, restoreLabHandoff} from '../release/lab-handoff.mjs';

const temporary = mkdtempSync(join(realpathSync(tmpdir()), 'pesto-handoff-check-'));
const sha = 'a'.repeat(40), hash = bytes => createHash('sha256').update(bytes).digest('hex');
let checks = 0, sequence = 0;
async function check(name, action) { await action(); checks++; console.log('OK   ' + name); }
function fixture(runner = 'pesto-lab') {
  const root = join(temporary, String(++sequence)), workspace = join(root, '_work/pesto/pesto');
  const out = join(workspace, 'v2/out'), release = join(workspace, 'release');
  mkdirSync(join(out, 'evidence/nested'), {recursive: true}); mkdirSync(join(root, '_work/_temp'));
  const env = {GITHUB_ACTIONS: 'true', GITHUB_REPOSITORY: 'M4D135/pesto', GITHUB_EVENT_NAME: 'workflow_dispatch',
    GITHUB_REF: 'refs/heads/master', PESTO_PUBLISH_RELEASE: 'true', PESTO_EXPECTED_SOURCE_SHA: sha,
    GITHUB_SHA: sha, GITHUB_RUN_ID: '123', GITHUB_RUN_ATTEMPT: '2', RUNNER_OS: 'Windows',
    RUNNER_ENVIRONMENT: 'self-hosted', RUNNER_NAME: runner, PESTO_SELECTED_RUNNER: runner, GITHUB_JOB: 'windows-critical',
    GITHUB_WORKSPACE: workspace, RUNNER_TEMP: join(root, '_work/_temp')};
  const zipBytes = Buffer.from('EXPLICIT SYNTHETIC NON-ZIP PROD-LIGHT');
  writeFileSync(join(out, 'Pesto_V2_PROD-LIGHT_official.zip'), zipBytes);
  const nativeBytes = JSON.stringify({synthetic: true, success: true, runtimeMode: 'evergreen', runtimeSource: 'evergreen'});
  writeFileSync(join(out, 'evidence/native-demo-PROD-LIGHT.json'), nativeBytes);
  const socleMatchBytes = JSON.stringify({schemaVersion: 1, kind: 'pesto.socle-match', success: true, version: '156.0.4314.42',
    cabSha256: 'd'.repeat(64), executableSha256: 'e'.repeat(64), indexSha256: 'f'.repeat(64), fileCount: 42, bytes: 100000, root: 'wad/runtime/webview2'});
  writeFileSync(join(out, 'evidence/socle-match.json'), socleMatchBytes);
  const socleRunnerBytes = JSON.stringify({schemaVersion: 1, kind: 'pesto.socle-runner', success: true, exactCopyValid: true,
    fingerprintUnchanged: true, demoRuntimeSource: 'evergreen', alteredRefusedCode: 'package.socle',
    withoutEvergreenQualified: false, withoutEvergreenNote: 'Le démarrage sur le Socle sans Evergreen est qualifié par la recette sur banc, pas sur le runner.'});
  writeFileSync(join(out, 'evidence/socle-runner.json'), socleRunnerBytes);
  const record = {channel: 'PROD', edition: 'PROD-LIGHT', sourceCommit: sha, runId: '123', runAttempt: '2',
    distribution: 'official', version: '2.0.10', executableSha256: 'b'.repeat(64), runtimeMode: 'evergreen',
    runtimeSource: 'evergreen', archiveSha256: hash(zipBytes),
    smokeSha256: '0'.repeat(64), socleVersion: '156.0.4314.42', socleIndexSha256: 'f'.repeat(64),
    socleMatchSha256: hash(socleMatchBytes), socleRunnerSha256: hash(socleRunnerBytes),
    soclePreservationQualified: true, socleReleaseUrl: 'https://github.com/M4D135/socle-windows/releases/tag/webview2-156.0.4314.42'};
  const smokeBytes = JSON.stringify({schemaVersion: 1, kind: 'pesto.release-evergreen-smoke', packageChannel: 'PROD',
    nativeProofSha256: hash(nativeBytes), success: true, ready: true, closeReturned: true, adQualification: false,
    bundledWebView2Absent: true, runtimeMode: 'evergreen', runtimeSource: 'evergreen', browserVersion: '140.0.100.12'});
  writeFileSync(join(out, 'evidence/prod-light-smoke.json'), smokeBytes);
  record.smokeSha256 = hash(smokeBytes);
  writeFileSync(join(out, 'evidence/artifacts.json'), '\uFEFF' + JSON.stringify([record]));
  writeFileSync(join(out, 'evidence/nested/report.json'), '{"synthetic":true}');
  writeFileSync(join(out, 'evidence/empty.log'), '');
  return {root, workspace, out, release, env, records: [record], batch: join(root, `pesto-release-handoffs/123-2-${sha}`)};
}
async function sealed() {
  const f = fixture(), result = await sealLabHandoff(f.out, f.env);
  return {...f, result, restoreEnv: {...f.env, GITHUB_JOB: 'publish-release', PESTO_LAB_HANDOFF_SHA256: result.manifestSha256}};
}
function changeManifest(f, change) {
  const path = join(f.batch, 'handoff.json'), value = JSON.parse(readFileSync(path)); change(value);
  const bytes = JSON.stringify(value); writeFileSync(path, bytes); f.restoreEnv.PESTO_LAB_HANDOFF_SHA256 = hash(bytes);
}
async function refusedRestore(f, expression) {
  await assert.rejects(restoreLabHandoff(f.release, f.restoreEnv), expression);
  assert.equal(existsSync(f.release), false, 'Invalid input must not create a publication directory');
}
function directoryLink(target, path) { symlinkSync(target, path, process.platform === 'win32' ? 'junction' : 'dir'); }
try {
  await check('round trip preserves the ZIP, every proof and empty logs; receipt binds the job output', async () => {
    const f = await sealed(), manifest = JSON.parse(readFileSync(join(f.batch, 'handoff.json')));
    assert.equal(hash(readFileSync(join(f.batch, 'handoff.json'))), f.result.manifestSha256);
    assert.equal(f.result.fileCount, 8);
    // Actions cleans the checkout between jobs. The sealed batch must survive that cleanup.
    rmSync(f.workspace, {recursive: true}); mkdirSync(f.workspace);
    assert.deepEqual(await restoreLabHandoff(f.release, f.restoreEnv), f.result);
    for (const entry of manifest.files) {
      const bytes = readFileSync(join(f.release, entry.path));
      assert.equal(bytes.length, entry.bytes); assert.equal(hash(bytes), entry.sha256);
    }
    const receipt = JSON.parse(readFileSync(join(f.release, 'evidence/lab-transfer-receipt.json')));
    assert.equal(receipt.manifestSha256, f.result.manifestSha256); assert.equal(receipt.sourceCommit, sha);
    assert.equal(receipt.runId, '123'); assert.equal(receipt.runAttempt, '2'); assert.deepEqual(receipt.files, manifest.files);
  });
  await check('only the selected dedicated runner can restore its batch', async () => {
    const f = fixture('pesto-ci'), result = await sealLabHandoff(f.out, f.env);
    const restoreEnv = {...f.env, GITHUB_JOB: 'publish-release', PESTO_LAB_HANDOFF_SHA256: result.manifestSha256};
    await assert.rejects(restoreLabHandoff(f.release, {...restoreEnv, PESTO_SELECTED_RUNNER: 'pesto-lab', RUNNER_NAME: 'pesto-lab'}), /identity/);
    assert.equal(existsSync(f.release), false);
    assert.deepEqual(await restoreLabHandoff(f.release, restoreEnv), result);
    assert.equal(JSON.parse(readFileSync(join(f.release, 'evidence/lab-transfer-receipt.json'))).runnerName, 'pesto-ci');
  });
  await check('existing sealed batch is refused without overwrite', async () => {
    const f = await sealed(), before = readFileSync(join(f.batch, 'handoff.json'));
    await assert.rejects(sealLabHandoff(f.out, f.env), /already exists/);
    assert.deepEqual(readFileSync(join(f.batch, 'handoff.json')), before);
  });
  for (const [name, mutate] of [
    ['light ZIP changed after tests', f => appendFileSync(join(f.out, 'Pesto_V2_PROD-LIGHT_official.zip'), 'changed')],
    ['light receipt changed', f => appendFileSync(join(f.out, 'evidence/prod-light-smoke.json'), ' ')],
    ['socle-match changed', f => appendFileSync(join(f.out, 'evidence/socle-match.json'), ' ')],
    ['socle-runner changed', f => appendFileSync(join(f.out, 'evidence/socle-runner.json'), ' ')],
    ['socle version wrong', f => { f.records[0].socleVersion = '155.0.0.0'; }],
    ['socle preservation not qualified', f => { f.records[0].soclePreservationQualified = false; }],
    ['foreign source', f => { f.records[0].sourceCommit = 'b'.repeat(40); }],
    ['foreign run', f => { f.records[0].runId = '124'; }],
    ['old attempt', f => { f.records[0].runAttempt = '1'; }],
    ['candidate distribution', f => { f.records[0].distribution = 'candidate'; }],
    ['wrong edition', f => { f.records[0].edition = 'PROD'; }]
  ]) await check('refuse seal: ' + name, async () => {
    const f = fixture(); mutate(f); writeFileSync(join(f.out, 'evidence/artifacts.json'), JSON.stringify(f.records));
    await assert.rejects(sealLabHandoff(f.out, f.env)); assert.equal(existsSync(f.batch), false);
  });
  for (const [key, value] of [['RUNNER_OS', 'Linux'], ['RUNNER_ENVIRONMENT', 'github-hosted'], ['RUNNER_NAME', 'another-lab'], ['PESTO_SELECTED_RUNNER', 'pesto-ci'], ['PESTO_SELECTED_RUNNER', ''],
    ['GITHUB_JOB', 'publish-release'], ['GITHUB_EVENT_NAME', 'push'], ['GITHUB_REF', 'refs/heads/feature'],
    ['PESTO_EXPECTED_SOURCE_SHA', 'b'.repeat(40)], ['PESTO_PUBLISH_RELEASE', 'false'], ['RUNNER_TEMP', '/unexpected']])
    await check('refuse context ' + key, async () => {
      const f = fixture(); await assert.rejects(sealLabHandoff(f.out, {...f.env, [key]: value}));
      assert.equal(existsSync(f.batch), false);
    });
  for (const [name, change] of [
    ['foreign source', m => { m.sourceCommit = 'b'.repeat(40); }], ['foreign run', m => { m.runId = '124'; }],
    ['old attempt', m => { m.runAttempt = '1'; }], ['wrong runner', m => { m.runnerName = 'other'; }],
    ['wrong kind', m => { m.kind = 'other'; }], ['wrong schema', m => { m.schemaVersion = 2; }],
    ['case collision', m => { m.files.push({...m.files[0], path: m.files[0].path.toLowerCase()}); }],
    ['negative size', m => { m.files[0].bytes = -1; }], ['invalid digest', m => { m.files[0].sha256 = 'bad'; }],
    ['light ZIP missing', m => { m.files = m.files.filter(f => !f.path.startsWith('PROD-LIGHT/')); }],
    ['missing socle-match', m => { m.files = m.files.filter(f => f.path !== 'evidence/socle-match.json'); }],
    ['missing socle-runner', m => { m.files = m.files.filter(f => f.path !== 'evidence/socle-runner.json'); }],
    ['missing provenance', m => { m.files = m.files.filter(f => f.path !== 'evidence/artifacts.json'); }],
    ['wrong byte count', m => { m.files[0].bytes++; }]
  ]) await check('refuse manifest: ' + name, async () => { const f = await sealed(); changeManifest(f, change); await refusedRestore(f); });
  for (const path of ['../escape', '/absolute', 'evidence/../escape', 'evidence/./file', 'evidence//file',
    'evidence/back\\slash', 'evidence/file:stream', 'evidence/CON.txt', 'evidence/trailing.', 'evidence/trailing ',
    'evidence/lab-transfer-receipt.json'])
    await check('refuse unsafe path ' + path, async () => {
      const f = await sealed(); changeManifest(f, m => { m.files.push({path, bytes: 0, sha256: hash('')}); }); await refusedRestore(f);
    });
  for (const [name, mutate, expected] of [
    ['missing output digest', f => { delete f.restoreEnv.PESTO_LAB_HANDOFF_SHA256; }, /digest/],
    ['manifest changed on disk', f => appendFileSync(join(f.batch, 'handoff.json'), ' '), /job output/],
    ['sealed ZIP corrupted', f => appendFileSync(join(f.batch, 'PROD-LIGHT/Pesto_V2_PROD-LIGHT_official.zip'), 'changed'), /bytes differ/],
    ['sealed socle-match corrupted', f => appendFileSync(join(f.batch, 'evidence/socle-match.json'), 'changed'), /bytes differ/],
    ['extra file', f => writeFileSync(join(f.batch, 'evidence/extra'), 'extra'), /missing or unexpected/],
    ['missing socle-runner', f => rmSync(join(f.batch, 'evidence/socle-runner.json')), /missing or unexpected/],
    ['missing manifest', f => rmSync(join(f.batch, 'handoff.json')), /ENOENT/],
    ['incomplete manifest', f => { writeFileSync(join(f.batch, 'handoff.json'), '{'); f.restoreEnv.PESTO_LAB_HANDOFF_SHA256 = hash('{'); }, SyntaxError]
  ]) await check('refuse restore: ' + name, async () => { const f = await sealed(); mutate(f); await refusedRestore(f, expected); });
  await check('existing publication directory and sentinel are preserved', async () => {
    const f = await sealed(); mkdirSync(f.release); writeFileSync(join(f.release, 'sentinel'), 'preserve');
    await assert.rejects(restoreLabHandoff(f.release, f.restoreEnv), /already exists/);
    assert.equal(readFileSync(join(f.release, 'sentinel'), 'utf8'), 'preserve');
  });
  await check('source directory links are rejected', async () => {
    const f = fixture(), path = join(f.out, 'evidence/nested'), target = join(f.root, 'linked-proof');
    renameSync(path, target); directoryLink(target, path);
    await assert.rejects(sealLabHandoff(f.out, f.env), /link/); assert.equal(existsSync(f.batch), false);
  });
  await check('sealed tree directory links are rejected', async () => {
    const f = await sealed(), path = join(f.batch, 'evidence/nested'), target = join(f.root, 'linked-proof');
    renameSync(path, target); directoryLink(target, path); await refusedRestore(f, /link/);
  });
  await check('handoff parent links are rejected', async () => {
    const f = fixture(), target = join(f.root, 'other-storage'); mkdirSync(target);
    directoryLink(target, join(f.root, 'pesto-release-handoffs'));
    await assert.rejects(sealLabHandoff(f.out, f.env), /link/);
  });
  await check('destination links are rejected without modifying their target', async () => {
    const f = await sealed(), target = join(f.root, 'other-release'); mkdirSync(target); directoryLink(target, f.release);
    await assert.rejects(restoreLabHandoff(f.release, f.restoreEnv), /link/);
    assert.equal(existsSync(join(target, 'PROD-LIGHT')), false);
  });
  await check('source and destination must use the runner checkout layout', async () => {
    const f = await sealed(); await assert.rejects(sealLabHandoff(f.root, f.env), /Source must/);
    await assert.rejects(restoreLabHandoff(f.root, f.restoreEnv), /Destination must/);
  });
  if (process.platform === 'win32') await check('Windows CLI writes the digest to GITHUB_OUTPUT and restores the same bytes', () => {
    const f = fixture(), output = join(f.root, 'github-output'); writeFileSync(output, 'existing=value\n');
    const cli = fileURLToPath(new URL('../release/lab-handoff.mjs', import.meta.url));
    const sealed = spawnSync(process.execPath, [cli, 'seal', f.out], {env: {...process.env, ...f.env, GITHUB_OUTPUT: output}, encoding: 'utf8'});
    assert.equal(sealed.status, 0, sealed.stderr); const result = JSON.parse(sealed.stdout);
    assert.equal(readFileSync(output, 'utf8'), `existing=value\nmanifest_sha256=${result.manifestSha256}\n`);
    const restored = spawnSync(process.execPath, [cli, 'restore', f.release], {env: {...process.env, ...f.env,
      GITHUB_JOB: 'publish-release', PESTO_LAB_HANDOFF_SHA256: result.manifestSha256}, encoding: 'utf8'});
    assert.equal(restored.status, 0, restored.stderr); assert.deepEqual(JSON.parse(restored.stdout), result);
  });
  console.log(`PASS ${checks} lab handoff checks (${process.platform}; synthetic files, no network)`);
} finally { rmSync(temporary, {recursive: true, force: true}); }
