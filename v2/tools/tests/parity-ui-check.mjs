// Actual page modules and shell in Chromium; all native APIs are declared memory fixtures.
// Static HTTP serves only this repository's web assets on loopback. No AD, SMB or Windows operation exists here.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, extname, isAbsolute, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const web = resolve(dirname(fileURLToPath(import.meta.url)), '../../web');
const moduleName = process.env.PESTO_PLAYWRIGHT_MODULE || 'playwright';
const { chromium } = await import(isAbsolute(moduleName) ? pathToFileURL(moduleName).href : moduleName);
const executablePath = process.env.PESTO_CHROMIUM_PATH || ['/usr/bin/google-chrome', '/usr/bin/chromium'].find(existsSync);
assert(executablePath && existsSync(executablePath), 'Chromium local requis.');
const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, 'http://localhost').pathname;
    if (path === '/fixture') {
      response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      response.end('<!doctype html><html lang="fr" data-theme="light" data-motion="reduced"><head><meta charset="utf-8">'
        + ['tokens', 'base', 'layout', 'motion', 'components', 'shell', 'kit'].map(n => `<link rel="stylesheet" href="/css/${n}.css">`).join('')
        + '</head><body><main></main><div id="announcer" aria-live="polite"></div><div class="toasts"></div></body></html>'); return;
    }
    if (path === '/favicon.ico') { response.writeHead(204); response.end(); return; }
    const file = resolve(web, '.' + path); assert(file.startsWith(web + sep));
    response.writeHead(200, { 'Content-Type': { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
      '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.woff2': 'font/woff2' }[extname(file)] || 'application/octet-stream' });
    response.end(await readFile(file));
  } catch { response.writeHead(404); response.end(); }
});
await new Promise(done => server.listen(0, '127.0.0.1', done));
const origin = 'http://127.0.0.1:' + server.address().port;
const filter = process.argv[2] ? new RegExp(process.argv[2], 'i') : null;
const errors = [], results = [];
let browser;
async function check(label, run) {
  if (filter && !filter.test(label)) return;
  try { await run(); results.push({ label, success: true }); console.log('OK ' + label); }
  catch (error) { results.push({ label, success: false, error: error.message }); console.error('FAIL ' + label + ': ' + error.message); }
}
try {
  browser = await chromium.launch({ headless: true, executablePath });
  async function freshPage() {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1120 } }); page.setDefaultTimeout(5000);
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/*', async route => {
      if (route.request().url().startsWith(origin + '/')) await route.continue();
      else { errors.push('External request: ' + route.request().url()); await route.abort(); }
    });
    return page;
  }
  async function pageFor(kind, options = {}) {
    const page = await freshPage();
    try {
      await page.goto(origin + '/fixture');
      await page.evaluate(async ({ kind, options }) => {
        const computer = 'P111301PAINF009', localName = 'LOCAL-CANARY', domain = 'example.local', dc = 'dc01.example.local';
        const ou = 'OU=Paris,OU=Postes,DC=example,DC=local', computerGuid = '11111111-1111-1111-1111-111111111111';
        const ouGuid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', managerGuid = '22222222-2222-2222-2222-222222222222';
        const managerDn = 'CN=Responsable,OU=Utilisateurs,DC=example,DC=local';
        const now = new Date().toISOString(), future = '2099-01-01T00:00:00Z';
        const f = window.fixture = { calls: [], releases: {}, mode: kind === 'offline' ? 'offline' : 'live', readOnly: false,
          domain, localName, serial: 0, ...options };
        const original = f.inspection = { inspectionId: 'attributes-inspection-fixture', mode: 'live', complete: true,
          computer, computerGuid, distinguishedName: `CN=${computer},${ou}`, domain, dc, ou, ouGuid,
          values: { description: '  Description initiale  ', location: 'Bureau 12', managedBy: '' },
          managedByReferenceGuid: null, observedAt: now, collectedAt: now, expiresAt: future, ...options.inspection };
        const item = { id: 'a'.repeat(64), state: options.itemState || 'Imported', computer: localName, domain,
          expectedAdGuid: computerGuid, targetOU: ou, identityDeclared: true, expiresAt: future, replayAllowed: false,
          receiptId: options.itemState && options.itemState !== 'Imported' ? 'receipt-offline-fixture' : null,
          canPrepare: !options.itemState || options.itemState === 'Imported', canObserve: !!options.itemState && options.itemState !== 'Imported',
          message: 'Références déclarées, aucune présence AD supposée.', ...options.item };
        f.items = options.emptyItems ? [] : [item];
        f.queue = Array.from({ length: 3 }, (_, i) => ({ id: 'q-' + (i + 1), planId: 'plan-' + (i + 1), kind: 'rename',
          computer: 'PC-0' + (i + 1), newName: 'NEW-0' + (i + 1), targetOU: ou, mode: 'live', status: 'ready',
          expiresAt: future, entraLeaveRequired: false, entraState: 'adOnly' }));
        if (kind === 'history') {
          f.requested = { description: '  Valeur historique exacte  ', managedBy: managerDn };
          f.changes = Object.entries(f.requested).map(([attribute, after]) => ({ attribute,
            before: original.values[attribute], after, referenceGuid: attribute === 'managedBy' ? managerGuid : null }));
        }
        const session = () => ({ mode: f.mode, readOnly: f.readOnly, localOnly: kind === 'offline', computer: f.localName,
          domain: f.domain, dc, account: 'EXAMPLE\\fixture' });
        const attributeReceipt = status => ({ id: 'receipt-attributes-fixture', kind: 'attributes', computer, newName: '',
          targetOU: ou, mode: 'live', status, code: status === 'succeeded' ? '30' : status === 'refused' ? '96' : '97',
          restartRequired: false, message: 'Reçu de fixture mémoire', time: now, computerGuid, domain, dc,
          attributeChanges: structuredClone(f.changes || []) });
        const observedAttributes = () => ({ ...original, values: { ...original.values, ...f.requested },
          managedByReferenceGuid: f.requested?.managedBy ? managerGuid : null,
          changes: (f.changes || []).map(c => ({ attribute: c.attribute, expected: c.after, observed: c.after, matches: true })) });
        const offlineReceipt = (status = 'pendingRestart') => ({ id: 'receipt-offline-fixture', kind: 'offlineJoin', computer: localName,
          newName: localName, targetOU: ou, mode: 'live', status, code: status === 'succeeded' ? 30 : status === 'pendingRestart' ? 10 : 97,
          restartRequired: status === 'pendingRestart', message: 'Redémarrage puis observation explicite nécessaires.', utc: now });
        const call = async (op, args = {}) => {
          f.calls.push({ op, args: structuredClone(args) });
          if (op === f.hold) await new Promise(resolve => { f.releases[op] = resolve; });
          if (op === 'attributes.inspect') return structuredClone(original);
          if (op === 'attributes.prepare') {
            f.requested = structuredClone(args.values);
            f.changes = Object.entries(args.values).filter(([key, value]) => value !== original.values[key]).map(([attribute, after]) => ({
              attribute, before: original.values[attribute], after: f.canonicalManager && attribute === 'managedBy' ? managerDn : after,
              referenceGuid: attribute === 'managedBy' && after ? managerGuid : null }));
            const plan = { planId: 'attributes-plan-fixture', kind: 'attributes', mode: 'live', computer, computerGuid, domain, dc,
              sourceOU: ou, targetOU: ou, confirmationName: computer, expiresAt: future, changes: structuredClone(f.changes), warnings: [], ...f.plan };
            if (f.planFault === 'before') plan.changes[0].before = 'Valeur étrangère';
            if (f.planFault === 'after') plan.changes[0].after = String(plan.changes[0].after).trim();
            return plan;
          }
          if (op === 'attributes.apply') {
            const status = f.applyStatus || 'succeeded';
            return { receipt: { ...attributeReceipt(status), ...f.receipt }, changes: structuredClone(f.changes), replayAllowed: false,
              observation: f.applyObservation === null ? null : { ...observedAttributes(), ...f.applyObservation } };
          }
          if (op === 'attributes.observe') return { receipt: { ...attributeReceipt(f.observeStatus || 'succeeded'), ...f.observeReceipt },
            verified: f.observeVerified ?? true, reason: 'Observation fixture incomplète : reçu conservé.', targetReadOnly: true, replayAllowed: false,
            observation: f.observation === null ? null : { ...observedAttributes(), ...f.observation } };
          if (op === 'receipts.list') return { items: [{ ...attributeReceipt('uncertain'), ...f.historyReceipt }], persistent: 1 };
          if (op === 'reservations.list') return { items: [] };
          if (op === 'offlineJoin.list') return { available: f.available !== false, reason: null,
            local: { computer: f.localName, activeName: f.localName, configuredName: f.localName, machineId: ouGuid,
              domain: 'WORKGROUP', partOfDomain: false, bootUtc: now, administrator: true }, items: structuredClone(f.items) };
          if (op === 'offlineJoin.import') {
            if (f.cancelFile) return { status: 'cancelled' };
            f.items = [item]; return { status: 'imported', item: structuredClone(item), message: 'Blob importé sans application.' };
          }
          if (op === 'offlineJoin.prepare') return { planId: 'offline-plan-fixture', id: item.id, kind: 'offlineJoin', mode: 'offline',
            identityDeclared: true, requiresConfirmation: true, computer: localName, newName: localName, confirmationName: localName,
            domain, expectedAdGuid: computerGuid, targetOU: ou, expiresAt: future, warnings: ['Un redémarrage manuel puis une observation restent requis.'], ...f.plan };
          if (op === 'offlineJoin.apply') {
            const next = { ...item, state: 'PendingRestart', canPrepare: false, canObserve: true, receiptId: 'receipt-offline-fixture' };
            f.items = [next]; return { item: { ...next, ...f.resultItem }, receipt: { ...offlineReceipt(), ...f.receipt }, message: 'Jonction acceptée, résultat après redémarrage non encore vérifié.' };
          }
          if (op === 'offlineJoin.observe') {
            const next = { ...item, state: 'Verified', identityDeclared: false, canPrepare: false, canObserve: true, receiptId: 'receipt-offline-fixture' };
            f.items = [next]; return { item: { ...next, ...f.resultItem }, receipt: { ...offlineReceipt('succeeded'), ...f.observeReceipt }, message: 'Preuves de fixture observées explicitement.' };
          }
          if (op === 'queue.list') return { items: structuredClone(f.queue), count: f.queue.length };
          if (op === 'queue.prepare') {
            f.batch = { batchId: 'batch-fixture-' + (++f.serial), pilot: args.pilot, remainingCount: args.pilot ? f.queue.length - 1 : 0,
              items: structuredClone(args.pilot ? f.queue.slice(0, 1) : f.queue), expiresAt: future, ...f.batchPatch };
            return structuredClone(f.batch);
          }
          if (op === 'queue.execute') {
            const done = f.queue.splice(0, f.batch.items.length);
            return { receipts: done.map((p, i) => ({ ...p, id: 'receipt-queue-' + i, status: 'succeeded', code: '30', restartRequired: false })), stopped: false };
          }
          throw new Error('API non déclarée de la fixture : ' + op);
        };
        let leaveGuard = null;
        const ctx = { session, call, params: { computer }, capability: () => ({ enabled: !f.readOnly && f.enabled !== false, reason: 'Fixture consultation.' }),
          setScreenCommands() {}, refreshSession: async () => {}, guardLeave: fn => { leaveGuard = fn; return () => { leaveGuard = null; }; } };
        const module = await import('/js/pages/' + { attributes: 'attributs', history: 'interventions', offline: 'offline-join', pilot: 'plusieurspostes' }[kind] + '.js');
        const main = document.querySelector('main'); const stop = module.render(main, ctx);
        window.stopPage = () => { stop(); main.innerHTML = '<p>Écran quitté</p>'; location.hash = '#gone'; };
        window.requestLeave = () => { f.leaveResult = null; Promise.resolve(leaveGuard ? leaveGuard() : true).then(allowed => {
          f.leaveResult = allowed; if (allowed) window.stopPage();
        }); };
      }, { kind, options });
      if (kind === 'attributes') await page.locator('[name="description"]').waitFor();
      if (kind === 'history') await page.locator('[data-zone="list"] [data-receipt]').waitFor();
      if (kind === 'offline') await page.locator('[data-local] h3').waitFor();
      if (kind === 'pilot') await page.waitForFunction(() => !document.querySelector('[data-act="prepare"]').disabled);
      return page;
    } catch (error) { await page.close(); throw error; }
  }
  const calls = (page, op) => page.evaluate(op => window.fixture.calls.filter(c => !op || c.op === op), op);
  const dialog = page => page.locator('.k-dlg-layer:not(.leaving) .k-dlg');
  const scenario = (label, kind, options, test) => check(label, async () => { const page = await pageFor(kind, options); try { await test(page); } finally { await page.close(); } });
  const typeTarget = async page => {
    const d = dialog(page); await d.waitFor();
    const input = d.locator('.k-cw-typed input');
    if (await input.count()) await input.fill(await d.locator('.k-cw-target b').innerText());
    return d;
  };
  const confirm = async page => { const d = await typeTarget(page); await d.locator('[data-id="confirm"]').click(); };
  const chooseAttributes = async (page, values = { description: '  Texte exact  ' }) => {
    for (const [key, value] of Object.entries(values)) { await page.locator(`[name="edit-${key}"]`).check(); await page.locator(`[name="${key}"]`).fill(value); }
    await page.locator('[data-prepare]').click();
  };
  const applyAttributes = async (page, values) => { await chooseAttributes(page, values); await page.locator('[data-apply]').click(); await confirm(page); };
  const prepareOffline = async page => { await page.locator('[data-prepare]').click(); await page.locator('[data-plan] [data-apply]').waitFor(); };
  const fillImport = async page => {
    await page.locator('[name="objectGuid"]').fill('11111111-1111-1111-1111-111111111111');
    await page.locator('[name="targetOU"]').fill('OU=Paris,OU=Postes,DC=example,DC=local');
    await page.locator('[data-import]').click();
  };

  await scenario('Attributs : ouverture avec une seule inspection et aucune préparation implicite', 'attributes', {}, async page => {
    assert.deepEqual((await calls(page)).map(c => c.op), ['attributes.inspect']);
    assert.equal(await page.locator('[data-prepare]').isDisabled(), true);
    assert.equal(await page.locator('[name="description"]').inputValue(), '  Description initiale  ');
  });
  await scenario('Brouillon attributs : annuler Relire conserve les valeurs et le diff préparé', 'attributes', {}, async page => {
    await chooseAttributes(page, { description: 'Texte à conserver' }); await page.locator('[data-apply]').waitFor();
    await page.locator('[data-read]').click(); const d = dialog(page); await d.waitFor();
    await d.getByRole('button', { name: 'Annuler', exact: true }).click();
    assert.equal(await page.locator('[name="description"]').inputValue(), 'Texte à conserver');
    assert.equal(await page.locator('[name="edit-description"]').isChecked(), true);
    assert.equal(await page.locator('[data-apply]').count(), 1);
    assert.equal((await calls(page, 'attributes.inspect')).length, 1);
    assert.equal((await calls(page, 'attributes.apply')).length, 0);
  });
  await scenario('Brouillon attributs : Relire confirmé remet les valeurs lues sans envoyer le diff', 'attributes', {}, async page => {
    await page.locator('[name="description"]').fill('Texte non appliqué');
    await page.locator('[data-read]').click(); const d = dialog(page); await d.waitFor(); await d.locator('[data-id="ok"]').click();
    await page.waitForFunction(() => document.querySelector('[name="description"]')?.value === '  Description initiale  ');
    assert.equal((await calls(page, 'attributes.inspect')).length, 2);
    assert.equal((await calls(page, 'attributes.prepare')).length, 0);
    assert.equal((await calls(page, 'attributes.apply')).length, 0);
  });
  await scenario('Brouillon attributs : navigation annulée conserve les champs puis accord explicite les abandonne', 'attributes', {}, async page => {
    await page.locator('[name="location"]').fill('Nouveau bureau');
    await page.evaluate(() => window.requestLeave()); const d = dialog(page); await d.waitFor();
    await d.getByRole('button', { name: 'Annuler', exact: true }).click();
    await page.waitForFunction(() => window.fixture.leaveResult === false);
    assert.equal(await page.locator('[name="location"]').inputValue(), 'Nouveau bureau');
    await page.evaluate(() => window.requestLeave()); await d.waitFor(); await d.locator('[data-id="ok"]').click();
    await page.waitForFunction(() => window.fixture.leaveResult === true);
    assert.equal(await page.locator('[data-values]').count(), 0);
    assert.equal((await calls(page, 'attributes.apply')).length, 0);
  });
  await scenario('Attributs : seuls champs cochés, espaces exacts et chaîne vide explicite', 'attributes', {}, async page => {
    await page.locator('[name="managedBy"]').fill('DN NON COCHÉ');
    await chooseAttributes(page, { description: '  Texte exact  ', location: '' });
    await page.locator('[data-apply]').waitFor();
    assert.deepEqual((await calls(page, 'attributes.prepare'))[0].args, { inspectionId: 'attributes-inspection-fixture', values: { description: '  Texte exact  ', location: '' } });
    assert.match(await page.locator('[data-plan]').innerText(), /Valeur vide — effacement/);
    assert.equal((await calls(page, 'attributes.apply')).length, 0);
    await page.locator('[data-apply]').click(); await confirm(page);
    await page.locator('[data-receipt="receipt-attributes-fixture"]').waitFor();
    assert.deepEqual((await calls(page, 'attributes.apply'))[0].args, { planId: 'attributes-plan-fixture', confirmationName: 'P111301PAINF009' });
    assert.equal(await page.locator('[data-receipt]').getAttribute('data-status'), 'succeeded');
  });
  for (const [name, options] of [['GUID', { plan: { computerGuid: '33333333-3333-3333-3333-333333333333' } }],
    ['avant', { planFault: 'before' }], ['espaces altérés', { planFault: 'after' }], ['expiration', { plan: { expiresAt: '2000-01-01T00:00:00Z' } }]])
    await scenario('Attributs : plan divergent refusé — ' + name, 'attributes', options, async page => {
      await chooseAttributes(page); await page.locator('[data-plan] [role="alert"]').waitFor();
      assert.equal(await page.locator('[data-apply]').count(), 0); assert.equal((await calls(page, 'attributes.apply')).length, 0);
    });
  await scenario('Attributs : annulation après préparation sans écriture', 'attributes', {}, async page => {
    await chooseAttributes(page); await page.locator('[data-apply]').click(); const d = await typeTarget(page);
    await d.getByRole('button', { name: 'Annuler', exact: true }).click();
    assert.equal((await calls(page, 'attributes.apply')).length, 0);
  });
  for (const change of ['valeur', 'lecture seule', 'domaine'])
    await scenario('Attributs : contexte modifié pendant la confirmation — ' + change, 'attributes', {}, async page => {
      await chooseAttributes(page); await page.locator('[data-apply]').click(); const d = await typeTarget(page);
      await page.evaluate(change => {
        if (change === 'valeur') { const el = document.querySelector('[name="description"]'); el.value = 'Autre contexte'; el.dispatchEvent(new Event('input', { bubbles: true })); }
        else if (change === 'lecture seule') window.fixture.readOnly = true;
        else window.fixture.domain = 'foreign.local';
      }, change);
      await d.locator('[data-id="confirm"]').click();
      await page.waitForFunction(() => !!document.querySelector('[data-plan] [role="alert"], [data-receipt]'));
      assert.equal((await calls(page, 'attributes.apply')).length, 0, 'Une confirmation ancienne ne doit produire aucun appel apply');
    });
  for (const [name, options] of [['preuve absente', { applyObservation: null }], ['code incorrect', { receipt: { code: '0' } }],
    ['GUID observé étranger', { applyObservation: { computerGuid: '33333333-3333-3333-3333-333333333333' } }], ['diff incomplet', { applyObservation: { changes: [] } }]])
    await scenario('Attributs : réponse de succès non prouvée sans vert — ' + name, 'attributes', options, async page => {
      await applyAttributes(page); await page.locator('[data-plan] [role="alert"]').waitFor();
      assert.equal(await page.locator('[data-status="succeeded"]').count(), 0); assert.equal((await calls(page, 'attributes.apply')).length, 1);
    });
  await scenario('Attributs : managedBy exige aussi le GUID de référence observé après écriture', 'attributes',
    { applyObservation: { managedByReferenceGuid: '33333333-3333-3333-3333-333333333333' } }, async page => {
      await applyAttributes(page, { managedBy: 'CN=Responsable,OU=Utilisateurs,DC=example,DC=local' });
      await page.waitForFunction(() => !!document.querySelector('[data-plan] [role="alert"], [data-receipt]'));
      assert.equal(await page.locator('[data-status="succeeded"]').count(), 0, 'Un responsable remplacé au même DN ne peut pas être vert');
    });
  await scenario('Attributs : DN managedBy canonique relu visible dans le diff avant confirmation', 'attributes', { canonicalManager: true }, async page => {
    await chooseAttributes(page, { managedBy: 'cn=responsable,ou=utilisateurs,dc=example,dc=local' });
    await page.waitForFunction(() => !!document.querySelector('[data-plan] [role="alert"], [data-apply]'));
    assert.equal(await page.locator('[data-apply]').count(), 1, 'Le moteur renvoie le DN canonique réellement observé avec son GUID');
    assert.match(await page.locator('[data-plan]').innerText(), /CN=Responsable,OU=Utilisateurs,DC=example,DC=local/);
    assert.equal((await calls(page, 'attributes.apply')).length, 0);
  });
  await scenario('Attributs : uncertain ne propose que la lecture, observe explicite sans rejeu', 'attributes', { applyStatus: 'uncertain' }, async page => {
    await applyAttributes(page); const card = page.locator('[data-receipt="receipt-attributes-fixture"]'); await card.waitFor();
    assert.equal(await card.getAttribute('data-status'), 'uncertain'); assert.equal((await calls(page, 'attributes.observe')).length, 0);
    assert.equal(await page.locator('[data-apply]').count(), 0); await page.locator('[data-observe]').click();
    await page.locator('[data-status="succeeded"]').waitFor();
    assert.deepEqual((await calls(page, 'attributes.observe'))[0].args, { id: 'receipt-attributes-fixture' });
    assert.equal((await calls(page, 'attributes.apply')).length, 1);
  });
  for (const [name, options] of [['preuve absente', { observation: null }], ['vérifié contradictoire', { observation: null, observeStatus: 'uncertain', observeVerified: true }]])
    await scenario('Attributs : observation incomplète ne certifie rien — ' + name, 'attributes', { applyStatus: 'uncertain', ...options }, async page => {
      await applyAttributes(page); await page.locator('[data-observe]').click(); await page.waitForFunction(() => document.querySelector('[data-observation]')?.textContent);
      assert.equal(await page.locator('[data-status="succeeded"]').count(), 0);
      assert.doesNotMatch(await page.locator('[data-observation]').innerText(), /Valeurs confirmées par observation et preuve durable/);
      assert.equal((await calls(page, 'attributes.apply')).length, 1);
    });
  await scenario('Attributs : navigation pendant la préparation ne crée pas un contrôle tardif', 'attributes', { hold: 'attributes.prepare' }, async page => {
    await chooseAttributes(page); await page.waitForFunction(() => !!window.fixture.releases['attributes.prepare']);
    await page.evaluate(() => { window.stopPage(); window.fixture.releases['attributes.prepare'](); });
    await page.evaluate(() => new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done))));
    assert.equal(await page.locator('[data-apply], .k-dlg').count(), 0); assert.equal((await calls(page, 'attributes.apply')).length, 0);
  });

  await scenario('Historique attributs : listes locales puis observation explicite liée au reçu et au diff complet', 'history', {}, async page => {
    assert.deepEqual((await calls(page)).map(c => c.op).sort(), ['receipts.list', 'reservations.list']);
    const card = page.locator('[data-zone="list"] [data-receipt]');
    assert.equal(await card.getAttribute('data-status'), 'uncertain');
    assert.match(await card.locator('.attribute-diff').innerText(), /Valeur historique exacte/);
    await card.locator('[data-act="verify"]').click();
    await page.locator('[data-zone="list"] [data-status="succeeded"]').waitFor();
    assert.deepEqual((await calls(page, 'attributes.observe'))[0].args, { id: 'receipt-attributes-fixture' });
    assert.equal((await calls(page)).filter(c => ['attributes.apply', 'attributes.prepare', 'receipts.reconcile'].includes(c.op)).length, 0);
    assert.match(await page.locator('[data-verification]').innerText(), /Aucune modification AD rejouée/);
  });
  for (const [name, observation] of [
    ['GUID', { computerGuid: '33333333-3333-3333-3333-333333333333' }],
    ['domaine', { domain: 'foreign.local' }], ['contrôleur', { dc: 'dc02.example.local' }],
    ['OU', { ou: 'OU=Autre,OU=Postes,DC=example,DC=local' }],
    ['diff vide', { changes: [] }],
    ['diff partiel', { changes: [{ attribute: 'description', expected: '  Valeur historique exacte  ', observed: '  Valeur historique exacte  ', matches: true }] }],
    ['GUID du responsable', { managedByReferenceGuid: '33333333-3333-3333-3333-333333333333' }],
  ]) await scenario('Historique attributs : observation divergente conserve le reçu incertain — ' + name, 'history', { observation }, async page => {
    await page.locator('[data-act="verify"]').click(); await page.locator('[data-verification][role="alert"]').waitFor();
    assert.equal(await page.locator('[data-status="succeeded"]').count(), 0);
    assert.equal(await page.locator('[data-zone="list"] [data-receipt]').getAttribute('data-status'), 'uncertain');
    assert.equal((await calls(page, 'attributes.observe')).length, 1);
  });
  await scenario('Historique attributs : nouveau reçu avec diff altéré ne remplace pas le résultat initial', 'history', {}, async page => {
    await page.evaluate(() => { window.fixture.observeReceipt = { attributeChanges: structuredClone(window.fixture.changes) };
      window.fixture.observeReceipt.attributeChanges[0].before = 'Autre valeur initiale'; });
    await page.locator('[data-act="verify"]').click(); await page.locator('[data-verification][role="alert"]').waitFor();
    assert.equal(await page.locator('[data-status="succeeded"]').count(), 0);
    assert.equal(await page.locator('[data-zone="list"] [data-receipt]').getAttribute('data-status'), 'uncertain');
  });
  await scenario('Historique attributs V1 : lecture du diff sans vérification V2 promise ni envoi implicite', 'history',
    { historyReceipt: { mode: 'V1 · registre local GP (relu, lecture seule)' } }, async page => {
      assert.equal(await page.locator('[data-act="verify"]').count(), 0);
      assert.match(await page.locator('[data-zone="list"]').innerText(), /Ce reçu attributs V1 reste consultable/);
      assert.equal((await calls(page, 'attributes.observe')).length, 0);
    });

  await scenario('ODJ : démarrage local seulement et aucune observation AD implicite', 'offline', { itemState: 'PendingRestart' }, async page => {
    assert.deepEqual((await calls(page)).map(c => c.op), ['offlineJoin.list']);
    assert.match(await page.locator('[data-items]').innerText(), /GUID AD déclaré, non vérifié/);
    assert.equal((await calls(page, 'offlineJoin.observe')).length, 0);
    assert.equal(await page.locator('[data-prepare]').count(), 0);
  });
  await scenario('ODJ : import déclaré confirmé, aucun chemin ni blob dans les arguments web', 'offline', { emptyItems: true }, async page => {
    await fillImport(page); const d = await typeTarget(page); assert.match(await d.innerText(), /n’applique aucune jonction/);
    assert.doesNotMatch(await d.innerText(), /Écriture dans l.annuaire/i);
    assert.equal((await calls(page, 'offlineJoin.import')).length, 0); await d.locator('[data-id="confirm"]').click();
    await page.waitForFunction(() => document.querySelector('[data-import-result]')?.textContent.includes('Blob importé'));
    assert.deepEqual((await calls(page, 'offlineJoin.import'))[0].args, { objectGuid: '11111111-1111-1111-1111-111111111111', targetOU: 'OU=Paris,OU=Postes,DC=example,DC=local', confirmed: true });
    assert.equal((await calls(page, 'offlineJoin.prepare')).length, 0); assert.equal((await calls(page, 'offlineJoin.apply')).length, 0);
  });
  await scenario('ODJ : annulation de confirmation sans ouverture du sélecteur natif', 'offline', { emptyItems: true }, async page => {
    await fillImport(page); await dialog(page).getByRole('button', { name: 'Annuler', exact: true }).click();
    assert.equal((await calls(page, 'offlineJoin.import')).length, 0);
  });
  await scenario('ODJ : sélecteur natif annulé sans préparation ni application', 'offline', { emptyItems: true, cancelFile: true }, async page => {
    await fillImport(page); await confirm(page);
    await page.waitForFunction(() => document.querySelector('[data-import-result]')?.textContent.includes('Sélection annulée'));
    assert.equal((await calls(page, 'offlineJoin.import')).length, 1); assert.equal((await calls(page, 'offlineJoin.prepare')).length, 0);
    assert.equal((await calls(page, 'offlineJoin.apply')).length, 0); assert.equal(await page.locator('[data-item]').count(), 0);
  });
  await scenario('ODJ : préparation puis confirmation du nom actuel, PendingRestart reste sans succès vert', 'offline', {}, async page => {
    await prepareOffline(page); assert.deepEqual((await calls(page, 'offlineJoin.prepare'))[0].args, { id: 'a'.repeat(64) });
    assert.equal((await calls(page, 'offlineJoin.apply')).length, 0); await page.locator('[data-apply]').click(); const d = await typeTarget(page);
    assert.equal(await d.locator('.k-cw-target b').innerText(), 'LOCAL-CANARY'); assert.match(await d.innerText(), /nom actuel de ce PC/i);
    assert.doesNotMatch(await d.innerText(), /Écriture dans l.annuaire/i);
    await d.locator('[data-id="confirm"]').click(); await page.locator('[data-status="pendingRestart"]').waitFor();
    assert.deepEqual((await calls(page, 'offlineJoin.apply'))[0].args, { planId: 'offline-plan-fixture', confirmationName: 'LOCAL-CANARY', confirmed: true });
    assert.equal(await page.locator('[data-status="succeeded"]').count(), 0); assert.equal((await calls(page, 'offlineJoin.observe')).length, 0);
    await page.locator('[data-observe]').click(); await page.locator('[data-status="succeeded"]').waitFor();
    assert.deepEqual((await calls(page, 'offlineJoin.observe'))[0].args, { id: 'a'.repeat(64) }); assert.equal((await calls(page, 'offlineJoin.apply')).length, 1);
  });
  for (const plan of [{ computer: 'FOREIGN' }, { expectedAdGuid: '33333333-3333-3333-3333-333333333333' }, { id: 'b'.repeat(64) }, { expiresAt: '2000-01-01T00:00:00Z' }])
    await scenario('ODJ : plan étranger ou expiré refusé — ' + Object.keys(plan)[0], 'offline', { plan }, async page => {
      await page.locator('[data-prepare]').click(); await page.locator('[data-result] [role="alert"]').waitFor();
      assert.equal(await page.locator('[data-apply]').count(), 0); assert.equal((await calls(page, 'offlineJoin.apply')).length, 0);
    });
  await scenario('ODJ : annulation de l’application conserve l’import sans envoi', 'offline', {}, async page => {
    await prepareOffline(page); await page.locator('[data-apply]').click(); await dialog(page).getByRole('button', { name: 'Annuler', exact: true }).click();
    assert.equal((await calls(page, 'offlineJoin.apply')).length, 0);
  });
  await scenario('ODJ : contexte local relu pendant le dialogue invalide le plan', 'offline', {}, async page => {
    await prepareOffline(page); await page.locator('[data-apply]').click(); const d = await typeTarget(page);
    await page.evaluate(() => { window.fixture.localName = 'CHANGED-PC'; document.querySelector('[data-refresh]').click(); });
    await page.waitForFunction(() => document.querySelector('[data-local] h3')?.textContent.includes('CHANGED-PC'));
    await d.locator('[data-id="confirm"]').click(); await page.locator('[data-result] [role="alert"]').waitFor();
    assert.equal((await calls(page, 'offlineJoin.apply')).length, 0);
  });
  await scenario('ODJ : succès immédiat contradictoire à l’application refusé', 'offline', { receipt: { status: 'succeeded', code: 30, restartRequired: false } }, async page => {
    await prepareOffline(page); await page.locator('[data-apply]').click(); await confirm(page);
    await page.locator('[data-result] [role="alert"]').waitFor(); assert.equal(await page.locator('[data-result] [data-status="succeeded"]').count(), 0);
  });
  await scenario('ODJ : observation contradictoire ne transforme pas une identité déclarée en succès', 'offline',
    { itemState: 'PendingRestart', resultItem: { state: 'Uncertain', identityDeclared: true } }, async page => {
      await page.locator('[data-observe]').click();
      await page.waitForFunction(() => !!document.querySelector('[data-result] [role="alert"], [data-result] [data-receipt]'));
      assert.equal(await page.locator('[data-result] [data-status="succeeded"]').count(), 0, 'Un état item incertain ne prouve aucune jonction vérifiée');
      assert.equal((await calls(page, 'offlineJoin.apply')).length, 0);
    });

  await scenario('Pilote : un seul plan confirmé, les autres lignes restent dans la file', 'pilot', {}, async page => {
    await page.locator('[data-act="pilot"]').check(); await page.locator('[data-act="prepare"]').click(); await page.locator('[data-act="execute"]').click();
    assert.deepEqual((await calls(page, 'queue.prepare'))[0].args, { pilot: true }); const d = await typeTarget(page);
    assert.match(await d.innerText(), /Confirmer le poste pilote/); assert.match(await d.locator('.k-cw-changes').innerText(), /PC-01/);
    assert.doesNotMatch(await d.locator('.k-cw-changes').innerText(), /PC-02|PC-03/); await d.locator('[data-id="confirm"]').click();
    await page.waitForFunction(() => document.querySelector('[data-slot="queue-count"]')?.textContent.startsWith('2 /'));
    assert.deepEqual((await calls(page, 'queue.execute'))[0].args, { batchId: 'batch-fixture-1', confirmed: true });
    assert.deepEqual(await page.evaluate(() => window.fixture.queue.map(p => p.computer)), ['PC-02', 'PC-03']);
  });
  await scenario('Pilote : changer la case invalide le lot déjà préparé', 'pilot', {}, async page => {
    await page.locator('[data-act="pilot"]').check(); await page.locator('[data-act="prepare"]').click(); await page.locator('[data-act="execute"]').waitFor();
    await page.locator('[data-act="pilot"]').uncheck(); assert.equal(await page.locator('[data-act="execute"]').count(), 0);
    assert.equal((await calls(page, 'queue.execute')).length, 0);
    await page.locator('[data-act="prepare"]').click(); await page.locator('[data-act="execute"]').waitFor();
    assert.deepEqual((await calls(page, 'queue.prepare')).map(c => c.args), [{ pilot: true }, { pilot: false }]);
  });
  await scenario('Pilote : changement pendant confirmation sans exécution tardive', 'pilot', {}, async page => {
    await page.locator('[data-act="pilot"]').check(); await page.locator('[data-act="prepare"]').click(); await page.locator('[data-act="execute"]').click(); const d = await typeTarget(page);
    await page.evaluate(() => { const el = document.querySelector('[data-act="pilot"]'); el.checked = false; el.dispatchEvent(new Event('change', { bubbles: true })); });
    await d.locator('[data-id="confirm"]').click(); await page.evaluate(() => new Promise(done => requestAnimationFrame(done)));
    assert.equal((await calls(page, 'queue.execute')).length, 0);
  });
  await scenario('Lot normal : pilot false et toutes les lignes affichées avant confirmation', 'pilot', {}, async page => {
    await page.locator('[data-act="prepare"]').click(); await page.locator('[data-act="execute"]').click(); const d = await typeTarget(page);
    assert.deepEqual((await calls(page, 'queue.prepare'))[0].args, { pilot: false });
    for (const name of ['PC-01', 'PC-02', 'PC-03']) assert.match(await d.locator('.k-cw-changes').innerText(), new RegExp(name));
    await d.getByRole('button', { name: 'Annuler', exact: true }).click(); assert.equal((await calls(page, 'queue.execute')).length, 0);
  });
  await scenario('Pilote : le moteur ne peut pas rendre un lot normal sous une confirmation pilote', 'pilot', { batchPatch: { pilot: false } }, async page => {
    await page.locator('[data-act="pilot"]').check(); await page.locator('[data-act="prepare"]').click();
    await page.locator('[data-zone="batch"] [role="alert"]').waitFor(); assert.equal(await page.locator('[data-act="execute"]').count(), 0);
  });

  await check('Shell ODJ réel : session et liste locales seulement, bannière opération réelle permanente', async () => {
    const page = await freshPage();
    try {
      await page.addInitScript(() => {
        window.shellCalls = []; const listeners = new Set(); window.chrome ||= {};
        localStorage.setItem('pesto.prefs.v1', JSON.stringify({ theme: 'light', motion: 'reduced', bannerCompact: true }));
        window.chrome.webview = {
          addEventListener(type, callback) { if (type === 'message') listeners.add(callback); },
          removeEventListener(type, callback) { if (type === 'message') listeners.delete(callback); },
          postMessage(request) {
            window.shellCalls.push(structuredClone(request)); let data;
            if (request.op === 'session.info') data = { mode: 'offline', localOnly: true, readOnly: false, computer: 'LOCAL-CANARY', domain: 'example.local', dc: null,
              account: 'EXAMPLE\\fixture', version: '2.0-fixture', capabilities: [{ id: 'offlineJoin', enabled: true }], demonstration: false };
            else if (request.op === 'offlineJoin.list') data = { available: true, local: { computer: 'LOCAL-CANARY', activeName: 'LOCAL-CANARY', configuredName: 'LOCAL-CANARY',
              machineId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', domain: 'WORKGROUP', partOfDomain: false, administrator: true, bootUtc: new Date().toISOString() }, items: [] };
            queueMicrotask(() => { const message = data === undefined ? { id: request.id, kind: 'error', error: { code: 'fixture.undeclared', message: 'API étrangère au contexte local.' } }
              : { id: request.id, kind: 'result', data }; listeners.forEach(callback => callback({ data: message })); });
          },
        };
      });
      await page.goto(origin + '/index.html#/offline-join'); await page.waitForFunction(() => document.documentElement.dataset.ready === 'offline-join');
      assert.deepEqual(await page.evaluate(() => window.shellCalls.map(c => c.op)), ['session.info', 'offlineJoin.list']);
      const banner = page.locator('.sim-banner'); assert.equal(await banner.isVisible(), true);
      assert.match(await banner.innerText(), /opération réelle sur ce PC après confirmation/); assert.match(await banner.innerText(), /observation AD explicite/);
      assert.equal(await page.locator('.mode-chip .txt').innerText(), 'Jonction locale réelle');
      assert.equal(await page.locator('.nav-item[href="#/accueil"], .nav-item[href="#/parametres"]').count(), 0);
      assert.equal(await page.locator('.demo-trigger').count(), 0);
      assert.equal(await page.locator('main h1').innerText(), 'Jonction hors ligne');
    } finally { await page.close(); }
  });
  await check('Aucune erreur JS ni requête extérieure au serveur de fixture', async () => assert.deepEqual(errors, []));
} finally { await browser?.close(); await new Promise(done => server.close(done)); }
const failures = results.filter(r => !r.success);
console.log(JSON.stringify({ suite: 'parity-ui', checks: results.length, passed: results.length - failures.length, failed: failures.length,
  memoryOnly: true, nativeEffects: false, failures }, null, 2));
if (!results.length || failures.length) process.exitCode = 1;
