// Browser checks for Ajouter ce PC and Noms disponibles against the actual Pesto ES modules, served on an ephemeral
// loopback port: failed site read (« Indisponible » + retry), the screen locked after an accepted join, « Autre nom »
// walking through the free names, and the interventions filter matching the French labels (browser simulation).
// Uses only an already-installed Chromium and Playwright; never installs/downloads a browser or calls Windows/AD.
// Example:
// PESTO_PLAYWRIGHT_MODULE=/absolute/node_modules/playwright/index.mjs PESTO_CHROMIUM_PATH=/usr/bin/google-chrome \
//   node v2/tools/tests/gui-join-check.mjs
// These checks cover browser simulation, not native WebView2, UIA, production bridge or AD qualification.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, extname, isAbsolute, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

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
let checks = 0, failures = 0;
const check = async (name, fn) => {
  checks += 1;
  try { await fn(); console.log(`  ok   ${name}`); }
  catch (e) { failures += 1; console.error(`  FAIL ${name} — ${e.message}`); }
};
const errors = [];
// Each scenario gets its own page, hence its own in-memory simulation.
async function openPage() {
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 }, colorScheme: 'light' });
  page.setDefaultTimeout(5000);
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.addInitScript(() => {
    if (!localStorage.getItem('pesto.prefs.v1')) localStorage.setItem('pesto.prefs.v1', JSON.stringify({ theme: 'system', motion: 'reduced' }));
  });
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  const ready = (id) => page.waitForFunction((id) => document.documentElement.dataset.ready === id, id);
  await ready('accueil');
  const go = async (id) => { await page.locator(`.nav-item[data-id="${id}"]`).click(); await ready(id); };
  const sim = (op, args = {}) => page.evaluate(async ({ op, args }) => (await import('/js/simulation.js')).browserSimulation.invoke(op, args), { op, args });
  return { page, go, sim };
}
const optionTexts = (select) => select.evaluate((s) => [...s.options].map((o) => o.text));

try {
  browser = await chromium.launch({ headless: true, executablePath });

  for (const [id, form] of [['ajouter', 'join'], ['noms', 'preview']]) {
    const { page, go, sim } = await openPage();
    try {
      await sim('demo.scenario', { id: 'directoryOffline', confirmed: true });
      await go(id);
      const host = page.locator(`form[data-form="${form}"]`);
      const site = host.locator('[name="site"]'), service = host.locator('[name="service"]');
      const retry = host.locator('[data-retry-sites]');
      await check(`${id} : échec de lecture des sites, saisie libre conservée et bouton Réessayer`, async () => {
        await retry.waitFor();
        assert.deepEqual(await optionTexts(site), ['Indisponible']);
        assert.equal(await service.inputValue(), '');
        assert.equal(await host.locator('[name="service"] + datalist option').count(), 0);
        assert.equal(await service.isEnabled(), true);
        assert.equal(await retry.getAttribute('type'), 'button');
        assert.match(await retry.innerText(), /Réessayer le chargement des sites/);
        assert.match(await host.locator('.k-field[data-name="site"] .k-msg').innerText(), /annuaire indisponible/);
      });
      await check(`${id} : Réessayer relit les sites et services, sans quitter l’écran`, async () => {
        await sim('demo.scenario', { id: 'standard', confirmed: true });
        await retry.click();
        await page.waitForFunction((f) => document.querySelector(`form[data-form="${f}"] [name="service"]`)?.value === 'INF', form);
        assert.deepEqual(await optionTexts(site), ['Paris (PA)', 'Lyon (LY)']);
        assert.equal(await host.locator('[data-retry-sites]').count(), 0);
        assert.equal(await host.locator('.k-field[data-name="site"] .k-msg').isHidden(), true);
        assert.equal(await page.evaluate((f) => document.activeElement === document.querySelector(`form[data-form="${f}"] [name="site"]`), form), true);
      });
    } finally { await page.close(); }
  }

  {
    const { page, go, sim } = await openPage();
    try {
      await check('Simulation : capacité de jonction active avant la jonction', async () => {
        const info = await sim('session.info');
        assert.equal(info.capabilities.find((c) => c.id === 'join').enabled, true);
      });
      await go('ajouter');
      const add = page.locator('[data-act="add"]');
      const submit = page.locator('form[data-form="join"] button[type="submit"]');
      const identity = page.locator('[data-zone="identity"]');
      await page.waitForFunction(() => document.querySelector('form[data-form="join"] [name="service"]')?.value === 'INF');
      await check('Ajouter : « Autre nom » propose à chaque clic un nom libre différent', async () => {
        await submit.click();
        const name = page.locator('main [data-zone="preview"] .name-preview .name');
        await name.waitFor();
        const seen = [await name.innerText()];
        for (let n = 0; n < 3; n++) {
          await page.locator('[data-zone="preview"] [data-act="other"]').click();
          await page.waitForFunction((prev) => {
            const el = document.querySelector('main [data-zone="preview"] .name-preview .name');
            return el && el.textContent !== prev;
          }, seen.at(-1));
          seen.push(await name.innerText());
        }
        assert.deepEqual(seen, ['P111301PAINF002', 'P111301PAINF003', 'P111301PAINF004', 'P111301PAINF005']);
      });
      await check('Ajouter : après la jonction acceptée, ajout et calcul verrouillés avec un message clair', async () => {
        await add.click();
        await page.locator('.k-dlg-foot button', { hasText: 'Confirmer' }).click();
        await page.locator('[data-zone="receipt"] [data-receipt][data-status="simulated"]').waitFor();
        assert.equal(await add.isDisabled(), true);
        assert.equal(await submit.isDisabled(), true);
        assert.match(await page.locator('[data-slot="add-hint"]').innerText(), /Jonction déjà demandée pour ce poste : redémarrez, puis vérifiez dans Interventions\./);
      });
      await check('Ajouter : carte Identité relue après la jonction', async () => {
        await page.waitForFunction(() => /P111301PAINF005/.test(document.querySelector('[data-zone="identity"]').textContent));
        assert.doesNotMatch(await identity.innerText(), /NOUVEAU-PC/);
      });
      await check('Ajouter : un calcul forcé n’appelle pas le moteur et le reçu de succès reste affiché', async () => {
        await page.evaluate(() => document.querySelector('form[data-form="join"]').requestSubmit());
        await page.waitForTimeout(300);
        assert.equal(await page.locator('[data-zone="preview"] .name-preview').count(), 0);
        assert.equal(await add.isDisabled(), true);
        assert.equal(await page.locator('[data-zone="receipt"] [data-receipt][data-status="simulated"]').count(), 1);
      });
      await check('Simulation : capacité de jonction désactivée une fois le poste joint', async () => {
        const join = (await sim('session.info')).capabilities.find((c) => c.id === 'join');
        assert.equal(join.enabled, false);
        assert.match(join.reason, /déjà rejoint le domaine/);
      });
      await check('Simulation : le filtre des reçus trouve les libellés affichés (statut, type, sans accents)', async () => {
        for (const query of ['Simulé', 'simu', 'simule', 'simulated', 'Jonction', 'jonc', 'join', 'P111301PAINF005']) {
          assert.equal((await sim('receipts.list', { query })).items.length, 1, query);
        }
        assert.equal((await sim('receipts.list', { query: 'Renommage' })).items.length, 0);
        assert.equal((await sim('receipts.list', {})).items.length, 1);
      });
      await check('Simulation : le filtre trouve « Renommage » et « Déplacement » sur les reçus correspondants', async () => {
        const preview = await sim('names.preview', { type: 'S', site: 'paris', service: 'ADM', computer: 'S111301PAADM001' });
        const plan = await sim('operation.prepare', { kind: 'rename', computer: 'S111301PAADM001', previewId: preview.previewId });
        await sim('operation.execute', { planId: plan.planId, confirmationName: plan.confirmationName });
        const movePlan = await sim('operation.prepare', { kind: 'move', computer: 'V111301LYINF001', targetOU: 'paris' });
        await sim('operation.execute', { planId: movePlan.planId, confirmationName: movePlan.confirmationName });
        for (const [query, count] of [['Renommage', 1], ['rename', 1], ['deplacement', 1], ['Déplacement', 1], ['Simulé', 3]]) {
          assert.equal((await sim('receipts.list', { query })).items.length, count, query);
        }
      });
    } finally { await page.close(); }
  }

  {
    const { page, go, sim } = await openPage();
    try {
      await go('noms');
      await page.waitForFunction(() => document.querySelector('form[data-form="preview"] [name="service"]')?.value === 'INF');
      await check('Noms : « Un autre nom » parcourt les noms libres au lieu d’alterner entre deux', async () => {
        await page.locator('form[data-form="preview"] button[type="submit"]').click();
        const name = page.locator('main [data-zone="result"] .name-preview .name');
        await name.waitFor();
        const seen = [await name.innerText()];
        for (let n = 0; n < 3; n++) {
          await page.locator('[data-zone="result"] [data-act="other"]').click();
          await page.waitForFunction((prev) => {
            const el = document.querySelector('main [data-zone="result"] .name-preview .name');
            return el && el.textContent !== prev;
          }, seen.at(-1));
          seen.push(await name.innerText());
        }
        assert.deepEqual(seen, ['P111301PAINF002', 'P111301PAINF003', 'P111301PAINF004', 'P111301PAINF005']);
      });
      await check('Simulation : après le dernier nom libre, « Autre nom » repart du premier', async () => {
        const settings = await sim('settings.get');
        await sim('settings.save', { ...settings, namingPattern: '{type}{prefix}{site}{service}{number:1}' });
        const names = [];
        for (let n = 0; n < 10; n++) names.push((await sim('names.preview', { type: 'P', site: 'paris', service: 'LOG', alternative: n > 0 || undefined })).name);
        assert.deepEqual(names, ['P111301PALOG1', 'P111301PALOG2', 'P111301PALOG3', 'P111301PALOG4', 'P111301PALOG5',
          'P111301PALOG6', 'P111301PALOG7', 'P111301PALOG8', 'P111301PALOG9', 'P111301PALOG1']);
      });
      await check('Simulation : le mode aléatoire reste aléatoire et ne repropose jamais le nom précédent', async () => {
        const settings = await sim('settings.get');
        await sim('settings.save', { ...settings, namingPattern: '{type}{prefix}{site}{service}{number:3}', randomNames: true });
        const names = [];
        for (let n = 0; n < 12; n++) names.push((await sim('names.preview', { type: 'P', site: 'lyon', service: 'ADM', alternative: n > 0 || undefined })).name);
        for (let n = 1; n < names.length; n++) assert.notEqual(names[n], names[n - 1]);
        const sequential = names.every((name, n) => n === 0 || Number(name.slice(-3)) === Number(names[n - 1].slice(-3)) + 1);
        assert.equal(sequential, false, 'tirage aléatoire attendu');
      });
    } finally { await page.close(); }
  }

  await check('Aucune exception JavaScript ni erreur de console', async () => assert.deepEqual(errors, []));
} finally {
  await browser?.close();
  await new Promise((done) => server.close(done));
}
console.log(`\n${checks - failures}/${checks} contrôles jonction et noms réussis (simulation Chromium, sans qualification native/AD).`);
process.exitCode = failures ? 1 : 0;
