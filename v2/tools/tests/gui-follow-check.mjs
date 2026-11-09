// Browser checks for the follow-up screens (Interventions, Journal, Paramètres) against the actual Pesto ES modules and
// CSS, served on an ephemeral loopback port. Uses only an already-installed Chromium and Playwright.
// Example:
// PESTO_PLAYWRIGHT_MODULE=/absolute/node_modules/playwright/index.mjs PESTO_CHROMIUM_PATH=/usr/bin/google-chrome \
//   node v2/tools/tests/gui-follow-check.mjs
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
let checks = 0, failures = 0;
const check = async (name, fn) => {
  checks += 1;
  try { await fn(); console.log(`  ok   ${name}`); }
  catch (e) { failures += 1; console.error(`  FAIL ${name} — ${e.message}`); }
};
try {
  browser = await chromium.launch({ headless: true, executablePath });
  // 1000x700 is the reference small window where the audit saw the defects.
  const page = await browser.newPage({ viewport: { width: 1000, height: 700 }, colorScheme: 'light' });
  page.setDefaultTimeout(5000);
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.addInitScript(() => {
    if (!localStorage.getItem('pesto.prefs.v1')) {
      localStorage.setItem('pesto.prefs.v1', JSON.stringify({ theme: 'system', motion: 'reduced' }));
    }
  });
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  const ready = (id) => page.waitForFunction((id) => document.documentElement.dataset.ready === id, id);
  await ready('accueil');
  const go = async (id) => { await page.locator(`.nav-item[data-id="${id}"]`).click(); await ready(id); };
  const liveText = () => page.evaluate(() => [...document.querySelectorAll('[aria-live]')].map((el) => el.textContent).join(' | '));

  await check('Journal : recherche et niveau occupent chacun la moitié de la carte', async () => {
    await go('journal');
    const card = await page.locator('form[data-form="q"]').evaluate((el) => el.getBoundingClientRect().width);
    for (const sel of ['[name="query"]', '[name="level"]']) {
      const w = await page.locator(`form[data-form="q"] ${sel}`).evaluate((el) => el.getBoundingClientRect().width);
      assert.ok(w > card * 0.4, `${sel} ${w}px pour une carte de ${card}px`);
    }
  });

  // One simulated rename gives Interventions a receipt to filter and re-read.
  await go('unposte');
  await pickRemote(page);
  const search = page.locator('form[data-form="search"] [name="query"]');
  await search.fill('P111301PAINF001'); await search.press('Enter');
  await page.locator('[data-pick="P111301PAINF001"]').click();
  await page.locator('form[data-form="rename"] button[type="submit"]').click();
  await page.locator('[data-act="apply"]').click();
  await page.locator('.k-dlg').waitFor();
  await page.locator('.k-dlg-foot button', { hasText: 'Confirmer' }).click();
  await page.locator('.k-dlg').waitFor({ state: 'detached' });
  await page.locator('main .receipt, main [data-receipt]').first().waitFor().catch(() => {});

  await check('Interventions : le filtre occupe toute la largeur de la carte', async () => {
    await go('interventions');
    const card = await page.locator('form[data-form="q"]').evaluate((el) => el.getBoundingClientRect().width);
    const w = await page.locator('form[data-form="q"] [name="query"]').evaluate((el) => el.getBoundingClientRect().width);
    assert.ok(w > card * 0.9, `filtre ${w}px pour une carte de ${card}px`);
  });

  const filtered = async (value) => {
    const q = page.locator('form[data-form="q"] [name="query"]');
    await q.fill(value); await q.press('Enter');
    await page.waitForFunction(() => !document.querySelector('[data-zone="list"]').hasAttribute('aria-busy'));
    await page.waitForTimeout(450);
    await page.waitForFunction(() => !document.querySelector('[data-zone="list"]').hasAttribute('aria-busy'));
    return page.locator('[data-zone="list"] [data-receipt]').count();
  };
  await check('Interventions : les libellés affichés filtrent (Simulé, simule, Renommage, Redémarrage)', async () => {
    assert.equal(await filtered(''), 1);
    assert.equal(await filtered('Simulé'), 1);
    assert.equal(await filtered('simule'), 1);
    assert.equal(await filtered('simulated'), 1);
    assert.equal(await filtered('Renommage'), 1);
    assert.equal(await filtered('P111301PAINF001'), 1);
    assert.equal(await filtered('Redémarrage'), 0);
    assert.equal(await filtered('Jonction'), 0);
    assert.equal(await filtered('Refusé'), 0);
    assert.equal(await filtered(''), 1);
  });

  await check('Interventions : libellés résolus par l’interface face à un moteur qui ne compare que les codes', async () => {
    // Same matching as LiveBackend.ReceiptsList (computer, newName, status code, id, message): no French label, no kind.
    await page.evaluate(async () => {
      const sim = (await import('/js/simulation.js')).browserSimulation;
      sim.codesOnly = sim.invoke;
      sim.invoke = async (op, args) => {
        if (op !== 'receipts.list') return sim.codesOnly(op, args);
        const all = await sim.codesOnly(op, {});
        const q = String(args?.query ?? '').toLowerCase();
        return { ...all, items: all.items.filter((r) => `${r.computer} ${r.newName} ${r.status} ${r.id} ${r.message ?? ''}`.toLowerCase().includes(q)) };
      };
    });
    try {
      assert.equal(await filtered('Simulé'), 1);
      assert.equal(await filtered('Renommage'), 1);
      assert.equal(await filtered('renomm'), 1);
      assert.equal(await filtered('Déplacement'), 0);
      assert.equal(await filtered('Incertain'), 0);
      assert.equal(await filtered('P111301PAINF001'), 1);
    } finally {
      await page.evaluate(async () => { const sim = (await import('/js/simulation.js')).browserSimulation; sim.invoke = sim.codesOnly; });
      await filtered('');
    }
  });

  await check('Interventions : « Détail moteur » garde le focus et dit le résultat de la relecture', async () => {
    const before = await page.locator('[data-zone="list"] [data-receipt]').first().innerText();
    await page.locator('[data-zone="list"] [data-act="detail"]').first().focus();
    await page.keyboard.press('Enter');
    const status = page.locator('[data-zone="list"] [data-receipt] [data-verification]');
    await status.waitFor();
    assert.equal((await status.innerText()).trim(), 'Reçu relu auprès du moteur : aucun changement.');
    assert.equal(await page.evaluate(() => document.activeElement?.dataset?.act ?? document.activeElement?.tagName), 'detail');
    assert.equal(await page.evaluate(() => !!document.activeElement.closest('[data-receipt]')?.isConnected), true);
    assert.ok((await page.locator('[data-zone="list"] [data-receipt]').first().innerText()).startsWith(before.trim().slice(0, 30)));
    // A second Enter must work from the restored focus, not from <body>.
    await page.locator('[data-zone="list"] [data-verification]').evaluate((el) => el.remove());
    await page.keyboard.press('Enter');
    await status.waitFor();
    assert.equal(await page.evaluate(() => document.activeElement?.dataset?.act), 'detail');
  });

  // A slow engine lets Chromium (and WebView2) move focus off the disabled button to <body> before the answer arrives.
  const slowReceiptsGet = (ms) => page.evaluate(async (ms) => {
    const sim = (await import('/js/simulation.js')).browserSimulation;
    sim.fastInvoke ??= sim.invoke;
    sim.invoke = ms ? async (op, args) => { if (op === 'receipts.get') await new Promise((r) => setTimeout(r, ms)); return sim.fastInvoke(op, args); } : sim.fastInvoke;
  }, ms);
  const focusedAct = () => page.evaluate(() => `${document.activeElement?.tagName}:${document.activeElement?.dataset?.act ?? ''}`);

  await check('Interventions : « Détail moteur » garde le focus quand le moteur met du temps à répondre', async () => {
    await slowReceiptsGet(400);
    try {
      await page.locator('[data-zone="list"] [data-verification]').evaluate((el) => el.remove()).catch(() => {});
      await page.locator('[data-zone="list"] [data-act="detail"]').first().focus();
      await page.keyboard.press('Enter');
      await page.waitForTimeout(150);
      assert.equal(await page.locator('[data-zone="list"] [data-receipt]').first().getAttribute('aria-busy'), 'true');
      const status = page.locator('[data-zone="list"] [data-receipt] [data-verification]');
      await status.waitFor();
      assert.equal((await status.innerText()).trim(), 'Reçu relu auprès du moteur : aucun changement.');
      assert.equal(await focusedAct(), 'BUTTON:detail');
    } finally { await slowReceiptsGet(0); }
  });

  await check('Interventions : la relecture lente ne reprend pas le focus déplacé ailleurs entre-temps', async () => {
    await slowReceiptsGet(400);
    try {
      await page.locator('[data-zone="list"] [data-verification]').evaluate((el) => el.remove()).catch(() => {});
      await page.locator('[data-zone="list"] [data-act="detail"]').first().focus();
      await page.keyboard.press('Enter');
      await page.waitForTimeout(100);
      await page.locator('form[data-form="q"] [name="query"]').focus();
      await page.locator('[data-zone="list"] [data-receipt] [data-verification]').waitFor();
      assert.equal(await page.evaluate(() => document.activeElement?.getAttribute('name')), 'query');
    } finally { await slowReceiptsGet(0); }
  });

  // Last screen visited: the unsaved sites draft would otherwise ask before leaving.
  await check('Paramètres : erreur de format des sites visible, champ focalisé et annoncée', async () => {
    await go('parametres');
    await page.locator('form[data-form="settings"].k-form-live').waitFor();
    const sites = page.locator('[name="sites"]');
    await page.waitForFunction(() => document.querySelector('[name="sites"]')?.value.length > 0);
    await sites.click(); await page.keyboard.press('Control+End'); await page.keyboard.type('\nligne invalide');
    await page.locator('main').evaluate((m) => { m.scrollTop = 0; });
    await page.locator('[data-act="save"]').click();
    const msg = page.locator('[data-slot="sites-msg"]');
    await msg.waitFor({ state: 'visible' });
    const text = (await msg.innerText()).trim();
    assert.ok(text.length > 0);
    // main may scroll smoothly: wait for the message to settle inside the visible part of main.
    const inView = () => msg.evaluate((el) => {
      const r = el.getBoundingClientRect(), m = document.querySelector('main').getBoundingClientRect();
      return r.top >= m.top - 1 && r.bottom <= m.bottom + 1;
    });
    const deadline = Date.now() + 2000;
    while (!await inView() && Date.now() < deadline) await page.waitForTimeout(50);
    assert.equal(await inView(), true, 'message hors écran');
    assert.equal(await sites.evaluate((el) => document.activeElement === el), true);
    assert.equal((await liveText()).split(text).length - 1, 1, 'erreur non annoncée, ou annoncée plusieurs fois');
    assert.equal(await page.locator('.k-dlg').count(), 0);
  });

  await check('Aucune exception JavaScript ni erreur de console', async () => assert.deepEqual(errors, []));
} finally {
  await browser?.close();
  await new Promise((done) => server.close(done));
}
console.log(`\n${checks - failures}/${checks} contrôles de suivi réussis (simulation Chromium, sans qualification native/AD).`);
process.exitCode = failures ? 1 : 0;
