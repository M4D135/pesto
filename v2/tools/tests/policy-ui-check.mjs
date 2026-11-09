// Real Pesto recovery/coordination components in Chromium. Declared in-memory backend; no AD/SMB/HTTP outside localhost.
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
const server = createServer(async (req, res) => {
  try {
    const path = new URL(req.url, 'http://localhost').pathname;
    if (path === '/fixture') {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end('<!doctype html><html lang="fr" data-theme="light" data-motion="reduced"><head>'
        + ['tokens','base','layout','motion','components','shell','kit'].map((n) => '<link rel="stylesheet" href="/css/' + n + '.css">').join('')
        + '</head><body><main id="main"></main><div id="announcer" aria-live="polite"></div></body></html>'); return;
    }
    if (path === '/favicon.ico') { res.writeHead(204); res.end(); return; }
    const file = resolve(web, '.' + path); assert(file.startsWith(web + sep));
    res.writeHead(200, { 'Content-Type': { '.js': 'text/javascript', '.css': 'text/css' }[extname(file)] || 'application/octet-stream' });
    res.end(await readFile(file));
  } catch { res.writeHead(404); res.end(); }
});
await new Promise((done) => server.listen(0, '127.0.0.1', done));
const origin = 'http://127.0.0.1:' + server.address().port;
let browser, checks = 0, failures = 0;
const errors = [];
async function check(label, run) {
  checks++;
  try { await run(); console.log('OK ' + label); }
  catch (error) { failures++; console.error('FAIL ' + label + ': ' + error.message); }
}
try {
  browser = await chromium.launch({ headless: true, executablePath });
  async function pageFor(kind = 'reservations', mode = 'live') {
    const page = await browser.newPage({ viewport: { width: 1450, height: 1100 } });
    page.setDefaultTimeout(5000); page.on('pageerror', (e) => errors.push(e.message));
    await page.route('**/*', async (route) => {
      if (route.request().url().startsWith(origin + '/')) await route.continue();
      else { errors.push('External request: ' + route.request().url()); await route.abort(); }
    });
    await page.goto(origin + '/fixture');
    await page.evaluate(async ({ kind, mode }) => {
      const reservation = { id: 'reservation-11111111111111111111111111111111', name: 'P111301PAINF123', computer: 'LOCAL-CANARY',
        domain: 'example.local', dc: 'dc01.example.local', targetOU: 'OU=Paris,DC=example,DC=local', state: 'Reserved',
        message: 'Compte conservé : inspection nécessaire.', needsReview: true, canResume: false, canRelease: false, parentReceiptId: 'receipt-original' };
      window.fixture = { calls: [], reservation, fail: null, sequence: 0, mode, planPatch: {}, resultPatch: {}, receiptPatch: {}, deferInspect: false,
        coordination: { configured: true, root: 'C:\\Approved\\Coordination', domain: 'example.local', required: true, message: 'Configuration locale, registre non sondé.' } };
      const call = async (op, args = {}) => {
        const f = window.fixture; f.calls.push({ op, args: structuredClone(args) });
        if (op === f.fail) throw Object.assign(new Error('Refus contrôlé : état non confirmé.'), { code: 'fixture.refused' });
        if (op === 'reservations.list') return { items: [structuredClone(f.reservation)] };
        if (op === 'reservations.inspect') {
          if (f.deferInspect) await new Promise((resolve) => { f.releaseInspection = resolve; });
          f.reservation = { ...f.reservation, needsReview: false, canResume: true, canRelease: true, message: 'GUID et marqueur relus ; aucun effet AD.' };
          return structuredClone(f.reservation);
        }
        if (op === 'reservations.prepare') return { ...f.reservation, planId: 'plan-' + (++f.sequence), reservationId: f.reservation.id,
          action: args.action, confirmationName: f.reservation.name, expiresAt: '2099-01-01T00:00:00Z', mode: 'live',
          steps: [{ label: 'Relire les preuves', detail: 'Exécuter cette seule action.' }], warnings: [], ...f.planPatch };
        if (op === 'reservations.execute') {
          const prepare = f.calls.filter((c) => c.op === 'reservations.prepare').at(-1);
          const resumed = prepare.args.action === 'resumeJoin';
          f.reservation = { ...f.reservation, state: resumed ? 'Consumed' : 'Released', canResume: false, canRelease: false,
            message: resumed ? 'Jonction acceptée : redémarrage à planifier explicitement.' : 'Absence du compte confirmée après retrait.' };
          return { reservation: { ...f.reservation, ...f.resultPatch }, ...(resumed ? { receipt: {
            id: 'receipt-child', kind: 'join', computer: f.reservation.computer, newName: f.reservation.name, targetOU: f.reservation.targetOU,
            mode: 'live · reprise de réservation · fixture', status: 'pendingRestart', restartRequired: true, time: '2026-10-25T18:00:00Z', message: 'Acceptée, aucun redémarrage lancé.', ...f.receiptPatch } } : {}) };
        }
        if (op === 'coordination.status') return structuredClone(f.coordination);
        if (op === 'coordination.inspect') return { ...f.coordination, prepared: true, message: 'Registre relu ; aucune écriture.' };
        if (op === 'coordination.prepare') return { ...f.coordination, planId: 'registry-' + (++f.sequence), expiresAt: '2099-01-01T00:00:00Z',
          requiresConfirmation: true, actions: ['Créer uniquement les éléments manquants'], warnings: [], ...f.planPatch };
        if (op === 'coordination.apply') return { ...f.coordination, status: 'prepared', prepared: true, message: 'Registre préparé et relu.', ...f.resultPatch };
        throw new Error('Undeclared fixture API: ' + op);
      };
      const ctx = { session: () => ({ mode: window.fixture.mode }), call };
      const main = document.querySelector('main');
      if (kind === 'reservations') {
        const m = await import('/js/pages/reservation-panel.js'); main.innerHTML = m.reservationMarkup(); window.disposePanel = m.mountReservations(main, ctx);
      } else {
        const m = await import('/js/pages/coordination-panel.js'); main.innerHTML = m.coordinationMarkup(); const panel = m.mountCoordination(main, ctx);
        window.disposePanel = () => panel.dispose(); window.refreshPanel = () => panel.refresh();
      }
    }, { kind, mode });
    if (mode === 'live') await page.waitForFunction(() => document.querySelector('main section').getAttribute('aria-busy') === 'false');
    return page;
  }
  const calls = (p, op) => p.evaluate((op) => window.fixture.calls.filter((c) => c.op === op), op);
  const dialog = (p) => p.locator('.k-dlg-layer:not(.leaving) .k-dlg').last();
  const action = (p, name) => p.locator('[data-reservation-action="' + name + '"]');
  async function inspect(p) { await action(p, 'inspect').click(); await p.waitForFunction(() => document.querySelector('[data-reservation-action="release"]').disabled === false); }
  async function confirm(p) {
    assert.equal(await dialog(p).locator('.k-cw-typed').count(), 0);
    await dialog(p).locator('[data-id="confirm"]').click();
  }
  async function close(p) { await p.close(); }

  await check('Panneau réservation : chargement local seulement, aucune action avant inspection', async () => {
    const p = await pageFor(); try {
      assert.deepEqual((await p.evaluate(() => window.fixture.calls)).map((c) => c.op), ['reservations.list']);
      assert.equal(await action(p, 'release').isDisabled(), true); assert.equal(await action(p, 'resumeJoin').isDisabled(), true);
    } finally { await close(p); }
  });
  await check('Inspection explicite limitée à l’identifiant du reçu', async () => {
    const p = await pageFor(); try { await inspect(p); assert.deepEqual((await calls(p, 'reservations.inspect'))[0].args, { id: 'reservation-11111111111111111111111111111111' }); assert.equal((await calls(p, 'reservations.execute')).length, 0); }
    finally { await close(p); }
  });
  await check('Retrait : annulation sans écriture, confirmation exacte, un seul envoi', async () => {
    const p = await pageFor(); try {
      await inspect(p); await action(p, 'release').click(); await dialog(p).waitFor();
      assert.equal((await calls(p, 'reservations.execute')).length, 0);
      assert.equal(await dialog(p).locator('.k-cw-typed').count(), 0);
      assert.equal(await dialog(p).locator('[data-id="confirm"]').isDisabled(), false);
      await dialog(p).locator('[data-id="cancel"]').click(); await p.waitForFunction(() => document.querySelector('[data-reservations]').getAttribute('aria-busy') === 'false');
      assert.equal((await calls(p, 'reservations.execute')).length, 0);
      await action(p, 'release').click(); await dialog(p).waitFor(); await confirm(p);
      await p.waitForFunction(() => document.querySelector('[data-reservation-status]').textContent.includes('Absence'));
      assert.deepEqual((await calls(p, 'reservations.execute'))[0].args, { planId: 'plan-2', confirmationName: 'P111301PAINF123' });
      assert.equal((await calls(p, 'reservations.execute')).length, 1); assert.equal((await calls(p, 'operation.execute')).length, 0);
    } finally { await close(p); }
  });
  await check('Reprise : reçu pendingRestart conservé, aucun reboot ni succès inventé', async () => {
    const p = await pageFor(); try {
      await inspect(p); await action(p, 'resumeJoin').click(); await dialog(p).waitFor(); await confirm(p);
      await p.locator('[data-receipt="receipt-child"]').waitFor(); assert.equal(await p.locator('[data-receipt]').getAttribute('data-status'), 'pendingRestart');
      assert.equal((await p.evaluate(() => window.fixture.calls)).some((c) => /restart|reboot/.test(c.op)), false);
    } finally { await close(p); }
  });
  for (const [name, patch] of [['identité', { name: 'AUTRE' }], ['reçu', { reservationId: 'other' }], ['mode', { mode: 'simulation' }], ['expiration', { expiresAt: '2000-01-01T00:00:00Z' }]]) {
    await check('Plan de réservation refusé si ' + name + ' divergente', async () => {
      const p = await pageFor(); try { await inspect(p); await p.evaluate((patch) => { window.fixture.planPatch = patch; }, patch); await action(p, 'release').click();
        await p.waitForFunction(() => document.querySelector('[data-reservation-status]').getAttribute('role') === 'alert');
        assert.equal((await calls(p, 'reservations.execute')).length, 0); assert.equal(await p.locator('.k-dlg').count(), 0);
      } finally { await close(p); }
    });
  }
  await check('Navigation pendant confirmation : aucun envoi tardif', async () => {
    const p = await pageFor(); try { await inspect(p); await action(p, 'release').click(); await dialog(p).waitFor(); await p.evaluate(() => window.disposePanel()); await confirm(p); assert.equal((await calls(p, 'reservations.execute')).length, 0); }
    finally { await close(p); }
  });
  await check('Échec de retrait : pas de rejeu ni de résultat réussi', async () => {
    const p = await pageFor(); try { await inspect(p); await p.evaluate(() => { window.fixture.fail = 'reservations.execute'; }); await action(p, 'release').click(); await dialog(p).waitFor(); await confirm(p);
      await p.waitForFunction(() => document.querySelector('[data-reservation-status]').getAttribute('role') === 'alert');
      assert.equal((await calls(p, 'reservations.execute')).length, 1); assert.doesNotMatch(await p.locator('[data-reservation-list]').innerText(), /Retrait confirmé/);
    } finally { await close(p); }
  });
  await check('Résultat associé à un autre reçu : aucun statut confirmé affiché', async () => {
    const p = await pageFor(); try { await inspect(p); await p.evaluate(() => { window.fixture.resultPatch = { id: 'foreign' }; }); await action(p, 'release').click(); await dialog(p).waitFor(); await confirm(p);
      await p.waitForFunction(() => document.querySelector('[data-reservation-status]').getAttribute('role') === 'alert'); assert.doesNotMatch(await p.locator('[data-reservation-list]').innerText(), /Retrait confirmé/);
    } finally { await close(p); }
  });
  await check('Reçu enfant incohérent : réservation utilisée et succès ne sont pas affichés', async () => {
    const p = await pageFor(); try {
      await inspect(p); await p.evaluate(() => { window.fixture.receiptPatch = { computer: 'AUTRE-POSTE' }; });
      await action(p, 'resumeJoin').click(); await dialog(p).waitFor(); await confirm(p);
      await p.waitForFunction(() => document.querySelector('[data-reservation-status]').getAttribute('role') === 'alert');
      assert.equal(await p.locator('[data-receipt]').count(), 0);
      assert.doesNotMatch(await p.locator('[data-reservation-list]').innerText(), /Réservation utilisée/);
      assert.equal((await calls(p, 'reservations.execute')).length, 1);
    } finally { await close(p); }
  });
  await check('Coordination : statut local, inspection uniquement au clic', async () => {
    const p = await pageFor('coordination'); try {
      assert.deepEqual((await p.evaluate(() => window.fixture.calls)).map((c) => c.op), ['coordination.status']);
      await p.locator('[data-coordination-action="inspect"]').click(); await p.waitForFunction(() => document.querySelector('[data-coordination-status]').textContent.includes('Registre relu'));
      assert.equal((await calls(p, 'coordination.apply')).length, 0);
    } finally { await close(p); }
  });
  await check('Coordination : aperçu puis confirmation, annulation sans création', async () => {
    const p = await pageFor('coordination'); try {
      await p.locator('[data-coordination-action="prepare"]').click(); await dialog(p).waitFor(); assert.match(await dialog(p).innerText(), /Aucun partage/);
      assert.equal((await calls(p, 'coordination.apply')).length, 0); await dialog(p).locator('[data-id="cancel"]').click();
      await p.waitForFunction(() => document.querySelector('[data-coordination]').getAttribute('aria-busy') === 'false');
      assert.equal((await calls(p, 'coordination.apply')).length, 0); await p.locator('[data-coordination-action="prepare"]').click(); await dialog(p).waitFor();
      await dialog(p).locator('[data-id="confirm"]').click(); await p.waitForFunction(() => document.querySelector('[data-coordination-status]').textContent.includes('préparé et relu'));
      assert.deepEqual((await calls(p, 'coordination.apply'))[0].args, { planId: 'registry-2', confirmed: true });
    } finally { await close(p); }
  });
  await check('Coordination : chemin différent du statut relu refusé', async () => {
    const p = await pageFor('coordination'); try { await p.evaluate(() => { window.fixture.planPatch = { root: 'C:\\Other' }; }); await p.locator('[data-coordination-action="prepare"]').click();
      await p.waitForFunction(() => document.querySelector('[data-coordination-status]').getAttribute('role') === 'alert');
      assert.equal((await calls(p, 'coordination.apply')).length, 0); assert.equal(await p.locator('.k-dlg').count(), 0);
    } finally { await close(p); }
  });
  await check('Démonstration : les deux panneaux ne demandent aucune API réelle', async () => {
    for (const kind of ['reservations', 'coordination']) { const p = await pageFor(kind, 'simulation'); try {
      assert.equal(await p.locator('main section').isHidden(), true); assert.deepEqual(await p.evaluate(() => window.fixture.calls), []);
    } finally { await close(p); } }
  });
  await check('Aucune erreur JavaScript ni accès extérieur pendant les scénarios', async () => { assert.deepEqual(errors, []); });
} finally { await browser?.close(); await new Promise((done) => server.close(done)); }
console.log('POLICY UI ' + (failures ? 'FAILED' : 'OK') + ': ' + (checks - failures) + '/' + checks + ' contrôles ; backend de fixture uniquement.');
process.exitCode = failures ? 1 : 0;
