#!/usr/bin/env node
// Smoke test invité headless du pack déployé (C:\PestoV2_Qual_20261024\Pesto-2.0.0-DEV), session labadmin
// (SessionId 0, sans session interactive tech.pesto — les essais GUI complets sont le lot suivant).
// Trois scénarios, jugés sur JSON invité relu (copyfrom), jamais sur un code VBox :
//  A args-refus   : Pesto.exe --mauvais-argument → refus host.args, exit 2 et message « Options acceptées » sur
//    stderr (canal non interactif : session 0 via guestcontrol, UserInteractive=false — le dialogue MessageBox
//    n'est possible qu'en session interactive, vérifié par le lot GUI). Aucun chemin de disque dans le message.
//  B runtime-absent : copie du tar sans runtime\webview2 → Pesto.exe doit refuser (exit 2, « moteur WebView2 fixe
//    manque » sur stderr, jamais de repli sur un navigateur installé), puis suppression de la copie.
//  C demarrage    : Pesto.exe --simulation → fenêtre « Pesto v2 — DEV — Simulation » réellement CRÉÉE (handle +
//    titre, via EnumWindows) et processus msedgewebview2.exe lancé depuis runtime\webview2 du pack (preuve que le
//    fixed runtime est chargé), process vivant sans erreur stderr. La VISIBILITÉ n'est pas exigée ici : le
//    harness guestcontrol tourne en SessionId 0 sans bureau interactif et un formulaire WinForms minimal y est
//    aussi IsWindowVisible=false (contrôle diag-minform-visible.json du 24/10 23:25 UTC) — la fenêtre visible,
//    rendue et navigable est qualifiée dans le lot GUI interactif tech.pesto (docs/QUALIFICATION-WINDOWS.md).
//    Avant/après : nettoyage limité aux processus Pesto/msedgewebview2 AU PROPRE identifiés par le chemin du
//    pack déployé (fuites des tentatives précédentes incluses) ; stderr lu APRÈS arrêt (les webviews enfants
//    héritent du handle de redirection — lecture partagée FileShare.ReadWrite).
// Aucun processus d'autre projet n'est touché ; aucune écriture hors dossier V2 de qualification et temp invité.
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { runGuestJsonFile } from './lab-driver.mjs';

const PACK = 'C:\\PestoV2_Qual_20261024\\Pesto-2.0.0-DEV';
const EXE = `${PACK}\\Pesto.exe`;

const WINDOW_PSH = `
if (-not ('Win32' -as [type])) {
  Add-Type -TypeDefinition 'using System;using System.Text;using System.Runtime.InteropServices;
  public class Win32{
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h,StringBuilder s,int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h,StringBuilder s,int n);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowExW(IntPtr p,IntPtr c,string cls,string win);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageW(IntPtr h,uint msg,IntPtr w,IntPtr l);
    public delegate bool EnumWindowsProc(IntPtr h,IntPtr l);
  }'
}
function Get-ProcWindows([int]$procId) {
  $script:found=@()
  $cb=[Win32+EnumWindowsProc]{ param($h,$l)
    $pid2=0; [void][Win32]::GetWindowThreadProcessId($h,[ref]$pid2)
    if ($pid2 -eq $procId) {
      $t=New-Object Text.StringBuilder 512; [void][Win32]::GetWindowTextW($h,$t,512)
      $c=New-Object Text.StringBuilder 256; [void][Win32]::GetClassNameW($h,$c,256)
      $texts=@()
      if ($c.ToString() -eq '#32770') {
        $child=[IntPtr]::Zero
        while ($true) {
          $child=[Win32]::FindWindowExW($h,$child,'Static',$null)
          if ($child -eq [IntPtr]::Zero) { break }
          $s=New-Object Text.StringBuilder 4096
          [void][Win32]::GetWindowTextW($child,$s,4096)
          if ($s.Length -gt 0) { $texts += $s.ToString() }
        }
      }
      # Visible est CONSIGNÉ mais ne filtre plus : en SessionId 0 (harness guestcontrol) toute fenêtre est
      # IsWindowVisible=false, y compris un formulaire WinForms minimal de contrôle — la visibilité réelle est
      # qualifiée dans le lot GUI interactif tech.pesto.
      $script:found += [ordered]@{ Title=$t.ToString(); Class=$c.ToString(); Texts=$texts;
        Visible=[bool][Win32]::IsWindowVisible($h) }
    }
    return $true }
  [void][Win32]::EnumWindows($cb,[IntPtr]::Zero)
  return $script:found
}`;

function scenarioScript(name) {
  const common = `$ErrorActionPreference='Stop'
${WINDOW_PSH}
$exe='${EXE}'
function Wait-ProcWindows([int]$pid2,[int]$timeoutSec) {
  $sw=[Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
    $w=Get-ProcWindows $pid2
    if ($w.Count -gt 0) { return $w }
    Start-Sleep -Milliseconds 500
  }
  return @()
}
`;
  if (name === 'args-refus') {
    return common + `$so='C:\\Windows\\Temp\\pesto-v2-qual\\smoke-args-out.txt'
$se='C:\\Windows\\Temp\\pesto-v2-qual\\smoke-args-err.txt'
Remove-Item -LiteralPath $so,$se -ErrorAction SilentlyContinue
$p=Start-Process -FilePath $exe -ArgumentList '--mauvais-argument' -PassThru -Wait -RedirectStandardOutput $so -RedirectStandardError $se
$err=''
if (Test-Path -LiteralPath $se) { $err=(Get-PlainText $se) }
$result=[ordered]@{ Scenario='args-refus'; Utc=(Get-Date).ToUniversalTime().ToString('o');
  Exit=$p.ExitCode; Stderr=$err }`;
  }
  if (name === 'runtime-absent') {
    // Copie séparée extraite du même tar invité, sans runtime\webview2 : le pack doit refuser de démarrer
    // (jamais de repli sur un navigateur installé). Le pack principal n'est pas modifié.
    return common + `$root='C:\\PestoV2_Qual_20261024'
$stage='C:\\Windows\\Temp\\pesto-v2-qual\\nr-stage'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
& 'C:\\Windows\\System32\\tar.exe' -xf 'C:\\Windows\\Temp\\pesto-v2-qual\\pesto-v2-pack.tar' -C $stage
if ($LASTEXITCODE -ne 0) { throw ('tar code ' + $LASTEXITCODE) }
$nr=Join-Path $root 'Pesto-2.0.0-DEV-NORUNTIME'
if (Test-Path -LiteralPath $nr) { Remove-Item -LiteralPath $nr -Recurse -Force }
Move-Item -LiteralPath (Join-Path $stage 'Pesto-2.0.0-DEV') -Destination $nr
Remove-Item -LiteralPath (Join-Path $nr 'runtime\\webview2') -Recurse -Force
try {
  $so='C:\\Windows\\Temp\\pesto-v2-qual\\smoke-nr-out.txt'
  $se='C:\\Windows\\Temp\\pesto-v2-qual\\smoke-nr-err.txt'
  Remove-Item -LiteralPath $so,$se -ErrorAction SilentlyContinue
  $p=Start-Process -FilePath (Join-Path $nr 'Pesto.exe') -PassThru -Wait -RedirectStandardOutput $so -RedirectStandardError $se
  $err=''
  if (Test-Path -LiteralPath $se) { $err=(Get-PlainText $se) }
} finally {
  Remove-Item -LiteralPath $nr -Recurse -Force -ErrorAction SilentlyContinue
}
$result=[ordered]@{ Scenario='runtime-absent'; Utc=(Get-Date).ToUniversalTime().ToString('o');
  NoRuntimeDeleted=(-not (Test-Path -LiteralPath $nr)); Exit=$p.ExitCode; Stderr=$err }`;
  }
  return common + `$packPath='${PACK}\\'
# Nettoyage AVANT : seuls les processus au propre dont le Path est sous le pack déployé (fuites des lots précédents).
Get-Process Pesto -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ($packPath+'*') } |
  Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process msedgewebview2 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '${PACK}\\runtime\\webview2\\*' } |
  Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
$so='C:\\Windows\\Temp\\pesto-v2-qual\\smoke-start-out.txt'
$se='C:\\Windows\\Temp\\pesto-v2-qual\\smoke-start-err.txt'
Remove-Item -LiteralPath $so,$se -ErrorAction SilentlyContinue
$p=Start-Process -FilePath $exe -ArgumentList '--simulation' -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
$sw=[Diagnostics.Stopwatch]::StartNew()
$wins=@(); $webviews=@(); $alive=$true; $exit=-99
while ($sw.Elapsed.TotalSeconds -lt 45) {
  $wins=@(Get-ProcWindows $p.Id)
  $webviews=@(Get-Process msedgewebview2 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '${PACK}\\runtime\\webview2\\*' } |
    ForEach-Object { [ordered]@{ Pid=[int]$_.Id; Path=[string]$_.Path } })
  try { $alive=(-not $p.HasExited) } catch { $alive=$false }
  if (-not $alive) { try { $exit=[int]$p.ExitCode } catch { $exit=-98 }; break }
  if ($wins.Count -gt 0 -and $webviews.Count -gt 0) { break }
  Assert-PestoGuard
  Start-Sleep -Milliseconds 1000
}
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
# Nettoyage limité aux processus au propre, identifiés par le chemin du pack déployé (aucun autre projet).
Get-Process msedgewebview2 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '${PACK}\\runtime\\webview2\\*' } |
  Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process Pesto -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ($packPath+'*') } |
  Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$err=''
if (Test-Path -LiteralPath $se) {
  # Lecture PARTAGÉE : les webviews enfants héritent du handle de redirection ; ReadAllBytes échouerait en sharing violation.
  try { $fs=[IO.File]::Open($se,'Open','Read','ReadWrite'); $sr=New-Object IO.StreamReader($fs,[Text.Encoding]::UTF8)
    $err=$sr.ReadToEnd(); $sr.Dispose() } catch { $err=('READ_ERR:'+($_.Exception.Message)) }
}
$webviewsAfter=@(Get-Process msedgewebview2 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '${PACK}\\runtime\\webview2\\*' } | ForEach-Object { $_.Id })
$pestoAfter=@(Get-Process Pesto -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ($packPath+'*') } | ForEach-Object { $_.Id })
$result=[ordered]@{ Scenario='demarrage'; Utc=(Get-Date).ToUniversalTime().ToString('o');
  SessionId=[int](Get-Process -Id $PID).SessionId; AliveAtEnd=$alive; ExitIfDead=$exit;
  Windows=$wins; WebviewProcesses=$webviews; Stderr=$err;
  WebviewAfterKill=$webviewsAfter; PestoAfterKill=$pestoAfter }`;
}

const evidenceDir = path.join(path.dirname(new URL(import.meta.url).pathname), '..', '..', 'logs', 'qualification');
const out = path.join(evidenceDir, 'smoke-pack.json');
const results = { utc: new Date().toISOString(), pack: PACK, scenarios: {} };
let allOk = true;

function judge(name, j) {
  if (!j) return false;
  if (name === 'args-refus') {
    const err = j.Stderr ?? '';
    return j.Exit === 2 && /Options accept/.test(err) && !/[A-Za-z]:\\/.test(err);
  }
  if (name === 'runtime-absent') {
    const err = j.Stderr ?? '';
    return j.NoRuntimeDeleted === true && j.Exit === 2 && /WebView2 fixe manque/.test(err) && !/[A-Za-z]:\\/.test(err);
  }
  // Session 0 : fenêtre créée (handle+titre) + fixed runtime réellement chargé + process vivant + stderr vide.
  // La visibilité/rendu de la fenêtre est jugée au lot GUI interactif (voir en-tête du scénario C).
  const w = j.Windows ?? [];
  return j.AliveAtEnd === true && (j.Stderr ?? 'x') === '' &&
    w.some((x) => /Pesto v2 — DEV — Simulation/.test(x.Title)) && (j.WebviewProcesses ?? []).length > 0;
}

for (const name of ['args-refus', 'runtime-absent', 'demarrage']) {
  const r = await runGuestJsonFile(scenarioScript(name), `smoke-${name}`, { timeoutMs: 180000 });
  const ok = judge(name, r.json);
  results.scenarios[name] = { ok, json: r.json ?? { error: 'aucun JSON relu', runCode: r.run?.code } };
  if (!ok) allOk = false;
  console.log(`[${name}] ok=${ok}`);
}
results.verdict = allOk ? 'OK' : 'ÉCHEC';
mkdirSync(evidenceDir, { recursive: true });
writeFileSync(out, JSON.stringify(results, null, 1), 'utf8');
console.log('VERDICT', results.verdict);
process.exitCode = allOk ? 0 : 1;
