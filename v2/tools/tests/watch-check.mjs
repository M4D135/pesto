#!/usr/bin/env node
// Contrôles STATIQUES du watcher UIA (WATCH_PS de gui-session1.mjs) — exécution Linux, sans PowerShell.
// Justification : la 1re exécution réelle (25/10 03:22 UTC, tick 113) a prouvé que le watcher précédent ne
// fonctionnait JAMAIS — $TS.Children sur une variable de type vaut $null en PS 5.1 (membres statiques = ::) et
// FindAll(scope, $CT::Window) passe un ControlType là où un PropertyCondition est exigé. Ces deux classes de
// faute sont interdites ici pour toujours, car aucun PowerShell n'existe sur ce poste pour les attraper.
import { WATCH_PS } from '../qualification/gui-session1.mjs';

let ok = 0, ko = 0;
const t = (name, cond) => { if (cond) { ok++; } else { ko++; console.error('ÉCHEC : ' + name); } };

const lines = WATCH_PS.split('\n');
t('aucun accès par point à une variable de scope ($TS.xxx / $CT.xxx / $AE.xxx hors ::)',
  !/\$TS\.|\$CT\.|\$AE\.[A-Za-z]/.test(WATCH_PS));
t('toutes les portées sont qualifiées TreeScope::',
  (WATCH_PS.match(/\[System\.Windows\.Automation\.TreeScope\]::(Children|Subtree)/g) || []).length >= 8);
for (const line of lines) {
  if (line.includes('.FindAll(') || line.includes('.FindFirst(')) {
    t('FindAll/FindFirst avec condition explicite (PropertyCondition/AndCondition ou variable $cond) : ' + line.trim().slice(0, 60),
      /PropertyCondition|AndCondition|\$cond\w/.test(line));
  }
}
const CMDS = ['LAUNCH_PESTO', 'READ_EDIT', 'MAXIMIZE_PESTO', 'RESTORE_PESTO', 'STOP_WATCH', 'FOCUS_PESTO', 'CLICK_NAMED=*'];
for (const c of CMDS) t('commande en liste fermée : ' + c, WATCH_PS.includes("'" + c + "'"));
t('STOP_WATCH termine la boucle par $i=$Ticks (auto-arrêt propre)', /\$i=\$Ticks/.test(WATCH_PS));
t('garde singleton watch.ps1 (exit si pair vivant même session)', /CommandLine -like '\*watch\.ps1\*'/.test(WATCH_PS) && /exit 0/.test(WATCH_PS));
t('latest2.json écrit atomiquement (tmp + Move-Item -Force)', /latest2\.tmp/.test(WATCH_PS) && /Move-Item -LiteralPath \$tmp/.test(WATCH_PS));
t('résultat de commande persistant entre ticks ($LC)', /\$LC=\[ordered\]/.test(WATCH_PS) && /Cmd=\$LC\.Cmd/.test(WATCH_PS));
// Exigence revue superviseur 25/10 03:17 UTC : le watcher ne tue RIEN et son auto-arrêt est gardé par identité.
t('aucun Stop-Process exécutable dans le watcher (KILL_PESTO retiré)',
  WATCH_PS.split('\n').every((l) => !l.includes('Stop-Process') || l.trim().startsWith('#')));
t('KILL_PESTO existe seulement en commentaire/refus (jamais exécuté)',
  WATCH_PS.split('\n').filter((l) => l.includes('KILL_PESTO'))
    .every((l) => { const s = l.trim(); return s.startsWith('#') || s.startsWith('throw') || /^elseif \(\$c -eq 'KILL_PESTO'\) \{$/.test(s); }));
t('identité enregistrée au démarrage (PID/création/propriétaire/script/session)',
  /watcher-identity\.json/.test(WATCH_PS) && /Creation=\[string\]\$wpi0\.CreationDate/.test(WATCH_PS)
  && /Owner=\[string\]\[System\.Security\.Principal\.WindowsIdentity\]::GetCurrent\(\)\.Name/.test(WATCH_PS)
  && /Script='C:\\Temp\\watch\.ps1'/.test(WATCH_PS) && /Session=\[int\]\$sid/.test(WATCH_PS));
t('STOP_WATCH relit l identité et refuse tout écart (STOP_REFUSE)',
  (WATCH_PS.match(/STOP_REFUSE/g) || []).length >= 5 && /ConvertFrom-Json \(Get-PlainText \$idf\)/.test(WATCH_PS));
t('aucun CLOSE_SNIP hors commentaire', WATCH_PS.split('\n').every((l) => !/CLOSE_SNIP/.test(l) || l.trim().startsWith('#')));

// Exigence revue superviseur 25/10 05:41 UTC : le verdict stopWatch() ne peut PAS annoncer STOPPED par défaut.
const SRC = (await import('node:fs')).readFileSync(new URL('../qualification/gui-session1.mjs', import.meta.url), 'utf8');
const stopFn = SRC.slice(SRC.indexOf('function stopWatch'), SRC.indexOf('const CLI = {'));
const { watcherStopResult } = await import('../qualification/watcher-result.mjs');
const identity = { Pid: 42 };
t('stopWatch utilise la décision testée sur la preuve native', /return watcherStopResult\(ident, gone\?\.json, verdict\)/.test(stopFn));
t('preuve absente ou malformée ne donne aucun succès',
  [null, {}, {Pid: 42, Present: null}, {Pid: 42, Present: 'false'}, {Pid: 43, Present: false}]
    .every(proof => watcherStopResult(identity, proof, {CmdDone: true}).stop === 'UNKNOWN'));
t('processus encore présent ne donne aucun succès',
  watcherStopResult(identity, {Pid: 42, Present: true}, {CmdDone: true}).stop === 'PRESENT');
t('disparition confirmée exige le bon PID et le booléen false',
  watcherStopResult(identity, {Pid: 42, Present: false}, {CmdDone: true}).stop === 'STOPPED');
t('absence d accusé ne fabrique pas CmdDone',
  watcherStopResult(identity, {Pid: 42, Present: false}, null).cmdDone === null);
t('erreur contradictoire reste incertaine',
  watcherStopResult(identity, {Pid: 42, Present: false}, {CmdErr: 'error'}).stop === 'UNKNOWN');
t('pré-contrôle avant envoi et PID déjà absent distinct',
  /watcherPresence\(ident.Pid, pre.json\)/.test(stopFn) && /stop: 'ALREADY_GONE'/.test(stopFn));
t('CLI stop-watch : code de sortie 2 hors STOPPED prouvé',
  /cmd === 'stop-watch' && r && r\.stop !== 'STOPPED'/.test(SRC) && /process\.exit\(2\)/.test(SRC));

console.log(`${ok}/${ok + ko} contrôles watcher réussis.`);
process.exitCode = ko ? 1 : 0;
