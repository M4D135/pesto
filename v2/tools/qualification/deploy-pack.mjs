#!/usr/bin/env node
// Déploiement du pack complet Pesto v2 dans la VM de qualification, dossier V2 DISTINCT (V1 intact).
// Le pack voyage en UN SEUL fichier tar (le copyfrom/copyto récursif de VBox a été vu tronquant — cf.
// logs/qualification/fetch-runtime.json premier essai) et chaque saut est jugé sur sha256 relu, jamais sur
// un code VBox : Spark(tar+hash) → scp hôte(hash relu) → copyto guest(hash relu) → extraction guest →
// recontrôle SHA256SUMS complet dans l'invité (1249 fichiers) avec preuve JSON rapatriée sur le Spark.
// Écritures invitées limitées à C:\PestoV2_Qual_20261024 et C:\Windows\Temp\pesto-v2-qual ; aucun V1 touché,
// aucune autre VM, aucun service, passwordfile par chemin seulement.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, existsSync, rmSync, statSync } from 'node:fs';
import path from 'node:path';
import { host, runGuestJson, runGuestJsonFile, ensureHelper } from './lab-driver.mjs';
import { strictPrelude } from './ps-strict.mjs';
import { laboMdpFichier } from './lab-config.mjs';

const PACK_NAME = 'Pesto-2.0.0-DEV';
const PACK_DIR = path.resolve(process.argv[2] ?? '../dist/' + PACK_NAME);
const DEPLOY_ROOT = 'C:\\PestoV2_Qual_20261024';
const GUEST_PACK = `${DEPLOY_ROOT}\\${PACK_NAME}`;
const GUEST_TMP = 'C:\\Windows\\Temp\\pesto-v2-qual';
const HOST_DEPLOY = 'C:\\ADCC-Lab\\validation\\pesto-v2-20261024\\deploy';
const HOST_DEPLOY_FWD = 'C:/ADCC-Lab/validation/pesto-v2-20261024/deploy';
const SSH_TARGET = 'degun@192.168.1.173';
const TAR_NAME = 'pesto-v2-pack.tar';

function scpTo(local, remote, timeoutMs) {
  const r = spawnSync('scp', ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=12',
    local, `${SSH_TARGET}:${remote}`], { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 16 * 1024 * 1024 });
  if (r.error) throw r.error;
  return { code: r.status, stderr: (r.stderr ?? '').trim() };
}
function scpFrom(remote, local, timeoutMs) {
  const r = spawnSync('scp', ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=12',
    `${SSH_TARGET}:${remote}`, local], { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 16 * 1024 * 1024 });
  if (r.error) throw r.error;
  return { code: r.status, stderr: (r.stderr ?? '').trim() };
}
function hostPs(script, timeoutMs = 120000) {
  const b64 = Buffer.from(script, 'utf16le').toString('base64');
  return host(`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ${b64}`, timeoutMs);
}
const sha256File = (abs) => createHash('sha256').update(readFileSync(abs)).digest('hex').toUpperCase();

/// Hash du tar côté hôte, jugé sur le JSON relu (jamais sur un code VBox). Retourne null si rien n'est relu.
/// Le JSON est écrit par le chemin STRICT commun (aucun ConvertTo-Json composite) — cf. ps-strict.mjs.
function runHostTarHash(tag = 'host') {
  const hs = `$ErrorActionPreference='Stop'
$result=[ordered]@{ Utc=(Get-Date).ToUniversalTime().ToString('o');
  TarBytes=(Get-Item -LiteralPath '${HOST_DEPLOY}\\${TAR_NAME}').Length;
  TarSha256=(Get-FileHash -LiteralPath '${HOST_DEPLOY}\\${TAR_NAME}' -Algorithm SHA256).Hash }
[System.IO.File]::WriteAllText('${HOST_DEPLOY}\\tar-host.json',(ConvertTo-PestoJson $result),(New-Object System.Text.UTF8Encoding($false)))`;
  const preludeOnly = strictPrelude({ helperPath: ensureHelper().hostPath });
  const r = hostPs(preludeOnly + '\n' + hs, 180000);
  const localHostTar = path.join(evidenceDir, `pack-tar-${tag}.json`);
  scpFrom(`${HOST_DEPLOY_FWD}/tar-host.json`, localHostTar, 60000);
  if (!existsSync(localHostTar)) { evidence.steps.push({ step: 'tar-hash-host-' + tag, ok: false, detail: { psCode: r.code, stderr: r.stderr?.slice(0, 300) } }); return null; }
  try { return JSON.parse(readFileSync(localHostTar, 'utf8').replace(/^\uFEFF/, '')); } catch { return null; }
}

/// Hash du tar côté invité, même règle (preuve relue, borne 180 s).
function runGuestTarHash(tag = 'guest') {
  const g = runGuestJson(`$result=[ordered]@{ Utc=(Get-Date).ToUniversalTime().ToString('o');
  TarBytes=(Get-Item -LiteralPath '${GUEST_TMP}\\${TAR_NAME}').Length;
  TarSha256=(Get-FileHash -LiteralPath '${GUEST_TMP}\\${TAR_NAME}' -Algorithm SHA256).Hash }`, `pack-tar-${tag}`, { timeoutMs: 180000 });
  return g.json ?? null;
}

const evidenceDir = path.join(path.dirname(new URL(import.meta.url).pathname), '..', '..', 'logs', 'qualification');
const out = path.join(evidenceDir, 'deploy-pack.json');
const evidence = { utc: new Date().toISOString(), packDir: PACK_DIR, deployRoot: DEPLOY_ROOT, steps: [] };
const finish = (verdict) => {
  evidence.verdict = verdict;
  mkdirSync(evidenceDir, { recursive: true });
  writeFileSync(out, JSON.stringify(evidence, null, 1), 'utf8');
  console.log(JSON.stringify({ verdict, steps: evidence.steps.map((s) => ({ step: s.step, ok: s.ok, detail: s.detail })) }, null, 1));
  process.exitCode = String(verdict).startsWith('OK') ? 0 : 1;
};

function main() {
  if (!existsSync(path.join(PACK_DIR, 'Pesto.exe'))) return finish('ÉCHEC: pack introuvable ' + PACK_DIR);

  // 0) Option --reuse (SERIALIZATION_REVIEW_REQUIRED.md §3) : le tar local, sa copie hôte et sa copie invitée
  //    existent déjà. On ne régénère et on ne retransfère PAS 1 Go identique : on relit les hashes et on
  //    poursuit directement s'ils sont identiques. Le test de sérialisation ne doit jamais redevenir un test de
  //    transfert.
  const REUSE = process.argv.includes('--reuse');
  // --check : s'arrête à la comparaison des hashes (aucune extraction, aucune écriture dans le dossier déployé).
  // C'est ce qu'exige la revue : vérifier les hashes et poursuivre directement si identiques, sans redéployer 1 Go.
  const CHECK = process.argv.includes('--check');
  const localTar = path.join(path.dirname(PACK_DIR), TAR_NAME);
  let tarSha = null;
  if (REUSE && existsSync(localTar)) {
    tarSha = sha256File(localTar);
    evidence.steps.push({ step: 'spark-tar-reuse', ok: true, detail: { tarSha, bytes: statSync(localTar).size } });
  } else {
    if (existsSync(localTar)) rmSync(localTar, { force: true });
    const tar = spawnSync('tar', ['-cf', localTar, '-C', path.dirname(PACK_DIR), PACK_NAME], { encoding: 'utf8', timeout: 900000 });
    if (tar.status !== 0) return finish('ÉCHEC: tar local code ' + tar.status);
    tarSha = sha256File(localTar);
    evidence.steps.push({ step: 'spark-tar', ok: true, detail: { tarSha, bytes: statSync(localTar).size } });
  }

  // 1) scp vers l'hôte, hash relu sur l'hôte (sauté si la copie hôte est déjà identique)
  const hostPre = runHostTarHash();
  if (hostPre && hostPre.TarSha256 === tarSha) {
    evidence.steps.push({ step: 'scp-host', ok: true, detail: { skipped: 'copie hôte déjà identique', hostTar: hostPre, expected: tarSha } });
  } else {
    hostPs(`if (-not (Test-Path -LiteralPath '${HOST_DEPLOY}')) { New-Item -ItemType Directory -Force -Path '${HOST_DEPLOY}' | Out-Null }`
      + `; if (Test-Path -LiteralPath '${HOST_DEPLOY}\\${TAR_NAME}') { Remove-Item -LiteralPath '${HOST_DEPLOY}\\${TAR_NAME}' -Force }`, 60000);
    const scp = scpTo(localTar, `${HOST_DEPLOY_FWD}/${TAR_NAME}`, 30 * 60000);
    const hostTar = runHostTarHash();
    const hostOk = scp.code === 0 && hostTar?.TarSha256 === tarSha;
    evidence.steps.push({ step: 'scp-host', ok: hostOk, detail: { scpCode: scp.code, hostTar, expected: tarSha } });
    if (!hostOk) return finish('ÉCHEC: hash du tar divergent après scp vers l\'hôte');
  }

  // 2) copyto du tar vers l'invité (fichier unique), hash relu dans l'invité (sauté si déjà identique)
  const guestPre = runGuestTarHash();
  if (guestPre && guestPre.TarSha256 === tarSha) {
    evidence.steps.push({ step: 'copyto-guest', ok: true, detail: { skipped: 'copie invitée déjà identique', guest: guestPre, expected: tarSha } });
  } else {
    const copy = host(`"C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe" guestcontrol 9b2ad4f0-0506-4f58-aed2-c43ac1973516 copyto`
      + ` --username labadmin --passwordfile ${laboMdpFichier()} --quiet`
      + ` "${HOST_DEPLOY}\\${TAR_NAME}" "${GUEST_TMP}\\${TAR_NAME}"`, 30 * 60000);
    const guestTar = runGuestTarHash();
    const guestTarOk = guestTar?.TarSha256 === tarSha;
    evidence.steps.push({ step: 'copyto-guest', ok: guestTarOk, detail: { copyCode: copy.code, guest: guestTar, expected: tarSha } });
    if (!guestTarOk) return finish('ÉCHEC: hash du tar divergent après copyto');
  }

  if (CHECK) return finish('OK: hashes du tar identiques Spark/hôte/invité — pack invité laissé en place, aucune extraction');

  // 4) Extraction invitée dans le dossier V2 distinct + recontrôle SHA256SUMS complet, preuve JSON relue
  // Script long : transfert en fichier (la voie EncodedCommand dépasse la limite cmd.exe de la ligne de
  // commande SSH — cause exacte de l'échec silencieux du premier déploiement, preuve invitée jamais écrite).
  const deploy = runGuestJsonFile(`$ErrorActionPreference='Stop'
$err='OK'; $checked=0; $bad=@(); $missing=@(); $present=-1; $exeSha=''; $sigStatus=-99; $sigSigner=''; $pkg=''
try {
  if (Test-Path -LiteralPath '${GUEST_PACK}') { Remove-Item -LiteralPath '${GUEST_PACK}' -Recurse -Force }
  New-Item -ItemType Directory -Force -Path '${DEPLOY_ROOT}' | Out-Null
  & 'C:\\Windows\\System32\\tar.exe' -xf '${GUEST_TMP}\\${TAR_NAME}' -C '${DEPLOY_ROOT}'
  if ($LASTEXITCODE -ne 0) { throw ('tar invite code ' + $LASTEXITCODE) }
  $sums=(Get-PlainText '${GUEST_PACK}\\SHA256SUMS') -split '\\r?\\n'
  foreach ($line in $sums) {
    if ($line.Trim() -eq '') { continue }
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { $bad += ('MALFORME:' + $line.Substring(0,[Math]::Min(80,$line.Length))); continue }
    $rel=$Matches[2]; $want=$Matches[1].ToUpper()
    $abs=Join-Path '${GUEST_PACK}' ($rel -replace '/','\\')
    if (-not (Test-Path -LiteralPath $abs)) { $missing += $rel; continue }
    $got=(Get-FileHash -LiteralPath $abs -Algorithm SHA256).Hash
    if ($got -ne $want) { $bad += $rel }
    $checked++
    Assert-PestoGuard
  }
  $present=@(Get-ChildItem -LiteralPath '${GUEST_PACK}' -Recurse -File).Count
  try {
    $sig=Get-AuthenticodeSignature -LiteralPath '${GUEST_PACK}\\runtime\\webview2\\msedgewebview2.exe'
    $sigStatus=[int]$sig.Status; $sigSigner=[string]$sig.SignerCertificate.Subject
  } catch { $sigSigner='ERR:'+(($_.Exception.Message) -replace '[\\r\\n]+',' ') }
  $exeSha=(Get-FileHash -LiteralPath '${GUEST_PACK}\\runtime\\webview2\\msedgewebview2.exe' -Algorithm SHA256).Hash
  # Get-Content -Raw enrichit le texte des proprietes ETS du provider (PSPath/PSDrive/PSProvider/ReadCount) :
  # c'est l'objet exact qui faisait exploser ConvertTo-Json -Depth 10. Get-PlainText lit en .NET, sans provider.
  $pkg=Get-PlainText '${GUEST_PACK}\\Pesto.package.json'
} catch { $err=($_.Exception.GetType().Name + ' :: ' + [string]$_.Exception.Message) -replace '[\\r\\n]+',' ' }
$result=[ordered]@{ Utc=(Get-Date).ToUniversalTime().ToString('o'); DeployedRoot='${GUEST_PACK}'; Err=$err;
  Checked=$checked; Mismatched=$bad; Missing=$missing; FilesPresent=$present;
  ExeSha256=$exeSha; ExeSignature=$sigStatus; ExeSigner=$sigSigner; PackageJson=$pkg }`, 'pack-deployed-verify', { timeoutMs: 180000 });
  const j = deploy.json;
  const expectedFiles = readFileSync(path.join(PACK_DIR, 'SHA256SUMS'), 'utf8').split(/\r?\n/).filter((line) => line.trim() !== '').length;
  const sumsOk = j && expectedFiles > 0 && j.Checked === expectedFiles && j.FilesPresent === expectedFiles + 1 && deploy.json.Err === 'OK' && deploy.json.Mismatched.length === 0 && deploy.json.Missing.length === 0
    && deploy.json.ExeSha256 === '93ACBCAD0B6F390AE1CE6A1DBF1E09E165520A7F1196EB22323AFA64A9BBA96B'
    && deploy.json.ExeSignature === 0 && /"webview2Runtime":\s*"fixed"/.test(deploy.json.PackageJson ?? '');
  evidence.steps.push({ step: 'guest-deploy-verify', ok: Boolean(sumsOk), detail: deploy.json ?? { error: 'aucun JSON relu', run: deploy.run?.stdout?.slice(0, 400) } });
  finish(sumsOk ? 'OK' : 'ÉCHEC: recontrôle SHA256SUMS invité non conforme');
}
main();
