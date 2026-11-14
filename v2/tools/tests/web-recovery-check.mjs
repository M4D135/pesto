// Actual Chromium interactions with Pesto modules, using an explicit in-memory native-channel fixture.
// Never calls Windows/AD. No browser installation/download. Same PESTO_* environment as web-dom-check.mjs.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, extname, isAbsolute, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const web = resolve(dirname(fileURLToPath(import.meta.url)), '../../web');
const name = process.env.PESTO_PLAYWRIGHT_MODULE || 'playwright';
const { chromium } = await import(isAbsolute(name) ? pathToFileURL(name).href : name);
const executablePath = process.env.PESTO_CHROMIUM_PATH || ['/usr/bin/google-chrome', '/usr/bin/chromium'].find(existsSync);
assert(executablePath && existsSync(executablePath), 'Un Chromium déjà installé est requis.');
const server = createServer(async (req, res) => {
  if (req.url === '/favicon.ico') { res.writeHead(204); res.end(); return; }
  try {
    const path = new URL(req.url, 'http://localhost').pathname;
    const file = resolve(web, `.${path === '/' ? '/index.html' : path}`);
    if (!file.startsWith(web + sep)) throw Error('path');
    const body = await readFile(file);
    res.writeHead(200, { 'Content-Type': { '.js': 'text/javascript', '.html': 'text/html', '.css': 'text/css' }[extname(file)] || 'application/octet-stream' }); res.end(body);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise((done) => server.listen(0, '127.0.0.1', done));
let browser, checks = 0, failures = 0;
const errors = [];
const filter = process.argv[2] ? new RegExp(process.argv[2], 'i') : null;
const check = async (label, run) => { if (filter && !filter.test(label)) return; checks++; try { await run(); console.log(`  ok   ${label}`); } catch (e) { failures++; console.error(`  FAIL ${label} — ${e.message}`); } };
try {
  browser = await chromium.launch({ headless: true, executablePath });
  const makePage = async (options = {}) => {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    page.setDefaultTimeout(5000);
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    await page.addInitScript(options => {
      localStorage.setItem('pesto.prefs.v1', JSON.stringify({ theme: 'light', motion: 'reduced' }));
      const base = { id: 'parent', kind: 'renameMove', code: '89', computer: 'PC-OLD', newName: 'PC-NEW',
        targetOU: 'OU=Target,DC=example,DC=local', mode: 'live · navigateur de test', status: 'uncertain',
        readable: true, restartRequired: true, time: '2026-10-25T09:00:00Z', message: 'Renommage accepté, déplacement non exécuté.',
        parentReceiptId: null, resolutionChildReceiptId: null };
      const parent = { ...base, ...options.parent };
      const items = options.eligibility ? [parent,
        { ...base, id: 'rename', kind: 'rename' }, { ...base, id: 'other-code', code: '5' },
        { ...base, id: 'done', status: 'succeeded' }, { ...base, id: 'simulation', mode: 'simulation' },
        { ...base, id: 'unreadable', readable: false }, { ...base, id: 'resolved', resolutionChildReceiptId: 'existing-child' }] : [parent];
      window.fixture = { calls: [], release: null, child: null };
      let receive;
      window.chrome ??= {};
      window.chrome.webview = {
        addEventListener(type, fn) { if (type === 'message') receive = fn; },
        async postMessage(request) {
          const f = window.fixture;
          f.calls.push({ op: request.op, args: request.args });
          try {
            let data;
            if (request.op === 'session.info') data = { mode: options.mode || 'live', readOnly: options.move === false,
              computer: 'PC-NEW', domain: 'example.local', account: 'EXAMPLE\\operator',
              capabilities: [{ id: 'move', enabled: options.move !== false }] };
            else if (request.op === 'receipts.list') data = { items };
            else if (request.op === 'reservations.list') data = { items: [] };
            else if (request.op === 'configuration.status') data = { configured: true, distribution: null };
            else if (request.op === 'receipts.prepareMove') {
              if (options.holdPrepare) await new Promise(done => { f.release = done; });
              if (options.prepareError) throw Error('Preuve de redémarrage insuffisante.');
              data = { planId: 'move-plan', kind: 'move', computer: 'PC-NEW', newName: 'PC-NEW', targetOU: base.targetOU,
                mode: 'live', parentReceiptId: 'parent', confirmationName: 'PC-NEW', expiresAt: '2099-01-01T00:00:00Z', ...options.plan };
            } else if (request.op === 'operation.execute') {
              if (request.args.planId !== 'move-plan' || request.args.confirmationName !== 'PC-NEW') throw Error('Exact confirmation required.');
              if (options.executeError) throw Error('Le moteur refuse ce plan périmé.');
              data = { ...base, id: 'child', kind: 'move', code: '0', computer: 'PC-NEW', status: options.status || 'succeeded',
                restartRequired: options.status === 'pendingRestart', parentReceiptId: 'parent', ...options.child };
              f.child = data;
            } else if (request.op === 'receipts.get') {
              if (options.parentReadError) throw Error('Historique indisponible.');
              data = { ...parent, resolutionChildReceiptId: f.child?.status === 'succeeded' && options.resolve !== false ? 'child' : null };
            } else throw Error('Unexpected operation ' + request.op);
            receive({ data: { id: request.id, kind: 'result', data: JSON.parse(JSON.stringify(data)) } });
          } catch (e) { receive({ data: { id: request.id, kind: 'error', error: { code: 'fixture.refused', message: e.message } } }); }
        },
      };
    }, options);
    await page.goto('http://127.0.0.1:' + server.address().port + '/#/interventions');
    await page.waitForFunction(() => document.documentElement.dataset.ready === 'interventions');
    await page.locator('[data-receipt="parent"]').waitFor();
    return page;
  };
  const parent = page => page.locator('[data-receipt="parent"]');
  const action = page => parent(page).getByRole('button', { name: 'Préparer le déplacement restant', exact: true });
  const dialog = page => page.getByRole('alertdialog', { name: 'Confirmer le déplacement restant', exact: true });
  const calls = (page, op) => page.evaluate(op => window.fixture.calls.filter(c => c.op === op), op);
  const prepare = async page => { await action(page).click(); await dialog(page).waitFor(); };
  const execute = async page => {
    const d = dialog(page);
    assert.equal(await d.getByRole('textbox').count(), 0);
    assert.equal(await d.locator('.k-cw-target b').innerText(), 'PC-NEW');
    await d.getByRole('button', { name: 'Confirmer le déplacement', exact: true }).click();
    await page.waitForFunction(() => document.querySelector('[data-receipt="parent"]')?.getAttribute('aria-busy') !== 'true');
  };
  const scenario = async (label, options, run) => check(label, async () => { const page = await makePage(options); try { await run(page); } finally { await page.close(); } });
  await scenario('Action réservée au reçu réel renameMove/code89 non résolu', { eligibility: true }, async page => {
    assert.equal(await page.getByRole('button', { name: 'Préparer le déplacement restant', exact: true }).count(), 1);
    assert.equal(await parent(page).getAttribute('data-status'), 'uncertain');
  });
  for (const options of [{ move: false }, { mode: 'simulation' }]) await scenario('Aucune reprise sans capacité move ou session réelle', options, async page => assert.equal(await action(page).count(), 0));
  await scenario('Preuve insuffisante : reçu conservé et aucune exécution', { prepareError: true }, async page => {
    await action(page).click(); await parent(page).getByRole('alert').waitFor();
    assert.match(await parent(page).innerText(), /Preuve de redémarrage insuffisante/);
    assert.equal(await parent(page).getAttribute('data-status'), 'uncertain');
    assert.equal((await calls(page, 'operation.execute')).length, 0);
  });
  for (const [field, value] of [['kind', 'renameMove'], ['parentReceiptId', 'other'], ['computer', 'OTHER'], ['newName', 'OTHER'], ['targetOU', 'OU=Other'], ['confirmationName', 'OTHER'], ['mode', 'simulation']]) {
    await scenario('Plan contradictoire refusé avant confirmation : ' + field, { plan: { [field]: value } }, async page => {
      await action(page).click(); await parent(page).getByRole('alert').waitFor();
      assert.match(await parent(page).innerText(), /Aucune exécution/);
      assert.equal(await dialog(page).count(), 0);
      assert.equal((await calls(page, 'operation.execute')).length, 0);
    });
  }
  await scenario('Annulation explicite : aucun déplacement envoyé', {}, async page => {
    await prepare(page); await dialog(page).getByRole('button', { name: 'Annuler', exact: true }).click();
    await page.waitForFunction(() => document.querySelector('[data-receipt="parent"]')?.getAttribute('aria-busy') !== 'true');
    assert.match(await parent(page).innerText(), /Confirmation annulée/);
    assert.equal((await calls(page, 'operation.execute')).length, 0);
  });
  await scenario('Plan affiché confirmé sans recopie : cible exacte envoyée, lien serveur et parent inchangé', {}, async page => {
    await prepare(page);
    const d = dialog(page), confirm = d.getByRole('button', { name: 'Confirmer le déplacement', exact: true });
    assert.equal(await d.getByRole('textbox').count(), 0);
    assert.equal(await d.locator('.k-cw-target b').innerText(), 'PC-NEW');
    assert.equal(await confirm.isEnabled(), true);
    assert.equal((await calls(page, 'operation.execute')).length, 0);
    await execute(page);
    assert.deepEqual(await calls(page, 'operation.execute'), [{ op: 'operation.execute', args: { planId: 'move-plan', confirmationName: 'PC-NEW' } }]);
    assert.equal(await parent(page).getAttribute('data-status'), 'uncertain');
    assert.equal(await page.locator('[data-receipt="child"]').getAttribute('data-status'), 'succeeded');
    assert.match(await parent(page).locator('[data-resolution]').innerText(), /child/);
    assert.equal(await action(page).count(), 0);
    assert.equal((await calls(page, 'receipts.get')).length, 1);
    const ops = await page.evaluate(() => window.fixture.calls.map(c => c.op));
    assert(ops.every(op => ['session.info', 'configuration.status', 'reservations.list', 'receipts.list', 'receipts.prepareMove', 'operation.execute', 'receipts.get'].includes(op)), JSON.stringify(ops));
  });
  for (const status of ['refused', 'uncertain', 'pendingRestart']) await scenario('Enfant ' + status + ' : aucune résolution optimiste', { status }, async page => {
    await prepare(page); await execute(page);
    assert.equal(await parent(page).getAttribute('data-status'), 'uncertain');
    assert.equal(await page.locator('[data-receipt="child"]').getAttribute('data-status'), status);
    assert.equal(await parent(page).locator('[data-resolution]').count(), 0);
    assert.equal((await calls(page, 'receipts.get')).length, 0);
    assert.equal((await calls(page, 'operation.execute')).length, 1);
  });
  for (const options of [{ resolve: false }, { parentReadError: true }]) await scenario('Enfant confirmé sans lien parent relu : parent non résolu', options, async page => {
    await prepare(page); await execute(page);
    assert.equal(await parent(page).getAttribute('data-status'), 'uncertain');
    assert.equal(await parent(page).locator('[data-resolution]').count(), 0);
    assert.equal(await action(page).isEnabled(), true);
    assert.equal(await page.locator('[data-receipt="child"]').getAttribute('data-status'), 'succeeded');
  });
  await scenario('Refus execute : pas de reçu enfant ni de nouvelle tentative', { executeError: true }, async page => {
    await prepare(page); await execute(page);
    assert.match(await parent(page).getByRole('alert').innerText(), /plan périmé/);
    assert.equal(await page.locator('[data-receipt="child"]').count(), 0);
    assert.equal((await calls(page, 'operation.execute')).length, 1);
  });
  await scenario('Enfant lié à un autre parent : résultat non accepté', { child: { parentReceiptId: 'other' } }, async page => {
    await prepare(page); await execute(page);
    assert.match(await parent(page).getByRole('alert').innerText(), /état reste inchangé/);
    assert.equal(await page.locator('[data-receipt="child"]').count(), 0);
    assert.equal(await parent(page).locator('[data-resolution]').count(), 0);
  });
  await scenario('Préparation : double clic bloqué et réponse périmée ignorée après relecture', { holdPrepare: true }, async page => {
    await action(page).click();
    await page.waitForFunction(() => typeof window.fixture.release === 'function');
    assert.equal(await action(page).isEnabled(), false);
    await action(page).evaluate(el => { el.click(); el.click(); });
    assert.equal((await calls(page, 'receipts.prepareMove')).length, 1);
    await page.getByRole('button', { name: 'Rafraîchir', exact: true }).click();
    await page.waitForFunction(() => window.fixture.calls.filter(c => c.op === 'receipts.list').length === 2);
    await page.evaluate(() => window.fixture.release());
    await page.waitForTimeout(100);
    assert.equal(await dialog(page).count(), 0);
    assert.equal((await calls(page, 'operation.execute')).length, 0);
  });
  await scenario('Simulation refuse explicitement la préparation réelle', {}, async page => {
    const code = await page.evaluate(async () => { try { const { browserSimulation } = await import('/js/simulation.js'); await browserSimulation.invoke('receipts.prepareMove', { id: 'parent' }); } catch (e) { return e.code; } });
    assert.equal(code, 'receipt.prepareMoveSimulation');
  });
  await check('Aucune exception JavaScript ni erreur console', async () => assert.deepEqual(errors, []));
} finally { await browser?.close(); await new Promise(done => server.close(done)); }
console.log((checks - failures) + '/' + checks + ' contrôles de reprise UI réussis (fixture navigateur, aucune preuve AD).');
process.exitCode = failures ? 1 : 0;
