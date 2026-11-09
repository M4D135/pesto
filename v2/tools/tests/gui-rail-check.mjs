// Browser checks for the navigation rail and the Ajouter forms, against the actual Pesto ES modules and CSS served on
// an ephemeral loopback port. Uses only an already-installed Chromium and Playwright; never installs a browser.
// Example:
// PESTO_PLAYWRIGHT_MODULE=/absolute/node_modules/playwright/index.mjs PESTO_CHROMIUM_PATH=/usr/bin/google-chrome \
//   node v2/tools/tests/gui-rail-check.mjs
// PESTO_WEB_ROOT serves another copy of web/ (used to show these checks fail on an older tree).
// These checks cover browser simulation, not native WebView2, UIA, production bridge or AD qualification.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, extname, isAbsolute, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

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
const mime = { '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html', '.json': 'application/json', '.svg': 'image/svg+xml' };
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
const base = `http://127.0.0.1:${server.address().port}`;
let browser;
let checks = 0, failures = 0;
const check = async (name, fn) => {
  checks += 1;
  try { await fn(); console.log(`  ok   ${name}`); }
  catch (e) { failures += 1; console.error(`  FAIL ${name} — ${e.message}`); }
};
const errors = [];

// Live session served by the browser simulation behind a chrome.webview stub; joinPrecreated as the policy sets it.
function liveFixture(precreated) {
  let receive;
  window.chrome ??= {};
  window.chrome.webview = {
    addEventListener(type, fn) { if (type === 'message') receive = fn; },
    async postMessage(request) {
      try {
        const { browserSimulation } = await import('/js/simulation.js');
        const data = request.op === 'reservations.list' ? { items: [] } : await browserSimulation.invoke(request.op, request.args);
        if (request.op === 'session.info') {
          data.mode = 'live'; data.readOnly = false;
          data.capabilities = data.capabilities.filter((c) => c.id !== 'joinPrecreated')
            .concat({ id: 'joinPrecreated', enabled: precreated, reason: precreated ? '' : 'La politique de jonction sur compte précréé est désactivée.' });
        }
        setTimeout(() => receive({ data: { id: request.id, kind: 'result', data } }));
      } catch (e) {
        setTimeout(() => receive({ data: { id: request.id, kind: 'error', error: { code: 'x', message: e.message } } }));
      }
    },
  };
}

async function open({ width = 1280, height = 800, route = '', prefs = {}, live = null } = {}) {
  const page = await browser.newPage({ viewport: { width, height }, colorScheme: 'light' });
  page.setDefaultTimeout(5000);
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.addInitScript((p) => localStorage.setItem('pesto.prefs.v1', JSON.stringify({ theme: 'light', motion: 'reduced', ...p })), prefs);
  if (live !== null) await page.addInitScript(liveFixture, live);
  await page.goto(`${base}/${route ? `#/${route}` : ''}`);
  await page.waitForFunction((id) => document.documentElement.dataset.ready === id, route || 'accueil');
  return page;
}
const prefsOf = (page) => page.evaluate(() => JSON.parse(localStorage.getItem('pesto.prefs.v1')));
// Text of the rail tooltip actually readable on screen: the floating tip, or an ::after tip that is not clipped.
const visibleTip = (page, selector) => page.evaluate((sel) => {
  const el = document.querySelector(sel);
  const fly = document.querySelector('.flytip.on');
  if (fly && getComputedStyle(fly).opacity === '1') {
    const r = fly.getBoundingClientRect();
    if (r.left >= el.getBoundingClientRect().right && r.right <= innerWidth) return fly.textContent;
  }
  const after = getComputedStyle(el, '::after');
  if (after.display === 'none' || after.content === 'none' || after.opacity !== '1') return null;
  // An ::after tip inside the rail is cut at the rail edge (overflow hidden): only count it if it fits.
  const nav = document.querySelector('.nav').getBoundingClientRect();
  const left = el.getBoundingClientRect().right + 10;
  return left + 60 <= nav.right ? after.content : null;
}, selector);

try {
  browser = await chromium.launch({ headless: true, executablePath });

  // ---------- Ajouter : formulaires masqués par l’attribut hidden ----------
  const hiddenState = (page, form) => page.evaluate((f) => {
    const el = document.querySelector(`form[data-form="${f}"]`);
    return { hidden: el.hidden, display: getComputedStyle(el).display, height: Math.round(el.getBoundingClientRect().height) };
  }, form);
  await check('Ajouter (simulation) : formulaire du compte précréé masqué, aucun champ ni message', async () => {
    const page = await open({ route: 'ajouter' });
    try {
      assert.deepEqual(await hiddenState(page, 'precreated'), { hidden: true, display: 'none', height: 0 });
      assert.equal(await page.locator('form[data-form="precreated"] [name="existingName"]').isVisible(), false);
      assert.equal(await page.getByRole('button', { name: 'Vérifier le compte précréé' }).isVisible(), false);
      // Tab out of the last join control must not reach (and flag) the hidden required field.
      await page.locator('form[data-form="join"] button[type="submit"]').focus();
      await page.keyboard.press('Tab');
      assert.equal(await page.evaluate(() => !!document.activeElement.closest('form[data-form="precreated"]')), false);
    } finally { await page.close(); }
  });
  await check('Ajouter (réel, politique précréé désactivée) : formulaire du compte précréé masqué', async () => {
    const page = await open({ route: 'ajouter', live: false });
    try {
      assert.equal(await page.locator('.mode-chip').getAttribute('data-mode'), 'readonly');
      const sw = page.locator('[name="usePrecreated"]');
      assert.equal(await sw.isChecked(), false);
      assert.equal(await sw.isDisabled(), true);
      assert.deepEqual(await hiddenState(page, 'precreated'), { hidden: true, display: 'none', height: 0 });
      assert.equal(await page.getByRole('button', { name: 'Vérifier le compte précréé' }).isVisible(), false);
    } finally { await page.close(); }
  });
  await check('Ajouter (réel, précréé autorisé) : l’interrupteur masque le formulaire de jonction ordinaire', async () => {
    const page = await open({ route: 'ajouter', live: true });
    try {
      const sw = page.locator('[name="usePrecreated"]');
      assert.equal(await sw.isDisabled(), false);
      await sw.evaluate((i) => { i.checked = true; i.dispatchEvent(new Event('change', { bubbles: true })); });
      assert.deepEqual(await hiddenState(page, 'join'), { hidden: true, display: 'none', height: 0 });
      assert.equal(await page.getByRole('button', { name: 'Calculer le nom libre' }).isVisible(), false);
      assert.equal((await hiddenState(page, 'precreated')).display, 'grid');
      await sw.evaluate((i) => { i.checked = false; i.dispatchEvent(new Event('change', { bubbles: true })); });
      assert.equal((await hiddenState(page, 'join')).display, 'grid');
      assert.equal((await hiddenState(page, 'precreated')).display, 'none');
    } finally { await page.close(); }
  });

  // ---------- Poignée de largeur ----------
  for (const [width, height] of [[1000, 700], [1280, 800]]) await check(`Poignée ${width}x${height} : bord du menu, glisser élargit le menu`, async () => {
    const page = await open({ width, height });
    try {
      const g = await page.evaluate(() => {
        const grip = document.querySelector('.nav-grip'), nav = document.querySelector('.nav');
        const r = grip.getBoundingClientRect(), n = nav.getBoundingClientRect();
        return { position: getComputedStyle(grip).position, h: Math.round(r.height), navH: Math.round(n.height), x: r.left + r.width / 2, navRight: n.right };
      });
      assert.equal(g.position, 'absolute');
      assert.equal(g.h, g.navH);
      assert.ok(Math.abs(g.x - g.navRight) < 4, `poignée à x=${g.x}, bord du menu à ${g.navRight}`);
      const col = () => page.evaluate(() => parseFloat(getComputedStyle(document.querySelector('.shell')).gridTemplateColumns));
      const before = await col();
      // The rail's 1 px border sits outside the grip's containing block: aim just inside it.
      await page.mouse.move(g.navRight - 3, 200);
      await page.mouse.down();
      await page.mouse.move(g.navRight + 40, 200, { steps: 5 });
      await page.mouse.up();
      assert.ok(await col() > before + 30, `menu ${before}px → ${await col()}px`);
      assert.ok((await prefsOf(page)).navWidth > 248);
    } finally { await page.close(); }
  });

  await check('Poignée 1280x800 : trait d’accent visible au focus clavier et au survol', async () => {
    const page = await open({ width: 1280, height: 800 });
    try {
      const line = () => page.evaluate(() => {
        const s = getComputedStyle(document.querySelector('.nav-grip'), '::after');
        return { content: s.content, display: s.display, opacity: s.opacity };
      });
      await page.locator('.nav-grip').focus();
      await page.keyboard.press('Shift+Tab');
      await page.keyboard.press('Tab');
      assert.equal(await page.evaluate(() => document.activeElement.matches('.nav-grip:focus-visible')), true);
      await page.waitForTimeout(300);
      let s = await line();
      assert.ok(s.content !== 'none' && s.display !== 'none' && s.opacity === '1', `focus : ${JSON.stringify(s)}`);
      await page.locator('main').focus();
      const r = await page.evaluate(() => document.querySelector('.nav').getBoundingClientRect().right);
      await page.mouse.move(r - 3, 300);
      await page.waitForTimeout(300);
      s = await line();
      assert.ok(s.content !== 'none' && s.display !== 'none' && s.opacity === '1', `survol : ${JSON.stringify(s)}`);
    } finally { await page.close(); }
  });

  // ---------- Infobulles du menu ----------
  await check('Menu replié 1000x520 : après défilement du menu, l’élément sous le pointeur retrouve son infobulle', async () => {
    const page = await open({ width: 1000, height: 520, prefs: { navCollapsed: true } });
    try {
      const box = await page.locator('.nav-item[data-id="noms"]').boundingBox();
      const x = box.x + box.width / 2, y = box.y + box.height / 2;
      await page.mouse.move(x, y);
      await page.waitForTimeout(450);
      assert.equal(await visibleTip(page, '.nav-item[data-id="noms"]'), 'Noms disponibles');
      await page.mouse.wheel(0, 200);
      await page.waitForFunction(() => document.querySelector('.nav').scrollTop > 0);
      await page.waitForTimeout(150);
      await page.mouse.move(x + 1, y);
      await page.waitForTimeout(450);
      const under = await page.evaluate(([px, py]) => document.elementFromPoint(px, py)?.closest('[data-tip]')?.dataset.tip || null, [x + 1, y]);
      assert.ok(under && under !== 'Noms disponibles', `élément sous le pointeur : ${under}`);
      const fly = await page.evaluate(() => document.querySelector('.flytip.on')?.textContent || null);
      assert.equal(fly, under);
    } finally { await page.close(); }
  });
  await check('Menu déplié : bouton de repli en ligne de menu, libellé visible, indice Ctrl B au survol, sans infobulle', async () => {
    const page = await open({ width: 1280, height: 800 });
    try {
      const state = await page.evaluate(() => {
        const t = document.querySelector('.nav-toggle'), label = t.querySelector('.nav-label');
        const item = document.querySelector('.nav-item[data-id="noms"]').getBoundingClientRect(), r = t.getBoundingClientRect();
        return { label: label.textContent, labelVisible: label.getBoundingClientRect().width > 40 && getComputedStyle(label).display !== 'none',
          aria: t.getAttribute('aria-label'), expanded: t.getAttribute('aria-expanded'), height: Math.round(r.height), sameWidth: Math.abs(r.width - item.width) < 1 };
      });
      assert.deepEqual(state, { label: 'Replier le menu', labelVisible: true, aria: 'Replier le menu', expanded: 'true', height: 40, sameWidth: true });
      await page.locator('.nav-toggle').hover();
      await page.waitForTimeout(450);
      assert.equal(await page.locator('.nav-toggle .nav-kbd').evaluate((k) => getComputedStyle(k).opacity), '1');
      assert.equal(await visibleTip(page, '.nav-toggle'), null);
    } finally { await page.close(); }
  });
  await check('Menu replié : bouton de repli en icône seule centrée, retournée, infobulle « Déplier le menu (Ctrl B) »', async () => {
    const page = await open({ width: 1280, height: 800, prefs: { navCollapsed: true } });
    try {
      const state = await page.evaluate(() => {
        const t = document.querySelector('.nav-toggle'), nav = document.querySelector('.nav').getBoundingClientRect(), r = t.getBoundingClientRect();
        return { labelShown: getComputedStyle(t.querySelector('.nav-label')).display !== 'none', aria: t.getAttribute('aria-label'), expanded: t.getAttribute('aria-expanded'),
          centred: Math.abs((r.left + r.right) / 2 - (nav.left + nav.right) / 2) < 2, mirrored: getComputedStyle(t.querySelector('svg')).transform !== 'none' };
      });
      assert.deepEqual(state, { labelShown: false, aria: 'Déplier le menu', expanded: 'false', centred: true, mirrored: true });
      await page.locator('.nav-toggle').hover();
      await page.waitForTimeout(450);
      assert.equal(await visibleTip(page, '.nav-toggle'), 'Déplier le menu (Ctrl B)');
    } finally { await page.close(); }
  });
  await check('Menu déplié 1000x700 : bouton de repli visible en bas sans défilement', async () => {
    const page = await open({ width: 1000, height: 700 });
    try {
      const r = await page.locator('.nav-toggle').boundingBox();
      assert.ok(r.y >= 0 && r.y + r.height <= 700, JSON.stringify(r));
      assert.equal(await page.evaluate(() => document.querySelector('.nav').scrollTop), 0);
    } finally { await page.close(); }
  });
  for (const [width, prefs, label] of [[1000, { navCollapsed: true }, 'menu replié'], [880, { navCollapsed: false }, '880 px, préférence dépliée']]) {
    await check(`Infobulles lisibles hors du menu en icônes (${label})`, async () => {
      const page = await open({ width, height: 700, prefs });
      try {
        await page.locator('.nav-item[data-id="noms"]').hover();
        await page.waitForTimeout(450);
        assert.equal(await visibleTip(page, '.nav-item[data-id="noms"]'), 'Noms disponibles');
        await page.mouse.move(700, 400);
        await page.waitForTimeout(100);
        assert.equal(await page.locator('.flytip.on').count(), 0);
        // Keyboard focus shows it too.
        await page.locator('.nav-item[data-id="journal"]').focus();
        await page.keyboard.press('Shift+Tab');
        await page.keyboard.press('Tab');
        await page.waitForTimeout(450);
        assert.equal(await visibleTip(page, '.nav-item[data-id="journal"]'), 'Journal');
      } finally { await page.close(); }
    });
  }

  // ---------- Focus sous le pied collant ----------
  for (const [width, height, collapsed] of [[1000, 520, false], [1000, 600, false], [1000, 700, false], [1000, 520, true]]) {
    await check(`Focus clavier ${width}x${height}${collapsed ? ' replié' : ''} : chaque élément du menu reste visible au-dessus du pied`, async () => {
      const page = await open({ width, height, prefs: { navCollapsed: collapsed } });
      try {
        await page.locator('.nav-item[data-id="accueil"]').focus();
        const covered = [];
        for (const id of ['ajouter', 'unposte', 'plusieurspostes', 'noms', 'interventions', 'journal', 'parametres', 'aide']) {
          await page.keyboard.press('Tab');
          const hit = await page.evaluate(() => {
            const el = document.activeElement, r = el.getBoundingClientRect();
            const top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
            return { id: el.dataset.id, self: el.contains(top) };
          });
          assert.equal(hit.id, id);
          if (!hit.self) covered.push(id);
        }
        assert.deepEqual(covered, []);
      } finally { await page.close(); }
    });
  }

  // ---------- Fenêtre étroite (≤ 900 px) ----------
  await check('880 px : Ctrl+B ne change pas la préférence, annonce le repli imposé, poignée absente', async () => {
    const page = await open({ width: 880, height: 700, prefs: { navCollapsed: false } });
    try {
      await page.locator('main').focus();
      await page.keyboard.press('Control+b');
      assert.equal((await prefsOf(page)).navCollapsed, false);
      await page.waitForFunction(() => /fenêtre trop étroite/.test(document.body.innerText));
      assert.equal(await page.evaluate(() => getComputedStyle(document.querySelector('.nav-grip')).display), 'none');
      await page.locator('.nav-item[data-id="aide"]').focus();
      await page.keyboard.press('Tab');
      assert.equal(await page.evaluate(() => document.activeElement.classList.contains('nav-grip')), false);
      await page.setViewportSize({ width: 1100, height: 700 });
      await page.waitForFunction(() => document.querySelector('.nav').getBoundingClientRect().width > 200);
    } finally { await page.close(); }
  });
  await check('1100 px : Ctrl+B replie toujours le menu et l’enregistre', async () => {
    const page = await open({ width: 1100, height: 700, prefs: { navCollapsed: false } });
    try {
      await page.locator('main').focus();
      await page.keyboard.press('Control+b');
      assert.equal((await prefsOf(page)).navCollapsed, true);
      assert.equal(await page.locator('.shell.nav-collapsed').count(), 1);
    } finally { await page.close(); }
  });

  await check('Aucune exception JavaScript ni erreur de console', async () => assert.deepEqual(errors, []));
} finally {
  await browser?.close();
  await new Promise((done) => server.close(done));
}
console.log(`\n${checks - failures}/${checks} contrôles du menu et d’Ajouter réussis (simulation Chromium, sans qualification native/AD).`);
process.exitCode = failures ? 1 : 0;
