#!/usr/bin/env node
// PREUVE Windows ciblée de la correction du helper COMMUN de sérialisation
// (SERIALIZATION_REVIEW_REQUIRED.md §2, 24/10/2026 21:31 UTC).
//
// Le cas exact qui gelait l'invité (PID 4740, 2681 Mo, ~20 min) : `Get-Content -Raw` renvoie un System.String
// enrichi par le provider (PSPath/PSParentPath/PSChildName/PSDrive/PSProvider/ReadCount/Length) ; placé dans
// $result sous la clé PackageJson puis passé par `ConvertTo-Json -Depth 10`, PowerShell descendait dans PSDrive
// (DriveInfo) et PSProvider (ProviderInfo) et partait en explosion du graphe d'objets.
//
// Ce pilote est STRICTEMENT EN LECTURE et ne reproduit PAS volontairement le gel : aucune application de
// ConvertTo-Json -Depth 10 sur l'objet enrichi. Il démontre, sur le VRAI Pesto.package.json du pack déployé :
//   1. l'enrichissement existe bien (noms des propriétés ETS, énumérés en simple lecture) ;
//   2. le chemin corrigé (Get-PlainText + ConvertTo-PestoJson) produit un JSON parseable, de longueur raisonnable,
//      avec TOUS les champs d'origine préservés, en quelques centaines de millisecondes ;
//   3. aucune expansion de propriétés provider : les balises [PESTO_NON_DATA_TYPE:...] remplacent les objets
//      hostiles (PSDriveInfo, Process, ProviderInfo) au lieu d'être parcourues ;
//   4. le paquet est identique à la copie locale du Spark (mêmes clés, mêmes valeurs), donc la preuve porte bien
//      sur le pack livré.
// Écritures invitées limitées à C:\Windows\Temp\pesto-v2-qual ; aucune écriture AD, aucun autre dossier, aucun
// redéploiement du tar de 1 Go, aucun arrêt de processus global.
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { runGuestJsonFile, LOCAL_EVIDENCE } from './lab-driver.mjs';

const PACK = 'C:\\PestoV2_Qual_20261024\\Pesto-2.0.0-DEV';
const EVIDENCE = 'ser-diag-v4';
const LOCAL_PACK = path.resolve(process.argv[2] ?? 'dist/Pesto-2.0.0-DEV');
const LOCAL_PKG = path.join(LOCAL_PACK, 'Pesto.package.json');

const GUEST = `$ErrorActionPreference='Stop'
$pack='${PACK}'
$pkgPath=Join-Path $pack 'Pesto.package.json'
if (-not (Test-Path -LiteralPath $pkgPath)) { throw 'Pesto.package.json absent du pack deploye' }
# 1) LECTURE SEULE de l'objet enrichi : on ne le serialise JAMAIS, on énumère seulement ses proprietes ETS.
$raw=Get-Content -LiteralPath $pkgPath -Raw -Encoding UTF8
$ets=@($raw.PSObject.Properties | ForEach-Object { [string]$_.Name })
$rawBaseType=[string](Get-PestoBase $raw).GetType().FullName
$rawChars=[int]$raw.Length
# 2) CHEMIN CORRIGE : texte lu en .NET (aucun provider implique) puis objet de données plat.
$text=Get-PlainText $pkgPath
$textType=[string]$text.GetType().FullName
$textEts=@($text.PSObject.Properties | ForEach-Object { [string]$_.Name })
$parsed=$text | ConvertFrom-Json
$keys=@($parsed.PSObject.Properties | ForEach-Object { [string]$_.Name })
# 3) Objets HOSTILES : ce que l'ancien ConvertTo-Json -Depth 10 aurait parcouru. Ici ils ne doivent produire
#    qu'une balise [PESTO_NON_DATA_TYPE:...], jamais une exploration du graphe.
$drv=Get-PSDrive -Name C
$prov=(Get-Item -LiteralPath $pkgPath).PSProvider
$proc=Get-Process -Id $PID
$fileInfo=Get-Item -LiteralPath $pkgPath
# 4) $result ne contient QUE des primitives, des tableaux et des dictionnaires de donnees.
$result=[ordered]@{
  Utc=(Get-Date).ToUniversalTime().ToString('o');
  Pack='$PACK';
  PackageJsonPath=$pkgPath;
  Enrichi_Type=$rawBaseType;
  Enrichi_PropertiesEts=$ets;
  Enrichi_Chars=$rawChars;
  Correct_Type=$textType;
  Correct_PropertiesEts=$textEts;
  Correct_Chars=[int]$text.Length;
  PackageJson=$text;
  PackageJsonKeys=$keys;
  HostileDrive=$drv;
  HostileProvider=$prov;
  HostileProcess=$proc;
  HostileNested=[ordered]@{ FileInfo=$fileInfo; Drive=(Get-Item -LiteralPath $pkgPath).PSDrive; Ok=$true }
}
`;

function main() {
  if (!existsSync(LOCAL_PKG)) {
    console.log(JSON.stringify({ verdict: 'ÉCHEC', reason: 'copie locale absente : ' + LOCAL_PKG }, null, 1));
    process.exitCode = 1; return;
  }
  const localText = readFileSync(LOCAL_PKG, 'utf8').replace(/^\uFEFF/, '');
  const localObj = JSON.parse(localText);
  const localKeys = Object.keys(localObj);

  const t0 = Date.now();
  const r = runGuestJsonFile(GUEST, EVIDENCE, { timeoutMs: 180000 });
  const wallMs = Date.now() - t0;
  const j = r.json;
  const evidenceFile = path.join(LOCAL_EVIDENCE, EVIDENCE + '.json');
  const raw = existsSync(evidenceFile) ? readFileSync(evidenceFile, 'utf8').replace(/^\uFEFF/, '') : '';

  const checks = {};
  const fail = [];
  if (!j) {
    console.log(JSON.stringify({ verdict: 'ÉCHEC', reason: 'aucun JSON invité relu',
      runCode: r.run?.code, stdout: r.run?.stdout?.slice(0, 800), stderr: r.run?.stderr?.slice(0, 800) }, null, 1));
    process.exitCode = 1; return;
  }

  checks.etsReellementPresent = ['PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider']
    .every((p) => (j.Enrichi_PropertiesEts ?? []).includes(p));
  // Un System.String .NET expose TOUJOURS sa propriété intrinsèque Length : ce n'est pas une propriété ETS du
  // provider. Ce qui doit avoir disparu, ce sont les 6 propriétés ajoutées par Get-Content.
  const PROVIDER_PROPS = ['PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider', 'ReadCount'];
  checks.texteCorrigeSansEts = Array.isArray(j.Correct_PropertiesEts)
    && j.Correct_PropertiesEts.every((p) => p === 'Length')
    && !PROVIDER_PROPS.some((p) => (j.Correct_PropertiesEts ?? []).includes(p));
  let pkgObj = null;
  try { pkgObj = JSON.parse(j.PackageJson ?? ''); } catch { pkgObj = null; }
  checks.jsonParseable = Boolean(pkgObj);
  checks.longueurRaisonnable = typeof j.PackageJson === 'string' && j.PackageJson.length > 20 && j.PackageJson.length < 200000;
  checks.champsPreserves = Boolean(pkgObj) && JSON.stringify(Object.keys(pkgObj).sort()) === JSON.stringify([...localKeys].sort())
    && JSON.stringify(pkgObj) === JSON.stringify(localObj);
  checks.identiqueALaCopieSpark = checks.champsPreserves;
  const noExpansion = raw.length > 0 && !/"(PSPath|PSParentPath|PSChildName|PSDrive|PSProvider|ReadCount|Length)"\s*:/.test(raw);
  checks.aucuneExpansionProvider = noExpansion;
  const balises = (raw.match(/\[PESTO_NON_DATA_TYPE:[^\]]+\]/g) ?? []);
  checks.hostilesRemplacesParBalise = balises.length >= 4
    && balises.some((b) => /PSDriveInfo/.test(b)) && balises.some((b) => /ProviderInfo/.test(b))
    && balises.some((b) => /Process/.test(b)) && balises.some((b) => /FileInfo/.test(b));
  checks.finRapide = (j.Guard?.ElapsedMs ?? 1e9) < 60000 && wallMs < 170000;
  checks.gardeSousBornes = Boolean(j.Guard) && j.Guard.WS_MB <= 512 && j.Guard.ElapsedMs <= 180000;
  checks.packageJsonContientFixedRuntime = /"webview2Runtime"\s*:\s*"fixed"/.test(j.PackageJson ?? '');

  for (const [k, v] of Object.entries(checks)) if (!v) fail.push(k);

  const verdict = fail.length === 0 ? 'OK' : 'ÉCHEC';
  console.log(JSON.stringify({
    verdict, fail,
    wallMs, guestElapsedMs: j.Guard?.ElapsedMs, guestWS_MB: j.Guard?.WS_MB, guestPid: j.Guard?.Pid,
    enrichi: { type: j.Enrichi_Type, chars: j.Enrichi_Chars, proprietesEts: j.Enrichi_PropertiesEts },
    corrige: { type: j.Correct_Type, chars: j.Correct_Chars, proprietesEts: j.Correct_PropertiesEts },
    packageJson: { chars: (j.PackageJson ?? '').length, cles: j.PackageJsonKeys, attenduCles: localKeys },
    balisesNonDonnees: balises,
    checks,
    evidence: evidenceFile, helper: r.helper ?? null,
  }, null, 1));
  process.exitCode = fail.length === 0 ? 0 : 1;
}
main();
