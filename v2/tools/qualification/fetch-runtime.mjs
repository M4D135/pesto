#!/usr/bin/env node
// Récupération du VRAI runtime WebView2 Fixed Version 155.0.4283.62 pour le pack complet
// (QUALIFICATION_PRIORITY.md §2 : « copie déjà présente sur le poste si provenance/signature vérifiables »).
// Le copyfrom récursif de VBox s'est révélé TRONQUÉ (54/916 fichiers, exit 0, sans erreur — journal
// logs/qualification/fetch-runtime.json du premier essai) : la chaîne utilise donc un SEUL fichier tar par
// transfert, jugé sur hash relu à chaque étape, jamais sur un code VBox :
//   invité : tar (bsdtar) du dossier du runtime + sha256 du tar (lecture seule du dossier Programme Files)
//   → copyfrom du tar vers l'hôte → hash du tar relu sur l'hôte (comparé à celui de l'invité)
//   → extraction hôte : inventaire 916 fichiers / 909 827 702 o, sha256 de msedgewebview2.exe, signature
//     (Get-AuthenticodeSignature ; l'énuméré Valid est sérialisé 0 par ConvertTo-Json de PowerShell 5.1)
//   → scp du tar vers le Spark → hash du tar comparé → extraction locale → inventaire + sha256 recomptés ici.
// Aucune écriture dans les dossiers V1, aucune autre VM, aucun service ; passwordfile par chemin seulement.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, existsSync, readdirSync, statSync, rmSync } from 'node:fs';
import path from 'node:path';
import { host, runGuestJson, ensureHelper } from './lab-driver.mjs';
import { strictPrelude } from './ps-strict.mjs';
import { laboMdpFichier } from './lab-config.mjs';

const VERSION = '155.0.4283.62';
const GUEST_PARENT = 'C:\\Program Files (x86)\\Microsoft\\EdgeWebView\\Application';
const GUEST_TMP = 'C:\\Windows\\Temp\\pesto-v2-qual';
const TAR_NAME = `webview2-${VERSION}.tar`;
const HOST_ROOT = 'C:\\ADCC-Lab\\validation\\pesto-v2-20261024\\webview2-fixed';
const HOST_FWD = 'C:/ADCC-Lab/validation/pesto-v2-20261024/webview2-fixed';
const SSH_TARGET = 'degun@192.168.1.173';
const EXPECTED = {
  version: VERSION,
  fileCount: 916,
  totalBytes: 909827702,
  exeSha256: '93ACBCAD0B6F390AE1CE6A1DBF1E09E165520A7F1196EB22323AFA64A9BBA96B',
};

function scpFrom(remote, local, timeoutMs) {
  const r = spawnSync('scp', ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=12',
    `${SSH_TARGET}:${remote}`, local], { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 16 * 1024 * 1024 });
  if (r.error) throw r.error;
  return { code: r.status, stderr: (r.stderr ?? '').trim() };
}

function hostPs(script, timeoutMs = 120000) {
  // meme helper COMMUN que les scripts invites : aucune sortie hote ne peut plus partir en ConvertTo-Json composite
  const b64 = Buffer.from(strictPrelude({ helperPath: ensureHelper().hostPath }) + '\n' + script, 'utf16le').toString('base64');
  return host(`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ${b64}`, timeoutMs);
}

function sha256File(abs) {
  return createHash('sha256').update(readFileSync(abs)).digest('hex').toUpperCase();
}

function walk(root) {
  const out = [];
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const abs = path.join(dir, e.name);
      if (e.isDirectory()) stack.push(abs);
      else if (e.isFile()) out.push(abs);
      else throw new Error(`entrée inattendue (lien ?) : ${abs}`);
    }
  }
  return out;
}

function main() {
const localRoot = path.resolve(process.argv[2] ?? 'vendor/webview2-fixed');
const evidence = { utc: new Date().toISOString(), expected: EXPECTED, steps: [] };
const evidenceDir = path.join(path.dirname(new URL(import.meta.url).pathname), '..', '..', 'logs', 'qualification');
const out = path.join(evidenceDir, 'fetch-runtime.json');
const finish = (verdict) => {
  evidence.verdict = verdict;
  mkdirSync(evidenceDir, { recursive: true });
  writeFileSync(out, JSON.stringify(evidence, null, 1), 'utf8');
  console.log(JSON.stringify({ verdict, steps: evidence.steps.map((s) => ({ step: s.step, ok: s.ok, detail: s.detail })) }, null, 1));
  process.exitCode = verdict === 'OK' ? 0 : 1;
};

// 1) Invité : tar du dossier du runtime (lecture seule) + sha256 du tar, preuve JSON relue.
const tarGuest = `${GUEST_TMP}\\${TAR_NAME}`;
const guest = runGuestJson(`
if (Test-Path -LiteralPath '${tarGuest}') { Remove-Item -LiteralPath '${tarGuest}' -Force }
$tar='C:\\Windows\\System32\\tar.exe'
& $tar -cf '${tarGuest}' -C '${GUEST_PARENT}' '${VERSION}'
if ($LASTEXITCODE -ne 0) { throw ('tar invité code ' + $LASTEXITCODE) }
$result=[ordered]@{ Utc=(Get-Date).ToUniversalTime().ToString('o'); Tar='$tarGuest';
  TarBytes=(Get-Item -LiteralPath '${tarGuest}').Length;
  TarSha256=(Get-FileHash -LiteralPath '${tarGuest}' -Algorithm SHA256).Hash }`, 'webview2-tar-guest', { timeoutMs: 600000 });
if (!guest.json?.TarSha256) return finish('ÉCHEC: tar invité sans preuve relue');
evidence.steps.push({ step: 'guest-tar', ok: true, detail: guest.json });

// 2) copyfrom du tar (fichier unique) puis hash relu sur l'hôte — la copie est jugée sur ce hash.
const rmHost = hostPs(`if (Test-Path -LiteralPath '${HOST_ROOT}') { Remove-Item -LiteralPath '${HOST_ROOT}' -Recurse -Force }`
  + `; New-Item -ItemType Directory -Force -Path '${HOST_ROOT}' | Out-Null`, 120000);
evidence.steps.push({ step: 'host-clean', ok: rmHost.code === 0, detail: rmHost.code });
const copy = host(`"C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe" guestcontrol 9b2ad4f0-0506-4f58-aed2-c43ac1973516 copyfrom`
  + ` --username labadmin --passwordfile ${laboMdpFichier()} --quiet`
  + ` "${tarGuest}" "${HOST_ROOT}\\${TAR_NAME}"`, 30 * 60000);
const hostTarAbs = `${HOST_ROOT}\\${TAR_NAME}`;
const hostHashPs = `$ErrorActionPreference='Stop'
$result=[ordered]@{ Utc=(Get-Date).ToUniversalTime().ToString('o');
  TarBytes=(Get-Item -LiteralPath '${hostTarAbs}').Length;
  TarSha256=(Get-FileHash -LiteralPath '${hostTarAbs}' -Algorithm SHA256).Hash }`;
const hh = hostPs(hostHashPs + `\n[System.IO.File]::WriteAllText('${HOST_ROOT}\\tar-host.json',(ConvertTo-PestoJson $result),(New-Object System.Text.UTF8Encoding($false)))`, 600000);
const localHostTar = path.join(evidenceDir, 'webview2-tar-host.json');
scpFrom(`${HOST_FWD}/tar-host.json`, localHostTar, 60000);
let hostTar = null;
if (existsSync(localHostTar)) { try { hostTar = JSON.parse(readFileSync(localHostTar, 'utf8').replace(/^\uFEFF/, '')); } catch { hostTar = null; } }
const tarCopied = hostTar && hostTar.TarSha256 === guest.json.TarSha256 && hostTar.TarBytes === guest.json.TarBytes;
evidence.steps.push({ step: 'copyfrom-tar', ok: Boolean(tarCopied), detail: { copyCode: copy.code, hostTar, expected: { TarSha256: guest.json.TarSha256, TarBytes: guest.json.TarBytes }, psCode: hh.code } });
if (!tarCopied) return finish('ÉCHEC: hash du tar divergent après copyfrom');

// 3) Extraction hôte + inventaire complet + signature (le résultat est jugé sur le JSON relu).
const invPs = `$ErrorActionPreference='Stop'
$root='${HOST_ROOT}'
$dir=Join-Path $root '${VERSION}'
if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
& 'C:\\Windows\\System32\\tar.exe' -xf (Join-Path $root '${TAR_NAME}') -C $root
if ($LASTEXITCODE -ne 0) { throw ('tar hôte code ' + $LASTEXITCODE) }
$files=Get-ChildItem -LiteralPath $dir -Recurse -File
$exe=Join-Path $dir 'msedgewebview2.exe'
$sig=Get-AuthenticodeSignature -LiteralPath $exe
$result=[ordered]@{ Utc=(Get-Date).ToUniversalTime().ToString('o'); Exists=(Test-Path -LiteralPath $exe);
  FileCount=$files.Count; TotalBytes=($files | Measure-Object -Sum Length).Sum;
  SignatureStatus=[string]$sig.Status; SignatureStatusInt=[int]$sig.Status;
  SignerSubject=$sig.SignerCertificate.Subject; SignerIssuer=$sig.SignerCertificate.Issuer;
  Thumbprint=$sig.SignerCertificate.Thumbprint;
  ExeSha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash }
[System.IO.File]::WriteAllText((Join-Path $root 'hostcheck.json'),(ConvertTo-PestoJson $result),(New-Object System.Text.UTF8Encoding($false)))
Write-Output 'WROTE'`;
const inv = hostPs(invPs, 900000);
const localHostCheck = path.join(evidenceDir, 'webview2-hostcheck.json');
scpFrom(`${HOST_FWD}/hostcheck.json`, localHostCheck, 60000);
let hostCheck = null;
if (existsSync(localHostCheck)) { try { hostCheck = JSON.parse(readFileSync(localHostCheck, 'utf8').replace(/^\uFEFF/, '')); } catch { hostCheck = null; } }
const hostOk = hostCheck && (hostCheck.SignatureStatusInt === 0 || hostCheck.SignatureStatus === 'Valid')
  && hostCheck.FileCount === EXPECTED.fileCount && hostCheck.TotalBytes === EXPECTED.totalBytes
  && hostCheck.ExeSha256 === EXPECTED.exeSha256;
evidence.steps.push({ step: 'host-extract-inventory', ok: Boolean(hostOk), detail: { psCode: inv.code, hostCheck } });
if (!hostOk) return finish('ÉCHEC: inventaire ou signature hôte non conformes');

// 4) scp du tar vers le Spark, hash comparé, extraction locale, inventaire + sha256 recomptés ici.
mkdirSync(localRoot, { recursive: true });
const localTar = path.join(localRoot, TAR_NAME);
if (existsSync(localTar)) rmSync(localTar, { force: true });
const scp = scpFrom(`${HOST_FWD}/${TAR_NAME}`, localTar, 30 * 60000);
const scpOk = scp.code === 0 && existsSync(localTar) && sha256File(localTar) === guest.json.TarSha256;
evidence.steps.push({ step: 'scp-to-spark', ok: scpOk, detail: { code: scp.code, stderr: scp.stderr.slice(0, 300) } });
if (!scpOk) return finish('ÉCHEC: scp du tar non conforme');
const localDir = path.join(localRoot, VERSION);
if (existsSync(localDir)) rmSync(localDir, { recursive: true, force: true });
mkdirSync(localDir, { recursive: true });
const untar = spawnSync('tar', ['-xf', localTar, '-C', localRoot], { encoding: 'utf8', timeout: 600000 });
const files = walk(localDir);
const totalBytes = files.reduce((s, f) => s + statSync(f).size, 0);
const exeAbs = path.join(localDir, 'msedgewebview2.exe');
const local = {
  dir: localDir, fileCount: files.length, totalBytes,
  exeSha256: existsSync(exeAbs) ? sha256File(exeAbs) : null,
  countOk: files.length === EXPECTED.fileCount, bytesOk: totalBytes === EXPECTED.totalBytes,
  hashOk: existsSync(exeAbs) && sha256File(exeAbs) === EXPECTED.exeSha256,
};
evidence.steps.push({ step: 'local-extract-inventory', ok: local.countOk && local.bytesOk && local.hashOk, detail: { untarCode: untar.status, ...local } });
finish(local.countOk && local.bytesOk && local.hashOk ? 'OK' : 'ÉCHEC: inventaire local non conforme');
}
main();
