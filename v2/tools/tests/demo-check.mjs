// Behavior of the real browser demo engine. No native host or network transport is involved.
import assert from 'node:assert/strict';
import { createSimulation } from '../../web/js/simulation.js';

const sim = () => createSimulation({ now: () => Date.UTC(2026, 9, 25) });
const select = (b, id) => b.invoke('demo.scenario', { id, confirmed: true });
const plan = async (b, computer = 'S111301PAADM001') => {
  const p = await b.invoke('names.preview', { type: 'S', site: 'paris', service: 'ADM', computer });
  return b.invoke('operation.prepare', { kind: 'rename', computer, previewId: p.previewId });
};
const execute = (b, p) => b.invoke('operation.execute', { planId: p.planId, confirmationName: p.confirmationName });
const rejects = (f, code) => assert.rejects(f, (e) => e.code === code);
let count = 0;
async function check(name, action) { await action(); count++; console.log(`OK ${name}`); }

await check('IDs uniques par fenêtre et à travers reset sous horloge figée', async () => {
  const a = sim(), b = sim(), before = await plan(a);
  const receipt = await execute(a, before);
  await a.invoke('demo.reset', { confirmed: true });
  const after = await plan(a), other = await plan(b);
  assert.equal(new Set([before.planId, after.planId, other.planId]).size, 3);
  await rejects(() => execute(a, before), 'plan.stale');
  await rejects(() => a.invoke('receipts.get', { id: receipt.id }), 'receipt.missing');
});
await check('Reset, scénario et reboot exigent une confirmation même en appel direct', async () => {
  const b = sim();
  for (const op of ['demo.reset', 'demo.scenario', 'demo.restart']) await rejects(() => b.invoke(op, { confirmed: false }), 'confirmation.invalid');
  await rejects(() => b.invoke('demo.reset', { confirmed: true, path: '\\\\share\\secret' }), 'invalid_arguments');
  assert.equal((await b.invoke('demo.status')).generation, 0);
});
await check('Scénario arbitraire refusé sans effacer le contexte', async () => {
  const b = sim(), p = await plan(b);
  await rejects(() => select(b, '../live'), 'demo.scenario');
  assert.equal((await execute(b, p)).status, 'simulated');
  assert.equal((await b.invoke('demo.status')).scenarios.length, 8);
});
await check('Reboot fictif confirme uniquement des opérations simulées en attente', async () => {
  const b = sim(); await select(b, 'pendingRestart');
  assert.equal((await b.invoke('demo.status')).pendingRestart, 1);
  await b.invoke('demo.restart', { confirmed: true });
  const r = (await b.invoke('receipts.list')).items[0];
  assert.equal(r.status, 'simulated'); assert.equal(r.mode, 'simulation'); assert.equal(r.restartRequired, false);
  assert.equal((await b.invoke('dashboard.read')).pendingRestart, 0);
});
await check('Déplacement restant fictif : reboot, confirmation et liens parent/enfant', async () => {
  const b = sim(); await select(b, 'partialMove');
  const parent = (await b.invoke('receipts.list')).items[0];
  await rejects(() => b.invoke('demo.prepareMove', { id: parent.id }), 'demo.restartRequired');
  await b.invoke('demo.restart', { confirmed: true });
  const p = await b.invoke('demo.prepareMove', { id: parent.id });
  const stale = await b.invoke('demo.prepareMove', { id: parent.id });
  assert.equal(p.kind, 'move'); assert.equal(p.newName, parent.newName);
  const child = await execute(b, p), reread = await b.invoke('receipts.get', { id: parent.id });
  assert.equal(child.parentReceiptId, parent.id); assert.equal(reread.resolutionChildReceiptId, child.id);
  assert.equal(reread.code, '89'); assert.equal(reread.status, 'pendingRestart');
  assert.equal((await b.invoke('computer.inspect', { computer: parent.newName })).ou, parent.targetOU);
  await rejects(() => execute(b, stale), 'demo.receipt');
});
await check('Refus explicite sans changer la cible, plan consommé', async () => {
  const b = sim(); await select(b, 'denied'); const p = await plan(b), r = await execute(b, p);
  assert.equal(r.status, 'refused'); assert.equal(r.code, '5');
  assert.equal((await b.invoke('computer.inspect', { computer: p.computer })).name, p.computer);
  await rejects(() => execute(b, p), 'plan.consumed');
});
await check('Incertain arrête le lot ; reboot ne permet aucun faux succès ni rejeu', async () => {
  const b = sim(); await select(b, 'uncertain');
  for (const computer of ['S111301PAADM001', 'P111301PAINF001']) {
    const p = await b.invoke('names.preview', { type: 'S', site: 'paris', service: 'ADM', computer });
    await b.invoke('queue.add', { kind: 'rename', computer, previewId: p.previewId });
  }
  const batch = await b.invoke('queue.prepare');
  const result = await b.invoke('queue.execute', { batchId: batch.batchId, confirmed: true });
  assert.equal(result.stopped, true); assert.equal(result.receipts.length, 1); assert.equal((await b.invoke('queue.list')).count, 1);
  await b.invoke('demo.restart', { confirmed: true });
  assert.equal((await b.invoke('receipts.list')).items[0].status, 'uncertain');
  await rejects(() => plan(b), 'demo.uncertain');
});
await check('Collision avant jonction, nouveau nom uniquement sur nouvel aperçu', async () => {
  const b = sim(); await select(b, 'nameCollision');
  const p = await b.invoke('names.preview', { type: 'P', site: 'paris', service: 'INF' });
  await rejects(() => b.invoke('operation.prepare', { kind: 'join', previewId: p.previewId }), 'name.taken');
  const after = await b.invoke('names.preview', { type: 'P', site: 'paris', service: 'INF' });
  assert.notEqual(p.name, after.name); assert.equal((await b.invoke('receipts.list')).items.length, 0);
});
await check('Panne annuaire explicite, compteurs inconnus et commandes démo toujours utilisables', async () => {
  const b = sim(); await select(b, 'directoryOffline');
  await rejects(() => b.invoke('directory.sites'), 'directory.unavailable');
  await rejects(() => b.invoke('names.preview', { type: 'P', site: 'paris', service: 'INF' }), 'directory.unavailable');
  assert.equal((await b.invoke('dashboard.read')).computers, null);
  await b.invoke('demo.reset', { confirmed: true }); assert.equal((await b.invoke('directory.sites')).items.length, 2);
});
await check('Maintenance réelle rejetée avant tout accès fichier, UNC ou HTTP', async () => {
  const b = sim();
  for (const op of ['configuration.status', 'configuration.settings', 'configuration.export', 'configuration.previewImport', 'configuration.previewSettings',
    'configuration.applyImport', 'configuration.decideDistribution', 'configuration.setDefault', 'references.preview', 'references.apply',
    'updates.status', 'updates.windows', 'updates.inspect', 'updates.prepare', 'updates.install', 'updates.rollback', 'updates.recover', 'host.reconnect',
    'coordination.status', 'coordination.inspect', 'coordination.prepare', 'coordination.apply',
    'reservations.list', 'reservations.inspect', 'reservations.prepare', 'reservations.execute',
    'join.precreated.preview', 'receipts.prepareAcknowledgement', 'receipts.acknowledge', 'receipts.prepareRestart', 'receipts.restart',
    'attributes.inspect', 'attributes.prepare', 'attributes.apply', 'attributes.observe',
    'offlineJoin.open', 'offlineJoin.list', 'offlineJoin.import', 'offlineJoin.prepare', 'offlineJoin.apply', 'offlineJoin.observe'])
    await rejects(() => b.invoke(op, { path: '\\\\server\\private', source: 'https://example.invalid', confirmed: true }), 'demo.isolated');
  await rejects(() => b.invoke('demo.prepareMove', { id: 'real-receipt' }), 'demo.receipt');
});
await check('La remise à zéro d’une fenêtre ne modifie pas une autre', async () => {
  const a = sim(), b = sim();
  await select(a, 'pendingRestart'); await select(b, 'partialMove');
  const receipt = (await b.invoke('receipts.list')).items[0];
  await a.invoke('demo.reset', { confirmed: true });
  assert.equal((await b.invoke('receipts.get', { id: receipt.id })).id, receipt.id);
  assert.equal((await b.invoke('demo.status')).scenario, 'partialMove');
});
console.log(`${count}/${count} contrôles de démonstration réussis (JavaScript, sans qualification Windows).`);
