// Behavioral browser checks against the actual Pesto ES modules and CSS, served on an ephemeral loopback port.
// Uses only an already-installed Chromium and Playwright; never installs/downloads a browser or calls Windows/AD.
// Example:
// PESTO_PLAYWRIGHT_MODULE=/absolute/node_modules/playwright/index.mjs PESTO_CHROMIUM_PATH=/usr/bin/google-chrome \
//   node v2/tools/tests/web-dom-check.mjs
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
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, colorScheme: 'light' });
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
  assert.equal(await page.locator('.mode-chip').getAttribute('data-mode'), 'simulation');
  await check('deux fenêtres : seule la décoration inactive se fige et reprend au même point', async () => {
    const front = await browser.newPage();
    const back = await browser.newPage();
    try {
      for (const p of [front, back]) {
        await p.goto(page.url().split('#')[0] + '#/parametres');
        await p.waitForFunction(() => document.documentElement.dataset.ready === 'parametres');
      }
      // Headless automation emulates window focus; deliver the two host events explicitly.
      const event = (p, type) => p.evaluate((key) => window.dispatchEvent(new FocusEvent(key)), type);
      const ornament = await back.evaluateHandle(() => document.getAnimations().find((a) => a.animationName === 'aurora-drift'));
      await event(front, 'focus');
      await event(back, 'blur');
      await back.waitForFunction(() => document.getAnimations().some((a) => a.animationName === 'aurora-drift' && a.playState === 'paused'));
      const tick = await ornament.evaluate(async (a) => { await a.ready; return a.currentTime; });
      assert.equal(await front.locator('.aurora').evaluate((el) => getComputedStyle(el).animationPlayState), 'running');
      assert.equal(await back.locator('.busy-line').evaluate((el) => getComputedStyle(el, '::after').animationPlayState), 'running');
      assert.equal(await back.locator('.glow-ring').evaluate((el) => getComputedStyle(el, '::before').animationPlayState), 'paused');
      assert.equal(await ornament.evaluate((a) => a.currentTime), tick);
      await event(back, 'focus');
      await back.waitForFunction(([a, t]) => a.playState === 'running' && a.currentTime > t, [ornament, tick]);

      const motion = back.getByLabel('Animations', { exact: true });
      await motion.selectOption('reduced');
      await event(back, 'blur');
      assert.equal(await back.locator('.aurora').evaluate((el) => getComputedStyle(el).animationName), 'none');
      await motion.selectOption('system');
      await back.emulateMedia({ reducedMotion: 'reduce' });
      await event(back, 'blur');
      const timing = await back.locator('.aurora').evaluate((el) => {
        const css = getComputedStyle(el); return [css.animationDuration, css.animationIterationCount, css.animationPlayState];
      });
      assert.deepEqual(timing, ['0.001s', '1', 'running']);
    } finally { await Promise.all([front.close(), back.close()]); }
  });
  const go = async (id) => { await page.locator(`.nav-item[data-id="${id}"]`).click(); await ready(id); };
  const pages = ['accueil', 'ajouter', 'unposte', 'plusieurspostes', 'noms', 'interventions', 'journal', 'parametres', 'aide'];
  for (const id of pages) await check(`${id} : contenu réel, aucun écran d’erreur`, async () => {
    await go(id);
    assert.equal(await page.locator('main .error-card').count(), 0);
    assert.equal(await page.locator('main h1').count(), 1);
    assert.equal(await page.locator(`.nav-item[data-id="${id}"]`).getAttribute('aria-current'), 'page');
  });
  for (const [id, form] of [['ajouter', 'join'], ['noms', 'preview']]) {
    await check(`${id} : formulaire validé et calcul du nom par le moteur simulé`, async () => {
      await go(id);
      const host = page.locator(`form[data-form="${form}"].k-form-live`);
      assert.equal(await host.count(), 1);
      await host.locator('[name="site"]').selectOption('paris');
      await host.locator('[name="service"]').selectOption('INF');
      await host.locator('button[type="submit"]').click();
      const name = page.locator('main .name-preview .name');
      await name.waitFor();
      assert.match(await name.innerText(), /^P111301PAINF\d{3}$/);
    });
  }
  await check('Un poste : recherche, sélection et formulaire de renommage utilisables', async () => {
    await go('unposte');
    await pickRemote(page);
    const search = page.locator('form[data-form="search"].k-form-live [name="query"]');
    await search.fill('P111301PAINF001'); await search.press('Enter');
    await page.locator('[data-pick="P111301PAINF001"]').click();
    const rename = page.locator('form[data-form="rename"].k-form-live');
    await rename.waitFor();
    await rename.locator('[name="service"]').selectOption('INF');
    await rename.locator('button[type="submit"]').click();
    await page.locator('[data-zone="rpreview"] .name-preview').waitFor();
  });
  await check('Plusieurs postes : liste collée analysée et sélection affichée', async () => {
    await go('plusieurspostes');
    assert.equal(await page.locator('form[data-form="search"].k-form-live').count(), 1);
    await page.locator('form[data-form="paste"].k-form-live [name="list"]').fill('P111301PAINF001\nS111301PAADM001');
    await page.getByRole('button', { name: 'Analyser la liste', exact: true }).click();
    assert.equal(await page.locator('[data-zone="sel-list"] [data-drop]').count(), 2);
    assert.equal(await page.getByRole('button', { name: 'Ajouter à la file', exact: true }).isEnabled(), true);
  });
  await check('Paramètres : données chargées, validation et dialogue protégé', async () => {
    await go('parametres');
    assert.equal(await page.locator('form[data-form="settings"].k-form-live').count(), 1);
    assert.notEqual(await page.locator('[name="domain"]').inputValue(), '');
    assert.notEqual(await page.locator('[name="sites"]').inputValue(), '');
    await page.getByRole('button', { name: 'Enregistrer', exact: true }).click();
    const dialog = page.getByRole('alertdialog', { name: 'Enregistrer les paramètres' });
    await dialog.waitFor();
    const navState = await page.locator('.nav-toggle').getAttribute('aria-expanded');
    for (const shortcut of ['Control+b', 'Control+k', 'Alt+1', 'F1']) await page.keyboard.press(shortcut);
    assert.equal(await page.locator('main').getAttribute('data-page'), 'parametres');
    assert.equal(await page.locator('.nav-toggle').getAttribute('aria-expanded'), navState);
    assert.equal(await page.getByRole('dialog', { name: 'Palette de commandes' }).isVisible(), false);
    assert.equal(await dialog.isVisible(), true);
    await page.keyboard.press('Escape'); await dialog.waitFor({ state: 'hidden' });
  });
  await check('Ctrl+B replie puis déplie la navigation', async () => {
    const before = await page.locator('.nav-toggle').getAttribute('aria-expanded');
    await page.keyboard.press('Control+b');
    assert.notEqual(await page.locator('.nav-toggle').getAttribute('aria-expanded'), before);
    await page.keyboard.press('Control+b');
    assert.equal(await page.locator('.nav-toggle').getAttribute('aria-expanded'), before);
  });
  await check('Ctrl+K, saisie palette et Entrée ouvrent réellement Journal', async () => {
    await page.keyboard.press('Control+k');
    const input = page.getByRole('combobox', { name: 'Rechercher un écran ou une commande' });
    await input.waitFor();
    assert.equal(await input.evaluate((el) => document.activeElement === el), true);
    await page.keyboard.press('F1');
    assert.equal(await page.locator('main').getAttribute('data-page'), 'parametres');
    await input.fill('journal'); await page.keyboard.press('Enter'); await ready('journal');
    assert.equal(await page.locator('main h1').innerText(), 'Journal');
  });
  await check('Sélecteurs de thème : clair, sombre, contraste et suivi système', async () => {
    for (const [theme, label] of [['light', 'Thème clair'], ['dark', 'Thème sombre'], ['contrast', 'Contraste élevé']]) {
      const button = page.getByRole('button', { name: label, exact: true });
      await button.click();
      assert.equal(await button.getAttribute('aria-pressed'), 'true');
      assert.equal(await page.locator('html').getAttribute('data-theme'), theme);
    }
    await page.getByRole('button', { name: 'Thème : suivre Windows', exact: true }).click();
    await page.emulateMedia({ colorScheme: 'dark' });
    await page.waitForFunction(() => document.documentElement.dataset.theme === 'dark');
    await page.emulateMedia({ colorScheme: 'light' });
    await page.waitForFunction(() => document.documentElement.dataset.theme === 'light');
    assert.equal(await page.locator('html').getAttribute('data-theme-pref'), 'system');
  });
  await check('Bandeau permanent même avec une ancienne préférence de masquage', async () => {
    await page.evaluate(async () => {
      const store = await import('/js/shell/store.js');
      store.setPrefs({ bannerCompact: true });
    });
    assert.equal(await page.locator('.sim-banner').isVisible(), true);
    assert.equal(await page.getByRole('button', { name: 'Masquer le bandeau', exact: true }).count(), 0);
    assert.equal(await page.locator('.mode-chip').getAttribute('data-mode'), 'simulation');
  });
  await check('Lien Aller au contenu : focus du contenu, route Journal conservée', async () => {
    await go('journal'); await page.locator('.skip-link').focus(); await page.keyboard.press('Enter');
    assert.equal(await page.evaluate(() => location.hash), '#/journal');
    assert.equal(await page.evaluate(() => document.activeElement.id), 'main');
  });
  await check('Préférence de repli propre au mode appliquée après lecture de session', async () => {
    await page.evaluate(() => {
      const common = JSON.parse(localStorage.getItem('pesto.prefs.v1'));
      localStorage.setItem('pesto.prefs.v1', JSON.stringify({ ...common, navCollapsed: false }));
      localStorage.setItem('pesto.prefs.v1#simulation', JSON.stringify({ ...common, navCollapsed: true }));
    });
    await page.reload(); await ready('journal');
    assert.equal(await page.locator('.nav-toggle').getAttribute('aria-expanded'), 'false');
  });
  for (const [width, columns] of [[1600, 4], [1200, 2], [850, 1]]) await check(`Accueil ${width}px : ${columns} indicateurs par rangée, sans débordement`, async () => {
    await page.setViewportSize({ width, height: 1000 }); await go('accueil');
    const rects = await page.locator('.kpi').evaluateAll((els) => els.map((el) => {
      const { x, y, width } = el.getBoundingClientRect(); return { x, y, width };
    }));
    assert.equal(rects.length, 4);
    assert.equal(rects.filter((r) => Math.abs(r.y - rects[0].y) < 2).length, columns);
    assert(rects.every((r) => r.width > 150 && r.x + r.width <= width + 1));
  });
  await check('Session différée : dernière route choisie puis lectures et sélection locale disponibles sans écriture', async () => {
    // An explicit native-channel fixture delays session.info; data still comes from the existing in-memory engine.
    // This exercises real UI/bridge startup ordering and read-only affordances, not Windows or AD.
    const readOnly = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    readOnly.setDefaultTimeout(5000);
    readOnly.on('pageerror', (e) => errors.push(e.message));
    readOnly.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    await readOnly.addInitScript(() => {
      localStorage.setItem('pesto.prefs.v1', JSON.stringify({ theme: 'light', motion: 'reduced' }));
      let receive;
      window.chrome ??= {};
      window.chrome.webview = {
        addEventListener(type, fn) { if (type === 'message') receive = fn; },
        async postMessage(request) {
          try {
            if (request.op === 'session.info') await new Promise((done) => { window.releaseTestSession = done; });
            const { browserSimulation } = await import('/js/simulation.js');
            const data = await browserSimulation.invoke(request.op, request.args);
            if (request.op === 'session.info') {
              data.mode = 'live'; data.readOnly = true;
              data.capabilities = data.capabilities.map((c) => ({ ...c, enabled: false, reason: 'Écritures indisponibles dans cette session de test.' }));
            }
            receive({ data: { id: request.id, kind: 'result', data } });
          } catch (e) { receive({ data: { id: request.id, kind: 'error', error: { code: e.code, message: e.message } } }); }
        },
      };
    });
    try {
      await readOnly.goto(`http://127.0.0.1:${server.address().port}/#/noms`);
      await readOnly.waitForFunction(() => typeof window.releaseTestSession === 'function');
      assert.equal(await readOnly.locator('main h1').count(), 0);
      assert.match(await readOnly.locator('main').innerText(), /Chargement de la session/);
      await readOnly.locator('.nav-item[data-id="plusieurspostes"]').click();
      await readOnly.evaluate(() => window.releaseTestSession());
      await readOnly.waitForFunction(() => document.documentElement.dataset.ready === 'plusieurspostes');
      assert.equal(await readOnly.locator('main .error-card').count(), 0);
      assert.equal(await readOnly.getByRole('button', { name: 'Rafraîchir', exact: true }).isEnabled(), true);
      await readOnly.locator('[name="list"]').fill('P111301PAINF001');
      await readOnly.getByRole('button', { name: 'Analyser la liste', exact: true }).click();
      assert.equal(await readOnly.getByRole('button', { name: 'Ajouter à la file', exact: true }).isEnabled(), false);
      await readOnly.getByRole('button', { name: 'Tout retirer', exact: true }).click();
      assert.equal(await readOnly.locator('[data-zone="sel-list"] [data-drop]').count(), 0);
      await readOnly.locator('.nav-item[data-id="noms"]').click();
      await readOnly.waitForFunction(() => document.documentElement.dataset.ready === 'noms');
      await readOnly.keyboard.press('Control+k');
      await readOnly.getByRole('combobox', { name: 'Rechercher un écran ou une commande' }).fill('Calculer un nom libre');
      assert.equal(await readOnly.getByRole('option', { name: 'Calculer un nom libre' }).getAttribute('aria-disabled'), null);
      await readOnly.keyboard.press('Enter');
      await readOnly.locator('main .name-preview .name').waitFor();
    } finally { await readOnly.close(); }
  });
  const receiptsPage = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  receiptsPage.setDefaultTimeout(5000);
  receiptsPage.on('pageerror', (e) => errors.push(e.message));
  receiptsPage.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await receiptsPage.addInitScript(() => {
    localStorage.setItem('pesto.prefs.v1', JSON.stringify({ theme: 'light', motion: 'reduced' }));
    const make = (id, status, extra = {}) => ({ id, status, mode: 'live · PowerShell 5.1', kind: 'rename', computer: 'PC-OLD', newName: 'PC-NEW',
      time: '2026-10-25T08:00:00Z', targetOU: 'OU=Postes,DC=example,DC=local', message: 'Reçu de test explicite.', restartRequired: status === 'pendingRestart', ...extra });
    const receipts = [make('pending', 'pendingRestart'), make('uncertain', 'uncertain'), make('confirmed', 'pendingRestart'),
      make('invalid', 'uncertain'), make('simulated', 'simulated', { mode: 'simulation' }), make('done', 'succeeded'), make('broken', 'uncertain', { readable: false })];
    window.proofCalls = []; window.releaseProof = {};
    let receive;
    window.chrome ??= {};
    window.chrome.webview = {
      addEventListener(type, fn) { if (type === 'message') receive = fn; },
      async postMessage(request) {
        window.proofCalls.push({ op: request.op, args: request.args });
        try {
          let data;
          if (request.op === 'session.info') data = { mode: 'live', readOnly: true, computer: 'PC-OLD', domain: 'example.local', account: 'EXAMPLE\\reader', capabilities: [] };
          else if (request.op === 'configuration.status') data = { configured: true, requiresDecision: false, pendingDistribution: null };
          else if (request.op === 'reservations.list') data = { items: [] };
          else if (request.op === 'receipts.list') data = { items: receipts };
          else if (request.op === 'receipts.get') data = receipts.find((r) => r.id === request.args.id);
          else if (request.op === 'receipts.reconcile') {
            const r = receipts.find((r) => r.id === request.args.id);
            await new Promise((done) => { window.releaseProof[r.id] = done; });
            if (r.id === 'uncertain') throw new Error('Lecture refusée : identité du poste non confirmée.');
            if (r.id === 'confirmed') data = { ...r, verified: true, status: 'succeeded', restartRequired: false, reason: null };
            else if (r.id === 'invalid') data = { ...r, verified: true, status: 'succeeded', restartRequired: true, reason: null };
            else data = { ...r, verified: false, reason: 'Le poste ne répond pas ; la lecture reste incomplète.' };
          } else throw new Error(`Opération inattendue : ${request.op}`);
          receive({ data: { id: request.id, kind: 'result', data: JSON.parse(JSON.stringify(data)) } });
        } catch (e) { receive({ data: { id: request.id, kind: 'error', error: { code: 'receipt.testRefusal', message: e.message } } }); }
      },
    };
  });
  try {
    await receiptsPage.goto(`http://127.0.0.1:${server.address().port}/#/interventions`);
    await receiptsPage.waitForFunction(() => document.documentElement.dataset.ready === 'interventions');
    const card = (id) => receiptsPage.locator(`[data-receipt="${id}"]`);
    const verify = async (id) => {
      await card(id).getByRole('button', { name: 'Vérifier l’état', exact: true }).click();
      await receiptsPage.waitForFunction((id) => typeof window.releaseProof[id] === 'function', id);
      assert.equal(await card(id).getAttribute('aria-busy'), 'true');
      assert.equal(await card(id).getByRole('button', { name: 'Vérifier l’état', exact: true }).isEnabled(), false);
      await card(id).locator('[data-act="verify"]').evaluate((el) => { el.click(); el.click(); });
      await receiptsPage.evaluate((id) => window.releaseProof[id](), id);
      await receiptsPage.waitForFunction((id) => document.querySelector(`[data-receipt="${id}"]`)?.getAttribute('aria-busy') !== 'true', id);
    };
    await check('Vérifier l’état : proposé seulement pour reçus réels lisibles en attente ou incertains', async () => {
      assert.equal(await receiptsPage.getByRole('button', { name: 'Vérifier l’état', exact: true }).count(), 4);
      for (const id of ['simulated', 'done', 'broken']) assert.equal(await card(id).locator('[data-act="verify"]').count(), 0);
    });
    await check('Vérification incomplète : reçu conservé, raison visible et aucun double envoi', async () => {
      await verify('pending');
      assert.equal(await card('pending').getAttribute('data-status'), 'pendingRestart');
      assert.match(await card('pending').locator('[data-verification]').innerText(), /État non confirmé.*lecture reste incomplète/);
      assert.equal(await receiptsPage.evaluate(() => window.proofCalls.filter((c) => c.op === 'receipts.reconcile' && c.args.id === 'pending').length), 1);
    });
    await check('Détail moteur : actions encore utilisables après deux relectures du reçu', async () => {
      for (let n = 1; n <= 2; n++) {
        await card('pending').getByRole('button', { name: 'Détail moteur', exact: true }).click();
        await receiptsPage.waitForFunction((n) => window.proofCalls.filter((c) => c.op === 'receipts.get' && c.args.id === 'pending').length === n, n);
        await receiptsPage.waitForFunction(() => document.querySelector('[data-receipt="pending"]')?.getAttribute('aria-busy') !== 'true');
        assert.equal(await card('pending').getByRole('button', { name: 'Vérifier l’état', exact: true }).isEnabled(), true);
      }
    });
    await check('Vérification refusée : état incertain conservé et refus visible', async () => {
      await verify('uncertain');
      assert.equal(await card('uncertain').getAttribute('data-status'), 'uncertain');
      assert.match(await card('uncertain').getByRole('alert').innerText(), /Lecture refusée/);
    });
    await check('Vérification confirmée : état relu réussi et action retirée', async () => {
      await verify('confirmed');
      assert.equal(await card('confirmed').getAttribute('data-status'), 'succeeded');
      assert.match(await card('confirmed').locator('[data-verification]').innerText(), /État confirmé/);
      assert.equal(await card('confirmed').locator('[data-act="verify"]').count(), 0);
    });
    await check('Réponse de preuve contradictoire : aucun succès affiché', async () => {
      await verify('invalid');
      assert.equal(await card('invalid').getAttribute('data-status'), 'uncertain');
      assert.match(await card('invalid').getByRole('alert').innerText(), /reste inchangé/);
    });
    await check('Vérification : lectures de session/configuration et reçus d’opérations/réservations seulement, aucun envoi de mutation', async () => {
      const calls = await receiptsPage.evaluate(() => window.proofCalls);
      const allowed = ['session.info', 'configuration.status', 'reservations.list', 'receipts.list', 'receipts.get', 'receipts.reconcile'];
      assert.deepEqual(calls.filter((c) => !allowed.includes(c.op)), []);
      assert.deepEqual(calls.filter((c) => c.op === 'configuration.status'), [{ op: 'configuration.status', args: {} }]);
      assert.deepEqual(calls.filter((c) => c.op === 'reservations.list'), [{ op: 'reservations.list', args: {} }]);
      assert.equal(calls.filter((c) => c.op === 'receipts.reconcile').length, 4);
    });
  } finally { await receiptsPage.close(); }
  await check('Aucune exception JavaScript ni erreur de console', async () => assert.deepEqual(errors, []));
} finally {
  await browser?.close();
  await new Promise((done) => server.close(done));
}
console.log(`\n${checks - failures}/${checks} contrôles DOM réussis (simulation Chromium, sans qualification native/AD).`);
process.exitCode = failures ? 1 : 0;
