#!/usr/bin/env node
// Qualification GUI RÉELLE en session interactive 1 (tech.pesto) — PROGRESS.nextLot du 24/10 23:37 UTC.
// Le harnais guestcontrol SessionId 0 est PROUVÉ inapte à la visibilité (diag-minform-visible.json) : ce pilote
// lance donc l'application dans la VRAIE session console via le clavier de la console VBox (scancodes AZERTY,
// méthode réussie de VM_RECOVERY_20261024.md) et juge sur deux preuves indépendantes :
//  1) énumération Win32 (EnumWindows/IsWindowVisible/GetWindowRect/SessionId) depuis labadmin en Session 0 :
//     une fenêtre visible de l'invité Session 1 est observable d'ici (IsWindowVisible est un attribut de fenêtre) ;
//  2) watcher UIAutomation exécuté DANS la session 1 (via Exécuter → C:\Temp\w.bat, donc sous tech.pesto) :
//     nom du document WebView2 (= « <page> · Pesto » posé par router.js), présence de la palette, largeur du rail.
// Aucun mot de passe tech.pesto n'existe sur l'hôte (inventaire 25/10 01:5x UTC : aucun fichier de C:\ADCC-Lab\private
// ne contient « pesto ») — le clavier console est la seule voie, et elle n'utilise aucun secret.
// Les variables WEBVIEW2_* restent nettoyées par HostPolicy.ClearBrowserOverrides : AUCUN contournement (CDP refusé
// par conception). Les captures d'écran sont des artefacts pour le superviseur, le JUGEMENT reste programmatique.
import { spawnSync, spawn } from 'node:child_process';
import { writeFileSync, mkdirSync, existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { host, runGuest, runGuestJsonFile } from './lab-driver.mjs';
import { HELPER_PS } from './ps-strict.mjs';
import { laboMdpFichier, laboNetbios } from './lab-config.mjs';
import { watcherPresence, watcherStopResult } from './watcher-result.mjs';

const PACK = 'C:\\PestoV2_Qual_20261024\\Pesto-2.0.0-DEV';
const TITLE = 'Pesto v2 — DEV — Simulation';
const TEMP = 'C:\\Temp';
const PUB = 'C:\\Users\\Public\\pesto-gui';
const HOST_DIR = 'C:\\ADCC-Lab\\validation\\pesto-v2-20261024';
const HOST_FWD = 'C:/ADCC-Lab/validation/pesto-v2-20261024';
const LOCAL_GUI = path.join(process.cwd(), 'logs', 'qualification', 'gui');
const SSH_TARGET = 'degun@192.168.1.173';
const VM_UUID = '9b2ad4f0-0506-4f58-aed2-c43ac1973516';
const VBOXMANAGE = '"C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe"';

// ---- Scancodes AZERTY (make ; break = make|0x80 ; étendus préfixés E0) ---------------------------------------
// Table 0000040C (français) COR Rigée le 25/10/2026 contre la capture supervisor-gui-current.png : l'ancien tableau
// tapait « CM\Te,p\w:bat » pour « C:\Temp\w.bat » — trois fautes, trois causes : ':' cherché sous Shift+0x27 (tapait
// « M »), 'm' à 0x32 (tapait « , »), '.' à 0x34 (tapait « : »). Les scancodes éprouvés du handoff (m=27 a7 ;
// w=2c ac ; :=34 b4 ; point=2a 33 b3 aa ; antislash=e0 38 09 89 e0 b8 ; slash=2a 34 b4 aa ; Ctrl+A=1d 10 90 9d)
// sont repris tels quels et vérifiés octet à octet par tools/tests/azerty-check.mjs.
// Rangée chiffres : la touche produit le symbole SANS shift et le chiffre AVEC shift (1=& 2=é 3=" 4=' 5=( 6=- 7=è
// 8=_ 9=ç 0=à ; puis 0x0c=) / shift=°, 0x0d== / shift=+). Rangée du bas : 0x32=, 0x33=; 0x34=: 0x35=! (shift :
// ? . / respectivement sur 0x32/0x33/0x34). 'm'=0x27, 'ù'=0x28, '²'=0x29, '<'=touche 102 e0 56.
const LETTERS = { a: 0x10, z: 0x11, e: 0x12, r: 0x13, t: 0x14, y: 0x15, u: 0x16, i: 0x17, o: 0x18, p: 0x19,
  q: 0x1e, s: 0x1f, d: 0x20, f: 0x21, g: 0x22, h: 0x23, j: 0x24, k: 0x25, l: 0x26, m: 0x27,
  w: 0x2c, x: 0x2d, c: 0x2e, v: 0x2f, b: 0x30, n: 0x31 };
const DIGITS = { '1': 0x02, '2': 0x03, '3': 0x04, '4': 0x05, '5': 0x06, '6': 0x07, '7': 0x08, '8': 0x09, '9': 0x0a, '0': 0x0b };
const PLAIN = { ' ': 0x39, '&': 0x02, 'é': 0x03, '"': 0x04, "'": 0x05, '(': 0x06, '-': 0x07, 'è': 0x08,
  '_': 0x09, 'ç': 0x0a, 'à': 0x0b, ')': 0x0c, '=': 0x0d, ',': 0x32, ';': 0x33, ':': 0x34, '!': 0x35,
  'ù': 0x28, '²': 0x29, '<': [0xe0, 0x56] };
const SHIFTED = { '?': 0x32, '.': 0x33, '/': 0x34, '+': 0x0d, '°': 0x0c };
// AltGr : seuls les replis réellement établis sont conservés ; un caractère non établi reste NON MAPPÉ
// (erreur explicite) plutôt qu'un code deviné qui taperait un autre caractère en silence.
const ALTGR = { '\\': 0x09, '@': 0x0b, '~': 0x02, '#': 0x03, 'µ': 0x27, '€': 0x12 };
const CTRL = 0x1d, ALT = 0x38, LSHIFT = 0x2a, ENTER = 0x1c, ESC = 0x01, F4 = 0x3e;
const NUMPAD = { 1: [0xe0, 0x4f], 2: [0xe0, 0x4c], 3: [0xe0, 0x50], 4: [0xe0, 0x45], 5: [0xe0, 0x47], 6: [0xe0, 0x48], 7: [0xe0, 0x4b], 8: [0xe0, 0x4d], 9: [0xe0, 0x52] };

function sendCodes(codes) {
  const r = host(`${VBOXMANAGE} controlvm ${VM_UUID} keyboardputscancode ${codes.map((c) => c.toString(16).padStart(2, '0')).join(' ')}`, 60000);
  if (r.code !== 0) throw new Error('keyboardputscancode code=' + r.code + ' ' + (r.stderr || r.stdout).slice(0, 300));
}
export function tapCodes(code, { ctrl = false, alt = false, shift = false } = {}) {
  const pre = [];
  if (ctrl) pre.push(CTRL);
  if (alt) pre.push(ALT);
  if (shift) pre.push(LSHIFT);
  const makeArr = Array.isArray(code) ? code : [code];
  const down = [...pre, ...makeArr];
  const up = makeArr.map((c) => (c >= 0xe0 ? c : c | 0x80));
  return [...down, ...up, ...[...pre].reverse().map((c) => c | 0x80)];
}
function tap(code, opts = {}) { sendCodes(tapCodes(code, opts)); }
export function charCodes(ch) {
  const low = ch.toLowerCase();
  if (PLAIN[ch] !== undefined) return tapCodes(PLAIN[ch]);
  if (SHIFTED[ch] !== undefined) return tapCodes(SHIFTED[ch], { shift: true });
  // AltGr = RMENU seul (e0 38), forme ÉPROUVÉE sur la console VBox (handoff 25/10 : antislash = e0 38 09 89 e0 b8).
  // L'ancienne forme Ctrl+Alt (e0 1d e0 38 …) n'est pas la séquence validée sur ce clavier.
  if (ALTGR[ch] !== undefined) return [0xe0, 0x38, ALTGR[ch], ALTGR[ch] | 0x80, 0xe0, 0xb8];
  if (DIGITS[ch] !== undefined) return tapCodes(DIGITS[ch], { shift: true });
  if (LETTERS[low] === undefined) throw new Error('caractère non mappé AZERTY : ' + JSON.stringify(ch));
  return tapCodes(LETTERS[low], { shift: ch !== low });
}
export function codesForText(text) { return [...text].flatMap(charCodes); }
export { sendCmd, readLatest, shot, collect, enumWindows, sendCodes, tapCodes as tapCodesX };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- Agent UIAutomation session 1 (lancé par tech.pesto ; canal de commande sans clavier) ----------------
// Le clavier console est capricieux (Start ne parse pas les arguments, politique DisableCMD soupçonnée) et
// aucune tâche InteractiveToken n'est possible sans élévation (labadmin = admin à jeton filtré). L'agent tourne
// DONC dans la session 1 sous tech.pesto (démarré une seule fois via Start : C:\Temp\w.bat) et sert de canal :
// le pilote écrit cmd.txt (liste fermée sans aucun arrêt de processus — voir revue 25/10 03:17 UTC),
// l'agent l'exécute et journalise chaque tick
// (fenêtres racine UIA, fenêtre Pesto, document WebView2, palette, largeur du rail) dans status.ndjson + latest.json.
export const WATCH_PS = `param([int]\$Ticks=600,[double]\$DelaySec=1.0,[string]\$Dir='C:\\Users\\Public\\pesto-gui')
` + HELPER_PS + `
# Agent UIAutomation — exécuté par tech.pesto DANS la session console 1 (C:\Temp\w.bat).
# Écritures limitées à C:\Users\Public\pesto-gui. Aucun réseau, aucun secret, aucune autre écriture.
\$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
\$AE=[System.Windows.Automation.AutomationElement]
function Get-EditValue(\$el) {
  # Chaîne de lecture du texte d'un champ : ValuePattern (cas général) → TextPattern (certains inputs WebView2
  # exposent le texte via Text et non Value — réel 25/10 07:3x UTC : la palette renvoyait « » alors que la
  # frappe était appliquée, prouvé par l'exécution Entrée qui fonctionnait) → Name (repli). $null si rien.
  if (\$null -eq \$el) { return \$null }
  \$v=\$null
  try { \$p=\$el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if (\$null -ne \$p) { \$v=[string]([System.Windows.Automation.ValuePattern]\$p).Current.Value } } catch {}
  if ([string]::IsNullOrEmpty(\$v)) { try { \$p=\$el.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern); if (\$null -ne \$p) { \$dr=([System.Windows.Automation.TextPattern]\$p).DocumentRange; if (\$null -ne \$dr) { \$v=[string]\$dr.GetText(-1) } } } catch {} }
  
  return \$v
}
# BUG RÉEL découvert à la 1re exécution (tick 113, 25/10 03:22 UTC) : sur une VARIABLE de type, PS 5.1 ne résout
# PAS les membres statiques par point (l'ancienne variable $TS portée par point donnait $null => FindAll levait « value "" »). Les portées sont donc
# écrites entièrement qualifiées avec ::, et le 2e argument de FindAll est un PropertyCondition, jamais un ControlType nu.
\$CT=[System.Windows.Automation.ControlType]
if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
\$sid=(Get-Process -Id $PID).SessionId
# GARDE SINGLETON (cause racine d'un latest.json corrompu, 25/10 05:3x UTC) : deux watch.ps1 simultanés
# entrelacent leurs WriteAllText (le plus court laisse la queue du plus long => JSON illisible). Un second agent
# qui détecte un pair déjà vivant dans la même session s'éteint immédiatement sans rien écrire.
$dup=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { ([int]$_.ProcessId -ne $PID) -and ([string]$_.CommandLine -like '*watch.ps1*') -and ([int]$_.SessionId -eq $sid) })
if ($dup.Count -gt 0) { exit 0 }
# IDENTITÉ enregistrée à chaque démarrage (exigence revue 25/10 03:17 UTC) : PID, date de création,
# propriétaire, chemin EXACT du script, session. Relue par STOP_WATCH avant tout auto-arrêt ; le pilote
# (stop-watch) la recontrôle côté lecture et prouve la disparition par le PID enregistré.
$wpi0=Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
$watchIdent=[ordered]@{ Pid=[int]$PID; Creation=[string]$wpi0.CreationDate; Owner=[string][System.Security.Principal.WindowsIdentity]::GetCurrent().Name; Script='C:\\Temp\\watch.ps1'; Session=[int]$sid; StartedUtc=(Get-Date).ToUniversalTime().ToString('o') }
$tmpi=Join-Path $Dir 'watcher-identity.tmp'
[System.IO.File]::WriteAllText($tmpi,(ConvertTo-PestoJson $watchIdent),(New-Object System.Text.UTF8Encoding($false)))
Move-Item -LiteralPath $tmpi -Destination (Join-Path $Dir 'watcher-identity.json') -Force
try { Add-Type -Namespace PestoGui -Name K -MemberDefinition '[DllImport("user32.dll")] public static extern short GetKeyState(int n); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, int flags, int extra);' } catch {}
\$nd=Join-Path $Dir 'status.ndjson'
\$cmdFile=Join-Path $Dir 'cmd.txt'
# Résultat de la DERNIÈRE commande conservé entre les ticks : les ticks défilent (~8/s, Sleep 1 s + UIA rapide)
# et le tick porteur de Cmd était écrasé dans latest.json avant la prochaine lecture (1,8 s) — jugements
# FOCUS/CLICK/READ_EDIT tombaient en « timeout » alors que la commande avait réussi (prouvé 25/10 06:1x UTC,
# 715 ticks sans erreur pendant que waitCmd « ne voyait rien »).
\$LC=[ordered]@{ Cmd=$null; CmdDone=$null; CmdErr=$null; EditText=$null; FocusWin=$null; LaunchedPid=$null; KillTargets=$null; Clicked=$null; ClickedVia=$null; Focused=$null; ForegroundOk=$null }
for (\$i=1; $i -le $Ticks; $i++) {
  $snap=[ordered]@{ Tick=$i; Utc=(Get-Date).ToUniversalTime().ToString('o'); SessionId=$sid; Err=$null; Cmd=$null }
  try {
    try { $snap.NumLock=[int]([PestoGui.K]::GetKeyState(0x90) -band 1) } catch {}
    if (Test-Path -LiteralPath $cmdFile) {
      $c=(Get-PlainText $cmdFile).Trim()
      Remove-Item -LiteralPath $cmdFile -Force
      $snap.Cmd=$c
      try {
        # Liste fermée de commandes, SANS AUCUN arrêt de processus (revue superviseur 25/10 03:17 UTC) :
        # KILL_PESTO et CLOSE_SNIP sont retirés ; le watcher observe, clique, lit — il ne tue jamais.
        $ownPesto=@(Get-CimInstance Win32_Process -Filter "Name='Pesto.exe'" | Where-Object { ([string]$_.ExecutablePath -like 'C:\\PestoV2_Qual_20261024\\*') -and ([int]$_.SessionId -eq $sid) })
        if ($c -eq 'LAUNCH_PESTO') {
          if ($ownPesto.Count -gt 0) { $snap.Launched='deja_en_cours' } else {
            $p=Start-Process -FilePath 'C:\\PestoV2_Qual_20261024\\Pesto-2.0.0-DEV\\Pesto.exe' -ArgumentList '--simulation' -PassThru
            $snap.LaunchedPid=[int]$p.Id
          }
          $snap.PestoPids=@($ownPesto | ForEach-Object { [int]$_.ProcessId })
        }
        elseif ($c -eq 'KILL_PESTO') {
          # RETIRÉ (revue superviseur 25/10 03:17 UTC) : « chemin sous le pack + session » ne prouve ni la
          # création, ni le propriétaire, ni que le PID a été lancé/adopté par ce pilote. Le watcher ne tue
          # plus jamais rien ; aucun Stop-Process ne subsiste dans ce script.
          throw 'KILL_PESTO retire du pilote : le watcher ne tue aucun processus (revue 25/10 03:17 UTC)'
        }
        elseif ($c -eq 'READ_EDIT') {
          # Relit le champ texte focalisé AVANT toute Entrée : validation de la frappe.
          # Cas 1/2 : dialogue Exécuter (élément focalisé ou fenêtre fille de la racine).
          $snap.EditText=$null; $snap.FocusWin=$null
          # Cas 3 (lot 31) : focus PROFOND dans la fenêtre Pesto (champ de la palette Ctrl+K) :
          # l'élément focalisé n'est jamais un fils direct de la racine, on le cherche dans le sous-arbre Pesto.
          $fe=$AE::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children,(New-Object System.Windows.Automation.PropertyCondition($AE::HasKeyboardFocusProperty,$true)))
          # Repli dialogue Exécuter : la 1re exécution réelle (25/10 03:50 UTC) montre le dialogue en ANGLAIS, nommé
          # « Run » (et non « Exécuter ») sur cette installation — les deux noms sont testés.
          if ($null -eq $fe) { $fe=$AE::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children,(New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty,'Exécuter'))) }
          if ($null -eq $fe) { $fe=$AE::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children,(New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty,'Run'))) }
          if ($null -ne $fe) { $snap.FocusWin=[string]$fe.Current.Name }
          if ($null -eq $fe) {
            $kw=$AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,$CT::Window))); $kn=$kw.Count; if ($kn -gt 40) { $kn=40 }
            $pw=$null
            for ($q=0; $q -lt $kn; $q++) { if ($kw.Item($q).Current.Name -like 'Pesto v2*') { $pw=$kw.Item($q); break } }
            if ($null -ne $pw) {
              $fe=$pw.FindFirst([System.Windows.Automation.TreeScope]::Subtree,(New-Object System.Windows.Automation.PropertyCondition($AE::HasKeyboardFocusProperty,$true)))
              if ($null -ne $fe) { $snap.FocusWin=[string]$pw.Current.Name }
            }
          }
          if ($null -ne $fe) {
            $ed=$fe.FindFirst([System.Windows.Automation.TreeScope]::Subtree,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,$CT::Edit)))
            if ($null -ne $ed) { $snap.EditText=Get-EditValue $ed }
          }
          # Repli palette WebView2 : HasKeyboardFocus n'est pas toujours posé sur l'élément DOM focalisé ;
          # le champ de recherche porte l'aria-label « Rechercher un écran ou une commande » (palette.js:60).
          if ($null -eq $snap.EditText) {
            $kw5=$AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,$CT::Window))); $kn5=$kw5.Count; if ($kn5 -gt 40) { $kn5=40 }
            $pw5=$null
            for ($q=0; $q -lt $kn5; $q++) { if ($kw5.Item($q).Current.Name -like 'Pesto v2*') { $pw5=$kw5.Item($q); break } }
            if ($null -ne $pw5) {
              $ed5=$pw5.FindFirst([System.Windows.Automation.TreeScope]::Subtree,(New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty,'Rechercher un écran ou une commande')))
              if ($null -ne $ed5) { $snap.EditText=Get-EditValue $ed5; if (-not $snap.FocusWin) { $snap.FocusWin='palette' } }
            }
          }
        }
        elseif ($c -eq 'MAXIMIZE_PESTO' -or $c -eq 'RESTORE_PESTO') {
          # Taille de la fenêtre Pesto (jugement KPI taille normale vs maximisée) — WindowPattern sur NOTRE fenêtre.
          $kw2=$AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,$CT::Window))); $kn2=$kw2.Count; if ($kn2 -gt 40) { $kn2=40 }
          $pw2=$null
          for ($q=0; $q -lt $kn2; $q++) { if ($kw2.Item($q).Current.Name -like 'Pesto v2*') { $pw2=$kw2.Item($q); break } }
          if ($null -eq $pw2) { throw 'fenetre Pesto absente' }
          $wp=[System.Windows.Automation.WindowPattern]$pw2.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
          if ($c -eq 'MAXIMIZE_PESTO') { $wp.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Maximized) }
          else { $wp.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Normal) }
          $snap.WinStateRequested=$c
        }
        elseif ($c -eq 'FOCUS_PESTO') {
          # Le clavier console va à la fenêtre ACTIVE : sans focus sur Pesto, Alt+1..9 et Ctrl+B/K ne servent à rien
          # (prouvé 25/10 03:47-03:50 UTC : les 9 Alt+N restaient sur « Accueil · Pesto », le focus était au console).
          $kw3=$AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,$CT::Window))); $kn3=$kw3.Count; if ($kn3 -gt 40) { $kn3=40 }
          $pw3=$null
          for ($q=0; $q -lt $kn3; $q++) { if ($kw3.Item($q).Current.Name -like 'Pesto v2*') { $pw3=$kw3.Item($q); break } }
          if ($null -eq $pw3) { throw 'fenetre Pesto absente' }
          # SetFocus est une méthode de l'AUTOMATION ELEMENT, pas du WindowPattern (CmdErr réel 25/10 06:2x UTC :
          # « [WindowPattern] does not contain a method named 'SetFocus' »).
          $pw3.SetFocus()
          # SetFocus (UIA) ne garantit PAS la fenêtre PREMIER PLAN : le clavier injecté part à la fenêtre active
          # (FAIL réel 25/10 07:5x UTC : Ctrl+B 223→223 malgré FOCUS_PESTO CmdDone=true). On force
          # SetForegroundWindow sur le HWND de Pesto et on le vérifie (ForegroundOk dans latest2).
          $hw3=[IntPtr]$pw3.Current.NativeWindowHandle
          [void][PestoGui.K]::SetForegroundWindow($hw3)
          $snap.ForegroundOk=([PestoGui.K]::GetForegroundWindow() -eq $hw3)
          $snap.Focused=$true
        }
        elseif ($c -like 'CLICK_NAMED=*') {
          # Clic UIA (InvokePattern) sur un élément NOMMÉ de la fenêtre Pesto : liens de navigation (aria-label =
          # label de page) et boutons de thème (aria-label « Thème sombre »…). Plus fiable que Tab/Entrée à l'aveugle.
          $nm=$c.Substring(12)
          if (-not $nm) { throw 'CLICK_NAMED sans nom' }
          $kw4=$AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,$CT::Window))); $kn4=$kw4.Count; if ($kn4 -gt 40) { $kn4=40 }
          $pw4=$null
          for ($q=0; $q -lt $kn4; $q++) { if ($kw4.Item($q).Current.Name -like 'Pesto v2*') { $pw4=$kw4.Item($q); break } }
          if ($null -eq $pw4) { throw 'fenetre Pesto absente' }
          # Le Name peut retomber sur un élément NON invokable : icône, ou texte de la live-region d'annonce
          # (les annonces de thème portent le même libellé que les boutons — collision réelle 25/10 06:3x UTC :
          # « Unsupported Pattern »). On énumère TOUS les candidats du nom et on invoke le premier qui supporte
          # InvokePattern, lui ou un ancêtre direct (6 niveaux max).
          # Sonde réelle 25/10 07:5x UTC (diag-uia-theme-lot31) : les boutons <button> du thème sont bien des
          # ControlType.Button nommés, Enabled, non offscreen — mais NE supportent PAS InvokePattern (Chromium
          # les expose via Toggle/LegacyIAccessible). Le clic UIA essaie donc la CHAÎNE de patterns, dans cet
          # ordre : Invoke → Toggle (aria-pressed) → LegacyIAccessible.DoDefaultAction. Aucun clavier injecté,
          # aucun retrait de contrôle : si aucun pattern ne répond, la commande échoue honnêtement.
          $condN=New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty,$nm)
          $cands=$pw4.FindAll([System.Windows.Automation.TreeScope]::Subtree,$condN)
          $via=$null
          $nc=$cands.Count; if ($nc -gt 12) { $nc=12 }
          for ($ci=0; $ci -lt $nc -and $null -eq $via; $ci++) {
            $up=$cands.Item($ci); $tries=0
            while ($null -ne $up -and $tries -lt 6 -and $null -eq $via) {
              try { $p=$up.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern); if ($null -ne $p) { ([System.Windows.Automation.InvokePattern]$p).Invoke(); $via='invoke' } } catch {}
              if ($null -eq $via -and $up.Current.IsKeyboardFocusable) {
                # Repli d'activation clavier RÉEL ciblé sur l'élément lui-même : les types TogglePattern et
                # LegacyIAccessiblePattern sont ABSENTS en PS 5.1/.NET FX (« Unable to find type », prouvé par
                # diag-uia-theme 25/10 07:5x UTC) alors que le bouton <button> du thème est IsKeyboardFocusable.
                # SetFocus sur l'élément + SetForegroundWindow du HWND Pesto + keybd_event Espace (même événement
                # qu'un utilisateur). Ce n'est PAS une frappe à l'aveugle : la cible est l'élément nommé lui-même.
                try { $up.SetFocus(); $hw4=[IntPtr]$pw4.Current.NativeWindowHandle; [void][PestoGui.K]::SetForegroundWindow($hw4); [PestoGui.K]::keybd_event(0x20,0,0,0); [PestoGui.K]::keybd_event(0x20,0,2,0); $via='focus-space' } catch {}
              }
              $up=[System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($up); $tries++
            }
          }
          if ($null -eq $via) { throw ('aucun pattern activable (invoke/toggle/legacy) pour : ' + $nm) }
          $snap.Clicked=$nm; $snap.ClickedVia=$via
        }
        elseif ($c -eq 'STOP_WATCH') {
          # Auto-arrêt PROPRE avec RELECTURE d'identité (revue 25/10 03:17 UTC) : le watcher ne termine que
          # SA propre boucle finie ($i=$Ticks — aucun Stop-Process, aucun processus tiers touché), et seulement
          # après avoir relu son identité enregistrée au démarrage : PID, date de création, propriétaire,
          # chemin EXACT du script, session. Tout écart refuse l'arrêt (le pilote doit alors prouver la
          # disparition par le PID enregistré, jamais tuer par motif).
          $idf=Join-Path $Dir 'watcher-identity.json'
          if (-not (Test-Path -LiteralPath $idf)) { throw 'STOP_REFUSE identite du watcher absente' }
          $wi=ConvertFrom-Json (Get-PlainText $idf)
          $curOwner=[string][System.Security.Principal.WindowsIdentity]::GetCurrent().Name
          $curWpi=Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
          if ($null -eq $curWpi) { throw 'STOP_REFUSE processus courant introuvable' }
          if ([int]$wi.Pid -ne [int]$PID) { throw 'STOP_REFUSE pid different de l identite enregistree' }
          if ([string]$wi.Creation -ne [string]$curWpi.CreationDate) { throw 'STOP_REFUSE date de creation differente' }
          if ([string]$wi.Owner -ne $curOwner) { throw 'STOP_REFUSE proprietaire different' }
          if ([string]$wi.Script -ne 'C:\\Temp\\watch.ps1') { throw 'STOP_REFUSE chemin script different' }
          if ([int]$wi.Session -ne [int]$sid) { throw 'STOP_REFUSE session differente' }
          $snap.StopSelf=$true; $i=$Ticks
        }
        else { throw ('commande inconnue refusee : ' + $c) }
        $snap.CmdDone=$true
      } catch { $snap.CmdErr=(($_.ToString()) -replace '[\\x00-\\x1f]','?') }
      # figer le résultat dans $LC (survit aux ticks suivants dans latest.json)
      $LC.Cmd=$c; $LC.CmdDone=$snap.CmdDone; $LC.CmdErr=$snap.CmdErr
      if ($snap.Contains('EditText')) { $LC.EditText=$snap.EditText }
      if ($snap.Contains('FocusWin')) { $LC.FocusWin=$snap.FocusWin }
      if ($snap.Contains('LaunchedPid')) { $LC.LaunchedPid=$snap.LaunchedPid }
      if ($snap.Contains('KillTargets')) { $LC.KillTargets=$snap.KillTargets }
      if ($snap.Contains('Clicked')) { $LC.Clicked=$snap.Clicked }
      if ($snap.Contains('ClickedVia')) { $LC.ClickedVia=$snap.ClickedVia }
      if ($snap.Contains('ForegroundOk')) { $LC.ForegroundOk=$snap.ForegroundOk }
      if ($snap.Contains('Focused')) { $LC.Focused=$snap.Focused }
    }
    $tickPesto=@(Get-CimInstance Win32_Process -Filter "Name='Pesto.exe'" | Where-Object { ([string]$_.ExecutablePath -like 'C:\\PestoV2_Qual_20261024\\*') -and ([int]$_.SessionId -eq $sid) })
    $snap.PestoPids=@($tickPesto | ForEach-Object { [int]$_.ProcessId })
    $kids=$AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,$CT::Window)))
    $wins=@(); $n=$kids.Count; if ($n -gt 40) { $n=40 }
    for ($j=0; $j -lt $n; $j++) {
      $w=$kids.Item($j); $r=$w.Current.BoundingRectangle
      $wins+=($w.Current.Name + '|' + [int]$r.X + ',' + [int]$r.Y + 'x' + [int]$r.Width + 'x' + [int]$r.Height + '|' + [bool]$w.Current.IsOffscreen)
    }
    $snap.AllWindows=$wins
    $pesto=$null
    for ($j=0; $j -lt $n; $j++) { if ($kids.Item($j).Current.Name -like 'Pesto v2*') { $pesto=$kids.Item($j); break } }
    if ($null -eq $pesto) {
      $snap.WindowFound=$false
    } else {
      $snap.WindowFound=$true
      $snap.WindowName=[string]$pesto.Current.Name
      $snap.Offscreen=[bool]$pesto.Current.IsOffscreen
      $r=$pesto.Current.BoundingRectangle
      $snap.Rect=@([int]$r.X,[int]$r.Y,[int]$r.Width,[int]$r.Height)
      try { $wpv=[System.Windows.Automation.WindowPattern]$pesto.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern); $snap.WinState=[string]$wpv.Current.WindowVisualState } catch {}
      $doc=$pesto.FindFirst([System.Windows.Automation.TreeScope]::Subtree,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,$CT::Document)))
      if ($null -ne $doc) {
        $snap.DocumentName=[string]$doc.Current.Name
        # Qualification du contenu réellement monté : un titre de route seul peut masquer une carte d'erreur.
        # Les métadonnées des champs/boutons sont lues sans valeur de saisie (aucun secret capturé).
        $controlList=@()
        foreach ($controlType in @($CT::Edit,$CT::ComboBox,$CT::Button)) {
          $docControls=$doc.FindAll([System.Windows.Automation.TreeScope]::Subtree,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,$controlType)))
          $dcCount=[Math]::Min($docControls.Count,100-$controlList.Count)
          for ($dc=0; $dc -lt $dcCount; $dc++) {
            $control=$docControls.Item($dc)
            $controlList+=([ordered]@{ Name=[string]$control.Current.Name; Type=[string]$control.Current.ControlType.ProgrammaticName; Enabled=[bool]$control.Current.IsEnabled; Offscreen=[bool]$control.Current.IsOffscreen; Focused=[bool]$control.Current.HasKeyboardFocus })
          }
        }
        $snap.Controls=$controlList
      }
      $pal=$pesto.FindFirst([System.Windows.Automation.TreeScope]::Subtree,(New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty,'Palette de commandes')))
      $snap.PaletteOpen=($null -ne $pal)
      $nav=$pesto.FindFirst([System.Windows.Automation.TreeScope]::Subtree,(New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty,'Journal')))
      if ($null -ne $nav) { $snap.NavJournalWidth=[int]$nav.Current.BoundingRectangle.Width }
      $texts=@(); $seen=@{}
      $all=$pesto.FindAll([System.Windows.Automation.TreeScope]::Subtree,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,$CT::Text)))
      $m=$all.Count; if ($m -gt 60) { $m=60 }
      for ($j2=0; $j2 -lt $m; $j2++) {
        $t=[string]$all.Item($j2).Current.Name
        if ($t -and -not $seen[$t]) { $seen[$t]=$true; $texts+=$t }
        if ($texts.Count -ge 40) { break }
      }
      $snap.Texts=$texts
    }
  } catch { $snap.Err=(($_ | Out-String) -replace '[\\x00-\\x1f]','?') }
  $line=ConvertTo-PestoJson $snap
  try { [System.IO.File]::AppendAllText($nd,$line+[char]10,(New-Object System.Text.UTF8Encoding($false))) } catch {}
  try { $latest=ConvertTo-PestoJson ([ordered]@{ Tick=$i; Utc=$snap.Utc; WindowFound=$snap.WindowFound; WindowName=$snap.WindowName; Offscreen=$snap.Offscreen; DocumentName=$snap.DocumentName; PaletteOpen=$snap.PaletteOpen; NavJournalWidth=$snap.NavJournalWidth; Cmd=$LC.Cmd; CmdDone=$LC.CmdDone; CmdErr=$LC.CmdErr; EditText=$LC.EditText; FocusWin=$LC.FocusWin; PestoPids=$snap.PestoPids; LaunchedPid=$LC.LaunchedPid; KillTargets=$LC.KillTargets; Clicked=$LC.Clicked; ClickedVia=$LC.ClickedVia; Focused=$LC.Focused; ForegroundOk=$LC.ForegroundOk; Rect=$snap.Rect; WinState=$snap.WinState; Texts=$snap.Texts; Controls=$snap.Controls })
    # Écriture ATOMIQUE : WriteAllText direct faisait lire à copyfrom la queue périmée du write (demi-JSON lu
    # côté hôte, réel 25/10 05:5x UTC). On écrit latest2.tmp puis Move-Item -Force : le lecteur ne voit qu'un
    # fichier complet. Nom latest2.json (25/10 07:2x UTC) : latest.json invité est verrouillé par un handle
    # fuié par VBoxService après un copyfrom interrompu (OpenWrite « used by another process », Move en échec
    # « Cannot create a file when that file already exists ») — le canal change de nom, le protocole atomique
    # ne change pas ; latest.json reste un artefact témoin (450 o figés à 06:40 UTC).
    $tmp=Join-Path $Dir 'latest2.tmp'
    [System.IO.File]::WriteAllText($tmp,$latest,(New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination (Join-Path $Dir 'latest2.json') -Force } catch {}
  Start-Sleep -Seconds $DelaySec
}
`;


// ---- Bootstrap SANS clavier, SANS tâche planifiée ni mot de passe saisi — découvert lot 31 (25/10 04:0x UTC) ----
// Preuves : probe-tp.json = {"Pid":9008,"SessionId":1,"Who":"LABO\\tech.pesto"} obtenu par
// guestcontrol run --username tech.pesto --domain LABO --passwordfile <chemin seulement>. Le compte tech.pesto
// possède la session console 1 : VBox y lance le processus. Le clavier console (Win+R) n'est DONC plus requis
// pour démarrer le watcher — il reste réservé aux frappes destinées à l'application (palette, dialogues).
// ATTENTION VBox : --timeout est en MILLISECONDS. --timeout 60 tue le process après 60 ms (faux échecs « code 20 »
// du début de lot ; lab-driver passe déjà des millisecondes).
function guestRunAs(user, argsExe, argList, { timeoutMs = 60000, wait = true } = {}) {
  const parts = [VBOXMANAGE, 'guestcontrol', VM_UUID, 'run', '--exe', `"${argsExe}"`,
    '--username', user, '--domain', laboNetbios(), '--passwordfile', laboMdpFichier(), '--quiet', '--timeout', String(timeoutMs)];
  // Sans --ignore-orphaned-processes, VBox tue l'arbre fils quand le cmd parent se termine : le « start » de
  // w2.bat produisait un powershell orphelin aussitôt tué (w2.log écrit, watcher jamais lancé). Observé lot 31.
  if (!wait) parts.push('--ignore-orphaned-processes');
  return host(`${parts.join(' ')} -- ${argList}`, timeoutMs + 30000);
}

function startWatch(ticks = 1200) {
  // Le watcher est lancé COMME processus guestcontrol (pas via « start » détaché : w2.log prouve 25/10 05:18 UTC
  // que cmd parent s'exécute et errorlevel=0, mais le powershell détaché ne survit pas — arbre orphelin/VBox).
  // Le ssh local part en arrière-plan (detach+unref) et VBox borne la vie du watcher : timeout = ticks+60 s.
  const tMs = ticks * 1000 + 60000;
  // --ignore-orphaned-processes : sans cette option, la chute du ssh local (réseau instable — réel 25/10
  // 06:3x UTC : watcher tué à tick 454 quand ssh est mort) entraînait la mort du watcher invité. La vie du
  // watcher reste BORNÉE par --timeout (ticks + 60 s) ; l'arrêt anticipé reste STOP_WATCH (auto-terminaison
  // après relecture d'identité), jamais un kill.
  const inner = `${VBOXMANAGE} guestcontrol ${VM_UUID} run --exe "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"`
    + ` --username tech.pesto --domain ${laboNetbios()} --passwordfile ${laboMdpFichier()} --quiet --timeout ${tMs} --ignore-orphaned-processes --`
    + ` -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\\Temp\\watch.ps1 -Ticks ${ticks}`;
  // nohup + detached : quand le CLI parent se termine (fin de lot), ssh survit ; sinon ssh meurt,
  // sshd tue VBoxManage et VBox abat le watcher invité (constaté 25/10 05:5x UTC).
  const child = spawn('nohup', ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=12', 'degun@192.168.1.173', inner],
    { stdio: 'ignore', detached: true });
  child.unref();
  return { launched: true, sshPid: child.pid, ticks, vboxTimeoutMs: tMs };
}

const G_BAT = '@echo off\r\nstart "" "' + PACK + '\\Pesto.exe" --simulation\r\n';
const W_BAT = '@echo off\r\npowershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + TEMP + '\\watch.ps1 -Ticks 1200\r\n';
const W2_BAT = '@echo off\r\n>> C:\\Users\\Public\\pesto-gui\\w2.log echo start %DATE% %TIME% ticks=%1\r\nstart "" /min C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + TEMP + '\\watch.ps1 -Ticks %1\r\n>> C:\\Users\\Public\\pesto-gui\\w2.log echo started %DATE% %TIME% errorlevel=%ERRORLEVEL%\r\n';

function deploy() {
  mkdirSync(LOCAL_GUI, { recursive: true });
  const prep = runGuest(`if (-not (Test-Path -LiteralPath '${TEMP}')) { New-Item -ItemType Directory -Path '${TEMP}' | Out-Null }
icacls '${TEMP}' /grant '*S-1-5-32-544:(OI)(CI)F' /Q | Out-Null
icacls '${TEMP}' /grant '*S-1-5-11:(OI)(CI)RX' /Q | Out-Null
if (-not (Test-Path -LiteralPath '${PUB}')) { New-Item -ItemType Directory -Path '${PUB}' | Out-Null }
icacls '${PUB}' /grant '*S-1-5-32-544:(OI)(CI)F' /Q | Out-Null
icacls '${PUB}' /grant '*S-1-5-11:(OI)(CI)F' /Q | Out-Null
Remove-Item -LiteralPath '${PUB}\\snap-*.json','${PUB}\\cmd.txt','${PUB}\\latest.json','${PUB}\\latest2.json','${PUB}\\latest2.tmp','${PUB}\\status.ndjson' -Force -ErrorAction SilentlyContinue
$result=[ordered]@{ Temp=(Test-Path -LiteralPath '${TEMP}'); Pub=(Test-Path -LiteralPath '${PUB}'); Pack=(Test-Path -LiteralPath '${PACK}\\Pesto.exe') }`, { timeoutMs: 60000 });
  const prepJson = (() => { try { return JSON.parse((prep.stdout.match(/\{[\s\S]*\}/) ?? ['{}'])[0]); } catch { return { raw: (prep.stdout + prep.stderr).slice(0, 300) }; } })();
  const files = { 'g.bat': G_BAT, 'w.bat': W_BAT, 'w2.bat': W2_BAT, 'watch.ps1': '\uFEFF' + WATCH_PS };
  const out = [];
  for (const [name, content] of Object.entries(files)) {
    const local = path.join(LOCAL_GUI, name);
    writeFileSync(local, content, 'utf8');
    const scp = spawnSync('scp', ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=12', local, `${SSH_TARGET}:${HOST_FWD}/${name}`],
      { encoding: 'utf8', timeout: 120000 });
    if (scp.status !== 0) throw new Error('scp ' + name + ' : ' + (scp.stderr || scp.error?.message));
    const copy = host(`${VBOXMANAGE} guestcontrol ${VM_UUID} copyto --username labadmin`
      + ` --passwordfile ${laboMdpFichier()} --quiet "${HOST_DIR}\\${name}" "${TEMP}\\${name}"`, 60000);
    out.push({ name, copyTo: copy.code });
  }
  const verify = runGuest(`$r=@{}
foreach ($f in @('g.bat','w.bat','w2.bat','watch.ps1')) { $r[$f]=[string](Test-Path -LiteralPath ('${TEMP}'+[char]92+$f)) }
$r['Sha']=(Get-FileHash -LiteralPath '${TEMP}\\watch.ps1' -Algorithm SHA256).Hash
$result=[ordered]@{ Files=$r }`, { timeoutMs: 60000 });
  return { prep: prepJson, out, verify: verify.stdout + verify.stderr };
}

// ---- Inventaire process depuis labadmin (Session 0) : CIM voit tous les sessions. La FENÊTRE se juge côté
// session 1 par le watcher UIA (EnumWindows Session 0 est confiné à la window station Service-0x0-… :
// TotalSystemWindows=1 constaté 25/10 02:32 UTC — même cause que diag-minform-visible.json, dans l'autre sens).
const ENUM_PS = `$ErrorActionPreference='Stop'
$procs = Get-CimInstance Win32_Process -Filter "Name='Pesto.exe' OR Name='msedgewebview2.exe'" |
  Where-Object { [string]$_.ExecutablePath -like 'C:\\PestoV2_Qual_20261024\\*' }
$result = [ordered]@{
  Utc = (Get-Date).ToUniversalTime().ToString('o');
  Procs = @($procs | ForEach-Object { [ordered]@{ Pid=[int]$_.ProcessId; Name=[string]$_.Name; Path=[string]$_.ExecutablePath; Session=[int]$_.SessionId; Parent=[int]$_.ParentProcessId } })
}
`;

function enumWindows(name) {
  const r = runGuestJsonFile(ENUM_PS, name, { timeoutMs: 60000 });
  return r.json ?? { NO_JSON: true, run: r.run?.code, stdout: r.run?.stdout?.slice(0, 500), stderr: r.run?.stderr?.slice(0, 500) };
}

function shot(name) {
  const png = `${HOST_DIR}\\gui-${name}.png`;
  const r = host(`${VBOXMANAGE} controlvm ${VM_UUID} screenshotpng ${png}`, 60000);
  if (r.code !== 0) return { code: r.code, err: (r.stderr || r.stdout).slice(0, 300) };
  mkdirSync(LOCAL_GUI, { recursive: true });
  const scp = spawnSync('scp', ['-o', 'BatchMode=yes', `${SSH_TARGET}:${HOST_FWD}/gui-${name}.png`, path.join(LOCAL_GUI, `gui-${name}.png`)],
    { encoding: 'utf8', timeout: 120000 });
  return { code: 0, scp: scp.status, local: path.join(LOCAL_GUI, `gui-${name}.png`) };
}

// Le watcher écrit status.ndjson (un JSON par tick) + latest.json — c'est CE canal que collect() rapatrie
// (l'ancien collect lisait snap-NNN.json que le watcher ne produit pas : lecture toujours vide, jamais d'erreur).
function collect() {
  mkdirSync(LOCAL_GUI, { recursive: true });
  const copy = copyFromGuest(`${PUB}\\status.ndjson`, `${HOST_DIR}\\status-read.ndjson`);
  if (copy.code !== 0) return { error: 'copyfrom status.ndjson code=' + copy.code, ticks: [] };
  const scp = spawnSync('scp', ['-o', 'BatchMode=yes', `${SSH_TARGET}:${HOST_FWD}/status-read.ndjson`, path.join(LOCAL_GUI, 'status-read.ndjson')],
    { encoding: 'utf8', timeout: 60000 });
  if (scp.status !== 0) return { error: 'scp status.ndjson code=' + scp.status, ticks: [] };
  const ticks = [];
  for (const line of readFileSync(path.join(LOCAL_GUI, 'status-read.ndjson'), 'utf8').replace(/^\uFEFF/, '').split('\n')) {
    const s = line.trim(); if (!s) continue;
    try { ticks.push(JSON.parse(s)); } catch { /* ligne partielle du tick en cours : tolérée */ }
  }
  return { count: ticks.length, first: ticks[0] ?? null, last: ticks[ticks.length - 1] ?? null };
}

// ---- Canal de commande au watcher (cmd.txt) et relance de latest.json ----------------------------------------
function sendCmd(cmd) {
  // KILL_PESTO retir\u00e9e de la liste (revue 25/10 03:17 UTC) : le pilote ne tue rien ; l'arrêt du watcher
  // passe par stop-watch (auto-arr\u00eat STOP_WATCH apr\u00e8s relecture d'identit\u00e9 + preuve de disparition).
  if (!/^(LAUNCH_PESTO|READ_EDIT|MAXIMIZE_PESTO|RESTORE_PESTO|STOP_WATCH|FOCUS_PESTO|CLICK_NAMED=[^\x00-\x1f\x7f]{1,80})$/.test(cmd)) throw new Error('commande hors liste ferm\u00e9e : ' + cmd);
  mkdirSync(LOCAL_GUI, { recursive: true });
  const local = path.join(LOCAL_GUI, 'cmd.txt');
  writeFileSync(local, cmd, 'utf8');
  const scp = spawnSync('scp', ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=12', local, `${SSH_TARGET}:${HOST_FWD}/cmd.txt`],
    { encoding: 'utf8', timeout: 120000 });
  if (scp.status !== 0) throw new Error('scp cmd.txt : ' + (scp.stderr || scp.error?.message));
  const copy = host(`${VBOXMANAGE} guestcontrol ${VM_UUID} copyto --username labadmin`
    + ` --passwordfile ${laboMdpFichier()} --quiet "${HOST_DIR}\\cmd.txt" "${PUB}\\cmd.txt"`, 60000);
  if (copy.code !== 0) throw new Error('copyto cmd.txt code=' + copy.code);
  return { cmd, copyTo: copy.code };
}

// copyfrom pendant que le watcher réécrit le fichier échoue (verrou transient) : 4 tentatives espacées.
// VBoxManage copyfrom NE TRONQUE PAS la destination : copier un fichier plus court que l'ancien laisse la
// queue du fichier précédent (latest.json « valide + queue » observé 25/10 05:0x-05:5x UTC, faussement
// attribué à l'écriture invitée). On supprime l'hôte avant chaque copie ; l'écriture invitée est de plus
// atomique (tmp + Move-Item -Force) pour qu'un tick ne soit jamais à moitié écrit.
function copyFromGuest(guestFile, hostFile, tries = 4) {
  let last = null;
  for (let i = 0; i < tries; i++) {
    try {
      host(`if exist "${hostFile}" del /q "${hostFile}"`, 30000);
      last = host(`${VBOXMANAGE} guestcontrol ${VM_UUID} copyfrom --username labadmin`
        + ` --passwordfile ${laboMdpFichier()} --quiet "${guestFile}" "${hostFile}"`, 30000);
      if (last.code === 0) return last;
    } catch (e) {
      // ETIMEDOUT ssh transient (réel 25/10 06:4x UTC) : une tentative ratée n'est pas un échec définitif.
      last = { code: -1, error: String(e?.message ?? e) };
    }
    const wait = 800 * (i + 1);
    const t = Date.now(); while (Date.now() - t < wait) { /* attente courte */ }
  }
  return last;
}

function readLatest() {
  // Nom d'hôte distinct (latest-read.json) : après une chute ssh en plein copyfrom, un handle zombie peut bloquer
  // la recréation du fichier hôte homonyme (« Opening/creating host file failed », réel 25/10 06:5x UTC) alors
  // que les autres fichiers passent. Changer le nom local suffit à l'éviter ; le fichier INVITÉ ne change pas.
  const copy = copyFromGuest(`${PUB}\\latest2.json`, `${HOST_DIR}\\latest-read.json`);
  if (copy.code !== 0) return null;
  mkdirSync(LOCAL_GUI, { recursive: true });
  const scp = spawnSync('scp', ['-o', 'BatchMode=yes', `${SSH_TARGET}:${HOST_FWD}/latest-read.json`, path.join(LOCAL_GUI, 'latest-read.json')],
    { encoding: 'utf8', timeout: 60000 });
  if (scp.status !== 0) return null;
  try { return JSON.parse(readFileSync(path.join(LOCAL_GUI, 'latest-read.json'), 'utf8').replace(/^\uFEFF/, '')); } catch { return null; }
}

// Frappe VALIDÉE avant Entrée (GUI_HANDOFF §1) : Ctrl+A (le texte existant du dialogue Exécuter est remplacé,
// aucune saisie accolée qui reconstituerait une ligne MRU dangereuse type shutdown), frappe en une seule rafale,
// capture d'écran pour le superviseur, puis relit le champ via UIA (commande READ_EDIT au watcher session 1).
// Cette fonction n'appuie JAMAIS sur Entrée : l'appelant juge `match` et déclenche key enter lui-même.
async function runVerified(text) {
  const before = readLatest();
  const baseUtc = before?.Utc ?? '';
  sendCodes(tapCodes(LETTERS.a, { ctrl: true }));
  await sleep(150);
  sendCodes(codesForText(text));
  await sleep(300);
  const capture = shot('typed-' + (process.argv[4] || 'run'));
  sendCmd('READ_EDIT');
  const deadline = Date.now() + 45000;
  while (Date.now() < deadline) {
    await sleep(1500);
    const l = readLatest();
    if (l && l.Cmd === 'READ_EDIT' && l.Utc > baseUtc) {
      return { expected: text, actual: l.EditText ?? null, focusWin: l.FocusWin ?? null,
        match: l.EditText === text, watcherTick: l.Tick, watcherUtc: l.Utc, capture };
    }
  }
  return { expected: text, actual: null, match: false, error: 'watcher injoignable (latest.json non renouvelé en 45 s) — ne pas valider à l’aveugle', capture };
}

const sleepArg = () => { const n = Number(process.argv[3] || 1000); return sleep(Math.min(n, 30000)); };

// ---- Lancement en session 1 SANS clavier ni mot de passe tech.pesto ------------------------------------------
// Tâches planifiées InteractiveToken créées par labadmin (administrateur local) : un admin peut enregistrer une
// tâche « Interactive » pour l'utilisateur connecté SANS son mot de passe ; l'exécution se fait dans la session
// interactive de CET utilisateur (SessionId 1). Réversible : supprimées par task-clean. Aucune mutation AD,
// écritures limitées à C:\Temp, C:\Users\Public\pesto-gui et C:\Windows\Temp\pesto-v2-qual.
const TASK_RUN = 'PestoGuiRun';
const TASK_WATCH = 'PestoGuiWatch';
function registerTasks() {
  const ps = `$ErrorActionPreference='Stop'
foreach ($n in @('${TASK_RUN}','${TASK_WATCH}')) { try { Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction Stop } catch {} }
$pa = New-ScheduledTaskAction -Execute 'C:\\Temp\\g.bat'
$pp = New-ScheduledTaskPrincipal -UserId '${laboNetbios()}\\tech.pesto' -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName '${TASK_RUN}' -Action $pa -Principal $pp | Out-Null
$wa = New-ScheduledTaskAction -Execute 'C:\\Temp\\w.bat'
$wp = New-ScheduledTaskPrincipal -UserId '${laboNetbios()}\\tech.pesto' -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName '${TASK_WATCH}' -Action $wa -Principal $wp | Out-Null
$t = @(Get-ScheduledTask -TaskName '${TASK_RUN}','${TASK_WATCH}' | ForEach-Object { [ordered]@{ Name=[string]$_.TaskName; State=[string]$_.State; User=$_.Principal.UserId } })
$result=[ordered]@{ Registered=$t }`;
  const r = runGuestJsonFile(ps, 'gui-tasks', { timeoutMs: 60000 });
  return r.json ?? { NO_JSON: true, run: r.run?.code, stderr: r.run?.stderr?.slice(0, 400) };
}
function runTask(task) {
  const ps = `$ErrorActionPreference='Stop'
Start-ScheduledTask -TaskName '${task}'
$t = Get-ScheduledTask -TaskName '${task}'
$i = $t | Get-ScheduledTaskInfo
$result=[ordered]@{ Task='${task}', State=[string]$t.State, LastRun=[string]$i.LastRunTime, Result=$i.LastTaskResult }`;
  const r = runGuestJsonFile(ps, `gui-task-${task}`, { timeoutMs: 60000 });
  return r.json ?? { NO_JSON: true, run: r.run?.code, stderr: r.run?.stderr?.slice(0, 400) };
}
function cleanTasks() {
  const ps = `$ErrorActionPreference='Stop'
foreach ($n in @('${TASK_RUN}','${TASK_WATCH}')) {
  try { Stop-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue } catch {}
  try { Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue } catch {}
}
$result=[ordered]@{ Left=@(@(Get-ScheduledTask -TaskName '${TASK_RUN}','${TASK_WATCH}' -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.TaskName })) }`;
  const r = runGuestJsonFile(ps, 'gui-task-clean', { timeoutMs: 60000 });
  return r.json ?? { NO_JSON: true, run: r.run?.code };
}

// ---- Arrêt du watcher SANS AUCUN Stop-Process (revue 25/10 03:17 UTC) ----------------------------------------
// Le watcher se termine LUI-MÊME (STOP_WATCH → fin de sa boucle finie), après avoir relu son identité
// enregistrée au démarrage. Le pilote : 1) relit watcher-identity.json et refuse tout champ inattendu ;
// 2) envoie STOP_WATCH ; 3) prouve la disparition par le PID enregistré (CIM, exécuté par labadmin qui voit
// tous les PID). Aucun arrêt par motif, aucun arrêt de la GUI, aucun arrêt par timeout.
function stopWatch() {
  const copy = copyFromGuest(`${PUB}\\watcher-identity.json`, `${HOST_DIR}\\watcher-identity.json`);
  if (copy.code !== 0) return { stop: 'REFUSED', reason: 'watcher-identity.json introuvable côté invité — arrêt refusé' };
  const scp = spawnSync('scp', ['-o', 'BatchMode=yes', `${SSH_TARGET}:${HOST_FWD}/watcher-identity.json`, path.join(LOCAL_GUI, 'watcher-identity.json')],
    { encoding: 'utf8', timeout: 60000 });
  if (scp.status !== 0) return { stop: 'REFUSED', reason: 'scp watcher-identity.json code=' + scp.status };
  let ident = null;
  try { ident = JSON.parse(readFileSync(path.join(LOCAL_GUI, 'watcher-identity.json'), 'utf8').replace(/^\uFEFF/, '')); } catch { /* dessous */ }
  if (!ident) return { stop: 'REFUSED', reason: 'watcher-identity.json illisible — arrêt refusé' };
  const checks = {
    Pid: Number.isSafeInteger(ident.Pid) && ident.Pid > 0,
    Creation: typeof ident.Creation === 'string' && ident.Creation.length > 0,
    Owner: ident.Owner === `${laboNetbios()}\\tech.pesto`,
    Script: ident.Script === 'C:\\Temp\\watch.ps1',
    Session: Number(ident.Session) === 1,
  };
  const bad = Object.entries(checks).filter(([, v]) => !v).map(([k]) => k);
  if (bad.length) return { stop: 'REFUSED', reason: 'identité non conforme : ' + bad.join(','), ident };
  const goneQ = () => runGuestJsonFile(`$p=Get-CimInstance Win32_Process -Filter "ProcessId=${ident.Pid}"
$result=[ordered]@{ Pid=${ident.Pid}; Present=[bool]$p; Name=[string]$p.Name }`, 'gui-watch-gone', { timeoutMs: 60000 });
  // REVUE 25/10 05:41 UTC — STOPPED n'est JAMAIS annoncé par défaut : chaque STOPPED exige une preuve native
  // CIM Present===false pour le PID enregistré. Sinon PRESENT / UNKNOWN / REFUSED, et aucun arrêt forcé.
  // 1) Pré-contrôle : le PID enregistré doit être vivant ET être un powershell.exe (sinon identité périmée
  //    ou PID recyclé → refus ; le cas « watcher réel sous un autre PID » reste à investiguer, pas à tuer).
  const pre = goneQ();
  if (watcherPresence(ident.Pid, pre.json) === 'UNKNOWN') return { stop: 'UNKNOWN', reason: 'pré-contrôle CIM illisible — aucun envoi, aucun arrêt', ident, preCheck: pre.json ?? { NO_JSON: true, run: pre.run?.code } };
  if (pre.json.Present === false) return { stop: 'ALREADY_GONE', ident, preCheck: pre.json, note: 'PID déjà absent avant STOP_WATCH — aucun accusé reçu, rien n a été arrêté par ce pilote' };
  if (pre.json.Name !== 'powershell.exe') return { stop: 'REFUSED', reason: 'le PID enregistré porte ' + pre.json.Name + ' (identité non conforme) — arrêt refusé', ident, preCheck: pre.json };
  // 2) Commande d auto-terminaison + accusé éventuel (canal latest2 ; peut être illisible si le canal est figé).
  const base = readLatest()?.Utc ?? '';
  sendCmd('STOP_WATCH');
  const t0 = Date.now();
  let verdict = null;
  while (Date.now() - t0 < 60000) {
    const l = readLatest();
    if (l && l.Cmd === 'STOP_WATCH' && l.Utc > base) { verdict = l; break; }
    const t = Date.now(); while (Date.now() - t < 1500) { /* attente */ }
  }
  // 3) PREUVE de disparition : CIM sur le PID enregistré, observé jusqu à 60 s.
  const t1 = Date.now();
  let gone = null;
  while (Date.now() - t1 < 60000) {
    gone = goneQ();
    if (watcherPresence(ident.Pid, gone.json) === 'ABSENT') break;
    const t = Date.now(); while (Date.now() - t < 3000) { /* attente */ }
  }
  return watcherStopResult(ident, gone?.json, verdict);
}

const CLI = {
  deploy: () => deploy(),
  'stop-watch': () => stopWatch(),
  enum: () => enumWindows(process.argv[3] || 'gui-enum'),
  shot: () => shot(process.argv[3] || 'shot'),
  type: () => { sendCodes(codesForText(process.argv[3] ?? '')); return { typed: process.argv[3] ?? '' }; },
  run: () => runVerified(process.argv[3] ?? ''),
  cmd: () => sendCmd(process.argv[3]),
  latest: () => readLatest() ?? { error: 'latest.json absent ou illisible' },
  key: () => {
    const k = process.argv[3];
    if (k === 'winr') sendCodes([0xe0, 0x5b, 0x13, 0x93, 0xe0, 0xdb]);
    else if (k === 'enter') tap(ENTER);
    else if (k === 'esc') tap(ESC);
    else if (k === 'ctrlb') tap(LETTERS.b, { ctrl: true });
    else if (k === 'ctrlk') tap(LETTERS.k, { ctrl: true });
    else if (k === 'altf4') tap(F4, { alt: true });
    // Alt+1..9 AZERTY : chiffres de la rangée haute AVEC shift (sinon e.key n'est pas le chiffre).
    // L'ancienne forme pavé numérique (e0 4f…) ne déclenchait pas le raccourci en session réelle.
    else if (/^alt[1-9]$/.test(k)) tap(DIGITS[k[3]], { alt: true, shift: true });
    else if (k === 'numlock') tap(0x45);
    else throw new Error('touche inconnue : ' + k);
  },
  sleep: sleepArg,
  'start-watch': () => startWatch(Number(process.argv[3] || 1200)),
  tasks: () => registerTasks(),
  'run-task': () => runTask(process.argv[3]),
  'clean-tasks': () => cleanTasks(),
  collect: () => collect(),
};

if (import.meta.url === `file://${process.argv[1]}`) {
  const cmd = process.argv[2];
  if (!CLI[cmd]) {
    console.error('usage: gui-session1.mjs deploy|start-watch [ticks]|stop-watch|enum <nom>|shot <nom>|type <texte>|run <texte>|cmd <LAUNCH_PESTO|READ_EDIT|MAXIMIZE_PESTO|RESTORE_PESTO|STOP_WATCH|FOCUS_PESTO|CLICK_NAMED=<nom>>|latest|key <winr|enter|esc|ctrlb|ctrlk|altf4|alt1..9|numlock>|sleep <ms>|collect');
    process.exit(2);
  }
  Promise.resolve(CLI[cmd]()).then((r) => {
    if (r !== undefined) console.log(typeof r === 'string' ? r : JSON.stringify(r, null, 1));
    // stop-watch : le code de sortie ne dit SUCCÈS que sur STOPPED prouvé (revue 25/10 05:41 UTC) ;
    // PRESENT / UNKNOWN / ALREADY_GONE / REFUSED sortent en 2 pour que le pilote ne puisse pas enchaîner
    // sur un faux succès.
    if (cmd === 'stop-watch' && r && r.stop !== 'STOPPED') process.exit(2);
  }).catch((e) => { console.error('ERREUR : ' + (e?.stack ?? e)); process.exit(1); });
}
