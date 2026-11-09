// Real UI modules in Chromium with a declared memory-only backend. Never executes AD, SMB or Windows.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, extname, isAbsolute, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
// « Un poste » targets this PC by default: searching another computer starts with that explicit choice.
const pickRemote = async (page) => { const remote = page.locator('[data-form="target"] input[value="remote"]'); if (await remote.count()) await remote.check(); };
const web = resolve(dirname(fileURLToPath(import.meta.url)), '../../web');
const moduleName = process.env.PESTO_PLAYWRIGHT_MODULE || 'playwright';
const { chromium } = await import(isAbsolute(moduleName) ? pathToFileURL(moduleName).href : moduleName);
const executablePath = process.env.PESTO_CHROMIUM_PATH || ['/usr/bin/google-chrome', '/usr/bin/chromium'].find(existsSync);
assert(executablePath && existsSync(executablePath), 'Chromium local requis.');
const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, 'http://localhost').pathname;
    if (path === '/fixture') {
      response.writeHead(200, { 'Content-Type': 'text/html' });
      response.end('<!doctype html><html lang="fr" data-theme="light" data-motion="reduced"><head>'
        + ['tokens', 'base', 'layout', 'motion', 'components', 'shell', 'kit'].map(n => '<link rel="stylesheet" href="/css/' + n + '.css">').join('')
        + '</head><body><main></main><div id="announcer" aria-live="polite"></div></body></html>'); return;
    }
    if (path === '/favicon.ico') { response.writeHead(204); response.end(); return; }
    const file = resolve(web, '.' + path); assert(file.startsWith(web + sep));
    response.writeHead(200, { 'Content-Type': { '.js': 'text/javascript', '.css': 'text/css' }[extname(file)] || 'application/octet-stream' });
    response.end(await readFile(file));
  } catch { response.writeHead(404); response.end(); }
});
await new Promise(done => server.listen(0, '127.0.0.1', done));
const origin = 'http://127.0.0.1:' + server.address().port;
let browser, checks = 0, failures = 0;
const errors = [], filter = process.argv[2] ? new RegExp(process.argv[2], 'i') : null;
async function check(label, run) {
  if (filter && !filter.test(label)) return;
  checks++;
  try { await run(); console.log('OK ' + label); }
  catch (error) { failures++; console.error('FAIL ' + label + ': ' + error.message); }
}
try {
  browser = await chromium.launch({ headless: true, executablePath });
  async function pageFor(kind, options = {}) {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1050 } }); page.setDefaultTimeout(5000);
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/*', async route => {
      if (route.request().url().startsWith(origin + '/')) await route.continue();
      else { errors.push('External request: ' + route.request().url()); await route.abort(); }
    });
    await page.goto(origin + '/fixture');
    await page.evaluate(async ({ kind, options }) => {
      const ou = 'OU=Paris,OU=Postes,DC=example,DC=local', name = 'P111301PAINF123';
      const base = { id: 'receipt-parent', kind: 'rename', computer: 'PC-OLD', newName: 'PC-NEW', targetOU: ou,
        mode: 'live · fixture', status: 'pendingRestart', code: '20', restartRequired: true, readable: true,
        acknowledged: false, message: 'Renommage accepté ; redémarrage restant.', time: '2026-10-25T17:00:00Z' };
      const f = window.fixture = { calls: [], receipt: { ...base, ...options.receipt }, planPatch: options.plan || {},
        resultPatch: options.result || {}, previewPatch: options.preview || {}, mode: options.mode || 'live', readOnly: options.readOnly === true,
        hold: options.hold, precreatedEnabled: options.precreated !== false, releases: {}, searches: {}, serial: 0, ...options.flags };
      const session = () => ({ mode: f.mode, readOnly: f.readOnly, computer: 'LOCAL-CANARY', domain: 'example.local', account: 'EXAMPLE\\operator',
        capabilities: options.acknowledgeEnabled === undefined ? [] : [{ id: 'acknowledge', enabled: options.acknowledgeEnabled }] });
      const entra = { entraLeaveRequired: true, entraState: 'hybrid', entraPolicy: 'HybridOnly', entraObservedAt: '2026-10-25T17:00:00Z', entraExpiresAt: '2099-01-01T00:00:00Z' };
      const renamePlan = { planId: 'rename-plan', kind: 'rename', computer: 'PC-OLD', newName: 'PC-NEW', targetOU: ou,
        confirmationName: 'PC-NEW', mode: 'live', expiresAt: '2099-01-01T00:00:00Z', ...entra, ...f.planPatch };
      const batchItems = Array.from({ length: 14 }, (_, i) => ({ ...renamePlan, planId: 'plan-' + i, computer: 'PC-' + String(i + 1).padStart(2, '0'),
        newName: 'NEW-' + String(i + 1).padStart(2, '0'), entraLeaveRequired: i === 13, entraState: i === 13 ? 'hybrid' : 'adOnly' }));
      const call = async (op, args = {}) => {
        f.calls.push({ op, args: structuredClone(args) });
        if (op === f.hold) await new Promise(resolve => { f.releases[op] = resolve; });
        if (op === 'directory.search') return new Promise((resolve, reject) => { f.searches[args.query] = { resolve, reject }; });
        if (op === 'computer.inspect') return { name: args.computer, site: 'paris', service: 'INF', type: 'P' };
        if (op === 'queue.add' || op === 'queue.remove') return { status: 'accepted' };
        if (op === 'reservations.list') return { items: [] };
        if (op === 'receipts.list') return { items: [structuredClone(f.receipt)] };
        if (op === 'receipts.get') return structuredClone(f.receipt);
        if (op === 'receipts.prepareAcknowledgement') return { planId: 'ack-plan', receiptId: f.receipt.id, action: 'acknowledge', mode: 'live',
          computer: f.receipt.computer, newName: f.receipt.newName, domain: 'example.local', phase: f.receipt.status === 'pendingRestart' ? 'PendingRestart' : 'Uncertain',
          code: f.receipt.code, confirmationName: f.receipt.newName || f.receipt.computer, expiresAt: '2099-01-01T00:00:00Z',
          warnings: ['La réinscription hybride reste à vérifier séparément.'], ...f.planPatch };
        if (op === 'receipts.acknowledge') {
          const acknowledgement = { id: 'ack-' + (++f.serial), utc: '2026-10-25T18:00:00Z', by: 'EXAMPLE\\operator', reason: args.reason,
            phase: f.receipt.status === 'pendingRestart' ? 'PendingRestart' : 'Uncertain', code: f.receipt.code };
          return { receipt: { ...f.receipt, acknowledged: true, ...f.resultPatch }, acknowledgement };
        }
        if (op === 'receipts.prepareRestart') return { planId: 'restart-plan', receiptId: f.receipt.id, action: 'restart', mode: 'live',
          computer: f.receipt.computer, newName: f.receipt.newName, domain: 'example.local', targetComputer: f.receipt.computer,
          confirmationName: f.receipt.computer, expiresAt: '2099-01-01T00:00:00Z', warnings: [], ...f.planPatch };
        if (op === 'receipts.restart') return { receipt: { ...f.receipt }, restart: { id: 'restart-' + (++f.serial), status: 'accepted',
          computer: f.receipt.computer, utc: '2026-10-25T18:00:00Z', ...f.resultPatch } };
        if (op === 'directory.sites') return { items: [{ id: 'paris', name: 'Paris', code: 'PA', ou }] };
        if (op === 'directory.services') return { items: [{ code: 'INF', name: 'Informatique' }] };
        if (op === 'join.precreated.preview') return { previewId: 'precreated-preview', name: args.name, ou, computer: session().computer,
          domain: 'example.local', dc: 'dc01.example.local', computerGuid: '11111111-2222-3333-4444-555555555555',
          targetOuGuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', joinAccountMode: 'precreated', existingAccount: true, complete: true,
          collectedAt: '2026-10-25T18:00:00Z', expiresAt: '2099-01-01T00:00:00Z', availableCount: null, source: 'Compte exact relu dans AD', warnings: [], ...f.previewPatch };
        if (op === 'names.preview') return { previewId: 'free-preview', name, ou, complete: true, expiresAt: '2099-01-01T00:00:00Z' };
        if (op === 'operation.prepare') {
          if (args.kind !== 'join') return renamePlan;
          const existing = args.previewId === 'precreated-preview';
          return { planId: 'join-plan', kind: 'join', computer: session().computer, newName: name, confirmationName: name, targetOU: ou,
            mode: 'live', expiresAt: '2099-01-01T00:00:00Z', ...(existing ? { joinAccountMode: 'precreated', computerGuid: '11111111-2222-3333-4444-555555555555', reservationRequired: false } : {}), ...f.planPatch };
        }
        if (op === 'operation.execute') return kind === 'join'
          ? { ...base, id: 'receipt-join', kind: 'join', computer: session().computer, newName: name }
          : { ...base, id: 'receipt-rename' };
        if (op === 'queue.list') {
          const snapshot = { count: 14, items: batchItems.map((p, i) => ({ ...p, id: 'q-' + i, status: 'ready' })) };
          if (f.deferQueue) { f.deferQueue = false; return new Promise(resolve => { f.releaseQueue = () => resolve({ count: 1, items: [{ id: 'stale', computer: 'STALE-LIST', status: 'ready' }] }); }); }
          return snapshot;
        }
        if (op === 'queue.prepare') return { batchId: 'batch-1', items: batchItems, expiresAt: '2099-01-01T00:00:00Z' };
        if (op === 'queue.execute') return { receipts: [{ ...base }], stopped: true, reason: 'Redémarrage en attente.' };
        throw new Error('Undeclared fixture API: ' + op);
      };
      const ctx = { session, call, capability: id => ({ enabled: !f.readOnly && (id !== 'joinPrecreated' || f.precreatedEnabled), reason: 'Politique désactivée.' }),
        params: {}, setScreenCommands() {}, refreshSession: async () => {} };
      const main = document.querySelector('main');
      if (kind === 'entra') {
        const { confirmAndExecute } = await import('/js/writeflow.js');
        window.launchConfirmation = () => { window.confirmResult = null; window.confirmPromise = confirmAndExecute(call, renamePlan).then(result => { window.confirmResult = result; }); };
        window.stopPage = () => { location.hash = '#gone'; };
      } else {
        const module = await import('/js/pages/' + ({ receipts: 'interventions', join: 'ajouter', batch: 'plusieurspostes', single: 'unposte' }[kind]) + '.js');
        const dispose = module.render(main, ctx);
        window.stopPage = () => { dispose(); main.innerHTML = '<p>Page quittée</p>'; location.hash = '#gone'; };
      }
    }, { kind, options });
    if (kind === 'receipts') await page.locator('[data-receipt="receipt-parent"]').waitFor();
    if (kind === 'join') await page.locator('[data-form="join"] option[value="INF"]').waitFor({ state: 'attached' });
    if (kind === 'batch') await page.waitForFunction(() => !document.querySelector('[data-act="prepare"]').disabled);
    return page;
  }
  const countCalls = (page, op) => page.evaluate(op => window.fixture.calls.filter(c => c.op === op), op);
  const dialog = page => page.locator('.k-dlg-layer:not(.leaving) .k-dlg');
  const parent = page => page.locator('[data-receipt="receipt-parent"]');
  const scenario = (label, kind, options, test) => check(label, async () => { const page = await pageFor(kind, options); try { await test(page); } finally { await page.close(); } });
  const typeTarget = async page => {
    const d = dialog(page); await d.waitFor();
    const input = d.locator('.k-cw-typed input');
    if (await input.count()) await input.pressSequentially(await d.locator('.k-cw-target b').innerText());
    return d;
  };
  const ackDialog = async page => { await parent(page).getByRole('button', { name: 'Acquitter sans valider', exact: true }).click(); return typeTarget(page); };
  await scenario('Acquittement : motif obligatoire, Entrée bloquée, état original conservé', 'receipts', { receipt: { status: 'uncertain', code: '97', restartRequired: false } }, async page => {
    assert.equal((await countCalls(page, 'receipts.prepareAcknowledgement')).length, 0);
    const d = await ackDialog(page);
    assert.match(await d.innerText(), /réinscription hybride/);
    assert.equal(await d.locator('.k-cw-typed').count(), 0);
    assert.equal(await d.locator('[data-id="confirm"]').isDisabled(), true);
    await d.locator('textarea').press('Enter'); assert.equal((await countCalls(page, 'receipts.acknowledge')).length, 0);
    await d.locator('textarea').fill('Contrôle manuel\nconsigné');
    await d.locator('[data-id="confirm"]').click();
    await parent(page).locator('[data-acknowledgement]').waitFor();
    assert.equal(await parent(page).getAttribute('data-status'), 'uncertain');
    assert.match(await parent(page).innerText(), /EXAMPLE\\operator.*Contrôle manuel consigné/);
    const calls = await countCalls(page, 'receipts.acknowledge'); assert.equal(calls.length, 1);
    assert.deepEqual(calls[0].args, { planId: 'ack-plan', confirmationName: 'PC-NEW', reason: 'Contrôle manuel consigné' });
    assert.equal(await parent(page).getByRole('button', { name: 'Acquitter sans valider', exact: true }).count(), 0);
  });
  await scenario('Acquittement annulé sans écriture', 'receipts', {}, async page => {
    const d = await ackDialog(page); await d.getByRole('button', { name: 'Annuler', exact: true }).click();
    assert.equal((await countCalls(page, 'receipts.acknowledge')).length, 0);
  });
  for (const plan of [{ receiptId: 'other' }, { code: '0' }, { expiresAt: '2000-01-01T00:00:00Z' }, { confirmationName: 'OTHER' }])
    await scenario('Acquittement : plan contradictoire refusé ' + Object.keys(plan)[0], 'receipts', { plan }, async page => {
      await parent(page).getByRole('button', { name: 'Acquitter sans valider', exact: true }).click(); await parent(page).getByRole('alert').waitFor();
      assert.equal(await page.locator('.k-dlg').count(), 0); assert.equal((await countCalls(page, 'receipts.acknowledge')).length, 0);
    });
  await scenario('Acquittement : un faux succès reçu ne remplace pas le résultat original', 'receipts', { result: { status: 'succeeded', restartRequired: false } }, async page => {
    const d = await ackDialog(page); await d.locator('textarea').fill('Vérification consignée'); await d.locator('[data-id="confirm"]').click();
    await parent(page).getByRole('alert').waitFor(); assert.equal(await parent(page).getAttribute('data-status'), 'pendingRestart');
    assert.equal(await parent(page).locator('[data-acknowledgement]').count(), 0);
  });
  await scenario('Acquittement : navigation pendant la préparation, aucun dialogue tardif', 'receipts', { hold: 'receipts.prepareAcknowledgement' }, async page => {
    await parent(page).getByRole('button', { name: 'Acquitter sans valider', exact: true }).click();
    await page.waitForFunction(() => !!window.fixture.releases['receipts.prepareAcknowledgement']);
    await page.evaluate(() => { window.stopPage(); window.fixture.releases['receipts.prepareAcknowledgement'](); });
    await page.evaluate(() => new Promise(resolve => setTimeout(resolve, 30)));
    assert.equal(await page.locator('.k-dlg').count(), 0); assert.equal((await countCalls(page, 'receipts.acknowledge')).length, 0);
  });
  for (const status of ['accepted', 'uncertain', 'refused']) await scenario('Redémarrage ' + status + ' : demande séparée, parent toujours en attente', 'receipts', { result: { status } }, async page => {
    await parent(page).getByRole('button', { name: 'Préparer le redémarrage', exact: true }).click(); const d = await typeTarget(page);
    assert.equal(await d.locator('.k-cw-target b').innerText(), 'PC-OLD'); assert.match(await d.innerText(), /sans forcer/);
    assert.equal((await countCalls(page, 'receipts.restart')).length, 0);
    await d.locator('[data-id="confirm"]').click(); await parent(page).locator('[data-restart-request]').waitFor();
    assert.equal(await parent(page).getAttribute('data-status'), 'pendingRestart'); assert.doesNotMatch(await parent(page).innerText(), /redémarrage réussi/i);
    assert.equal((await countCalls(page, 'receipts.restart')).length, 1);
    if (status !== 'refused') assert.equal(await parent(page).getByRole('button', { name: 'Préparer le redémarrage', exact: true }).count(), 0);
  });
  await scenario('Redémarrage : cible étrangère refusée avant confirmation', 'receipts', { plan: { targetComputer: 'OTHER', confirmationName: 'OTHER' } }, async page => {
    await parent(page).getByRole('button', { name: 'Préparer le redémarrage', exact: true }).click(); await parent(page).getByRole('alert').waitFor();
    assert.equal((await countCalls(page, 'receipts.restart')).length, 0);
  });
  await scenario('Résultat partiel 89 : redémarrage séparé sans déplacement ni résolution du parent', 'receipts',
    { receipt: { kind: 'renameMove', code: '89', status: 'uncertain' } }, async page => {
      await parent(page).getByRole('button', { name: 'Préparer le redémarrage', exact: true }).click(); const d = await typeTarget(page);
      assert.match(await d.innerText(), /résultat partiel 89 reste conservé/); assert.match(await d.innerText(), /ne relance pas le déplacement/);
      await d.locator('[data-id="confirm"]').click(); await parent(page).locator('[data-restart-request]').waitFor();
      assert.equal(await parent(page).getAttribute('data-status'), 'uncertain');
      assert.equal((await countCalls(page, 'receipts.restart')).length, 1);
      assert.equal((await countCalls(page, 'operation.execute')).length, 0);
      assert.equal((await countCalls(page, 'receipts.prepareMove')).length, 0);
    });
  for (const code of ['32', '97']) await scenario('Effet non prouvé ' + code + ' : aucune préparation de redémarrage proposée', 'receipts',
    { receipt: { kind: 'renameMove', code, status: 'uncertain' } }, async page => {
      assert.equal(await parent(page).locator('[data-act="prepare-restart"]').count(), 0);
      assert.equal((await countCalls(page, 'receipts.prepareRestart')).length, 0);
    });
  for (const options of [{ mode: 'simulation' }, { readOnly: true }])
    await scenario('Décisions réelles absentes en démo ou lecture seule', 'receipts', options, async page => {
      assert.equal(await parent(page).locator('[data-act="prepare-restart"], [data-act="prepare-acknowledgement"]').count(), 0);
    });
  await scenario('Mode incident : acquittement autorisé par capacité, aucune autorisation de redémarrage', 'receipts',
    { readOnly: true, acknowledgeEnabled: true }, async page => {
      assert.equal(await parent(page).locator('[data-act="prepare-restart"]').count(), 0);
      const d = await ackDialog(page); await d.locator('textarea').fill('Décision après analyse de l’incident');
      await d.locator('[data-id="confirm"]').click(); await parent(page).locator('[data-acknowledgement]').waitFor();
      assert.equal(await parent(page).getAttribute('data-status'), 'pendingRestart');
      assert.equal((await countCalls(page, 'receipts.acknowledge')).length, 1);
    });
  await scenario('Capacité acquittement explicitement refusée : aucun bouton ni appel', 'receipts', { acknowledgeEnabled: false }, async page => {
    assert.equal(await parent(page).locator('[data-act="prepare-acknowledgement"]').count(), 0);
    assert.equal((await countCalls(page, 'receipts.prepareAcknowledgement')).length, 0);
  });
  await scenario('Reçu V1 : seul acquittement V2 proposé, portée séparée annoncée', 'receipts', { receipt: { mode: 'V1 · registre local GP (relu, lecture seule)' } }, async page => {
    assert.equal(await parent(page).locator('[data-act="prepare-restart"]').count(), 0);
    const d = await ackDialog(page); assert.match(await d.innerText(), /barrière de l’ancien exécutable V1 restent inchangés/);
    await d.locator('textarea').fill('Décision assumée dans V2'); await d.locator('[data-id="confirm"]').click();
    await parent(page).locator('[data-acknowledgement]').waitFor(); assert.equal(await parent(page).getAttribute('data-status'), 'pendingRestart');
    assert.equal(await parent(page).getAttribute('data-mode'), 'V1 · registre local GP (relu, lecture seule)');
  });
  const inspectPrecreated = async page => {
    await page.getByRole('switch', { name: 'Utiliser un compte ordinateur déjà créé dans AD', exact: true }).check();
    await page.locator('[name="existingName"]').fill('P111301PAINF123');
    await page.getByRole('button', { name: 'Vérifier le compte précréé', exact: true }).click();
  };
  await scenario('Compte précréé : nom/GUID/OU visibles avant Ajouter, plan lié sans autorité du navigateur', 'join', {}, async page => {
    // The page computes a free name on load; switching to a pre-created account must drop it before Ajouter.
    await page.waitForFunction(() => !document.querySelector('[data-act="add"]').disabled);
    await page.getByRole('switch', { name: 'Utiliser un compte ordinateur déjà créé dans AD', exact: true }).check();
    assert.equal(await page.locator('[data-act="add"]').isDisabled(), true);
    await inspectPrecreated(page); await page.locator('.name-preview').waitFor();
    assert.match(await page.locator('.name-preview').innerText(), /P111301PAINF123.*OU=Paris/s);
    assert.equal((await countCalls(page, 'operation.prepare')).length, 0); assert.equal((await countCalls(page, 'operation.execute')).length, 0);
    await page.locator('[data-act="add"]').click(); const d = dialog(page); await d.waitFor();
    assert.equal(await d.locator('.k-cw-typed').count(), 0);
    assert.match(await d.innerText(), /compte AD précréé/); assert.match(await d.innerText(), /Aucun nouveau compte/);
    await d.locator('[data-id="confirm"]').click(); await page.locator('[data-zone="receipt"] [data-receipt]').waitFor();
    assert.deepEqual((await countCalls(page, 'operation.prepare'))[0].args, { kind: 'join', previewId: 'precreated-preview' });
    assert.deepEqual((await countCalls(page, 'operation.execute'))[0].args, { planId: 'join-plan', confirmationName: 'P111301PAINF123' });
  });
  await scenario('Compte précréé : identité locale non concordante bloque Ajouter', 'join', { preview: { computer: 'OTHER' } }, async page => {
    await inspectPrecreated(page); await page.locator('[data-zone="preview"] [role="alert"]').waitFor();
    assert.equal(await page.locator('[data-act="add"]').isDisabled(), true); assert.equal((await countCalls(page, 'operation.prepare')).length, 0);
  });
  await scenario('Compte précréé : changement du nom pendant lecture invalide la réponse tardive', 'join', { hold: 'join.precreated.preview' }, async page => {
    await inspectPrecreated(page); await page.waitForFunction(() => !!window.fixture.releases['join.precreated.preview']);
    await page.locator('[name="existingName"]').fill('OTHER'); await page.evaluate(() => window.fixture.releases['join.precreated.preview']());
    await page.evaluate(() => new Promise(resolve => setTimeout(resolve, 30)));
    assert.equal(await page.locator('[data-act="add"]').isDisabled(), true); assert.equal(await page.locator('.name-preview').count(), 0);
  });
  await scenario('Compte précréé : plan qui recrée un compte refusé avant confirmation', 'join', { plan: { reservationRequired: true } }, async page => {
    await inspectPrecreated(page); await page.locator('.name-preview').waitFor(); await page.locator('[data-act="add"]').click();
    await page.locator('[data-zone="receipt"] [role="alert"]').waitFor(); assert.equal((await countCalls(page, 'operation.execute')).length, 0);
  });
  await scenario('Compte précréé : politique désactivée ne propose aucune lecture de compte', 'join', { precreated: false }, async page => {
    assert.equal(await page.getByRole('switch', { name: 'Utiliser un compte ordinateur déjà créé dans AD', exact: true }).isDisabled(), true);
    assert.equal((await countCalls(page, 'join.precreated.preview')).length, 0);
  });
  await scenario('Entra : case dédiée obligatoire, le nom affiché part sans saisie', 'entra', {}, async page => {
    await page.evaluate(() => window.launchConfirmation()); const d = dialog(page); await d.waitFor();
    assert.match(await d.innerText(), /retrait Entra.*avant le renommage/s);
    assert.equal(await d.locator('.k-cw-typed').count(), 0);
    assert.equal(await d.locator('[data-id="confirm"]').isDisabled(), true);
    assert.equal((await countCalls(page, 'operation.execute')).length, 0);
    await d.locator('[data-consent="entraLeave"]').check(); await d.locator('[data-id="confirm"]').click();
    await page.waitForFunction(() => !!window.confirmResult);
    assert.deepEqual((await countCalls(page, 'operation.execute'))[0].args, { planId: 'rename-plan', confirmationName: 'PC-NEW', entraLeaveConfirmed: true });
  });
  for (const plan of [{ entraState: 'unknown' }, { entraPolicy: 'Disabled' }, { entraExpiresAt: '2000-01-01T00:00:00Z' }, { entraLeaveRequired: 'true' }])
    await scenario('Entra : autorisation contradictoire refusée ' + Object.keys(plan)[0], 'entra', { plan }, async page => {
      await page.evaluate(() => window.launchConfirmation()); await page.waitForFunction(() => !!window.confirmResult);
      assert.equal(await page.locator('.k-dlg').count(), 0); assert.equal((await countCalls(page, 'operation.execute')).length, 0);
    });
  await scenario('Lot Entra : poste au-delà des douze premiers visible et confirmation dédiée obligatoire', 'batch', {}, async page => {
    await page.locator('[data-act="prepare"]').click(); await page.locator('[data-act="execute"]').click(); const d = await typeTarget(page);
    assert.match(await d.locator('.k-cw-changes').innerText(), /Retrait Entra avant renommage\s+PC-14/);
    assert.equal(await d.locator('[data-id="confirm"]').isDisabled(), true);
    await d.locator('[data-consent="entraLeave"]').check(); await d.locator('[data-id="confirm"]').click();
    await page.waitForFunction(() => window.fixture.calls.some(c => c.op === 'queue.execute'));
    assert.deepEqual((await countCalls(page, 'queue.execute'))[0].args, { batchId: 'batch-1', confirmed: true, entraLeaveConfirmed: true });
  });
  for (const kind of ['single', 'batch']) {
    const submitSearch = async (page, query) => {
      await pickRemote(page);
      await page.locator('[data-form="search"] input[name="query"]').fill(query);
      await page.locator('[data-form="search"]').evaluate(form => form.requestSubmit());
      await page.waitForFunction(query => !!window.fixture.searches[query], query);
    };
    for (const rejected of [false, true]) await scenario(kind + ' : une ancienne recherche ne remplace pas la plus récente ' + (rejected ? 'échec' : 'succès'), kind, {}, async page => {
      await submitSearch(page, 'OLD'); await submitSearch(page, 'NEW');
      await page.evaluate(() => window.fixture.searches.NEW.resolve({ items: [{ name: 'NEW-PC' }], complete: true }));
      await page.locator('[data-pick="NEW-PC"]').waitFor();
      await page.evaluate(rejected => {
        const request = window.fixture.searches.OLD;
        if (rejected) request.reject(new Error('OLD-ERROR'));
        else request.resolve({ items: [{ name: 'OLD-PC' }], complete: true });
      }, rejected);
      await page.evaluate(() => new Promise(done => setTimeout(done, 40)));
      assert.equal(await page.locator('[data-pick="NEW-PC"]').count(), 1);
      assert.doesNotMatch(await page.locator('[data-zone="results"]').innerText(), /OLD/);
    });
    await scenario(kind + ' : modifier la recherche invalide la réponse en cours', kind, {}, async page => {
      await submitSearch(page, 'OLD');
      await pickRemote(page);
      await page.locator('[data-form="search"] input[name="query"]').fill('NEXT');
      await page.evaluate(() => window.fixture.searches.OLD.resolve({ items: [{ name: 'OLD-PC' }], complete: true }));
      await page.evaluate(() => new Promise(done => setTimeout(done, 40)));
      assert.equal(await page.locator('[data-pick]').count(), 0);
    });
  }
  await scenario('File : retrait en cours bloque un second retrait et la préparation', 'batch', { hold: 'queue.remove' }, async page => {
    await page.locator('[data-act="prepare"]').click(); await page.locator('[data-act="execute"]').waitFor();
    await page.locator('[data-qdrop]').first().click();
    await page.waitForFunction(() => !!window.fixture.releases['queue.remove']);
    assert.equal(await page.locator('[data-act="execute"]').count(), 0);
    assert.equal(await page.locator('[data-act="prepare"]').isDisabled(), true);
    assert.equal(await page.locator('[data-qdrop]').nth(1).isDisabled(), true);
    await page.locator('[data-qdrop]').nth(1).dispatchEvent('click');
    assert.equal((await countCalls(page, 'queue.remove')).length, 1);
    await page.evaluate(() => window.fixture.releases['queue.remove']());
    await page.waitForFunction(() => !document.querySelector('[data-act="prepare"]').disabled);
  });
  await scenario('File : quitter pendant un ajout empêche toute lecture du poste suivant', 'batch', { hold: 'queue.add' }, async page => {
    await page.locator('[data-form="paste"] textarea').fill('PC-ONE\nPC-TWO');
    await page.locator('[data-form="paste"] button[type="submit"]').click();
    await page.locator('[data-act="addqueue"]').click();
    await page.waitForFunction(() => !!window.fixture.releases['queue.add']);
    await page.evaluate(() => { window.stopPage(); window.fixture.releases['queue.add'](); });
    await page.evaluate(() => new Promise(done => setTimeout(done, 40)));
    assert.equal((await countCalls(page, 'computer.inspect')).length, 1);
    assert.equal((await countCalls(page, 'queue.add')).length, 1);
  });
  await scenario('File : une liste antérieure au retrait ne remplace pas la relecture après mutation', 'batch', {}, async page => {
    await page.evaluate(() => { window.fixture.deferQueue = true; });
    await page.locator('[data-act="refreshqueue"]').click();
    await page.waitForFunction(() => !!window.fixture.releaseQueue);
    await page.locator('[data-qdrop]').first().click();
    await page.waitForFunction(() => window.fixture.calls.some(c => c.op === 'queue.remove') && !document.querySelector('[data-act="prepare"]').disabled);
    await page.evaluate(() => window.fixture.releaseQueue());
    await page.evaluate(() => new Promise(done => setTimeout(done, 40)));
    assert.doesNotMatch(await page.locator('[data-zone="queue-list"]').innerText(), /STALE-LIST/);
    assert.equal(await page.locator('[data-qdrop]').count(), 14);
  });
  await check('Aucune erreur JS ni requête extérieure au serveur de fixture', async () => assert.deepEqual(errors, []));
} finally { await browser?.close(); await new Promise(done => server.close(done)); }
console.log(`${checks - failures}/${checks} contrôles opérateur réussis ; backend mémoire déclaré, aucune opération AD/SMB/Windows.`);
if (failures) process.exitCode = 1;
