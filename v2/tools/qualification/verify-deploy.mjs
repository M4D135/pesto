#!/usr/bin/env node
// Recontrôle d'intégrité du pack déployé, exécuté en process invité DÉTACHÉ.
//
// Diagnostic instrumenté (recadrage superviseur 24/10 17:26 UTC — VM_PACK_REVIEW_REQUIRED.md) :
//  - Les deux anciens vérificateurs (verify-pack / verify-pack2) stagnaient à Checked=1200/1249 sans preuve de
//    fin. La sonde attachée diag-verify-tail.json a haché les fichiers 1195→1249 en 1 s (max 171 ms, tous ok) :
//    le hachage n'est DONC PAS la cause. Comme 1249 n'est pas multiple de 50, le dernier heartbeat était 1200 même
//    si la boucle avait fini → le gel est soit dans la section post-boucle (énumération / hash exe / ConvertTo-Json
//    final), soit dans une écriture hôte (barre de progression WriteProgress) du process détaché dont stdout est un
//    pipe orphelin quand le parent guestcontrol run est déjà sorti. Cause NON affirmée : on instrumente pour trancher.
//  - Règle superviseur : réparer le PILOTE et ses preuves d'exécution, PAS les règles de validation du pack. On
//    conserve donc exactement les contrôles (SHA256 de chaque ligne, absence, hash exe, package.json) et on ajoute :
//      * heartbeat « phase » + chemin exact AVANT chaque opération potentiellement bloquante (dont chaque hash) ;
//      * try/catch/finally → statut terminal COMPLETED/FAILED + ErrorRecord, écrit même en échec ;
//      * Start-Process avec -RedirectStandardOutput/-RedirectStandardError vers fichiers (plus de pipe orphelin) ;
//      * ProgressPreference/VerbosePreference/WarningPreference = SilentlyContinue (plus d'écriture hôte bloquante) ;
//      * enregistrement PID + heure de création + chemins stdout/stderr pour un arrêt ciblé par le superviseur.
//  - Nouveaux IDs/chemins de run (suffixe 3) : les anciens fichiers pollés (verify-*2) sont périmés et ignorés.
// Écritures invitées limitées à C:\Windows\Temp\pesto-v2-qual. Résultat jugé sur fichiers relus (copyfrom), jamais
// sur un code VBox. Aucun pkill/killall, aucun Stop-Process global : si un appel se bloque, on rapporte phase/PID.
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import path from 'node:path';
import { host, runGuestJson, ensureHelper } from './lab-driver.mjs';
import { strictPrelude } from './ps-strict.mjs';
import { laboMdpFichier } from './lab-config.mjs';

const PACK = 'C:\\PestoV2_Qual_20261024\\Pesto-2.0.0-DEV';
const GUEST_TMP = 'C:\\Windows\\Temp\\pesto-v2-qual';
const SCRIPT = `${GUEST_TMP}\\verify-pack3.ps1`;
const SELF = `${GUEST_TMP}\\verify-pack3.self.json`;
const PHASE = `${GUEST_TMP}\\verify-phase3.json`;
const PROGRESS = `${GUEST_TMP}\\verify-progress3.json`;
const FINAL = `${GUEST_TMP}\\verify-final3.json`;
const STDOUT = `${GUEST_TMP}\\verify-stdout3.txt`;
const STDERR = `${GUEST_TMP}\\verify-stderr3.txt`;
const HOST_FWD = 'C:/ADCC-Lab/validation/pesto-v2-20261024';
const HOST_DIR = 'C:\\ADCC-Lab\\validation\\pesto-v2-20261024';
const SSH_TARGET = 'degun@192.168.1.173';
const EXPECTED_EXE_SHA = '93ACBCAD0B6F390AE1CE6A1DBF1E09E165520A7F1196EB22323AFA64A9BBA96B';

// ---- vérificateur invité (règles de validation IDENTIQUES à l'ancien, + instrumentation) ---------------------
// Sérialisation : le résultat FINAL passe par le helper COMMUN ConvertTo-PestoJson (v2/tools/qualification/
// ps-strict.mjs), qui n'accepte que primitives / tableaux / dictionnaires de données et remplace tout objet
// non-données par une balise. L'ancienne exception manuelle (Esc/ArrJson recopiée ici) est supprimée : c'est le
// helper partagé qui corrige le chemin pour TOUS les pilotes (diagnostics, deploy, smoke), pas une 4e exception.
// Le gel observé (PID 4740, 2681 Mo) venait de ConvertTo-Json -Depth 10 sur le texte enrichi par le provider.
const VERIFIER = `$ErrorActionPreference='Stop'
$pack='${PACK}'
$phase='${PHASE}'
$progress='${PROGRESS}'
$final='${FINAL}'
foreach ($f in @($phase,$progress,$final)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
function Write-Phase([string]$name,[hashtable]$extra) {
  $o=[ordered]@{ Utc=(Get-Date).ToUniversalTime().ToString('o'); Phase=$name }
  if ($extra) { foreach ($k in $extra.Keys) { $o[$k]=$extra[$k] } }
  try { [System.IO.File]::WriteAllText($phase,(ConvertTo-PestoJson $o),(New-Object System.Text.UTF8Encoding($false))) } catch {}
}
$sw=[Diagnostics.Stopwatch]::StartNew()
$checked=0; $bad=@(); $missing=@(); $malformed=@(); $total=0; $finalObj=$null; $status='NO_RESULT'
try {
  Write-Phase 'begin' $null
  $sums=(Get-PlainText (Join-Path $pack 'SHA256SUMS')) -split '\\r?\\n'
  $lines=@($sums | Where-Object { $_.Trim() -ne '' })
  $total=$lines.Count
  Write-Phase 'sums-read' @{ Total=$total }
  foreach ($line in $lines) {
    if ($line.Trim() -eq '') { continue }
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { $malformed += ('MALFORME:' + $line.Substring(0,[Math]::Min(80,$line.Length))); continue }
    $rel=$Matches[2]; $want=$Matches[1].ToUpper()
    $abs=Join-Path $pack ($rel -replace '/','\\')
    Write-Phase 'hashing' @{ Checked=($checked+1); Rel=$rel }
    if (-not (Test-Path -LiteralPath $abs)) { $missing += $rel; $checked++; continue }
    $got=(Get-FileHash -LiteralPath $abs -Algorithm SHA256).Hash
    if ($got -ne $want) { $bad += $rel }
    $checked++
    Assert-PestoGuard
    if (($checked % 50) -eq 0) {
      $hb=[ordered]@{ Utc=(Get-Date).ToUniversalTime().ToString('o'); Checked=$checked; Total=$total; Mismatched=$bad.Count; Missing=$missing.Count; ElapsedSec=[int]$sw.Elapsed.TotalSeconds }
      [System.IO.File]::WriteAllText($progress,(ConvertTo-PestoJson $hb),(New-Object System.Text.UTF8Encoding($false)))
    }
  }
  Write-Phase 'loop-done' @{ Checked=$checked }
  Write-Phase 'enumerating' $null
  $present=@(Get-ChildItem -LiteralPath $pack -Recurse -File).Count
  Write-Phase 'exe-hash' $null
  $exePath=Join-Path $pack 'runtime\\webview2\\msedgewebview2.exe'
  $exeSha=(Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
  Write-Phase 'package-read' $null
  $pkg=Get-PlainText (Join-Path $pack 'Pesto.package.json')
  $note='signature prouvee sur la copie hote (webview2-hostcheck.json Valid) + egalite sha256; non re-testee dans l invite sans reseau'
  $status='COMPLETED'
  $finalObj=[ordered]@{ Utc=(Get-Date).ToUniversalTime().ToString('o'); Status='COMPLETED';
    ElapsedSec=[int]$sw.Elapsed.TotalSeconds; Checked=$checked; Total=$total;
    Mismatched=$bad; Missing=$missing; Malformed=$malformed; FilesPresent=$present;
    ExeSha256=$exeSha; SignatureNote=$note; PackageJson=$pkg }
  Write-Phase 'final-write' $null
} catch {
  $status='FAILED'
  $etype=if ($_.Exception) { $_.Exception.GetType().FullName } else { 'unknown' }
  $er=[string]($_ | Out-String)
  if ($er.Length -gt 4000) { $er=$er.Substring($er.Length-4000) }
  $finalObj=[ordered]@{ Utc=(Get-Date).ToUniversalTime().ToString('o'); Status='FAILED';
    ElapsedSec=[int]$sw.Elapsed.TotalSeconds; Checked=$checked; Total=$total;
    ExceptionType=$etype; Message=[string]$_.Exception.Message; ErrorRecord=$er }
} finally {
  if (-not $finalObj) { $finalObj=[ordered]@{ Status='NO_RESULT'; Checked=$checked; Total=$total } }
  try { [System.IO.File]::WriteAllText($final,(ConvertTo-PestoJson $finalObj),(New-Object System.Text.UTF8Encoding($false))) } catch {}
  try { Write-Phase 'exit' @{ Status=$status; Checked=$checked } } catch {}
}
`;

function evidenceDir() {
  return path.join(path.dirname(new URL(import.meta.url).pathname), '..', '..', 'logs', 'qualification');
}

function tail(file, n = 4000) {
  if (!existsSync(file)) return null;
  const s = readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
  return s.length > n ? s.slice(-n) : s;
}

// ---- start : copie le vérificateur sur l'invité puis le lance DÉTACHÉ avec stdout/stderr redirigés ------------
function start() {
  const dir = evidenceDir();
  mkdirSync(dir, { recursive: true });
  const localScript = path.join(dir, 'verify-pack3.ps1');
  // le vérificateur est lancé par Start-Process -File : il ne passe pas par le wrapper runGuestJsonFile,
  // donc le prélude STRICT (ConvertTo-PestoJson / Get-PlainText / gardes) est injecté ici, depuis le MÊME module.
  const h = ensureHelper();
  writeFileSync(localScript, '\uFEFF' + strictPrelude({ name: 'verify-pack3', selfPath: SELF, maxSec: 180, maxMb: 512, helperPath: h.guestPath }) + VERIFIER, 'utf8');
  const scp = spawnSync('scp', ['-o', 'BatchMode=yes', localScript, `${SSH_TARGET}:${HOST_FWD}/verify-pack3.ps1`],
    { encoding: 'utf8', timeout: 120000 });
  const copy = host(`"C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe" guestcontrol 9b2ad4f0-0506-4f58-aed2-c43ac1973516 copyto`
    + ` --username labadmin --passwordfile ${laboMdpFichier()} --quiet`
    + ` "${HOST_DIR}\\verify-pack3.ps1" "${SCRIPT}"`);
  const launcher = `$ErrorActionPreference='Stop'
foreach ($f in @('${SCRIPT}','${PHASE}','${PROGRESS}','${FINAL}','${STDOUT}','${STDERR}')) { }
Remove-Item -LiteralPath '${PHASE}','${PROGRESS}','${FINAL}','${STDOUT}','${STDERR}' -ErrorAction SilentlyContinue
$so='${STDOUT}'; $se='${STDERR}'
$p=Start-Process -FilePath 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe' `
  + `-ArgumentList '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File','${SCRIPT}' `
  + `-WindowStyle Hidden -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
$result=[ordered]@{ Started=(Get-Date).ToUniversalTime().ToString('o'); Pid=$p.Id;
  StartedProc=if ($p){$true}else{$false}; Stdout=$so; Stderr=$se }
`;
  const st = runGuestJson(launcher, 'verify-start3', { timeoutMs: 60000 });
  const out = { scpCode: scp.status, copyCode: copy.code, start: st.json ?? null,
    startError: st.json ? null : (st.run?.stdout + st.run?.stderr) };
  console.log(JSON.stringify(out, null, 1));
  process.exitCode = st.json?.Pid ? 0 : 1;
}

// ---- status : instantané complet lu côté invité (phase, progress, final, vivacité PID, tails stdout/stderr) ----
function status() {
  const dir = evidenceDir();
  mkdirSync(dir, { recursive: true });
  const probe = `$ErrorActionPreference='SilentlyContinue'
function ReadJson($p){ if (Test-Path -LiteralPath $p) { try { return (Get-PlainText $p | ConvertFrom-Json) } catch { return [ordered]@{ ParseError=$true } } } return $null }
function Tail($p,$n){ if (Test-Path -LiteralPath $p) { $s=Get-PlainText $p; if ($s.Length -gt $n) { return $s.Substring($s.Length-$n) } return $s } return $null }
$start=ReadJson '${GUEST_TMP}\\verify-start3.json'
$pid_=if ($start) { $start.Pid } else { $null }
$alive=$false; $procInfo=$null
if ($pid_) { $proc=Get-Process -Id $pid_ -ErrorAction SilentlyContinue; if ($proc) { $alive=$true;
  $procInfo=[ordered]@{ Id=$proc.Id; CPU=[math]::Round($proc.CPU,2); WS_MB=[math]::Round($proc.WorkingSet64/1MB,1);
    Threads=$proc.Threads.Count; Responding=$proc.Responding } } }
$result=[ordered]@{
  Now=(Get-Date).ToUniversalTime().ToString('o');
  Started=if ($start) { $start.Started } else { $null };
  Pid=$pid_; Alive=$alive; Proc=$procInfo;
  Phase=ReadJson '${PHASE}';
  Progress=ReadJson '${PROGRESS}';
  Final=ReadJson '${FINAL}';
  StdoutTail=Tail '${STDOUT}' 3000;
  StderrTail=Tail '${STDERR}' 3000 }
`;
  const st = runGuestJson(probe, 'verify-status3', { timeoutMs: 90000 });
  const s = st.json;
  if (!s) {
    console.log(JSON.stringify({ readable: false, runError: (st.run?.stdout + st.run?.stderr) }, null, 1));
    process.exitCode = 5;
    return;
  }
  const fin = s.Final;
  if (fin && fin.Status === 'COMPLETED') {
    const ok = (fin.Mismatched?.length ?? 1) === 0 && (fin.Missing?.length ?? 1) === 0
      && (fin.Malformed?.length ?? 1) === 0
      && fin.ExeSha256 === EXPECTED_EXE_SHA
      && fin.Checked === fin.Total && fin.Total === 1249
      && /"webview2Runtime":\s*"fixed"/.test(fin.PackageJson ?? '');
    const out = path.join(dir, 'pack-deployed-verify.json');
    writeFileSync(out, JSON.stringify({ verdict: ok ? 'OK' : 'ÉCHEC', ...fin }, null, 1), 'utf8');
    console.log(JSON.stringify({ done: true, ok, Checked: fin.Checked, Total: fin.Total,
      Mismatched: fin.Mismatched, Missing: fin.Missing, Malformed: fin.Malformed,
      FilesPresent: fin.FilesPresent, ExeSha256: fin.ExeSha256, ElapsedSec: fin.ElapsedSec }, null, 1));
    process.exitCode = ok ? 0 : 1;
  } else if (fin && fin.Status === 'FAILED') {
    console.log(JSON.stringify({ done: true, ok: false, failed: true, ...fin }, null, 1));
    process.exitCode = 1;
  } else {
    // pas de final : instantané de progression pour diagnostic (phase exacte + PID à transmettre au superviseur)
    const local = path.join(dir, 'verify-status3.json');
    console.log(JSON.stringify({ done: false, alive: s.Alive, pid: s.Pid, proc: s.Proc,
      phase: s.Phase, progress: s.Progress, stdoutTail: s.StdoutTail, stderrTail: s.StderrTail }, null, 1));
    process.exitCode = 3;
  }
}

// ---- stop : arrêt ciblé du SEUL vérificateur de pack (permission VM_RECOVERY_20261024.md §2) ------------------
// Identité exigée AVANT tout arrêt : Win32_Process du PID enregistré au start, Name=powershell.exe ET
// CommandLine contenant le chemin exact du script Pesto ; fields sérialisés en primitifs seulement (le gel
// précédent venait d'objets composites). Annulation refusée si identité différente. Aucun kill global.
function stop() {
  const dir = evidenceDir();
  mkdirSync(dir, { recursive: true });
  // $result reste PLAT et primitif (string/int/bool) ; la sérialisation passe par le helper COMMUN
  // ConvertTo-PestoJson, qui refuserait de toute façon d'explorer un objet Win32_Process/Get-Process complet.
  const kill = `$ErrorActionPreference='Stop'
$result=[ordered]@{ Status='NO_RESULT' }
$start=if (Test-Path -LiteralPath '${GUEST_TMP}\\verify-start3.json') { Get-PlainText '${GUEST_TMP}\\verify-start3.json' | ConvertFrom-Json } else { $null }
if (-not $start) {
  $result.Status='REFUSED'; $result.Reason='start3 absent'
} else {
  $pid_=[int]$start.Pid
  $wp=Get-CimInstance Win32_Process -Filter "ProcessId=$pid_" -ErrorAction SilentlyContinue
  if (-not $wp) {
    $result.Status='ALREADY_GONE'; $result.Pid=$pid_
  } elseif ($wp.Name -ne 'powershell.exe' -or $wp.CommandLine -notlike '*verify-pack3.ps1*') {
    $result.Status='REFUSED'; $result.Reason='identite differente'; $result.Pid=$pid_
    $result.Name=[string]$wp.Name
    $result.CmdTail=[string]((' ' + [string]$wp.CommandLine).Substring([Math]::Max(0,(' ' + [string]$wp.CommandLine).Length - 160)) -replace '[\x00-\x1f"\\]','?')
  } else {
    $result.Pid=$pid_; $result.Name=[string]$wp.Name; $result.CreationDate=[string]$wp.CreationDate
    Stop-Process -Id $pid_ -Force
    Start-Sleep -Milliseconds 800
    $gone = -not (Get-Process -Id $pid_ -ErrorAction SilentlyContinue)
    $result.Status=if ($gone) { 'STOPPED' } else { 'STOP_FAILED' }
    $result.Gone=$gone
  }
}
`;
  const st = runGuestJson(kill, 'verify-stop3', { timeoutMs: 60000 });
  console.log(JSON.stringify({ stop: st.json ?? null, runError: st.json ? null : (st.run?.stdout + st.run?.stderr) }, null, 1));
  process.exitCode = st.json && /^(STOPPED|ALREADY_GONE)$/.test(st.json.Status) ? 0 : 1;
}

const mode = process.argv[2];
if (mode === 'start') start();
else if (mode === 'status') status();
else if (mode === 'stop') stop();
else { console.error('usage: verify-deploy.mjs start | status | stop'); process.exitCode = 4; }
