// Behavioral browser checks against the actual Pesto ES modules and CSS, served on an ephemeral loopback port.
// Uses only an already-installed Chromium and Playwright; never installs/downloads a browser or calls Windows/AD.
// Example:
// PESTO_PLAYWRIGHT_MODULE=/absolute/node_modules/playwright/index.mjs PESTO_CHROMIUM_PATH=/usr/bin/google-chrome \
//   node v2/tools/tests/demo-dom-check.mjs
// These checks cover browser simulation, not native WebView2, UIA, production bridge or AD qualification.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, extname, isAbsolute, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// « Un poste » targets this PC by default: searching another computer starts with that explicit choice.
const pickRemote = async (page) => { const remote = page.locator('[data-form="target"] input[value="remote"]'); if (await remote.count()) await remote.check(); };
const here = dirname(fileURLToPath(import.meta.url));
const web = resolve(here, '../../web');
const moduleName = process.env.PESTO_PLAYWRIGHT_MODULE || 'playwright';
let chromium;
try {
  ({ chromium } = await import(isAbsolute(moduleName) ? pathToFileURL(moduleName).href : moduleName));
} catch {
  throw new Error('Playwright local requis : définir PESTO_PLAYWRIGHT_MODULE vers son index.mjs installé. Aucun téléchargement automatique.');
}
const executablePath = process.env.PESTO_CHROMIUM_PATH
  || ['/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser'].find(existsSync);
assert(executablePath && existsSync(executablePath), 'Chromium local requis : définir PESTO_CHROMIUM_PATH vers un exécutable installé.');
const mime = { '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html' };
const server = createServer(async (req, res) => {
  if (req.url === '/favicon.ico') { res.writeHead(204); res.end(); return; }
  try {
    const pathname = new URL(req.url, 'http://localhost').pathname;
    const file = resolve(web, `.${pathname === '/' ? '/index.html' : pathname}`);
    if (!file.startsWith(web + sep)) throw new Error('path');
    const body = await readFile(file);
    res.writeHead(200, { 'Content-Type': mime[extname(file)] || 'application/octet-stream' });
    res.end(body);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise((done) => server.listen(0, '127.0.0.1', done));
let browser;
let checks = 0;
const errors = [];
const check = async (name, action) => { await action(); checks++; console.log(`OK ${name}`); };
try {
  browser = await chromium.launch({ headless: true, executablePath });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.setDefaultTimeout(5000);
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.addInitScript(() => {
    localStorage.setItem('pesto.prefs.v1', JSON.stringify({ theme: 'dark', motion: 'reduced', bannerCompact: true }));
  });
  await check('Sonde native : seules les captures prêtes interrogent les animations finies', async () => {
    // Read the exact closed JavaScript resource embedded in Pesto.App; exercise it in an isolated Chromium document.
    const source = await readFile(resolve(here, '../../src/Pesto.App/DemoQualificationSnapshot.js'), 'utf8');
    const probe = await browser.newPage();
    try {
      const fixture = `http://127.0.0.1:${server.address().port}/snapshot-fixture`;
      await probe.route(fixture, route => route.fulfill({ contentType: 'text/html',
        body: '<!doctype html><main data-page="accueil"><section class="page"><h1>Accueil</h1></section></main>' }));
      await probe.goto(fixture);
      const counts = await probe.evaluate(`(() => {
        const snapshot = ${source.trim()};
        const root = document.documentElement;
        const nativeAnimations = document.getAnimations.bind(document);
        const nativeTiming = KeyframeEffect.prototype.getComputedTiming;
        let polls = 0, timings = 0;
        globalThis.__pestoNativeQualificationPending = () => [{ op: 'session.info', count: 1, ageMilliseconds: 4210 }];
        document.getAnimations = () => { polls++; return nativeAnimations(); };
        KeyframeEffect.prototype.getComputedTiming = function() { timings++; return nativeTiming.call(this); };
        const beforeReady = snapshot(true);
        root.dataset.ready = 'accueil';
        const infinite = root.animate([{opacity:1},{opacity:0.99}], {duration:60000, iterations:Infinity});
        const regular = snapshot(false);
        const normalCounts = [polls, timings];
        const busy = document.createElement('i');
        busy.setAttribute('aria-busy','true');
        document.querySelector('main').append(busy);
        const whileBusy = snapshot(true);
        const busyCounts = [polls, timings];
        busy.remove();
        const onlyInfinite = snapshot(true);
        const finite = root.animate([{opacity:1},{opacity:0.98}], {duration:60000});
        const both = snapshot(true);
        finite.finish();
        const finished = snapshot(true);
        delete globalThis.__pestoNativeQualificationPending;
        const withoutHook = snapshot(false);
        infinite.cancel(); finite.cancel();
        return {beforeReady, regular, whileBusy, onlyInfinite, both, finished, withoutHook, normalCounts, busyCounts, polls, timings};
      })()`);
      assert.equal(counts.beforeReady.ready, false);
      assert.ok(!Object.hasOwn(counts.beforeReady, 'finiteAnimationsRunning'));
      // Un écran qui ne devient jamais prêt doit nommer l’appel moteur qui le retient.
      assert.deepEqual(counts.beforeReady.pendingOps, [{ op: 'session.info', count: 1, ageMilliseconds: 4210 }]);
      assert.deepEqual(counts.whileBusy.pendingOps, [{ op: 'session.info', count: 1, ageMilliseconds: 4210 }]);
      assert.deepEqual(counts.withoutHook.pendingOps, []);
      assert.equal(counts.regular.ready, true);
      assert.ok(Object.hasOwn(counts.regular, 'preferences') && Object.hasOwn(counts.regular, 'draft'));
      assert.ok(!Object.hasOwn(counts.regular, 'finiteAnimationsRunning'));
      assert.deepEqual(counts.normalCounts, [0, 0]);
      assert.equal(counts.whileBusy.ready, false);
      assert.deepEqual(counts.busyCounts, [0, 0]);
      assert.equal(counts.onlyInfinite.finiteAnimationsRunning, false);
      assert.equal(counts.both.finiteAnimationsRunning, true);
      assert.equal(counts.finished.finiteAnimationsRunning, false);
      assert.ok(!Object.hasOwn(counts.both, 'preferences') && !Object.hasOwn(counts.both, 'draft'));
      assert.equal(counts.polls, 3);
      assert.ok(counts.timings >= 3);
      console.log(JSON.stringify({ kind: 'pesto.demo-snapshot-check', ordinary: counts.normalCounts,
        notReady: counts.busyCounts, readyCaptureAnimationQueries: counts.polls, readyCaptureTimingQueries: counts.timings }));
    } finally { await probe.close(); }
  });
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  const ready = (id) => page.waitForFunction((id) => document.documentElement.dataset.ready === id, id);
  const data = (op, args = {}) => page.evaluate(async ({ op, args }) => (await import('/js/simulation.js')).browserSimulation.invoke(op, args), { op, args });
  // Paramètres shows one section at a time: the demonstration button and the Animations field are in Interface.
  const openInterface = async () => {
    await page.locator('main .pr-nav-item[data-section="interface"]').click();
    await page.locator('main [data-section-panel="interface"]:not([hidden])').waitFor();
  };
  // The link of the navigation is #/parametres: from another screen it mounts Paramètres; from #/parametres?section=interface
  // it shows Annuaire in place, without remount. Either way, wait for Annuaire shown at the bare address on a ready screen.
  const openSettings = async () => {
    await page.locator('.nav-item[data-id="parametres"]').click();
    await page.waitForFunction(() => document.documentElement.dataset.ready === 'parametres' && location.hash === '#/parametres'
      && !!document.querySelector('main [data-section-panel="annuaire"]:not([hidden])'));
  };
  const controls = async () => {
    await openSettings();
    await openInterface();
    await page.getByRole('button', { name: 'Piloter la démonstration', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: 'Piloter la démonstration', exact: true });
    await dialog.waitFor(); return dialog;
  };
  const select = async (id, label, destination) => {
    const dialog = await controls();
    await dialog.getByLabel('Scénario de démonstration').selectOption(id);
    await dialog.getByRole('button', { name: 'Charger le scénario', exact: true }).click();
    const confirmation = page.getByRole('dialog', { name: `Charger « ${label} »`, exact: true });
    await confirmation.getByRole('button', { name: 'Charger le scénario', exact: true }).click();
    await ready(destination);
  };
  const restart = async () => {
    const dialog = await controls();
    await dialog.getByRole('button', { name: 'Redémarrage fictif', exact: true }).click();
    await page.getByRole('dialog', { name: 'Redémarrage fictif', exact: true }).getByRole('button', { name: 'Simuler le redémarrage', exact: true }).click();
    await page.waitForFunction(async () => (await import('/js/simulation.js')).browserSimulation.invoke('demo.status').then((s) => s.pendingRestart === 0));
    await ready('interventions');
  };
  await ready('accueil');
  await check('Démonstration et animations uniquement dans les paramètres, choix mémorisé', async () => {
    assert.equal(await page.locator('.demo-trigger, [name="interfaceMotion"]').count(), 0);
    await page.locator('.nav-item[data-id="parametres"]').click(); await ready('parametres');
    assert.equal(await page.locator('main .demo-trigger').count(), 1);
    assert.equal(await page.locator('.topbar .demo-trigger, .sim-banner button').count(), 0);
    await openInterface();
    await page.getByLabel('Animations', { exact: true }).selectOption('system');
    assert.equal(await page.locator('html').getAttribute('data-motion'), 'system');
    await page.reload(); await ready('parametres');
    // The section is part of the address: a reload shows Interface again.
    assert.equal(await page.evaluate(() => location.hash), '#/parametres?section=interface');
    assert.equal(await page.getByLabel('Animations', { exact: true }).inputValue(), 'system');
    await page.getByLabel('Animations', { exact: true }).selectOption('reduced');
    await page.locator('.nav-item[data-id="accueil"]').click(); await ready('accueil');
    assert.equal(await page.locator('.demo-trigger, [name="interfaceMotion"]').count(), 0);
  });
  await check('Bannière présente dès le démarrage malgré bannerCompact mémorisé', async () => {
    assert.equal(await page.locator('.sim-banner').isVisible(), true);
    assert.match(await page.locator('.sim-banner').innerText(), /DÉMONSTRATION/);
    assert.equal(await page.getByRole('button', { name: 'Masquer le bandeau', exact: true }).count(), 0);
  });
  await check('Le dialogue expose les huit scénarios et l’annulation conserve le monde', async () => {
    const before = await data('demo.status'); const dialog = await controls();
    assert.equal(await dialog.locator('option').count(), 8);
    await dialog.getByRole('button', { name: 'Remettre à zéro', exact: true }).click();
    await page.getByRole('dialog', { name: 'Remettre la démonstration à zéro', exact: true }).getByRole('button', { name: 'Annuler', exact: true }).click();
    assert.equal((await data('demo.status')).generation, before.generation);
  });
  await check('Scénario pendingRestart et reboot fictif manipulés depuis les boutons réels', async () => {
    await select('pendingRestart', 'Redémarrage en attente', 'interventions');
    assert.equal((await data('demo.status')).pendingRestart, 1);
    await restart();
    const receipt = (await data('receipts.list')).items[0];
    assert.equal(receipt.mode, 'simulation'); assert.equal(receipt.status, 'simulated'); assert.equal(receipt.restartRequired, false);
  });
  await check('Scénario partiel : reboot puis confirmation exacte du seul déplacement', async () => {
    await select('partialMove', 'Déplacement restant', 'interventions');
    const parent = (await data('receipts.list')).items[0];
    let dialog = await controls();
    assert.equal(await dialog.getByRole('button', { name: 'Préparer le déplacement restant fictif', exact: true }).isDisabled(), true);
    await dialog.getByRole('button', { name: 'Fermer', exact: true }).last().click();
    await restart(); dialog = await controls();
    await dialog.getByRole('button', { name: 'Préparer le déplacement restant fictif', exact: true }).click();
    const confirmation = page.getByRole('alertdialog', { name: 'Confirmer le déplacement fictif restant', exact: true });
    await confirmation.waitFor();
    assert.match(await confirmation.locator('.k-dlg-badge').innerText(), /Démonstration/);
    assert.equal(await confirmation.locator('.k-cw-typed').count(), 0);
    assert.equal(await confirmation.getByRole('button', { name: 'Simuler ce déplacement', exact: true }).isDisabled(), false);
    await confirmation.getByRole('button', { name: 'Simuler ce déplacement', exact: true }).click();
    await page.waitForFunction(async (id) => (await import('/js/simulation.js')).browserSimulation.invoke('receipts.get', { id }).then((r) => !!r.resolutionChildReceiptId), parent.id);
    const result = await data('receipts.get', { id: parent.id });
    assert.equal(result.code, '89'); assert.equal(result.status, 'pendingRestart');
    assert.equal((await data('receipts.get', { id: result.resolutionChildReceiptId })).parentReceiptId, parent.id);
  });
  await check('Reset confirmé réinitialise les reçus et conserve les IDs non réutilisables', async () => {
    const old = (await data('receipts.list')).items[0];
    const dialog = await controls();
    await dialog.getByRole('button', { name: 'Remettre à zéro', exact: true }).click();
    await page.getByRole('dialog', { name: 'Remettre la démonstration à zéro', exact: true }).getByRole('button', { name: 'Remettre à zéro', exact: true }).click();
    await ready('ajouter');
    assert.equal((await data('receipts.list')).items.length, 0);
    await select('partialMove', 'Déplacement restant', 'interventions');
    assert.notEqual((await data('receipts.list')).items[0].id, old.id);
  });
  await check('Un poste : ce poste par défaut, lu sans recherche ; autre poste par choix explicite, sans exemple', async () => {
    await select('joined', 'Poste déjà joint', 'unposte');
    const local = (await data('session.info')).computer;
    const target = page.locator('[data-form="target"]');
    assert.equal(await target.locator('input[value="local"]').isChecked(), true);
    assert.match(await target.innerText(), new RegExp(`Ce poste \\(${local}\\)`));
    assert.equal(await page.locator('[data-form="search"]').isHidden(), true);
    await page.locator('[data-zone="identity"] .kv-grid').waitFor();
    assert.match(await page.locator('[data-zone="identity"]').innerText(), new RegExp(local));
    await page.locator('[data-form="rename"]').waitFor();
    await target.locator('input[value="remote"]').check();
    const query = page.locator('[data-form="search"] [name="query"]');
    await query.waitFor();
    assert.equal(await query.getAttribute('placeholder'), null);
    assert.match(await page.locator('[data-zone="identity"]').innerText(), /Aucun poste sélectionné/);
    assert.equal(await page.locator('[data-form="rename"], [data-form="move"]').count(), 0);
    await target.locator('input[value="local"]').check();
    await page.locator('[data-zone="identity"] .kv-grid').waitFor();
    assert.equal(await page.locator('[data-form="search"]').isHidden(), true);
    assert.match(await page.locator('[data-zone="identity"]').innerText(), new RegExp(local));
  });
  await check('Un poste : ce poste hors domaine renvoie vers la jonction sans lecture de l’annuaire', async () => {
    await select('standard', 'Nouveau poste', 'ajouter');
    await page.locator('.nav-item[data-id="unposte"]').click(); await ready('unposte');
    assert.equal(await page.locator('[data-form="target"] input[value="local"]').isChecked(), true);
    await page.locator('[data-zone="identity"] [role="status"]').waitFor();
    assert.match(await page.locator('[data-zone="identity"]').innerText(), /n’est pas membre du domaine.*Ajouter ce PC au domaine/s);
    assert.equal(await page.locator('[data-form="rename"], [data-form="move"]').count(), 0);
    assert.equal(await page.locator('[data-zone="identity"] .kv-grid').count(), 0);
    await page.locator('.nav-item[data-id="plusieurspostes"]').click(); await ready('plusieurspostes');
    assert.equal(await page.locator('[data-form="search"] [name="query"]').getAttribute('placeholder'), null);
    assert.equal(await page.locator('[name="list"]').getAttribute('placeholder'), null);
  });
  await check('CSV : changement de site déplace, même site renomme sans déplacement', async () => {
    await select('joined', 'Poste déjà joint', 'unposte');
    await page.locator('.nav-item[data-id="plusieurspostes"]').click();
    await ready('plusieurspostes');
    await page.getByLabel('Fichier CSV de postes').setInputFiles({
      name: 'parcours-sites.csv', mimeType: 'text/csv',
      buffer: Buffer.from('name;type;site;service\nP111301PAINF001;P;lyon;INF\nS111301PAADM001;S;paris;ADM\n'),
    });
    await page.waitForFunction(() => document.querySelectorAll('[data-zone="sel-list"] [data-drop]').length === 2);
    await page.getByRole('button', { name: 'Ajouter à la file', exact: true }).click();
    await page.waitForFunction(async () => (await import('/js/simulation.js')).browserSimulation.invoke('queue.list').then((q) => q.items.length === 2));
    const queued = (await data('queue.list')).items;
    assert.deepEqual(queued.map((q) => q.kind), ['renameMove', 'rename']);
    assert.match(queued[0].targetOU, /^OU=Lyon,/);
    assert.match(queued[1].targetOU, /^OU=Paris,/);
    await page.getByRole('button', { name: 'Préparer le lot', exact: true }).click();
    await page.getByRole('button', { name: 'Exécuter le lot', exact: true }).click();
    const dialog = page.getByRole('alertdialog', { name: 'Confirmer l’exécution du lot', exact: true });
    await dialog.waitFor();
    assert.match(await dialog.locator('.k-dlg-badge').innerText(), /Démonstration/);
    assert.equal(await dialog.getByRole('button', { name: 'Exécuter le lot', exact: true }).isDisabled(), true);
    const batchId = await page.locator('[data-zone="batch"] .kv-grid .v.mono').innerText();
    await dialog.locator('.k-cw-typed input').fill(batchId);
    await dialog.getByRole('button', { name: 'Exécuter le lot', exact: true }).click();
    await page.waitForFunction(async () => (await import('/js/simulation.js')).browserSimulation.invoke('receipts.list').then((r) => r.items.length === 2));
    const receipts = (await data('receipts.list')).items;
    const moved = receipts.find((r) => r.computer === 'P111301PAINF001');
    const renamed = receipts.find((r) => r.computer === 'S111301PAADM001');
    assert.equal(String(moved.code), '77'); assert.equal(moved.kind, 'renameMove');
    assert.equal(String(renamed.code), '20'); assert.equal(renamed.kind, 'rename');
    assert.match((await data('computer.inspect', { computer: moved.newName })).ou, /^OU=Lyon,/);
    assert.match((await data('computer.inspect', { computer: renamed.newName })).ou, /^OU=Paris,/);
  });
  for (const [scenario, label, destination, status, code] of [
    ['denied', 'Droits insuffisants', 'unposte', 'refused', '5'],
    ['uncertain', 'Résultat incertain', 'plusieurspostes', 'uncertain', '97'],
  ]) await check(`Déplacement fictif ${scenario} : reçu du plan visible, identité et OU inchangées`, async () => {
    await select(scenario, label, destination);
    if (destination !== 'unposte') { await page.locator('.nav-item[data-id="unposte"]').click(); await ready('unposte'); }
    const computer = 'S111301PAADM001';
    const before = await data('computer.inspect', { computer });
    await pickRemote(page);
    await page.locator('[data-form="search"] [name="query"]').fill(computer);
    await page.locator('[data-form="search"] [name="query"]').press('Enter');
    await page.locator(`[data-pick="${computer}"]`).click();
    const form = page.locator('[data-form="rename"]');
    await form.locator('[name="site"]').selectOption('lyon');
    await form.locator('[name="service"] option[value="INF"]').waitFor({ state: 'attached' });
    await form.locator('[name="service"]').selectOption('INF');
    await form.locator('button[type="submit"]').click();
    await page.locator('[data-zone="rpreview"] .name').waitFor();
    await page.locator('[data-act="apply"]').click();
    const dialog = page.locator('.k-dlg-layer:not(.leaving) .k-dlg').last(); await dialog.waitFor();
    assert.match(await dialog.innerText(), /OU=Lyon,/);
    await dialog.locator('[data-id="confirm"]').click();
    const card = page.locator(`[data-zone="receipt"] [data-status="${status}"]`); await card.waitFor();
    assert.match(await card.innerText(), /OU=Lyon,/);
    const receipt = (await data('receipts.list')).items[0];
    assert.equal(receipt.kind, 'renameMove'); assert.equal(receipt.status, status); assert.equal(receipt.code, code);
    assert.match(receipt.targetOU, /^OU=Lyon,/);
    const after = await data('computer.inspect', { computer });
    for (const field of ['name', 'guid', 'ou']) assert.equal(after[field], before[field]);
    assert.equal(await page.locator('[data-act="domove"]').count(), 0);
  });
  await check('Deux fenêtres de navigateur ont des mondes distincts', async () => {
    const second = await browser.newPage();
    try {
      await second.goto(`http://127.0.0.1:${server.address().port}`);
      await second.waitForFunction(() => document.documentElement.dataset.ready === 'accueil');
      const other = await second.evaluate(async () => (await import('/js/simulation.js')).browserSimulation.invoke('demo.status'));
      assert.notEqual(other.instanceId, (await data('demo.status')).instanceId);
      assert.equal(other.scenario, 'standard');
    } finally { await second.close(); }
  });
  await check('Aucune erreur JavaScript ni ressource manquante', async () => assert.deepEqual(errors, []));
  console.log(`${checks}/${checks} contrôles DOM démo réussis (Chromium, sans qualification native Windows).`);
} finally {
  await browser?.close();
  await new Promise((done) => server.close(done));
}
