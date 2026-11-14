#!/usr/bin/env node
// Auto-test du chemin d'ANNULATION CIBLÉE exigé par SERIALIZATION_REVIEW_REQUIRED.md §2 :
// « Tous les pilotes EN LECTURE doivent avoir borne 180 s/512 Mo et annulation de leur propre PID
// identifié/création/owner/script ».
//
// Deux modes :
//   sleep  : lance en invité un script de lecture qui dort 90 s (aucune écriture, aucune mutation) et enregistre
//            son PID via le helper commun (self-<name>.json : PID, nom, création, owner, script).
//   cancel : annule CE SEUL processus après contrôle d'identité complet. Si l'identité ne correspond pas
//            (nom, date de création, script, owner), le résultat est REFUSED et aucun processus n'est touché.
// Aucun arrêt global : ni pkill, ni killall, ni Stop-Process sans identité vérifiée.
import { runGuestJson, cancelOwnRun } from './lab-driver.mjs';

const NAME = process.env.PESTO_CANCEL_NAME ?? 'cancel-test-v4';
const mode = process.argv[2];

if (mode === 'sleep') {
  const t0 = Date.now();
  const r = runGuestJson(`$result=[ordered]@{ BeforeSleep=(Get-Date).ToUniversalTime().ToString('o') }
Start-Sleep -Seconds 90
$result.AfterSleep=(Get-Date).ToUniversalTime().ToString('o')`, NAME, { timeoutMs: 180000 });
  console.log(JSON.stringify({ wallMs: Date.now() - t0, runCode: r.run?.code, json: r.json ?? null }, null, 1));
  process.exitCode = 0;
} else if (mode === 'cancel') {
  const t0 = Date.now();
  const r = cancelOwnRun(NAME);
  const j = r.json;
  console.log(JSON.stringify({ wallMs: Date.now() - t0, runCode: r.run?.code, json: j ?? null,
    stderr: r.run?.stderr?.slice(0, 400) }, null, 1));
  process.exitCode = j && /^(STOPPED|ALREADY_GONE)$/.test(String(j.Status)) ? 0 : 1;
} else if (mode === 'refuse') {
  // Faux enregistrement : le PID vise n'est PAS un powershell lancé par ce pilote. L'annulation doit être REFUSÉE
  // et le processus visé doit rester vivant (démonstration que le contrôle d'identité n'est pas décoratif).
  const forged = runGuestJson(`$wp=Get-CimInstance Win32_Process -Filter "Name='svchost.exe'" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $wp) { throw 'aucun svchost trouve' }
$self=[ordered]@{ Name='cancel-foreign-v4'; Pid=[int]$wp.ProcessId; ProcessName='powershell.exe';
  Owner=[string][System.Security.Principal.WindowsIdentity]::GetCurrent().Name;
  CreationDate=[string]$wp.CreationDate; CommandLineTail='forge'; ScriptPath='C:\\Windows\\Temp\\pesto-v2-qual\\tool-cancel-foreign-v4.ps1';
  StartedUtc=(Get-Date).ToUniversalTime().ToString('o') }
$result=[ordered]@{ ForgedPid=[int]$wp.ProcessId; ForgedName=[string]$wp.Name;
  Written=(Write-PestoResult -Result $self -Path 'C:\\Windows\\Temp\\pesto-v2-qual\\cancel-foreign-v4.self.json') }`, 'cancel-foreign-self', { timeoutMs: 60000 });
  const c = cancelOwnRun('cancel-foreign-v4');
  const j = c.json;
  const pid = forged.json?.ForgedPid;
  const alive = runGuestJson(`$wp=Get-CimInstance Win32_Process -Filter "ProcessId=${pid}" -ErrorAction SilentlyContinue
$result=[ordered]@{ StillAlive=[bool]$wp; Name=[string]$wp.Name }`, 'cancel-foreign-alive', { timeoutMs: 60000 });
  const ok = Boolean(j) && j.Status === 'REFUSED' && alive.json?.StillAlive === true;
  console.log(JSON.stringify({ forged: forged.json, cancel: j ?? null, cible: alive.json,
    attendu: 'REFUSED + cible toujours vivante', ok }, null, 1));
  process.exitCode = ok ? 0 : 1;
} else {
  console.error('usage: cancel-selftest.mjs sleep | cancel | refuse');
  process.exitCode = 2;
}
