// Local transport only. Publication still requires the separate successful Windows job and publisher gates.
import {createHash} from 'node:crypto';
import {appendFileSync, constants, copyFileSync, createReadStream, lstatSync, mkdirSync, mkdtempSync,
  readFileSync, readdirSync, renameSync, writeFileSync} from 'node:fs';
import {basename, dirname, isAbsolute, join, relative, resolve, sep} from 'node:path';
import {pathToFileURL} from 'node:url';
import {contextFromEnv} from './publish-release.mjs';

const requireValue = (value, message) => { if (!value) throw new Error(message); };
const digestPattern = /^[0-9a-f]{64}$/;
const manifestLimit = 1024 * 1024, fileLimit = 4 * 1024 ** 3;
const receiptPath = 'evidence/lab-transfer-receipt.json';
const variants = ['PROD-LIGHT'];
const zipPath = channel => `${channel}/Pesto_V2_${channel}_official.zip`;
const hashBytes = bytes => createHash('sha256').update(bytes).digest('hex');
const pathKey = path => resolve(path).toLowerCase();
const inside = (parent, child) => pathKey(child) === pathKey(parent) || pathKey(child).startsWith(pathKey(parent) + sep);
function statOrNull(path) {
  try { return lstatSync(path); } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function noLinks(path) {
  for (let cursor = resolve(path);; cursor = dirname(cursor)) {
    const stat = statOrNull(cursor);
    requireValue(!stat?.isSymbolicLink(), 'A handoff path contains a link.');
    if (dirname(cursor) === cursor) break;
  }
}
function directory(path) { noLinks(path); requireValue(lstatSync(path).isDirectory(), 'Expected a directory.'); }
function ensureDirectory(path) { noLinks(path); mkdirSync(path, {recursive: true}); directory(path); }
function regularFile(path, maximum = fileLimit) {
  noLinks(path); const stat = lstatSync(path);
  requireValue(stat.isFile() && stat.size <= maximum, 'Invalid handoff file.'); return stat;
}
function sameFile(before, after) {
  return before.size === after.size && before.mtimeMs === after.mtimeMs && before.ctimeMs === after.ctimeMs
    && before.ino === after.ino && before.dev === after.dev;
}
async function fingerprint(path) {
  const before = regularFile(path), hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  requireValue(sameFile(before, regularFile(path)), 'A handoff file changed while hashing.');
  return {bytes: before.size, sha256: hash.digest('hex'), stat: before};
}
function readBounded(path) {
  const before = regularFile(path, manifestLimit);
  requireValue(before.size > 0, 'Empty handoff metadata.');
  const bytes = readFileSync(path);
  requireValue(sameFile(before, regularFile(path, manifestLimit)) && bytes.length === before.size,
    'Handoff metadata changed while reading.');
  return bytes;
}
const parseJson = bytes => JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/, ''));
function safeRelative(path) {
  requireValue(typeof path === 'string' && path.length > 0 && !/[\\:<>"|?*\x00-\x1f]/.test(path), 'Unsafe handoff relative path.');
  const parts = path.split('/');
  requireValue(parts.every(part => part && part !== '.' && part !== '..' && !/[. ]$/.test(part)
    && !/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(part)), 'Unsafe handoff path component.');
  requireValue(variants.some(variant => path === zipPath(variant)) || path.startsWith('evidence/'), 'Unexpected handoff payload path.');
  requireValue(path.toLowerCase() !== receiptPath, 'Reserved transfer receipt already present.');
}
function inventory(root) {
  const files = [];
  function visit(dir) {
    directory(dir);
    for (const name of readdirSync(dir).sort()) {
      const path = join(dir, name); noLinks(path); const stat = lstatSync(path);
      if (stat.isDirectory()) visit(path);
      else { requireValue(stat.isFile(), 'Special file in handoff tree.'); files.push(relative(root, path).split(sep).join('/')); }
    }
  }
  visit(root); return files.sort();
}
function validateFiles(files) {
  requireValue(Array.isArray(files) && files.length >= 6 && files.length <= 10000, 'Invalid handoff inventory.');
  const names = new Set();
  for (const file of files) {
    requireValue(file && typeof file === 'object', 'Invalid handoff entry.'); safeRelative(file.path);
    const key = file.path.toLowerCase(); requireValue(!names.has(key), 'Duplicate or case-colliding handoff path.'); names.add(key);
    requireValue(Number.isSafeInteger(file.bytes) && file.bytes >= 0 && file.bytes <= fileLimit
      && digestPattern.test(file.sha256 ?? ''), 'Invalid handoff size or digest.');
  }
  requireValue(files.some(file => file.path === zipPath('PROD-LIGHT') && file.bytes > 0), 'Missing or empty official ZIP.');
  for (const path of ['evidence/artifacts.json', 'evidence/prod-light-smoke.json', 'evidence/native-demo-PROD-LIGHT.json',
    'evidence/socle-match.json', 'evidence/socle-runner.json'])
    requireValue(files.some(file => file.path === path && file.bytes > 0), 'Missing artifact provenance or socle proof.');
}
async function copyVerified(source, destination, expected) {
  const identity = await fingerprint(source);
  if (expected) requireValue(identity.bytes === expected.bytes && identity.sha256 === expected.sha256, 'Source handoff bytes differ from manifest.');
  ensureDirectory(dirname(destination)); noLinks(destination);
  requireValue(sameFile(identity.stat, regularFile(source)), 'Source changed before copying.');
  copyFileSync(source, destination, constants.COPYFILE_EXCL);
  requireValue(sameFile(identity.stat, regularFile(source)), 'Source changed during copying.');
  const copied = await fingerprint(destination);
  requireValue(copied.bytes === identity.bytes && copied.sha256 === identity.sha256, 'Copied handoff bytes differ.');
  return {bytes: copied.bytes, sha256: copied.sha256};
}
function labContext(env, job) {
  const context = contextFromEnv(env);
  requireValue(env.RUNNER_OS === 'Windows' && env.RUNNER_ENVIRONMENT === 'self-hosted'
    && ['pesto-lab', 'pesto-ci'].includes(env.PESTO_SELECTED_RUNNER)
    && env.RUNNER_NAME === env.PESTO_SELECTED_RUNNER && env.GITHUB_JOB === job, 'Unexpected lab runner or job.');
  for (const name of ['GITHUB_WORKSPACE', 'RUNNER_TEMP']) requireValue(typeof env[name] === 'string'
    && isAbsolute(env[name]) && !/^(\\\\|\/\/)/.test(env[name]), 'Expected an absolute local runner path.');
  const workspace = resolve(env.GITHUB_WORKSPACE), temporary = resolve(env.RUNNER_TEMP);
  requireValue(basename(temporary).toLowerCase() === '_temp' && basename(dirname(temporary)).toLowerCase() === '_work',
    'Unexpected runner temporary layout.');
  directory(workspace); directory(temporary);
  const base = resolve(temporary, '..', '..', 'pesto-release-handoffs');
  requireValue(!inside(workspace, base) && !inside(temporary, base), 'Handoff must be outside the checkout and runner temporary directory.');
  noLinks(base);
  return {...context, workspace, base, batch: join(base, `${context.runId}-${context.runAttempt}-${context.sha}`)};
}
function validateRecords(root, context, files) {
  const records = parseJson(readBounded(join(root, 'evidence/artifacts.json')));
  requireValue(Array.isArray(records) && records.length === 1, 'Exactly one publishable artifact record is required.');
  const record = records[0];
  requireValue(record.channel === 'PROD' && record.edition === 'PROD-LIGHT', 'Artifact must be the single PROD-LIGHT record.');
  requireValue(record.sourceCommit === context.sha && record.runId === context.runId && record.runAttempt === context.runAttempt
    && record.distribution === 'official', 'Artifact provenance differs from this handoff.');
  requireValue(record.archiveSha256 === files.find(file => file.path === zipPath('PROD-LIGHT'))?.sha256,
    'Official ZIP differs from artifact provenance.');
  requireValue(/^2\.\d+\.\d+(?:\.\d+)?$/.test(record.version ?? '') && digestPattern.test(record.executableSha256 ?? ''),
    'Invalid version or executable digest.');
  requireValue(record.runtimeMode === 'evergreen' && record.runtimeSource === 'evergreen',
    'Runtime mode and source must be evergreen.');
  requireValue(record.smokeSha256 === files.find(file => file.path === 'evidence/prod-light-smoke.json')?.sha256,
    'Smoke proof SHA differs from the sealed build.');
  requireValue(record.socleMatchSha256 === files.find(file => file.path === 'evidence/socle-match.json')?.sha256,
    'Socle match proof SHA differs from the sealed build.');
  requireValue(record.socleRunnerSha256 === files.find(file => file.path === 'evidence/socle-runner.json')?.sha256,
    'Socle runner proof SHA differs from the sealed build.');
  requireValue(record.socleVersion === '156.0.4314.42', 'Socle version must be 156.0.4314.42.');
  requireValue(digestPattern.test(record.socleIndexSha256 ?? ''), 'Invalid socle index digest.');
  requireValue(record.soclePreservationQualified === true, 'Socle preservation must be qualified by Engine tests.');
  requireValue(record.socleReleaseUrl === 'https://github.com/M4D135/socle-windows/releases/tag/webview2-156.0.4314.42',
    'Socle release URL differs from the pinned reference.');
  const smoke = parseJson(readBounded(join(root, 'evidence/prod-light-smoke.json')));
  requireValue(smoke.success === true && smoke.ready === true && smoke.closeReturned === true
    && smoke.bundledWebView2Absent === true && smoke.runtimeMode === 'evergreen' && smoke.runtimeSource === 'evergreen',
    'Smoke proof is not a valid evergreen qualification.');
  const nativeDemo = parseJson(readBounded(join(root, 'evidence/native-demo-PROD-LIGHT.json')));
  requireValue(nativeDemo.success === true, 'Native demo proof must be successful.');
  requireValue(smoke.nativeProofSha256 === files.find(file => file.path === 'evidence/native-demo-PROD-LIGHT.json')?.sha256,
    'Smoke native proof SHA differs from the sealed native demo.');
}
export async function sealLabHandoff(outputDirectory, env) {
  const context = labContext(env, 'windows-critical'), source = join(context.workspace, 'v2/out');
  requireValue(pathKey(outputDirectory) === pathKey(source), 'Source must be workspace/v2/out.'); directory(source);
  requireValue(!statOrNull(context.batch), 'Handoff batch already exists.');
  const payload = variants.map(channel => ({source: join(source, `Pesto_V2_${channel}_official.zip`), path: zipPath(channel)}));
  for (const path of inventory(join(source, 'evidence'))) payload.push({source: join(source, 'evidence', path), path: 'evidence/' + path});
  payload.sort((a, b) => a.path.localeCompare(b.path, 'en'));
  const original = [];
  for (const file of payload) { safeRelative(file.path); const identity = await fingerprint(file.source); original.push({path: file.path, bytes: identity.bytes, sha256: identity.sha256}); }
  validateFiles(original); validateRecords(source, context, original);
  ensureDirectory(context.base);
  const staging = mkdtempSync(join(context.base, `.stage-${context.runId}-${context.runAttempt}-`));
  const files = [];
  for (let i = 0; i < payload.length; i++) {
    const file = payload[i]; files.push({path: file.path, ...await copyVerified(file.source, join(staging, file.path), original[i])});
  }
  // Validate the copied metadata as well; the publisher retains all detailed SDK and qualification gates.
  validateRecords(staging, context, files);
  files.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
  const manifest = {schemaVersion: 1, kind: 'pesto.lab-release-handoff', sourceCommit: context.sha,
    runId: context.runId, runAttempt: context.runAttempt, runnerName: env.RUNNER_NAME, files};
  const bytes = Buffer.from(JSON.stringify(manifest, null, 2) + '\n');
  requireValue(bytes.length <= manifestLimit, 'Handoff manifest exceeds its bound.');
  writeFileSync(join(staging, 'handoff.json'), bytes, {flag: 'wx'});
  noLinks(context.batch); requireValue(!statOrNull(context.batch), 'Handoff batch appeared during sealing.');
  renameSync(staging, context.batch);
  return {manifestSha256: hashBytes(bytes), fileCount: files.length, totalBytes: files.reduce((sum, file) => sum + file.bytes, 0)};
}
export async function restoreLabHandoff(destinationDirectory, env) {
  const context = labContext(env, 'publish-release'), destination = join(context.workspace, 'release');
  requireValue(pathKey(destinationDirectory) === pathKey(destination), 'Destination must be workspace/release.');
  noLinks(destination); requireValue(!statOrNull(destination), 'Publication destination already exists.');
  requireValue(digestPattern.test(env.PESTO_LAB_HANDOFF_SHA256 ?? ''), 'A manifest digest from the Windows job output is required.');
  directory(context.batch);
  const bytes = readBounded(join(context.batch, 'handoff.json'));
  requireValue(hashBytes(bytes) === env.PESTO_LAB_HANDOFF_SHA256, 'Handoff manifest differs from the Windows job output.');
  const manifest = parseJson(bytes);
  requireValue(manifest?.schemaVersion === 1 && manifest.kind === 'pesto.lab-release-handoff' && manifest.sourceCommit === context.sha
    && manifest.runId === context.runId && manifest.runAttempt === context.runAttempt && manifest.runnerName === env.RUNNER_NAME,
    'Handoff identity differs from this publication.');
  validateFiles(manifest.files);
  const actual = inventory(context.batch).filter(path => path !== 'handoff.json');
  const expected = manifest.files.map(file => file.path).sort();
  requireValue(JSON.stringify(actual) === JSON.stringify(expected), 'Handoff files are missing or unexpected.');
  for (const file of manifest.files) {
    const identity = await fingerprint(join(context.batch, file.path));
    requireValue(identity.bytes === file.bytes && identity.sha256 === file.sha256, 'Handoff bytes differ from the manifest.');
  }
  validateRecords(context.batch, context, manifest.files);
  mkdirSync(destination); directory(destination);
  for (const file of manifest.files) await copyVerified(join(context.batch, file.path), join(destination, file.path), file);
  const receipt = {schemaVersion: 1, kind: 'pesto.lab-release-transfer', manifestSha256: env.PESTO_LAB_HANDOFF_SHA256,
    sourceCommit: context.sha, runId: context.runId, runAttempt: context.runAttempt, runnerName: env.RUNNER_NAME, files: manifest.files};
  writeFileSync(join(destination, receiptPath), JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx'});
  return {manifestSha256: env.PESTO_LAB_HANDOFF_SHA256, fileCount: manifest.files.length,
    totalBytes: manifest.files.reduce((sum, file) => sum + file.bytes, 0)};
}
if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  try {
    requireValue(process.platform === 'win32', 'The lab handoff CLI requires Windows.');
    requireValue(process.argv.length === 4 && ['seal', 'restore'].includes(process.argv[2]), 'Usage: lab-handoff.mjs <seal|restore> <directory>');
    if (process.argv[2] === 'seal') {
      requireValue(typeof process.env.GITHUB_OUTPUT === 'string' && process.env.GITHUB_OUTPUT.length > 0, 'GITHUB_OUTPUT is required.');
      regularFile(process.env.GITHUB_OUTPUT);
      const result = await sealLabHandoff(process.argv[3], process.env);
      appendFileSync(process.env.GITHUB_OUTPUT, `manifest_sha256=${result.manifestSha256}\n`);
      console.log(JSON.stringify(result));
    } else console.log(JSON.stringify(await restoreLabHandoff(process.argv[3], process.env)));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
