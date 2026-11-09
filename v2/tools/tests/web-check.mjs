// Contrôle portable de l'interface web Pesto (no browser, no network, no native host) :
//  1. graphe d'imports : tout fichier importé par un module JS ou par index.html existe ; aucune dépendance externe ;
//  2. liste fermée du pont : toute opération demandée via call('…') ou le simulateur appartient à docs/BRIDGE.md ;
//  3. module d'import pur (liste collée, CSV) : validation ligne à ligne, bornes, doublons, sans DOM ;
//  4. scénario complet sur la simulation JS : aperçu → préparation → confirmation exacte → exécution → reçu,
//     refus (confirmation fausse, plan consommé, aperçu expiré, poste d'un autre, jonction distante), file, reçus ;
//  5. scénario file « côté page » (monde neuf) : ajouts multiples, doublon refusé, retrait, lot préparé,
//     exécution séquentielle arrêtée sur la ligne dont le poste a bougé, ligne échouée jamais rejouée ;
//  6. icônes, couverture réelle des 9 pages vs docs/BRIDGE.md, repli _todo réservé au routeur,
//     shell (Ctrl+B, Ctrl+K, 4 thèmes) et copies figées du kit Domenia vérifiées octet à octet (provenance.json).
// Sortie 0 seulement si tout passe. Ce contrôle ne remplace ni les tests Engine (dotnet) ni la qualification Windows/AD.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, dirname, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createSimulation } from '../../web/js/simulation.js';
import { parsePastedList, parseQueueCsv, MAX_ROWS } from '../../web/js/csv.js';

const here = dirname(fileURLToPath(import.meta.url));
const webDir = resolve(here, '../../web');
const jsDir = join(webDir, 'js');

let checks = 0;
let failures = 0;
const ok = (name) => { checks += 1; console.log(`  ok   ${name}`); };
const fail = (name, detail) => { checks += 1; failures += 1; console.error(`  FAIL ${name} — ${detail}`); };
const assert = (cond, name, detail = 'condition fausse') => (cond ? ok(name) : fail(name, detail));
const section = (title) => console.log(`\n== ${title} ==`);

function walk(dir) {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(p));
    else if (entry.isFile() && entry.name.endsWith('.js')) out.push(p);
  }
  return out;
}

const files = walk(jsDir);
const read = (p) => readFileSync(p, 'utf8');

// ---------- 1. imports and assets ----------
section('Graphe d’imports et actifs');

const IMPORT_RE = /(?:import|export)\s+(?:[^'"]*?\sfrom\s+)?['"]([^'"]+)['"]/g;
const DYN_RE = /import\(\s*['"]([^'"]+)['"]\s*\)/g;
let importCount = 0;
let importsOk = true;
for (const file of files) {
  const src = read(file);
  const specs = [...src.matchAll(IMPORT_RE), ...src.matchAll(DYN_RE)].map((m) => m[1]);
  for (const spec of specs) {
    importCount += 1;
    const rel = relative(jsDir, file);
    if (!spec.startsWith('./') && !spec.startsWith('../')) {
      fail(`import externe ${rel} → ${spec}`, 'aucune dépendance ni CDN admis (mission : ES modules locaux)');
      importsOk = false;
      continue;
    }
    const target = resolve(dirname(file), spec);
    if (!existsSync(target)) {
      fail(`import manquant ${rel} → ${spec}`, 'fichier absent');
      importsOk = false;
    }
  }
}
if (importsOk) ok(`${importCount} imports résolus dans ${files.length} modules`);

const html = read(join(webDir, 'index.html'));
for (const m of html.matchAll(/(?:src|href)="([^"]+)"/g)) {
  const target = join(webDir, m[1]);
  assert(existsSync(target), `index.html → ${m[1]}`, 'fichier absent');
}
assert(/connect-src 'none'/.test(html), 'CSP connect-src none (aucun réseau depuis la webapp)');
assert(/script-src 'self'/.test(html), 'CSP script-src self (aucun CDN)');

// ---------- 2. closed bridge list ----------
section('Liste fermée du pont (docs/BRIDGE.md)');

const OPS = new Set([
  'session.info', 'dashboard.read', 'directory.sites', 'directory.services', 'directory.search',
  'computer.inspect', 'names.preview', 'operation.prepare', 'operation.execute',
  'attributes.inspect', 'attributes.prepare', 'attributes.apply', 'attributes.observe',
  'offlineJoin.open', 'offlineJoin.list', 'offlineJoin.import', 'offlineJoin.prepare', 'offlineJoin.apply', 'offlineJoin.observe',
  'queue.add', 'queue.list', 'queue.remove', 'queue.prepare', 'queue.execute',
  'receipts.list', 'receipts.get', 'receipts.reconcile', 'receipts.prepareMove', 'logs.list', 'settings.get', 'settings.save', 'diagnostics.read',
  'reservations.list', 'reservations.inspect', 'reservations.prepare', 'reservations.execute',
  'join.precreated.preview', 'receipts.prepareAcknowledgement', 'receipts.acknowledge', 'receipts.prepareRestart', 'receipts.restart',
  'coordination.status', 'coordination.inspect', 'coordination.prepare', 'coordination.apply',
  'demo.open', 'demo.status', 'demo.reset', 'demo.scenario', 'demo.restart', 'demo.prepareMove',
  'configuration.status', 'configuration.settings', 'configuration.export', 'configuration.previewImport', 'configuration.previewSettings',
  'configuration.applyImport', 'configuration.decideDistribution', 'configuration.setDefault', 'references.preview', 'references.apply',
  'updates.status', 'updates.windows', 'updates.inspect', 'updates.prepare', 'updates.install', 'updates.rollback', 'updates.recover', 'host.reconnect',
]);
const LIVE_ONLY = [...OPS].filter((op) => /^(configuration|references|updates|reservations|coordination|attributes|offlineJoin)\./.test(op) || op === 'host.reconnect'
  || ['join.precreated.preview', 'receipts.prepareAcknowledgement', 'receipts.acknowledge', 'receipts.prepareRestart', 'receipts.restart'].includes(op));

const CALL_RE = /\bcall\(\s*'([a-z][a-zA-Z.]*)'/g;
const usedOps = new Set();
let callsOk = true;
for (const file of files) {
  for (const m of read(file).matchAll(CALL_RE)) {
    usedOps.add(m[1]);
    if (!OPS.has(m[1])) {
      fail(`opération hors liste : ${relative(jsDir, file)} → ${m[1]}`, 'non déclarée dans docs/BRIDGE.md');
      callsOk = false;
    }
  }
}
if (callsOk) ok(`toutes les opérations appelées (${usedOps.size}) appartiennent à la liste fermée`);

const simSrc = read(join(jsDir, 'simulation.js'));
const simOps = [...simSrc.matchAll(/case '([a-z][a-zA-Z.]*)':/g)].map((m) => m[1]);
const unknownSim = simOps.filter((op) => !OPS.has(op));
assert(unknownSim.length === 0, `simulateur : ${simOps.length} opérations déclarées`, `hors liste : ${unknownSim.join(', ')}`);
const missingSim = [...OPS].filter((op) => !LIVE_ONLY.includes(op) && !simOps.includes(op));
assert(missingSim.length === 0, 'simulateur couvre la liste complète', `absentes : ${missingSim.join(', ')}`);
const isolated = createSimulation();
for (const op of LIVE_ONLY) {
  let denied = false;
  try { await isolated.invoke(op, { path: '\\\\server\\share', source: 'https://example.invalid/', confirmed: true }); }
  catch (error) { denied = error.code === 'demo.isolated'; }
  assert(denied, `${op} refusée en appel direct à la démonstration avant tout I/O`);
}

// pages : chaque écran de la navigation de app.js a son module (le repli _todo reste réservé aux écrans non portés)
const appSrc = read(join(jsDir, 'app.js'));
const pageBranches = /const PAGES = OFFLINE_ENTRY \? \[([\s\S]*?)\] : \[([\s\S]*?)\n\];/.exec(appSrc);
const declaredPageIds = (block) => [...(block ?? '').matchAll(/\{ id: '([a-z0-9-]+)', label:/g)].map((m) => m[1]);
const offlinePageIds = declaredPageIds(pageBranches?.[1]);
const pageIds = declaredPageIds(pageBranches?.[2]);
const expectedPages = ['accueil', 'ajouter', 'unposte', 'plusieurspostes', 'noms', 'interventions', 'journal', 'parametres', 'aide'];
assert(JSON.stringify(pageIds) === JSON.stringify(expectedPages), 'navigation normale : 9 écrans exacts dans leur ordre déclaré', `trouvés : ${pageIds.join(', ')}`);
assert(JSON.stringify(offlinePageIds) === JSON.stringify(['offline-join']), 'navigation locale ODJ : uniquement la jonction hors ligne', `trouvés : ${offlinePageIds.join(', ')}`);
// Écrans volontairement non portés à ce lot : ils rendent l'honnête écran _todo. Tout autre écran de la navigation
// doit avoir son module ; quand une page est écrite, elle sort de cette liste (sinon le contrôle échoue).
const UNPORTED = new Set([]);
for (const id of [...pageIds, ...offlinePageIds]) {
  if (UNPORTED.has(id)) {
    assert(!existsSync(join(jsDir, 'pages', `${id}.js`)), `page ${id} non portée (écran _todo)`, 'module écrit : retirer de UNPORTED');
  } else {
    assert(existsSync(join(jsDir, 'pages', `${id}.js`)), `page ${id}`, 'module absent (écran encore en maquette)');
  }
}
for (const id of ['ajouter', 'unposte', 'plusieurspostes', 'interventions', 'journal', 'parametres', 'aide']) {
  const p = join(jsDir, 'pages', `${id}.js`);
  if (existsSync(p)) assert(/export function render\(/.test(read(p)), `page ${id} exporte render`, 'export manquant');
}

// ---------- 3. import module (pasted list + CSV, pure) ----------
section('Module d’import (liste collée et CSV, sans DOM)');

const csvSrc = read(join(jsDir, 'csv.js'));
assert(!/\b(document|window|fetch|localStorage|XMLHttpRequest)\b/.test(csvSrc), 'csv.js reste pur (aucun DOM, aucun réseau, aucun pont)');

const pl = parsePastedList('P111301PAINF001\r\np111301painf001\n# commentaire\nPC-2\nmauvais nom\nPC-\n');
assert(pl.names.length === 2 && pl.names[0] === 'P111301PAINF001' && pl.names[1] === 'PC-2',
  'liste collée : majuscules, doublon ignoré, lignes invalides refusées ligne à ligne', JSON.stringify(pl));
assert(pl.issues.length === 3 && pl.issues.every((i) => i.line > 0 && i.reason),
  'liste collée : chaque ligne rejetée est signalée avec son numéro', JSON.stringify(pl.issues));
const plEmpty = parsePastedList('  \n\n# rien\n');
assert(plEmpty.names.length === 0 && plEmpty.issues.length === 1, 'liste collée vide : refus explicite', JSON.stringify(plEmpty));
const many = Array.from({ length: MAX_ROWS + 10 }, (_, i) => `PC${String(i).padStart(3, '0')}`).join('\n');
const plMany = parsePastedList(many);
assert(plMany.names.length === MAX_ROWS && plMany.truncated === true,
  `liste collée bornée à ${MAX_ROWS} postes (limite moteur de la file)`, JSON.stringify({ n: plMany.names.length, t: plMany.truncated }));

const csv = parseQueueCsv('name;type;site;service\nS111301PAADM001;S;paris;ADM\nP111301LYLOG001;X;lyon;LOG\nmauvais nom;;;\n');
assert(csv.rows.length === 1 && csv.rows[0].name === 'S111301PAADM001' && csv.rows[0].type === 'S' && csv.rows[0].service === 'ADM',
  'CSV : en-tête sauté, colonnes lues, lignes invalides rejetées ligne à ligne', JSON.stringify(csv));
assert(csv.issues.length === 2 && csv.issues.every((i) => i.line > 0),
  'CSV : type invalide et nom invalide signalés avec leur ligne', JSON.stringify(csv.issues));
const csvComma = parseQueueCsv('"PC-1","P","paris","INF"\nPC-2');
assert(csvComma.rows.length === 2 && csvComma.rows[0].name === 'PC-1' && csvComma.rows[1].site === null,
  'CSV : virgule et guillemets admis, colonnes optionnelles = null (le moteur tranchera)', JSON.stringify(csvComma));
const csvEmpty = parseQueueCsv('\n\n');
assert(csvEmpty.rows.length === 0 && csvEmpty.issues.length === 1, 'CSV vide : refus explicite', JSON.stringify(csvEmpty));
const csvTooMany = parseQueueCsv(Array.from({ length: MAX_ROWS + 5 }, (_, i) => `PC${String(i).padStart(3, '0')}`).join('\n'));
assert(csvTooMany.rows.length === MAX_ROWS && csvTooMany.truncated === true, `CSV borné à ${MAX_ROWS} lignes`, JSON.stringify({ n: csvTooMany.rows.length }));

// ---------- 4. simulation scenario ----------
section('Scénario simulation (moteur JS en mémoire)');

let t = Date.UTC(2026, 9, 24, 8, 0, 0);
const sim = createSimulation({ now: () => t });
const advance = (ms) => { t += ms; };
const MIN = 60_000;

async function expectError(op, args, code, name) {
  try {
    await sim.invoke(op, args);
    fail(name, `erreur ${code} attendue, résultat renvoyé à la place`);
  } catch (err) {
    assert(err.code === code, name, `code ${err.code} reçu, ${code} attendu (${err.message})`);
  }
}

const session = await sim.invoke('session.info');
assert(session.mode === 'simulation', 'session.info annonce la simulation');
assert(['join', 'rename', 'move', 'renameMove', 'queue'].every((id) => session.capabilities.some((c) => c.id === id)),
  'capabilities join/rename/move/renameMove/queue présentes');

const sites = (await sim.invoke('directory.sites')).items;
assert(sites.length === 2, 'directory.sites renvoie les deux sites de démonstration');
const services = (await sim.invoke('directory.services', { site: 'paris' })).items;
assert(services.length === 3, 'directory.services renvoie les services');

// --- jonction : aperçu → préparation → confirmation exacte → exécution unique → reçu ---
// La garde « jonction locale seule » est vérifiée avant toute jonction (le moteur teste l'état joint en premier).
const pLocal = await sim.invoke('names.preview', { type: 'S', site: 'lyon', service: 'ADM' });
await expectError('operation.prepare', { kind: 'join', computer: 'AUTRE-PC', previewId: pLocal.previewId }, 'join.localOnly',
  'jonction d’un poste distant refusée');
const p1 = await sim.invoke('names.preview', { type: 'P', site: 'paris', service: 'INF' });
assert(p1.complete === true && /^P\d{6}PAINF\d{3}$/.test(p1.name), 'names.preview calcule un nom libre complet', JSON.stringify(p1));
const plan1 = await sim.invoke('operation.prepare', { kind: 'join', previewId: p1.previewId });
assert(plan1.confirmationName === p1.name && plan1.mode === 'simulation', 'plan de jonction lié à l’aperçu (mode simulation)');
await expectError('operation.execute', { planId: plan1.planId, confirmationName: 'MAUVAIS-NOM' }, 'confirmation.invalid',
  'exécution refusée si la confirmation n’est pas exacte');
const r1 = await sim.invoke('operation.execute', { planId: plan1.planId, confirmationName: p1.name });
assert(r1.status === 'simulated' && r1.mode === 'simulation' && r1.restartRequired === true, 'reçu simulé avec redémarrage à planifier', JSON.stringify(r1));
await expectError('operation.execute', { planId: plan1.planId, confirmationName: p1.name }, 'plan.consumed',
  'un plan consommé ne peut pas être rejoué');
await expectError('operation.prepare', { kind: 'join', previewId: p1.previewId }, 'join.alreadyJoined',
  'double jonction refusée');

// --- renommage : le nom provient de l'aperçu, l'identité de l'aperçu est vérifiée ---
const target = 'S111301PAADM001';
const p2 = await sim.invoke('names.preview', { type: 'S', site: 'paris', service: 'ADM', computer: target });
await expectError('operation.prepare', { kind: 'rename', computer: 'P111301PAINF001', previewId: p2.previewId }, 'preview.identity',
  'aperçu d’un autre poste refusé pour ce renommage');
const plan2 = await sim.invoke('operation.prepare', { kind: 'rename', computer: target, previewId: p2.previewId });
const r2 = await sim.invoke('operation.execute', { planId: plan2.planId, confirmationName: plan2.confirmationName });
assert(r2.computer === target && r2.newName === p2.name, 'renommage appliqué : reçu computer → newName', JSON.stringify(r2));
const inspected = await sim.invoke('computer.inspect', { computer: p2.name });
assert(inspected.name === p2.name, 'le nouveau nom est relisible dans l’annuaire simulé');
await expectError('computer.inspect', { computer: target }, 'computer.missing', 'l’ancien nom a disparu');

// --- même site = OU inchangée ---
const deep = await sim.invoke('names.preview', { type: 'V', site: 'lyon', service: 'INF', computer: 'V111301LYINF001' });
assert(deep.ou === 'OU=Lyon,OU=Postes,DC=example,DC=local', 'aperçu sur même site conserve l’OU du poste');

// --- déplacement ---
const plan3 = await sim.invoke('operation.prepare', { kind: 'move', computer: 'V111301LYINF001', targetOU: sites[0].ou });
const r3 = await sim.invoke('operation.execute', { planId: plan3.planId, confirmationName: plan3.confirmationName });
assert(r3.targetOU === sites[0].ou && r3.restartRequired === false, 'déplacement sans redémarrage requis', JSON.stringify(r3));
await expectError('operation.prepare', { kind: 'move', computer: 'V111301LYINF001' }, 'invalid_arguments',
  'déplacement sans OU refusé');

// --- expiration : l'horloge avance au-delà de la validité ---
const p4 = await sim.invoke('names.preview', { type: 'P', site: 'lyon', service: 'LOG' });
advance(6 * MIN);
await expectError('operation.prepare', { kind: 'rename', computer: 'P111301LYLOG001', previewId: p4.previewId }, 'plan.stale',
  'aperçu expiré refusé (jamais exécuté sur un plan périmé)');

// --- file : ajout, doublons, lot séquentiel, confirmation explicite ---
await expectError('queue.add', { kind: 'join', computer: 'X' }, 'queue.local', 'jonction jamais mise en file');
const p5 = await sim.invoke('names.preview', { type: 'P', site: 'paris', service: 'ADM', computer: 'P111301PAINF001' });
const added = await sim.invoke('queue.add', { kind: 'rename', computer: 'P111301PAINF001', previewId: p5.previewId });
assert(added.count === 1, 'poste ajouté à la file');
await expectError('queue.add', { kind: 'rename', computer: 'P111301PAINF001', previewId: p5.previewId }, 'queue.duplicate',
  'doublon refusé (même poste)');
const batch = await sim.invoke('queue.prepare');
assert(batch.items.length === 1 && batch.batchId, 'lot préparé avec ses plans');
await expectError('queue.execute', { batchId: batch.batchId, confirmed: false }, 'confirmation.invalid',
  'lot sans confirmation explicite refusé');
const done = await sim.invoke('queue.execute', { batchId: batch.batchId, confirmed: true });
assert(done.receipts.length === 1 && done.stopped === false, 'lot exécuté séquentiellement, sans arrêt');
assert((await sim.invoke('queue.list')).count === 0, 'file vidée après exécution');

// --- reçus, journaux, opérations inconnues ---
const receipts = (await sim.invoke('receipts.list', {})).items;
assert(receipts.length === 4 && receipts.every((r) => r.mode === 'simulation' && r.status === 'simulated'),
  'les quatre écritures de la session ont un reçu simulé');
const one = await sim.invoke('receipts.get', { id: receipts[0].id });
assert(one.id === receipts[0].id, 'reçu relu à l’identifiant');
await expectError('receipts.get', { id: 'receipt-inexistant' }, 'receipt.missing', 'reçu inconnu refusé');
await expectError('receipts.reconcile', { id: receipts[0].id }, 'receipt.reconcileSimulation', 'la simulation refuse de fabriquer une preuve d’état réel');
await expectError('receipts.prepareMove', { id: receipts[0].id }, 'receipt.prepareMoveSimulation', 'la simulation refuse la préparation restante d’une opération réelle');
const logs = (await sim.invoke('logs.list', {})).items;
assert(logs.length > 0 && logs.every((l) => l.time && l.level && l.message), 'journal non vide, lignes complètes');
await expectError('operation.inventee', {}, 'operation.unknown', 'opération hors liste refusée par le moteur');

// --- paramètres : validation moteur et invalidation des aperçus ---
await expectError('settings.save', { domain: 'pas-un-fqdn', dc: '', prefix: '111', production: false, namingPattern: '{type}{prefix}{site}{service}{number:3}', randomNames: false, sites },
  'settings.domain', 'domaine invalide refusé par le moteur');
const saved = await sim.invoke('settings.save', { domain: 'labo.local', dc: 'dc01.labo.local', prefix: '2220', production: false, namingPattern: '{type}{prefix}{site}{service}{number:3}', randomNames: false,
  sites: [{ id: 'nantes', name: 'Nantes', code: 'NA', ou: 'OU=Nantes,OU=Postes,DC=labo,DC=local' }] });
assert(saved.domain === 'labo.local' && saved.sites[0].code === 'NA', 'paramètres validés puis relus');
const p6 = await sim.invoke('names.preview', { type: 'V', site: 'nantes', service: 'INF' });
await sim.invoke('settings.save', { domain: 'labo.local', dc: 'dc01.labo.local', prefix: '2220', production: false, namingPattern: '{type}{prefix}{site}{service}{number:3}', randomNames: false,
  sites: [{ id: 'nantes', name: 'Nantes', code: 'NA', ou: 'OU=Nantes,OU=Postes,DC=labo,DC=local' }] });
await expectError('operation.prepare', { kind: 'rename', computer: 'V111301LYINF001', previewId: p6.previewId }, 'plan.stale',
  'les paramètres enregistrés invalident les aperçus (re-préparation obligatoire)');
await expectError('settings.save', { domain: 'labo.local', dc: '', prefix: '2220', production: false, namingPattern: '{type}{prefix}{site}{service}{number:3}', randomNames: false,
  sites: [{ id: 'nantes', name: 'Nantes', code: 'NA', ou: 'OU=Nantes,OU=Postes,DC=labo,DC=local' }], liveExecutionEnabled: true },
  'simulation.only', 'les écritures réelles ne s’activent pas depuis la simulation');

// ---------- 5. scénario file « côté page » (monde neuf, même horloge) ----------
section('Scénario file côté page (ajouts multiples, retrait, arrêt en cours de lot)');

const sim2 = createSimulation({ now: () => t });
async function expectError2(op, args, code, name) {
  try {
    await sim2.invoke(op, args);
    fail(name, `erreur ${code} attendue, résultat renvoyé à la place`);
  } catch (err) {
    assert(err.code === code, name, `code ${err.code} reçu, ${code} attendu (${err.message})`);
  }
}
const queueRename = async (computer, type, site, service) => {
  const p = await sim2.invoke('names.preview', { type, site, service, computer });
  return sim2.invoke('queue.add', { kind: 'rename', computer, previewId: p.previewId });
};

await expectError2('queue.add', { kind: 'rename', computer: 'S111301PAADM001' }, 'plan.stale',
  'page : aucun ajout en file sans aperçu (le nom vient de names.preview, jamais d’une saisie)');
// même moteur que la page : le simulateur du navigateur refuse aussi les opérations hors liste fermée
await expectError2('queue.add', { kind: 'join', computer: 'NOUVEAU-PC' }, 'queue.local', 'page : la jonction reste hors file');

await queueRename('S111301PAADM001', 'S', 'paris', 'ADM');
await queueRename('P111301PAINF001', 'P', 'paris', 'INF');
await queueRename('P111301LYLOG001', 'P', 'lyon', 'LOG');
assert((await sim2.invoke('queue.list')).count === 3, 'page : trois postes en file après ajout');
await expectError2('queue.add', { kind: 'rename', computer: 'S111301PAADM001', previewId: (await sim2.invoke('names.preview', { type: 'S', site: 'paris', service: 'ADM', computer: 'S111301PAADM001' })).previewId },
  'queue.duplicate', 'page : doublon refusé par le moteur, affiché tel quel');

const qItems = (await sim2.invoke('queue.list')).items;
const thirdId = qItems.find((q) => q.computer === 'P111301LYLOG001').id;
const afterRemove = await sim2.invoke('queue.remove', { id: thirdId });
assert(afterRemove.count === 2, 'page : retrait d’une ligne de la file');
await queueRename('P111301LYLOG001', 'P', 'lyon', 'LOG');
assert((await sim2.invoke('queue.list')).count === 3, 'page : la ligne retirée peut être réajoutée (aperçu recalculé)');

const batch2 = await sim2.invoke('queue.prepare');
assert(batch2.items.length === 3 && batch2.batchId && batch2.expiresAt, 'page : lot préparé, aperçu complet avant exécution');

// Le poste de la troisième ligne est renommé hors file pendant la préparation : le lot doit s’arrêter là.
const stray = await sim2.invoke('names.preview', { type: 'P', site: 'lyon', service: 'LOG', computer: 'P111301LYLOG001' });
const strayPlan = await sim2.invoke('operation.prepare', { kind: 'rename', computer: 'P111301LYLOG001', previewId: stray.previewId });
await sim2.invoke('operation.execute', { planId: strayPlan.planId, confirmationName: strayPlan.confirmationName });

const run2 = await sim2.invoke('queue.execute', { batchId: batch2.batchId, confirmed: true });
assert(run2.stopped === true && run2.receipts.length === 2 && run2.reason,
  'page : exécution séquentielle arrêtée à la ligne dont le poste a bougé, un reçu par ligne appliquée', JSON.stringify(run2));
assert((await sim2.invoke('queue.list')).count === 1, 'page : la ligne échouée reste en file, jamais rejouée automatiquement');
await expectError2('queue.execute', { batchId: batch2.batchId, confirmed: true }, 'batch.stale',
  'page : un lot envoyé ne peut pas être renvoyé (aucun rejeu automatique)');
await expectError2('queue.prepare', {}, 'computer.missing',
  'page : la ligne échouée ne se re-prépare pas tant que le poste manque — retrait explicite requis');
const leftover = (await sim2.invoke('queue.list')).items[0];
await sim2.invoke('queue.remove', { id: leftover.id });
assert((await sim2.invoke('queue.list')).count === 0, 'page : file vidée après retrait explicite de la ligne échouée');
await expectError2('queue.prepare', {}, 'queue.empty', 'page : lot sur file vide refusé');

// ---------- 6. icons, real page coverage, frozen kit ----------
section('Icônes, couverture réelle des pages, kit Domenia figé');

const iconsSrc = read(join(jsDir, 'icons.js'));
const iconNames = new Set([...iconsSrc.matchAll(/^ {2}([a-zA-Z]+): '/gm)].map((m) => m[1]));
assert(iconNames.size >= 40, `icons.js déclare ${iconNames.size} icônes`, 'jeu d’icônes inattendu (copie Domenia figée ?)');
let iconsOk = true;
let iconUses = 0;
for (const file of files) {
  if (relative(jsDir, file) === 'icons.js') continue;
  for (const m of read(file).matchAll(/\bicon\(\s*'([a-zA-Z]+)'/g)) {
    iconUses += 1;
    if (!iconNames.has(m[1])) {
      fail(`icône inconnue : ${relative(jsDir, file)} → icon('${m[1]}')`, 'absente de icons.js — l’usage doit viser une icône existante (repli info = dérive silencieuse)');
      iconsOk = false;
    }
  }
}
if (iconsOk) ok(`${iconUses} appels icon('nom') statiques référencent tous une icône de icons.js`);

// icônes de la navigation et des thèmes, rendues par icon(page.icon) / icon(t.icon) dans app.js
const navIcons = [...appSrc.matchAll(/icon: '([a-zA-Z]+)'/g)].map((m) => m[1]);
const badNavIcons = navIcons.filter((n) => !iconNames.has(n));
assert(badNavIcons.length === 0, `icônes navigation+thèmes (${navIcons.length}) existantes dans icons.js`, `inconnues : ${badNavIcons.join(', ')}`);

// options { icon: 'nom' } hors kit (pill, commandes d'écran) : rendues par glyph() avec repli icon() — le nom doit exister quelque part
const glyphNames = new Set([...read(join(jsDir, 'kit', 'glyphs.js')).matchAll(/^ {2}([a-zA-Z]+): '/gm)].map((m) => m[1]));
const optionIcons = [];
for (const file of files) {
  if (relative(jsDir, file).startsWith('kit' + '/') || relative(jsDir, file) === 'icons.js') continue;
  for (const m of read(file).matchAll(/\bicon: '([a-zA-Z]+)'/g)) optionIcons.push([relative(jsDir, file), m[1]]);
}
const badOptionIcons = optionIcons.filter(([, n]) => !iconNames.has(n) && !glyphNames.has(n));
assert(badOptionIcons.length === 0, `${optionIcons.length} options { icon } hors kit référencent une icône existante (icons.js ou glyphs.js)`,
  badOptionIcons.map(([f, n]) => `${f} → ${n}`).join(', '));

// shell promis par la mission : Ctrl+B (menu), Ctrl+K (palette), 4 thèmes dont système et contraste
assert(/e\.ctrlKey[\s\S]{0,80}e\.key === 'b'/.test(appSrc), 'raccourci Ctrl+B câblé (repli du menu, bouton tout en bas)');
assert(/e\.ctrlKey[\s\S]{0,80}e\.key === 'k'/.test(appSrc), 'raccourci Ctrl+K câblé (palette de commandes)');
// Régression AZERTY (session réelle 25/10/2026) : Alt+1..9 doit accepter la touche physique (e.code Digit1..9),
// Shift autorisé — sur clavier français le chiffre exige Shift et l'ancienne condition le rendait inatteignable.
assert(/e\.altKey && !e\.ctrlKey && \(\/\^\[1-9\]\$\/\.test\(e\.key\) \|\| \/\^Digit\[1-9\]\$\/\.test\(e\.code\)\)/.test(appSrc),
  'Alt+1..9 compatible AZERTY (e.code Digit1..9 accepté, shift autorisé)');
const themeIds = [...appSrc.matchAll(/\{ id: '(light|dark|contrast|system)', label:/g)].map((m) => m[1]);
assert(themeIds.length === 4, 'thèmes clair/sombre/contraste/système présents', `trouvés : ${themeIds.join(', ')}`);

// régression fenêtre réelle 25/10 : les cartes KPI de l'accueil sont dans .grid (12 colonnes, layout.css) ;
// sans classe span-*, chaque carte occupe 1/12 (texte coupé + espace vide — constat en session interactive).
const accueilSrc = read(join(jsDir, 'pages', 'accueil.js'));
const kpiFn = /function kpiCard[\s\S]*?\n}/.exec(accueilSrc)?.[0] ?? '';
assert(/class="card kpi[^"]*span-3[^"]*"/.test(kpiFn),
  'accueil : chaque carte KPI occupe 3/12 colonnes (4 cartes = ligne pleine)',
  kpiFn ? 'classe span absente du gabarit kpiCard' : 'gabarit kpiCard introuvable');

// couverture réelle : chaque opération de docs/BRIDGE.md est effectivement appelée par l’interface (page ou shell)
const usedEverywhere = new Set(usedOps);
for (const file of files) {
  for (const m of read(file).matchAll(/\btrackedCall\(\s*'([a-z][a-zA-Z.]*)'/g)) usedEverywhere.add(m[1]);
}
const neverUsed = [...OPS].filter((op) => !usedEverywhere.has(op));
assert(neverUsed.length === 0, `les ${OPS.size} opérations de docs/BRIDGE.md sont toutes utilisées par l’interface`, `jamais appelées : ${neverUsed.join(', ')}`);

// l’écran maquette _todo reste le repli du seul routeur : aucune page ne se présente comme porté via lui
const todoImporters = files.filter((f) => !f.endsWith('router.js') && /pages\/_todo\.js/.test(read(f)));
assert(todoImporters.length === 0, 'repli _todo réservé au routeur (aucune page maquette présentée comme portée)',
  todoImporters.map((f) => relative(jsDir, f)).join(', '));

// kit Domenia : les copies figées de provenance.json sont contrôlées par empreinte, puis octet à octet contre la référence si elle est là
const prov = JSON.parse(read(join(webDir, 'provenance.json')));
const refWeb = resolve(here, '../../../../references/domenia/v2/web');
const refAvailable = existsSync(refWeb);
const provBad = [];
const refBad = [];
let frozenCount = 0;
for (const entry of prov.files) {
  const local = join(webDir, entry.path);
  if (!existsSync(local)) { provBad.push(`${entry.path} (absent de web/)`); continue; }
  const localHash = createHash('sha256').update(readFileSync(local)).digest('hex');
  if (localHash !== entry.sha256) { provBad.push(entry.path); continue; }
  if (entry.modified) continue;
  frozenCount += 1;
  if (!refAvailable) continue;
  const refFile = join(refWeb, entry.path);
  if (!existsSync(refFile)) { refBad.push(`${entry.path} (référence absente)`); continue; }
  if (createHash('sha256').update(readFileSync(refFile)).digest('hex') !== entry.sha256) refBad.push(entry.path);
}
assert(provBad.length === 0, `provenance.json : ${prov.files.length} entrées, empreintes SHA-256 locales exactes`, `dérive : ${provBad.join(', ')}`);
assert(prov.files.every((f) => !f.modified || (typeof f.modified === 'string' && f.modified.length > 0)),
  'copies écartées du figé marquées « modified » avec leur motif');
if (refAvailable) {
  assert(refBad.length === 0, `${frozenCount} copies figées identiques octet à octet à la référence Domenia figée`, `dérive : ${refBad.join(', ')}`);
} else {
  ok(`référence Domenia absente de ce poste : comparaison octet à octet non exécutée (${frozenCount} empreintes locales vérifiées)`);
}

// ---------- refus de l’interface ----------
section('Refus de l’interface');
// errorText n’affiche que les erreurs codées : une erreur non codée s’afficherait « Erreur interne de l’interface ».
const uncoded = files.filter((f) => /(?<!Object\.assign\()new Error\(/.test(read(f))).map((f) => relative(webDir, f));
assert(uncoded.length === 0, 'chaque refus de l’interface est codé (refusal), son motif est affiché', `non codés : ${uncoded.join(', ')}`);

// ---------- bilan ----------
console.log(`\n${checks - failures}/${checks} contrôles réussis.`);
process.exit(failures === 0 ? 0 : 1);
