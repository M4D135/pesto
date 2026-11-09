#!/usr/bin/env node
// Pilote réutilisable de qualification Pesto v2 — demande David du 24/10/2026 (QUALIFICATION_PRIORITY.md).
// Chaîne : Spark → SSH BatchMode degun@192.168.1.173 (clé) → VBoxManage guestcontrol sur la SEULE VM
// PESTO-W11-TEST (UUID vérifié par le superviseur) → Windows PowerShell 5.1 invité en EncodedCommand UTF16LE.
// Règles appliquées : le passwordfile n'est JAMAIS lu ni affiché (le chemin seul circule) ; les preuves sont des
// JSON écrits par l'invité dans C:\Windows\Temp\pesto-v2-qual puis copyfrom vers le dossier de qualification de
// l'hôte et scp vers le Spark ; la sortie VBox est décodée avec replacement (CLIXML/codepage) et le résultat est
// jugé sur le fichier relu et le code réel, jamais sur le seul code VBox ; aucune autre VM, aucun service, aucun
// tunnel ; aucune destruction de processus globale.
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, existsSync, rmSync, appendFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { strictPrelude, resultTail, cancelScript, HELPER_BYTES, helperFileName, GUARD_MAX_SEC, GUARD_MAX_MB } from './ps-strict.mjs';
import { laboMdpFichier } from './lab-config.mjs'; // chemin seulement, jamais lu ici

const SSH_TARGET = 'degun@192.168.1.173';
const VM_UUID = '9b2ad4f0-0506-4f58-aed2-c43ac1973516';
const VBOXMANAGE = '"C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe"';
const GUEST_USER = 'labadmin';
const HOST_EVIDENCE_DIR = 'C:\\ADCC-Lab\\validation\\pesto-v2-20261024';
const HOST_EVIDENCE_FWD = 'C:/ADCC-Lab/validation/pesto-v2-20261024';
const GUEST_TMP = 'C:\\Windows\\Temp\\pesto-v2-qual';
const POWERSHELL_51 = 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
const LOCAL_EVIDENCE = process.env.PESTO_QUAL_LOGS ?? path.join(process.cwd(), 'logs', 'qualification');
export { LOCAL_EVIDENCE };

const decoder = () => new TextDecoder('utf-8', { fatal: false });

function ssh(remoteCommand, timeoutMs = 180000) {
  const r = spawnSync('ssh', ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=12', SSH_TARGET, remoteCommand],
    { encoding: 'buffer', timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024 });
  if (r.error) throw r.error;
  return { code: r.status, stdout: decoder().decode(r.stdout ?? new Uint8Array()), stderr: decoder().decode(r.stderr ?? new Uint8Array()) };
}

/// Exécute un script PowerShell dans l'invité (EncodedCommand UTF16LE, session du compte local labadmin).
export function runGuest(psScript, { timeoutMs = 120000 } = {}) {
  const b64 = Buffer.from(psScript, 'utf16le').toString('base64');
  const cmd = `${VBOXMANAGE} guestcontrol ${VM_UUID} run --exe "${POWERSHELL_51}" --username ${GUEST_USER}`
    + ` --passwordfile ${laboMdpFichier()} --quiet --timeout ${timeoutMs} --`
    + ` -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ${b64}`;
  return ssh(cmd, timeoutMs + 30000);
}

function fetchGuestJson(guestPath, name) {
  const hostPath = `${HOST_EVIDENCE_DIR}\\guest-${name}.json`;
  // VBoxManage copyfrom ne tronque PAS la destination : sans suppression préalable, une copie plus courte que
  // l'ancien fichier laisse la queue périmée (proof « valide + queue » — cause réelle du latest.json corrompu
  // du lot GUI 31, 25/10/2026). On supprime toujours l'hôte avant la copie.
  ssh(`if exist "${hostPath}" del /q "${hostPath}"`, 30000);
  const copy = ssh(`${VBOXMANAGE} guestcontrol ${VM_UUID} copyfrom --username ${GUEST_USER}`
    + ` --passwordfile ${laboMdpFichier()} --quiet "${guestPath}" "${hostPath}"`);
  mkdirSync(LOCAL_EVIDENCE, { recursive: true });
  const localPath = path.join(LOCAL_EVIDENCE, `${name}.json`);
  const scp = spawnSync('scp', ['-o', 'BatchMode=yes', `${SSH_TARGET}:${HOST_EVIDENCE_FWD}/guest-${name}.json`, localPath],
    { encoding: 'utf8', timeout: 60000 });
  let parsed = null;
  if (existsSync(localPath)) {
    try { parsed = JSON.parse(readFileSync(localPath, 'utf8').replace(/^\uFEFF/, '')); } catch { parsed = null; }
  }
  return { copy, scpCode: scp.status, scpError: scp.error?.message ?? scp.stderr?.trim() ?? null, localPath, json: parsed };
}

/// Piège stale-read : sans nettoyage, un échec du script invité ferait relire le JSON d'un lot précédent
/// comme s'il était neuf. On supprime le fichier invité AVANT exécution et le fichier local AVANT rapatriement.
/// SERIALIZATION_REVIEW_REQUIRED.md §3 : la suppression doit être précédée d'un ARCHIVAGE, sinon la preuve
/// précédente est perdue (la dernière exécution a purgé pack-deployed-verify.json avant d'échouer). L'original
/// est conservé côté invité par copie horodatée, rapatrié sur l'hôte puis sur le Spark ; rien n'est écrasé.
function archiveGuestJson(guestPath, name) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const hostArchive = `${HOST_EVIDENCE_DIR}\\archive`;
  const hostArchiveFwd = `${HOST_EVIDENCE_FWD}/archive`;
  const hostFile = `${hostArchive}\\${stamp}-${name}.json`;
  const dir = path.join(LOCAL_EVIDENCE, 'archive');
  const localFile = path.join(dir, `${stamp}-${name}.json`);
  let copyCode = null, scpCode = null, bytes = null;
  try {
    ssh(`if not exist "${hostArchive}" mkdir "${hostArchive}"`, 30000);
    copyCode = ssh(`${VBOXMANAGE} guestcontrol ${VM_UUID} copyfrom --username ${GUEST_USER}`
      + ` --passwordfile ${laboMdpFichier()} --quiet "${guestPath}" "${hostFile}"`, 60000).code;
    if (copyCode === 0) {
      mkdirSync(dir, { recursive: true });
      const scp = spawnSync('scp', ['-o', 'BatchMode=yes', `${SSH_TARGET}:${hostArchiveFwd}/${stamp}-${name}.json`, localFile],
        { encoding: 'utf8', timeout: 60000 });
      scpCode = scp.status;
      if (existsSync(localFile)) bytes = statSync(localFile).size;
    }
  } catch { /* archivage best-effort : ne bloque jamais la purge */ }
  try {
    mkdirSync(dir, { recursive: true });
    appendFileSync(path.join(dir, 'index.jsonl'),
      JSON.stringify({ archivedUtc: new Date().toISOString(), name, guestPath, stamp, copyCode, scpCode, bytes, localFile }) + '\n', 'utf8');
  } catch { /* index non bloquant */ }
  return { stamp, copyCode, scpCode, bytes };
}

function purgeGuestJson(guestPath, name) {
  archiveGuestJson(guestPath, name);
  runGuest(`Remove-Item -LiteralPath '${guestPath}' -Force -ErrorAction SilentlyContinue`, { timeoutMs: 30000 });
  const localPath = path.join(LOCAL_EVIDENCE, `${name}.json`);
  if (existsSync(localPath)) rmSync(localPath);
  const hostPath = `${HOST_EVIDENCE_FWD}/guest-${name}.json`;
  ssh(`if exist "${hostPath.replace(/\//g, '\\')}" del /q "${hostPath.replace(/\//g, '\\')}"`, 30000);
}

/// Dépose le helper COMMUN (ps-strict.mjs) sur l'hôte de qualification puis dans l'invité, une fois par process.
/// Le nom du fichier porte le sha256 du contenu : un helper modifié est un nouveau fichier, aucun script ne peut
/// tourner avec un helper périmé. Sans helper, tout appel échoue bruyamment (aucun repli sur ConvertTo-Json).
let helperCache = null;
export function ensureHelper({ force = false } = {}) {
  if (helperCache && !force) return helperCache;
  const fileName = helperFileName();
  const hostPath = `${HOST_EVIDENCE_DIR}\\${fileName}`;
  const hostFwd = `${HOST_EVIDENCE_FWD}/${fileName}`;
  const guestPath = `${GUEST_TMP}\\${fileName}`;
  mkdirSync(LOCAL_EVIDENCE, { recursive: true });
  const local = path.join(LOCAL_EVIDENCE, fileName);
  writeFileSync(local, HELPER_BYTES, 'utf8');
  const scp = spawnSync('scp', ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=12', local, `${SSH_TARGET}:${hostFwd}`],
    { encoding: 'utf8', timeout: 120000 });
  if (scp.status !== 0) throw new Error('dépôt hôte du helper impossible : ' + (scp.stderr || scp.error?.message || scp.status));
  const copy = ssh(`${VBOXMANAGE} guestcontrol ${VM_UUID} copyto --username ${GUEST_USER}`
    + ` --passwordfile ${laboMdpFichier()} --quiet "${hostPath}" "${guestPath}"`, 60000);
  if (copy.code !== 0) throw new Error('copie invitée du helper impossible (code ' + copy.code + ')');
  helperCache = { fileName, hostPath, guestPath, scpCode: scp.status, copyToCode: copy.code };
  return helperCache;
}

/// Borne dure des pilotes EN LECTURE (SERIALIZATION_REVIEW_REQUIRED.md §2) : 180 s et 512 Mo, avec annulation du
/// propre PID. Un timeoutMs supérieur est refusé plutôt que de laisser un process invité saturer la mémoire.
const READ_ONLY_CAP_MS = GUARD_MAX_SEC * 1000;
function bounded(timeoutMs) {
  if (typeof timeoutMs !== 'number' || !isFinite(timeoutMs) || timeoutMs <= 0) return READ_ONLY_CAP_MS;
  if (timeoutMs > READ_ONLY_CAP_MS) {
    console.error(`[lab-driver] timeoutMs=${timeoutMs} ramené à la borne lecture ${READ_ONLY_CAP_MS} ms`);
    return READ_ONLY_CAP_MS;
  }
  return timeoutMs;
}

const guestJsonPath = (name) => `${GUEST_TMP}\\${name}.json`;
const guestSelfPath = (name) => `${GUEST_TMP}\\${name}.self.json`;

/// Exécute un script qui doit renseigner $result, l'écrit en JSON dans l'invité, le rapatrie (copyfrom puis scp)
/// et retourne l'objet relu. L'échec est démontré par l'absence/ill lisibilité du fichier, jamais par un code VBox.
/// Réservé aux scripts courts : la ligne de commande SSH (cmd.exe hôte) est limitée à ~8191 caractères.
export function runGuestJson(psScript, name, { timeoutMs = READ_ONLY_CAP_MS, autoCancel = true } = {}) {
  if (!/^[A-Za-z0-9._-]{1,64}$/.test(name)) throw new Error('nom de preuve invalide : ' + name);
  const guestPath = guestJsonPath(name);
  purgeGuestJson(guestPath, name);
  const t = bounded(timeoutMs);
  const h = ensureHelper();
  const full = strictPrelude({ name, selfPath: guestSelfPath(name), maxSec: Math.ceil(t / 1000), maxMb: GUARD_MAX_MB, helperPath: h.guestPath })
    + `\n${psScript}\n${resultTail(guestPath)}`;
  const run = runGuest(full, { timeoutMs: t });
  if (autoCancel && timedOut(run)) cancelOwnRun(name);
  return { run, ...fetchGuestJson(guestPath, name) };
}

/// Le process invité peut survivre à la mort du ssh (VBoxManage run est détaché de la session SSH) :
/// on annule alors le SEUL processus que ce pilote a enregistré, après contrôle d'identité complet.
function timedOut(run) {
  if (!run) return true;
  if (run.code === null || run.code === undefined) return true;
  return /timed out|timeout/i.test((run.stderr || '') + (run.stdout || ''));
}

/// Annulation ciblée d'une exécution invitée lancée par ce pilote (proof name). Aucune cible globale.
export function cancelOwnRun(name) {
  if (!/^[A-Za-z0-9._-]{1,64}$/.test(name)) throw new Error('nom de preuve invalide : ' + name);
  const guestPath = `${GUEST_TMP}\\cancel-${name}.json`;
  const script = cancelScript({ selfPath: guestSelfPath(name), name });
  const t = 60000;
  const h = ensureHelper();
  const full = strictPrelude({ name: `cancel-${name}`, selfPath: null, maxSec: 60, maxMb: GUARD_MAX_MB, helperPath: h.guestPath })
    + `\n${script}\n${resultTail(guestPath)}`;
  const run = runGuest(full, { timeoutMs: t });
  return { run, ...fetchGuestJson(guestPath, `cancel-${name}`) };
}

/// Même contrat que runGuestJson mais le script est TRANSFÉRÉ en fichier (scp → copyto → powershell -File) :
/// seul moyen pour les scripts longs, l'EncodedCommand dépasse la limite de ligne de commande cmd.exe de l'hôte.
export function runGuestJsonFile(psScript, name, { timeoutMs = READ_ONLY_CAP_MS, autoCancel = true } = {}) {
  if (!/^[A-Za-z0-9._-]{1,64}$/.test(name)) throw new Error('nom de preuve invalide : ' + name);
  const guestPath = guestJsonPath(name);
  const guestScript = `${GUEST_TMP}\\tool-${name}.ps1`;
  const t = bounded(timeoutMs);
  const h = ensureHelper();
  mkdirSync(LOCAL_EVIDENCE, { recursive: true });
  const localScript = path.join(LOCAL_EVIDENCE, `tool-${name}.ps1`);
  const full = strictPrelude({ name, selfPath: guestSelfPath(name), maxSec: Math.ceil(t / 1000), maxMb: GUARD_MAX_MB, helperPath: h.guestPath })
    + `\n${psScript}\n${resultTail(guestPath)}`;
  writeFileSync(localScript, '\uFEFF' + full, 'utf8');
  purgeGuestJson(guestPath, name);
  const scpTool = spawnSync('scp', ['-o', 'BatchMode=yes', localScript, `${SSH_TARGET}:${HOST_EVIDENCE_FWD}/tool-${name}.ps1`],
    { encoding: 'utf8', timeout: 120000 });
  const copyTo = ssh(`${VBOXMANAGE} guestcontrol ${VM_UUID} copyto --username ${GUEST_USER}`
    + ` --passwordfile ${laboMdpFichier()} --quiet "${HOST_EVIDENCE_DIR}\\tool-${name}.ps1" "${guestScript}"`);
  const cmd = `${VBOXMANAGE} guestcontrol ${VM_UUID} run --exe "${POWERSHELL_51}" --username ${GUEST_USER}`
    + ` --passwordfile ${laboMdpFichier()} --quiet --timeout ${t} --`
    + ` -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ${guestScript}`;
  const run = ssh(cmd, t + 30000);
  if (autoCancel && timedOut(run)) cancelOwnRun(name);
  return { run, scpToolCode: scpTool.status, copyToCode: copyTo.code, helper: h, ...fetchGuestJson(guestPath, name) };
}

/// Commande brute sur l'hôte (VBoxManage hors guestcontrol, type, etc.) — la sortie est à juger sur fichier relu.
export function host(rawCommand, timeoutMs = 120000) { return ssh(rawCommand, timeoutMs); }

// ---- CLI ---------------------------------------------------------------------------------------------------
if (import.meta.url === `file://${process.argv[1]}`) {
  const [cmd, arg1, arg2] = process.argv.slice(2);
  if (cmd === 'run' && arg1) {
    const r = runGuest(readFileSync(arg1, 'utf8'));
    process.stdout.write(r.stdout); process.stderr.write(r.stderr); process.exitCode = r.code;
  } else if (cmd === 'json' && arg1 && arg2) {
    const r = runGuestJson(readFileSync(arg1, 'utf8'), arg2);
    process.stdout.write((r.json ? JSON.stringify(r.json, null, 1) : 'AUCUN JSON RELU\n' + r.run.stdout + r.run.stderr) + '\n');
    process.exitCode = r.json ? 0 : 1;
  } else if (cmd === 'jsonfile' && arg1 && arg2) {
    const r = runGuestJsonFile(readFileSync(arg1, 'utf8'), arg2);
    process.stdout.write((r.json ? JSON.stringify(r.json, null, 1)
      : `AUCUN JSON RELU (scpTool=${r.scpToolCode} copyTo=${r.copyToCode} run=${r.run?.code})\n` + r.run.stdout + r.run.stderr) + '\n');
    process.exitCode = r.json ? 0 : 1;
  } else if (cmd === 'cancel' && arg1) {
    const r = cancelOwnRun(arg1);
    process.stdout.write((r.json ? JSON.stringify(r.json, null, 1)
      : `AUCUN JSON RELU (run=${r.run?.code})\n` + r.run.stdout + r.run.stderr) + '\n');
    process.exitCode = r.json && /^(STOPPED|ALREADY_GONE)$/.test(r.json.Status) ? 0 : 1;
  } else if (cmd === 'host' && arg1) {
    const r = host(arg1);
    process.stdout.write(r.stdout); process.stderr.write(r.stderr); process.exitCode = r.code;
  } else {
    console.error('usage: lab-driver.mjs run <script.ps1> | json <script.ps1> <nom-preuve> | jsonfile <script.ps1> <nom-preuve> | cancel <nom-preuve> | host "<commande hôte>"');
    process.exitCode = 2;
  }
}
