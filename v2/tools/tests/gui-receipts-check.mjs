// Browser checks for receipts, Accueil read failures, operator wording and stale search results, against the actual
// Pesto ES modules and CSS served on an ephemeral loopback port. Receipt checks run with motion 'full' (the default
// preference): under 'reduced' motion the CSS forces `.reveal` visible and hides a receipt left at opacity 0.
// Example:
// PESTO_PLAYWRIGHT_MODULE=/absolute/node_modules/playwright/index.mjs PESTO_CHROMIUM_PATH=/usr/bin/google-chrome \
//   node v2/tools/tests/gui-receipts-check.mjs
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
const web = resolve(process.env.PESTO_WEB_ROOT || resolve(here, '../../web'));
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
  catch (e) { failures += 1; console.error(`  FAIL ${name} — ${e.message.split('\n')[0]}`); }
};
const text = async (locator) => (await locator.innerText()).replace(/\s+/g, ' ').trim();
const RAW_CODES = /\b(pendingRestart|simulated|succeeded|uncertain|refused|rename|renameMove|ready)\b/;

try {
  browser = await chromium.launch({ headless: true, executablePath });
  // Fresh page = fresh in-memory simulation world.
  const open = async (motion = 'full') => {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, colorScheme: 'light' });
    page.setDefaultTimeout(6000);
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    await page.addInitScript((motion) => {
      localStorage.setItem('pesto.prefs.v1', JSON.stringify({ theme: 'light', motion }));
    }, motion);
    await page.goto(`http://127.0.0.1:${server.address().port}`);
    const ready = (id) => page.waitForFunction((id) => document.documentElement.dataset.ready === id, id);
    await ready('accueil');
    const go = async (id) => { await page.locator(`.nav-item[data-id="${id}"]`).click(); await ready(id); };
    return { page, errors, ready, go };
  };
  const failOps = (page, ops) => page.evaluate(async (ops) => {
    const { browserSimulation: sim } = await import('/js/simulation.js');
    const orig = sim.__orig || (sim.__orig = sim.invoke);
    sim.invoke = async (op, args) => {
      if (ops.includes(op)) throw Object.assign(new Error(`Panne injectée : ${op}.`), { code: 'test.inject' });
      return orig(op, args);
    };
  }, ops);
  const restoreOps = (page) => page.evaluate(async () => {
    const { browserSimulation: sim } = await import('/js/simulation.js');
    if (sim.__orig) sim.invoke = sim.__orig;
  });
  const receiptVisible = async (page, zone) => {
    const card = page.locator(`[data-zone="${zone}"] .receipt-card`).first();
    await card.waitFor({ state: 'attached' });
    await page.locator(`[data-zone="${zone}"]`).scrollIntoViewIfNeeded();
    await page.waitForTimeout(1200); // longer than any entrance animation
    const info = await card.evaluate((c) => ({ opacity: getComputedStyle(c).opacity, visible: c.checkVisibility({ opacityProperty: true }) }));
    assert.equal(info.opacity, '1', `opacité calculée du reçu = ${info.opacity}`);
    assert.equal(info.visible, true, 'reçu invisible (checkVisibility)');
    assert.ok((await text(card)).length > 20, 'corps du reçu vide');
  };
  const renameOnUnposte = async (page) => {
    await pickRemote(page);
    await page.locator('[data-form="search"] [name="query"]').fill('111301');
    await page.locator('[data-form="search"] [name="query"]').press('Enter');
    await page.locator('[data-zone="results"] [data-pick="P111301PAINF001"]').click();
    await page.locator('[data-form="rename"] button[type="submit"]').click();
    await page.locator('[data-zone="rpreview"] .name-preview').waitFor();
    await page.locator('[data-zone="rename"] [data-act="apply"]').click();
    const dlg = page.locator('.k-dlg'); await dlg.waitFor();
    await dlg.locator('.k-dlg-foot button', { hasText: 'Confirmer' }).click();
    await dlg.waitFor({ state: 'hidden' });
    await page.locator('[data-zone="receipt"] .receipt-card').waitFor({ state: 'attached' });
  };

  await check('Ajouter : reçu de jonction simulée visible (opacité 1, mouvement complet)', async () => {
    const { page, errors, go } = await open('full');
    await go('ajouter');
    const join = page.locator('form[data-form="join"]');
    await join.locator('[name="site"]').selectOption('paris');
    await join.locator('[name="service"] + datalist option[value="INF"]').waitFor({ state: 'attached' });
    await join.locator('[name="service"]').fill('INF');
    await join.locator('button[type="submit"]').click();
    await page.locator('main .name-preview .name').waitFor();
    await page.locator('[data-act="add"]').click();
    const dlg = page.locator('.k-dlg'); await dlg.waitFor();
    await dlg.locator('[data-id="confirm"]').click(); await dlg.waitFor({ state: 'hidden' });
    await receiptVisible(page, 'receipt');
    assert.deepEqual(errors, []);
    await page.close();
  });

  await check('Un poste : reçu de renommage visible, recherche marquée périmée, en-tête Identité conservé sur erreur', async () => {
    const { page, errors, go } = await open('full');
    await go('unposte');
    await renameOnUnposte(page);
    await receiptVisible(page, 'receipt');
    const results = page.locator('[data-zone="results"]');
    assert.equal(await results.locator('[data-pick]').count(), 0, 'l’ancien nom reste proposé après le renommage');
    assert.match(await text(results), /relancez la recherche/);
    // A failed identity read keeps the card frame (header) instead of a bare error line.
    await pickRemote(page);
    await page.locator('[data-form="search"] [name="query"]').fill('111301');
    await page.locator('[data-form="search"] [name="query"]').press('Enter');
    await results.locator('[data-pick]').first().waitFor();
    await failOps(page, ['computer.inspect']);
    await results.locator('[data-pick]').first().click();
    const identity = page.locator('[data-zone="identity"]');
    await identity.getByRole('alert').waitFor();
    assert.equal(await identity.locator('.card-head h3').innerText(), 'Identité lue');
    await restoreOps(page);
    assert.deepEqual(errors, []);
    await page.close();
  });

  await check('Accueil : libellé français du statut dans la chronologie, aucun code interne', async () => {
    const { page, go } = await open('reduced');
    await page.evaluate(async () => {
      const { browserSimulation } = await import('/js/simulation.js');
      await browserSimulation.invoke('demo.scenario', { id: 'pendingRestart', confirmed: true });
    });
    await go('journal'); await go('accueil');
    const activity = await text(page.locator('[data-zone="activity"]'));
    assert.match(activity, /Redémarrage en attente/);
    assert.doesNotMatch(activity, RAW_CODES, activity.slice(0, 200));
    await page.close();
  });

  await check('Accueil : échec de lecture → indicateurs « — », aucun toast « relu », zone non occupée', async () => {
    const { page, go, ready } = await open('reduced');
    await failOps(page, ['dashboard.read']);
    await go('journal');
    await page.locator('.nav-item[data-id="accueil"]').click();
    await ready('accueil'); // aria-busy left set would prevent data-ready
    const kpis = page.locator('[data-zone="kpis"]');
    assert.equal(await kpis.getAttribute('aria-busy'), null);
    const values = await page.locator('[data-kpi]').evaluateAll((els) => els.map((e) => e.textContent.trim()));
    assert.deepEqual(values, ['—', '—', '—', '—']);
    await page.locator('[data-act="refresh"]').click();
    await page.waitForTimeout(400);
    const toasts = await page.evaluate(() => [...document.querySelectorAll('.toast, [class*="toast"]')].map((t) => t.innerText).join(' | '));
    assert.doesNotMatch(toasts, /Tableau de bord relu/);
    assert.equal(await kpis.getAttribute('aria-busy'), null);
    // A later successful read shows figures and confirms it.
    await restoreOps(page);
    await page.locator('[data-act="refresh"]').click();
    await page.waitForFunction(() => document.body.innerText.includes('Tableau de bord relu.'));
    await page.waitForFunction(() => /\d/.test(document.querySelector('[data-kpi="Postes suivis"]').textContent));
    await page.close();
  });

  await check('Accueil : échec pendant un comptage animé (mouvement complet) → aucun ancien chiffre réécrit', async () => {
    const { page, errors } = await open('full');
    // The refresh starts a ~1.2 s count; the failing read lands while it is still animating.
    await page.locator('[data-act="refresh"]').click();
    await page.waitForTimeout(150);
    await failOps(page, ['dashboard.read']);
    await page.locator('[data-act="refresh"]').click();
    await page.locator('[data-zone="activity"] h3', { hasText: 'Lecture impossible' }).waitFor();
    await page.waitForTimeout(2000);
    const values = await page.locator('[data-kpi]').evaluateAll((els) => els.map((e) => e.textContent.trim()));
    assert.deepEqual(values, ['—', '—', '—', '—']);
    await restoreOps(page);
    assert.deepEqual(errors, []);
    await page.close();
  });

  await check('Un poste : échec d’exécution après confirmation → recherche marquée périmée ; annulation → résultats conservés', async () => {
    const { page, errors, go } = await open('full');
    await go('unposte');
    const results = page.locator('[data-zone="results"]');
    const startRename = async () => {
      await pickRemote(page);
      await page.locator('[data-form="search"] [name="query"]').fill('111301');
      await page.locator('[data-form="search"] [name="query"]').press('Enter');
      await results.locator('[data-pick="P111301PAINF001"]').click();
      await page.locator('[data-form="rename"] button[type="submit"]').click();
      await page.locator('[data-zone="rpreview"] .name-preview').waitFor();
      await page.locator('[data-zone="rename"] [data-act="apply"]').click();
      const dlg = page.locator('.k-dlg'); await dlg.waitFor();
      return dlg;
    };
    // Nothing sent: the listed names stay valid.
    let dlg = await startRename();
    await dlg.locator('.k-dlg-foot button', { hasText: 'Annuler' }).click();
    await dlg.waitFor({ state: 'hidden' });
    assert.ok(await results.locator('[data-pick]').count() > 0, 'résultats retirés alors que rien n’a été envoyé');
    // Execute sent, answer lost: the rename may have happened.
    await page.locator('[data-zone="rpreview"] .name-preview').waitFor();
    await failOps(page, ['operation.execute']);
    await page.locator('[data-zone="rename"] [data-act="apply"]').click();
    dlg = page.locator('.k-dlg'); await dlg.waitFor();
    await dlg.locator('.k-dlg-foot button', { hasText: 'Confirmer' }).click();
    await dlg.waitFor({ state: 'hidden' });
    await page.locator('[data-zone="rpreview"] [role="alert"]').waitFor();
    assert.equal(await results.locator('[data-pick]').count(), 0, 'l’ancien nom reste proposé après un échec d’exécution');
    assert.match(await text(results), /relancez la recherche/);
    await restoreOps(page);
    assert.deepEqual(errors, []);
    await page.close();
  });

  await check('Plusieurs postes : libellés français de la file et du lot, reçus visibles, recherche périmée après exécution', async () => {
    const { page, errors, go } = await open('full');
    await go('plusieurspostes');
    await pickRemote(page);
    await page.locator('[data-form="search"] [name="query"]').fill('111301');
    await page.locator('[data-form="search"] [name="query"]').press('Enter');
    const picks = page.locator('[data-zone="results"] [data-pick]');
    await picks.first().waitFor();
    await picks.nth(0).click(); await picks.nth(2).click();
    await page.locator('[data-act="addqueue"]').click();
    const queue = page.locator('[data-zone="queue-list"]');
    await queue.locator('[data-qdrop]').nth(1).waitFor();
    const queueText = await text(queue);
    assert.match(queueText, /Renommage/); assert.match(queueText, /Prêt/);
    assert.doesNotMatch(queueText, RAW_CODES, queueText.slice(0, 200));
    await page.locator('[data-act="prepare"]').click();
    const batch = page.locator('[data-zone="batch"]');
    await batch.locator('.result-list li').first().waitFor();
    const batchText = await text(batch);
    assert.match(batchText, /Renommage/);
    assert.doesNotMatch(batchText, RAW_CODES, batchText.slice(0, 200));
    await page.locator('[data-act="execute"]').click();
    const dlg = page.locator('.k-dlg'); await dlg.waitFor();
    const typed = dlg.locator('.k-cw-typed input');
    if (await typed.count()) { await typed.click(); await page.keyboard.type((await dlg.locator('.k-cw-target b').innerText()).trim()); }
    await dlg.locator('.k-dlg-foot button', { hasText: 'Exécuter' }).click();
    await dlg.waitFor({ state: 'hidden' });
    await receiptVisible(page, 'receipt');
    const results = page.locator('[data-zone="results"]');
    assert.equal(await results.locator('[data-pick]').count(), 0, 'les anciens noms restent sélectionnables après le lot');
    assert.match(await text(results), /relancez la recherche/);
    assert.deepEqual(errors, []);
    await page.close();
  });
} finally {
  await browser?.close();
  server.close();
}
console.log(`${checks - failures}/${checks} contrôles reçus, accueil et libellés réussis`);
if (failures) process.exit(1);
