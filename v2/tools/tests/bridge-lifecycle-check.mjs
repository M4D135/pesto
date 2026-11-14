import assert from 'node:assert/strict';
import fs from 'node:fs';
const source = fs.readFileSync(new URL('../../web/js/bridge.js', import.meta.url), 'utf8');
const { createBridge } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
let passed = 0;
const check = async (name, run) => { await run(); passed++; process.stdout.write(`  ok   ${name}\n`); };
function harness() {
  let receiver, now = 0, id = 0;
  const timers = new Map(), sent = [];
  const clock = { setTimeout(fn, delay) { const key = ++id; timers.set(key, { fn, at: now + delay }); return key; }, clearTimeout(key) { timers.delete(key); } };
  const channel = { addEventListener(_type, fn) { receiver = fn; }, removeEventListener() { receiver = null; }, postMessage(message) { sent.push(message); } };
  return { bridge: createBridge({ channel, clock, timeoutMs: 120_000 }), sent,
    tick(ms) { now += ms; for (const [key, timer] of timers) if (timer.at <= now) { timers.delete(key); timer.fn(); } },
    result(data) { receiver({ data: { id: sent.at(-1).id, kind: 'result', data } }); },
    error(code) { receiver({ data: { id: sent.at(-1).id, kind: 'error', error: { code, message: 'Refus natif explicite.' } } }); },
    refuse(message) { receiver({ data: message }); },
  };
}
await check('Une lecture bloquée expire sans bascule vers une simulation', async () => {
  const h = harness(); const pending = h.bridge.call('directory.search', { query: 'CANARY' });
  h.tick(120_001); await assert.rejects(pending, { code: 'bridge.timeout' }); assert.equal(h.sent.length, 1); h.bridge.close();
});
for (const op of ['operation.prepare', 'operation.execute', 'queue.prepare', 'queue.execute', 'reservations.execute', 'coordination.apply',
  'receipts.reconcile', 'receipts.prepareMove', 'receipts.prepareAcknowledgement', 'receipts.acknowledge', 'receipts.prepareRestart', 'receipts.restart', 'updates.prepare', 'updates.inspect', 'configuration.setDefault', 'configuration.previewImport', 'configuration.export', 'references.preview']) {
  await check(`${op} attend le résultat natif au-delà du délai de lecture, sans réenvoi`, async () => {
    const h = harness(); let settled = false;
    const pending = h.bridge.call(op, {}).finally(() => { settled = true; });
    h.tick(3_600_000); await Promise.resolve(); await Promise.resolve();
    assert.equal(settled, false); assert.equal(h.sent.length, 1);
    h.result({ status: 'pendingRestart', code: 20 });
    assert.deepEqual(await pending, { status: 'pendingRestart', code: 20 }); h.bridge.close();
  });
}
await check('Un refus tardif demeure un refus et ne déclenche aucun second envoi', async () => {
  const h = harness(); const pending = h.bridge.call('operation.execute', {});
  h.tick(3_600_000); h.error('operation.uncertain');
  await assert.rejects(pending, { code: 'operation.uncertain' }); assert.equal(h.sent.length, 1); h.bridge.close();
});
await check('La fermeture rejette une mutation encore en attente sans la rejouer', async () => {
  const h = harness(); const pending = h.bridge.call('operation.execute', {});
  h.tick(3_600_000); h.bridge.close();
  await assert.rejects(pending, { code: 'bridge.closed' }); assert.equal(h.sent.length, 1);
});
await check('Un refus corrélé du pont settle l’écran sans attendre le délai de lecture', async () => {
  const h = harness(); const pending = h.bridge.call('directory.search', { query: 'CANARY' });
  assert.equal(h.sent.length, 1);
  h.refuse({ id: h.sent.at(-1).id, kind: 'error', op: 'directory.search',
    error: { code: 'bridge.rejected.backpressure', message: 'Trop d’opérations sont déjà en attente. Aucune opération n’a été lancée.', retryable: true } });
  await assert.rejects(pending, { code: 'bridge.rejected.backpressure', message: 'Trop d’opérations sont déjà en attente. Aucune opération n’a été lancée.',
    retryable: true, operation: 'directory.search' });
  h.tick(120_001); assert.equal(h.sent.length, 1); h.bridge.close();
});
await check('Un refus ordinaire du moteur ne reçoit ni rejouabilité ni opération inventées', async () => {
  const h = harness(); const pending = h.bridge.call('directory.search', { query: 'CANARY' });
  h.refuse({ id: h.sent.at(-1).id, kind: 'error', error: { code: 'engine.denied', message: 'Refusé par la politique hôte.' } });
  await assert.rejects(pending, { code: 'engine.denied' });
  const error = await pending.then(() => null, (reason) => reason);
  assert.equal(error.retryable, undefined); assert.equal(error.operation, undefined);
  h.bridge.close();
});
await check('Un refus sans identifiant correspondant ne settle aucune demande et ne masque pas le délai', async () => {
  const h = harness(); const pending = h.bridge.call('directory.search', { query: 'CANARY' });
  h.refuse({ id: 'p999', kind: 'error', error: { code: 'bridge.rejected.size', message: 'Refus étranger.' } });
  h.refuse({ id: h.sent.at(-1).id, kind: 'progress' });
  await Promise.resolve(); await Promise.resolve();
  h.tick(120_001); await assert.rejects(pending, { code: 'bridge.timeout' }); assert.equal(h.sent.length, 1); h.bridge.close();
});
process.stdout.write(`\n${passed}/${passed} contrôles de cycle du pont réussis, horloge et canal explicitement factices.\n`);
