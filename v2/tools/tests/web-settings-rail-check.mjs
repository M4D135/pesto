// Paramètres façon Domenia 2 (2.0.15) : rail de sections, adresse #/parametres?section=…, recherche « / », tuiles, animations,
// contraste et fenêtre étroite, contre les vrais modules ES et CSS de Pesto servis sur un port loopback éphémère.
// Démonstration du navigateur seulement (moteur simulé en mémoire) : aucun pont natif, aucun Windows ni AD, aucun téléchargement.
// Exemple :
// PESTO_PLAYWRIGHT_MODULE=/absolute/node_modules/playwright/index.mjs PESTO_CHROMIUM_PATH=/usr/bin/google-chrome \
//   node v2/tools/tests/web-settings-rail-check.mjs
// Ces contrôles couvrent la simulation Chromium, pas WebView2, UIA ni la qualification native.
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
const origin = `http://127.0.0.1:${server.address().port}`;
let browser;
let checks = 0, failures = 0;
const errors = [];
const filter = process.argv[2] ? new RegExp(process.argv[2], 'i') : null;
const check = async (name, fn) => {
  if (filter && !filter.test(name)) return;
  checks += 1;
  try { await fn(); console.log(`  ok   ${name}`); }
  catch (e) { failures += 1; console.error(`  FAIL ${name} — ${e.message}`); }
};

// Rail of the demonstration (no operation policies: Politiques is absent), with the exact labels of the rail and the headers.
const RAIL = [
  { id: 'annuaire', label: 'Annuaire', desc: 'Domaine, préfixe, convention et sites', intro: 'Domaine, contrôleur, préfixe, convention de nommage et sites.' },
  { id: 'configuration', label: 'Configuration', desc: 'Export, import, défaut et référentiels', intro: 'État de la configuration en vigueur, partage par export et import, configuration par défaut de l’installation et référentiels.' },
  { id: 'mises-a-jour', label: 'Mises à jour', desc: 'ZIP, dossier ou partage UNC', intro: 'Inspecter, préparer puis confirmer l’installation d’un pack vérifié.' },
  { id: 'interface', label: 'Interface', desc: 'Animations et démonstration', intro: 'Préférences d’affichage de ce poste et fenêtre de démonstration.' },
];

// Records, from the start of each document, every box that receives the flash of a setting (the flash lasts 1.7 s:
// reading the class later would depend on the speed of the machine). Each entry: data-setting, then the names inside.
const FLASH_RECORDER = () => {
  window.flashed = [];
  new MutationObserver((records) => {
    for (const r of records) {
      const el = r.target;
      if (!(el instanceof Element) || !el.classList.contains('pr-flash') || String(r.oldValue ?? '').split(/\s+/).includes('pr-flash')) continue;
      window.flashed.push([el.dataset.setting, ...[...el.querySelectorAll('[data-maint], [name]')].map((n) => n.dataset.maint || n.getAttribute('name'))].filter(Boolean));
    }
  }).observe(document, { subtree: true, attributes: true, attributeFilter: ['class'], attributeOldValue: true });
};

try {
  browser = await chromium.launch({ headless: true, executablePath });

  // One isolated browser context per page: its own storage, its own simulated world.
  async function openPage({ address = '#/parametres', theme = 'light', motion = 'reduced', width = 1440, height = 1000, forced = false } = {}) {
    const page = await browser.newPage({ viewport: { width, height }, colorScheme: 'light', forcedColors: forced ? 'active' : 'none' });
    page.setDefaultTimeout(5000);
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    await page.route('**/*', async (route) => {
      if (route.request().url().startsWith(origin + '/')) await route.continue();
      else { errors.push('Requête externe inattendue : ' + route.request().url()); await route.abort(); }
    });
    await page.addInitScript(({ theme, motion }) => {
      localStorage.setItem('pesto.prefs.v1', JSON.stringify({ theme, motion }));
    }, { theme, motion });
    await page.addInitScript(FLASH_RECORDER);
    await page.goto(`${origin}/${address}`);
    await ready(page);
    await countCalls(page);
    return page;
  }
  const ready = (page) => page.waitForFunction(() => document.documentElement.dataset.ready === 'parametres');
  // Every later call to the simulated engine is counted (the bridge reads browserSimulation.invoke at each call).
  const countCalls = (page) => page.evaluate(async () => {
    const { browserSimulation } = await import('/js/simulation.js');
    if (browserSimulation.__counted) return;
    const invoke = browserSimulation.invoke;
    window.engineCalls = [];
    browserSimulation.invoke = (op, args) => { window.engineCalls.push(op); return invoke(op, args); };
    browserSimulation.__counted = true;
  });
  const engineCalls = (page) => page.evaluate(() => window.engineCalls.slice());
  const flashed = (page) => page.evaluate(() => window.flashed.slice());
  const hash = (page) => page.evaluate(() => location.hash);
  const shown = (page) => page.locator('main [data-section-panel]:not([hidden])').evaluateAll((nodes) => nodes.map((node) => node.dataset.sectionPanel));
  const current = (page) => page.locator('main .pr-nav-item[aria-current="true"]').evaluateAll((nodes) => nodes.map((node) => node.dataset.section));
  const focused = (page) => page.evaluate(() => {
    const el = document.activeElement;
    return el?.getAttribute('name') || el?.id || el?.dataset?.section || el?.tagName || null;
  });
  const frames = (page) => page.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))));
  const announced = (page, text) => page.locator('.live-polite p, .live-assertive p').evaluateAll((nodes, text) => nodes.filter((node) => node.textContent === text).length, text);
  const openSection = async (page, id) => {
    await page.locator(`main .pr-nav-item[data-section="${id}"]`).click();
    await page.locator(`main [data-section-panel="${id}"]:not([hidden])`).waitFor();
  };
  // An address typed or followed from outside the page: a hashchange, then a new mount (never the screen it replaces).
  const visit = async (page, address) => {
    await page.evaluate((address) => { document.querySelector('main').firstElementChild.dataset.stale = '1'; location.hash = address; }, address);
    await page.waitForFunction(() => document.documentElement.dataset.ready === 'parametres'
      && document.querySelector('main').firstElementChild?.dataset.stale !== '1');
  };
  // Keyboard modality first, so the focus given by the page matches :focus-visible as it would after a key press.
  const keyboardFocus = async (page, selector) => { await page.keyboard.press('Shift'); await page.locator(selector).evaluate((el) => el.focus()); };
  // Read once the style has settled (reduced motion still runs 1 ms transitions, applied on the next frame).
  const outline = async (page, selector) => { await frames(page); return page.locator(selector).evaluate((el) => {
    const css = getComputedStyle(el);
    return [css.outlineStyle, css.outlineWidth, css.outlineColor, css.outlineOffset].join(' ');
  }); };
  const inView = (page, selector) => page.evaluate((selector) => {
    const main = document.querySelector('main').getBoundingClientRect();
    const box = document.querySelector(selector).getBoundingClientRect();
    return box.top >= main.top - 1 && box.bottom <= main.bottom + 1;
  }, selector);

  await check('Rail démonstration : quatre sections, Politiques absente, libellés et descriptions exacts', async () => {
    const page = await openPage();
    try {
      assert.equal(await page.locator('.mode-chip').getAttribute('data-mode'), 'simulation');
      assert.equal(await page.getByRole('navigation', { name: 'Sections des paramètres', exact: true }).count(), 1);
      const items = await page.locator('main .pr-nav-item').evaluateAll((nodes) => nodes.map((node) => ({
        id: node.dataset.section, label: node.querySelector('.pr-nav-label').textContent, desc: node.querySelector('.pr-nav-desc').textContent,
        current: node.getAttribute('aria-current'), controls: node.getAttribute('aria-controls'), type: node.type,
      })));
      assert.deepEqual(items, RAIL.map((s, n) => ({ id: s.id, label: s.label, desc: s.desc, current: n === 0 ? 'true' : 'false', controls: `pr-panel-${s.id}`, type: 'button' })));
      for (const s of RAIL) {
        const panel = page.locator(`main #pr-panel-${s.id}`);
        assert.equal(await panel.getAttribute('data-section-panel'), s.id);
        assert.equal(await panel.getAttribute('aria-labelledby'), `pr-title-${s.id}`);
        assert.equal(await panel.locator(`h2#pr-title-${s.id}`).textContent(), s.label);
        assert.equal(await panel.locator('.pr-sec-titles p').textContent(), s.intro);
      }
      assert.equal(await page.locator('main [data-section-panel="politiques"], main [data-section="politiques"], main [data-coordination]').count(), 0);
      assert.equal(await page.locator('main [name="coordinationRoot"], main [name="rootOu"]').count(), 0);
      assert.deepEqual(await shown(page), ['annuaire']);
      assert.equal(await hash(page), '#/parametres');
      assert.equal(await page.locator('main h1').count(), 1);
      assert.equal(await page.locator('main h1').textContent(), 'Paramètres');
      assert.equal(await page.locator('main .nav-item, main .nav-pill, main [aria-current="page"]').count(), 0);
      assert.equal(await page.locator('main .pr-nav-pill').getAttribute('aria-hidden'), 'true');
    } finally { await page.close(); }
  });

  await check('Adresse : section lue, alias normalisé, section inconnue ramenée à Annuaire', async () => {
    const page = await openPage({ address: '#/parametres?section=configuration' });
    try {
      assert.deepEqual(await shown(page), ['configuration']);
      assert.deepEqual(await current(page), ['configuration']);
      assert.equal(await hash(page), '#/parametres?section=configuration');
      for (const [address, expected, section] of [
        ['#/parametres?section=demo', '#/parametres?section=interface', 'interface'],
        ['#/parametres?section=politiques', '#/parametres', 'annuaire'],
        ['#/parametres?section=MAJ', '#/parametres?section=mises-a-jour', 'mises-a-jour'],
        ['#/parametres?section=xyz&onglet=a', '#/parametres', 'annuaire'],
        [`#/parametres?section=${encodeURIComponent(' Démonstration ')}`, '#/parametres?section=interface', 'interface'],
        ['#/parametres?section=sites', '#/parametres', 'annuaire'],
        ['#/parametres?section=import&onglet=b', '#/parametres?section=configuration', 'configuration'],
      ]) {
        await visit(page, address);
        assert.equal(await hash(page), expected, address);
        assert.deepEqual(await shown(page), [section], address);
        assert.deepEqual(await current(page), [section], address);
      }
    } finally { await page.close(); }
  });

  await check('Adresse : ouvrir consommé une fois, réglage éclairé et focalisé, aucune action lancée', async () => {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    page.setDefaultTimeout(5000);
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    await page.route('**/*', async (route) => {
      if (route.request().url().startsWith(origin + '/')) await route.continue();
      else { errors.push('Requête externe inattendue : ' + route.request().url()); await route.abort(); }
    });
    try {
      await page.addInitScript(() => localStorage.setItem('pesto.prefs.v1', JSON.stringify({ theme: 'light', motion: 'reduced' })));
      await page.addInitScript(FLASH_RECORDER);
      await page.goto(`${origin}/#/parametres?ouvrir=prefix`);
      await ready(page);
      assert.deepEqual(await flashed(page), [['prefix']]);
      assert.equal(await focused(page), 'prefix');
      assert.deepEqual(await shown(page), ['annuaire']);
      assert.equal(await hash(page), '#/parametres');
      await page.reload(); await ready(page);
      assert.equal(await hash(page), '#/parametres');
      assert.deepEqual(await flashed(page), []);
      assert.notEqual(await focused(page), 'prefix');
      await countCalls(page);
      // A maintenance action is only shown: the section of the target wins over ?section=, nothing is clicked.
      await visit(page, '#/parametres?section=interface&ouvrir=zip');
      assert.deepEqual(await shown(page), ['mises-a-jour']);
      assert.equal(await hash(page), '#/parametres?section=mises-a-jour');
      assert.deepEqual(await flashed(page), [['zip', 'folder']]);
      assert.equal(await page.evaluate(() => document.activeElement?.dataset.maint ?? null), null);
      await frames(page);
      // The new mount reads the settings once, as any mount does; ouvrir adds no call and no dialog.
      assert.deepEqual(await engineCalls(page), ['settings.get']);
      assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
      // An unknown target keeps the section asked; a value outside the expected form is ignored.
      await visit(page, '#/parametres?section=configuration&ouvrir=inconnu');
      assert.deepEqual(await shown(page), ['configuration']);
      assert.equal(await hash(page), '#/parametres?section=configuration');
      assert.equal((await flashed(page)).length, 1);
      await visit(page, `#/parametres?ouvrir=${encodeURIComponent('"]prefix')}`);
      assert.deepEqual(await shown(page), ['annuaire']);
      assert.equal(await hash(page), '#/parametres');
      assert.equal((await flashed(page)).length, 1);
    } finally { await page.close(); }
  });

  await check('Recherche : / focalise hors champ, ignoré dans un champ et avec Ctrl', async () => {
    const page = await openPage();
    try {
      const search = page.locator('main #pr-search');
      assert.equal(await search.getAttribute('aria-keyshortcuts'), '/');
      assert.equal(await search.getAttribute('aria-label'), 'Rechercher un réglage');
      assert.equal(await search.getAttribute('placeholder'), 'Rechercher un réglage…');
      await page.locator('main').focus();
      await page.keyboard.press('/');
      assert.equal(await focused(page), 'pr-search');
      assert.equal(await search.inputValue(), '');
      // In a text field « / » is a character of that field.
      const domain = page.locator('main [name="domain"]');
      const before = await domain.inputValue();
      await domain.focus();
      await page.keyboard.press('/');
      assert.equal(await focused(page), 'domain');
      assert.equal(await domain.inputValue(), `${before}/`);
      await page.keyboard.press('Backspace');
      assert.equal(await domain.inputValue(), before);
      // With Ctrl, Alt or Cmd it is someone else’s shortcut.
      for (const shortcut of ['Control+/', 'Alt+/', 'Meta+/']) {
        await page.locator('main').focus();
        await page.keyboard.press(shortcut);
        assert.notEqual(await focused(page), 'pr-search', shortcut);
      }
      // AZERTY: « / » is Shift+: ; Shift is not a reason to ignore it.
      await page.locator('main').focus();
      await page.evaluate(() => document.querySelector('main').dispatchEvent(new KeyboardEvent('keydown', { key: '/', code: 'Period', shiftKey: true, bubbles: true, cancelable: true })));
      assert.equal(await focused(page), 'pr-search');
      // Never under a dialog.
      await page.locator('main').focus();
      await page.getByRole('button', { name: 'Enregistrer', exact: true }).click();
      const dialog = page.getByRole('alertdialog', { name: 'Enregistrer les paramètres' });
      await dialog.waitFor();
      await page.keyboard.press('/');
      assert.notEqual(await focused(page), 'pr-search');
      assert.equal(await dialog.isVisible(), true);
      await page.keyboard.press('Escape'); await dialog.waitFor({ state: 'hidden' });
      assert.deepEqual((await engineCalls(page)).filter((op) => op === 'settings.save'), []);
    } finally { await page.close(); }
  });

  await check('Recherche : flèches, Entrée, section ouverte et réglage éclairé ; Échap vide ; aucun résultat dit', async () => {
    const page = await openPage();
    try {
      const search = page.locator('main #pr-search');
      const list = page.locator('main #pr-search-list');
      const hits = () => list.locator('li[data-hit]').evaluateAll((nodes) => nodes.map((node) => [node.querySelector('.pr-hit-label').textContent, node.querySelector('.pr-hit-sec').textContent, node.getAttribute('aria-selected')]));
      await page.locator('main').focus();
      await page.keyboard.press('/');
      await page.keyboard.type('mise a jour');
      assert.equal(await list.isVisible(), true);
      assert.equal(await search.getAttribute('aria-expanded'), 'true');
      assert.deepEqual(await hits(), [
        ['Importer une mise à jour des référentiels', 'Configuration', 'true'],
        ['Choisir un ZIP de mise à jour', 'Mises à jour', 'false'],
        ['Choisir un dossier de mise à jour', 'Mises à jour', 'false'],
      ]);
      assert.equal(await search.getAttribute('aria-activedescendant'), 'pr-hit-0');
      for (const [key, active] of [['ArrowDown', 1], ['ArrowDown', 2], ['ArrowDown', 0], ['ArrowUp', 2], ['ArrowUp', 1]]) {
        await page.keyboard.press(key);
        assert.equal(await search.getAttribute('aria-activedescendant'), `pr-hit-${active}`, key);
        assert.deepEqual((await hits()).map((hit) => hit[2]), [0, 1, 2].map((n) => String(n === active)), key);
      }
      // Échap empties the field and closes the list; nothing else happens.
      await page.keyboard.press('Escape');
      assert.equal(await search.inputValue(), '');
      assert.equal(await list.isHidden(), true);
      assert.equal(await search.getAttribute('aria-expanded'), 'false');
      assert.equal(await focused(page), 'pr-search');
      assert.deepEqual(await shown(page), ['annuaire']);
      // At most eight results.
      await page.keyboard.type('e');
      assert.equal(await list.locator('li[data-hit]').count(), 8);
      await page.keyboard.press('Escape');
      // No match, and no setting of the real directory in the demonstration.
      for (const query of ['zzz', 'coordination', 'OU racine']) {
        await search.fill(query);
        assert.deepEqual(await list.locator('li').evaluateAll((nodes) => nodes.map((node) => [node.textContent, node.getAttribute('role'), node.getAttribute('aria-disabled')])),
          [['Aucun réglage ne correspond.', 'option', 'true']], query);
        assert.equal(await search.getAttribute('aria-activedescendant'), null);
        await page.keyboard.press('Enter');
        assert.deepEqual(await shown(page), ['annuaire'], query);
      }
      // Enter opens the section of the result, lights the setting up and focuses it.
      await search.fill('');
      await page.keyboard.type('animations');
      assert.deepEqual(await hits(), [['Animations', 'Interface', 'true']]);
      await page.keyboard.press('Enter');
      assert.deepEqual(await shown(page), ['interface']);
      assert.equal(await hash(page), '#/parametres?section=interface');
      assert.equal(await focused(page), 'interfaceMotion');
      assert.equal(await page.locator('main .k-field[data-name="interfaceMotion"].pr-flash').count(), 1);
      assert.equal(await search.inputValue(), '');
      assert.equal(await list.isHidden(), true);
      await frames(page);
      assert.equal(await announced(page, 'Section Interface'), 1);
      // A result without a field of its own (the note of the theme) is lit up. « / » is typed outside the select.
      await page.locator('main').focus();
      await page.keyboard.press('/');
      await page.keyboard.type('theme');
      await page.keyboard.press('Enter');
      assert.equal(await page.locator('main [data-setting="theme"].pr-flash').count(), 1);
      assert.equal(await page.locator('html').getAttribute('data-motion'), 'reduced');
      assert.deepEqual((await engineCalls(page)).filter((op) => op !== 'settings.get'), []);
    } finally { await page.close(); }
  });

  await check('Liste de recherche au-dessus du contenu : le premier résultat reçoit le point', async () => {
    const page = await openPage();
    try {
      await page.locator('main').focus();
      await page.keyboard.press('/');
      await page.keyboard.type('configuration');
      const first = page.locator('main #pr-hit-0');
      await first.waitFor();
      const point = await first.evaluate((li) => {
        const r = li.getBoundingClientRect();
        const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
        return { own: li === hit || li.contains(hit), label: li.querySelector('.pr-hit-label').textContent };
      });
      assert.deepEqual(point, { own: true, label: 'Configuration en vigueur' });
      // The last result too, even when the list covers the tiles or the rail.
      const last = await page.locator('main #pr-search-list li[data-hit]').last().evaluate((li) => {
        const r = li.getBoundingClientRect();
        const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
        return li === hit || li.contains(hit);
      });
      assert.equal(last, true);
      await first.click();
      assert.deepEqual(await shown(page), ['configuration']);
      assert.equal(await page.locator('main [data-setting="config-summary"].pr-flash').count(), 1);
      assert.equal(await page.locator('main #pr-search-list').isHidden(), true);
    } finally { await page.close(); }
  });

  await check('Clavier du rail : flèches, Début et Fin déplacent le focus ; Entrée affiche ; annonce « Section … » unique', async () => {
    const page = await openPage();
    try {
      const item = (id) => page.locator(`main .pr-nav-item[data-section="${id}"]`);
      await item('annuaire').focus();
      for (const [key, id] of [['ArrowDown', 'configuration'], ['ArrowDown', 'mises-a-jour'], ['ArrowDown', 'interface'], ['ArrowDown', 'annuaire'],
        ['ArrowUp', 'interface'], ['Home', 'annuaire'], ['End', 'interface'], ['ArrowUp', 'mises-a-jour']]) {
        await page.keyboard.press(key);
        assert.equal(await focused(page), id, key);
        // Moving the focus never shows another section.
        assert.deepEqual(await shown(page), ['annuaire'], key);
        assert.deepEqual(await current(page), ['annuaire'], key);
      }
      await page.keyboard.press('End');
      await page.keyboard.press('Enter');
      assert.deepEqual(await shown(page), ['interface']);
      assert.deepEqual(await current(page), ['interface']);
      assert.equal(await focused(page), 'interface');
      assert.equal(await hash(page), '#/parametres?section=interface');
      await page.keyboard.press('ArrowUp');
      await page.keyboard.press(' ');
      assert.deepEqual(await shown(page), ['mises-a-jour']);
      assert.equal(await focused(page), 'mises-a-jour');
      assert.equal(await hash(page), '#/parametres?section=mises-a-jour');
      // The section already shown is not announced again.
      await page.keyboard.press('Enter');
      await frames(page);
      assert.equal(await announced(page, 'Section Interface'), 1);
      assert.equal(await announced(page, 'Section Mises à jour'), 1);
      assert.equal(await announced(page, 'Section Annuaire'), 0);
      assert.deepEqual(await engineCalls(page), []);
    } finally { await page.close(); }
  });

  await check('Animations réduites : aucune classe d’entrée et défilement immédiat', async () => {
    const page = await openPage({ height: 700 });
    try {
      assert.equal(await page.locator('html').getAttribute('data-motion'), 'reduced');
      await openSection(page, 'configuration');
      assert.equal(await page.locator('main .pr-section.pr-enter').count(), 0);
      assert.equal(await page.locator('main .pr-bump').count(), 0);
      await openSection(page, 'annuaire');
      assert.equal(await page.locator('main .pr-section.pr-enter').count(), 0);
      await page.evaluate(() => { document.querySelector('main').scrollTop = 0; });
      // The Sites box starts below the fold of this short window: the search must bring it into view at once.
      assert.equal(await inView(page, 'main [name="sites"]'), false);
      await page.locator('main').focus();
      await page.keyboard.press('/');
      await page.keyboard.type('sites ou code');
      await page.keyboard.press('Enter');
      assert.equal(await inView(page, 'main [name="sites"]'), true);
      assert.equal(await focused(page), 'sites');
      const flash = await page.locator('main .pr-flash').evaluate((el) => ({ name: getComputedStyle(el, '::after').animationName, opacity: getComputedStyle(el, '::after').opacity }));
      assert.deepEqual(flash, { name: 'none', opacity: '1' });
    } finally { await page.close(); }
  });

  await check('Animations complètes : entrée finie, aucune animation infinie ajoutée par la page', async () => {
    const page = await openPage({ motion: 'full' });
    try {
      assert.equal(await page.locator('html').getAttribute('data-motion'), 'full');
      await openSection(page, 'configuration');
      const panel = page.locator('main [data-section-panel="configuration"]');
      assert.match(await panel.getAttribute('class'), /\bpr-enter\b/);
      const entry = await panel.evaluate(async (el) => {
        const own = el.getAnimations().filter((a) => a.animationName === 'pr-section-in');
        await Promise.all(own.map((a) => a.finished));
        return own.map((a) => [a.playState, a.effect.getComputedTiming().iterations]);
      });
      assert.deepEqual(entry, [['finished', 1]]);
      const infinite = await page.evaluate(() => {
        const main = document.querySelector('main');
        return document.getAnimations().filter((a) => a.effect?.getComputedTiming().iterations === Infinity && main.contains(a.effect.target))
          .map((a) => ({ name: a.animationName, ring: a.effect.target.matches('.glow-ring'), orb: a.effect.target.matches('.orb'), hero: !!a.effect.target.closest('.pr-hero-deco') }));
      });
      assert.ok(infinite.length >= 1);
      assert.deepEqual(infinite.filter((a) => !(a.hero && (a.ring || a.orb))), []);
      // Changing the section adds no looping animation.
      await openSection(page, 'interface'); await openSection(page, 'annuaire');
      const after = await page.evaluate(() => {
        const main = document.querySelector('main');
        return document.getAnimations().filter((a) => a.effect?.getComputedTiming().iterations === Infinity && main.contains(a.effect.target)).length;
      });
      assert.equal(after, infinite.length);
    } finally { await page.close(); }
  });

  await check('Contraste élevé : rail, tuiles et brouillon encadrés, halos masqués', async () => {
    const page = await openPage({ theme: 'contrast' });
    try {
      assert.equal(await page.locator('html').getAttribute('data-theme'), 'contrast');
      const frame = (selector) => page.locator(selector).evaluateAll((nodes) => nodes.map((node) => getComputedStyle(node).borderTopWidth));
      assert.deepEqual(await frame('main .pr-nav'), ['2px']);
      assert.deepEqual(await frame('main .pr-draft'), ['2px']);
      assert.deepEqual(await frame('main .pr-pulse-tile'), ['2px', '2px', '2px', '2px']);
      const hidden = await page.locator('main .pr-hero .glow-ring, main .pr-hero .orb').evaluateAll((nodes) => nodes.map((node) => getComputedStyle(node).display));
      assert.deepEqual(hidden, ['none', 'none', 'none', 'none']);
      const currentItem = await page.locator('main .pr-nav-item[aria-current="true"]').evaluate((el) => [getComputedStyle(el).outlineStyle, getComputedStyle(el).outlineWidth]);
      assert.deepEqual(currentItem, ['solid', '2px']);
      const shadows = await page.locator('main .pr-pulse-tile, main .pr-nav, main .pr-draft').evaluateAll((nodes) => nodes.map((node) => getComputedStyle(node).boxShadow));
      assert.deepEqual([...new Set(shadows)], ['none']);
      // The keyboard focus of the current item is not its state outline (first Tab stop of the rail).
      const state = await outline(page, 'main .pr-nav-item[aria-current="true"]');
      await keyboardFocus(page, 'main .pr-nav-item[aria-current="true"]');
      assert.equal(await page.locator('main .pr-nav-item[aria-current="true"]').evaluate((el) => el.matches(':focus-visible')), true);
      const focus = await outline(page, 'main .pr-nav-item[aria-current="true"]');
      assert.notEqual(focus, state);
      assert.match(focus, /^solid 3px rgb\(255, 255, 0\)/);
      // Search: an opaque list, the active result (the one Enter opens) framed, the others not.
      await page.locator('main').focus();
      await page.keyboard.press('/');
      await page.keyboard.type('mise a jour');
      await page.keyboard.press('ArrowDown');
      await frames(page);
      assert.deepEqual(await page.locator('main #pr-search-list').evaluate((el) => [getComputedStyle(el).backgroundColor, getComputedStyle(el).backdropFilter]), ['rgb(0, 0, 0)', 'none']);
      const options = await page.locator('main #pr-search-list li[data-hit]').evaluateAll((nodes) => nodes.map((node) => [node.getAttribute('aria-selected'), getComputedStyle(node).outlineStyle]));
      assert.deepEqual(options, [['false', 'none'], ['true', 'solid'], ['false', 'none']]);
    } finally { await page.close(); }
  });

  await check('Fenêtre étroite : rail au-dessus, aucun défilement horizontal', async () => {
    const page = await openPage();
    try {
      const layout = () => page.evaluate(() => {
        const main = document.querySelector('main');
        const aside = main.querySelector('.pr-aside').getBoundingClientRect();
        const content = main.querySelector('.pr-content').getBoundingClientRect();
        return { position: getComputedStyle(main.querySelector('.pr-aside')).position, beside: aside.right <= content.left + 1, above: aside.bottom <= content.top + 1,
          overflow: main.scrollWidth - main.clientWidth,
          // Elements of the page past the right edge of main (the decorative layer of the hero is clipped by its own box).
          // The window itself is not measured: the fixed aurora of the shell widens it by the same amount on every screen.
          outside: [...main.querySelectorAll('.pr-page *')].filter((el) => !el.closest('.pr-hero-deco') && el.getClientRects().length
            && el.getBoundingClientRect().right > main.getBoundingClientRect().right + 1).map((el) => el.className || el.tagName).slice(0, 5),
          pill: getComputedStyle(main.querySelector('.pr-nav-pill')).display };
      });
      const wide = await layout();
      assert.deepEqual([wide.position, wide.beside, wide.above], ['sticky', true, false]);
      assert.ok(wide.overflow <= 0 && !wide.outside.length, JSON.stringify(wide));
      // 480 px: the unbreakable example of the sites must not widen the section (it did, 13 px, where 2.0.14 had none).
      for (const width of [900, 700, 480]) {
        await page.setViewportSize({ width, height: 900 });
        for (const s of RAIL) {
          await openSection(page, s.id);
          await frames(page);
          const narrow = await layout();
          assert.deepEqual([narrow.position, narrow.above, narrow.pill], ['static', true, 'none'], `${width} ${s.id}`);
          assert.ok(narrow.overflow <= 0 && !narrow.outside.length, `${width} ${s.id} ${JSON.stringify(narrow)}`);
        }
      }
    } finally { await page.close(); }
  });

  await check('Tuile Démonstration : visible en simulation, ouvre Interface', async () => {
    const page = await openPage();
    try {
      const tile = (id) => page.locator(`main [data-pulse="${id}"]`);
      assert.deepEqual(await page.locator('main .pr-pulse-tile').evaluateAll((nodes) => nodes.map((node) => node.dataset.pulse)), ['configuration', 'nommage', 'demonstration', 'brouillon']);
      assert.equal(await tile('politiques').count(), 0);
      assert.equal(await page.getByRole('group', { name: 'État des paramètres', exact: true }).count(), 1);
      const text = (id) => tile(id).evaluate((el) => [el.querySelector('.pr-pulse-k').textContent, el.querySelector('.pr-pulse-v').textContent, el.querySelector('.pr-pulse-s').textContent]);
      assert.deepEqual(await text('configuration'), ['Configuration', 'Démonstration', 'Monde fictif']);
      assert.deepEqual(await text('nommage'), ['Nommage', '111301', '{type}{prefix}{site}{service}{number:3}']);
      assert.deepEqual(await text('demonstration'), ['Démonstration', 'Active', 'Aucun effet réel']);
      assert.deepEqual(await text('brouillon'), ['Brouillon', 'Enregistré', 'Aucune modification en attente']);
      assert.equal(await page.locator('main [data-setting="config-summary"] [data-summary-title]').textContent(), 'Configuration de démonstration');
      assert.equal(await page.locator('main [aria-busy="true"], main .skeleton').count(), 0);
      await tile('demonstration').click();
      await page.locator('main [data-section-panel="interface"]:not([hidden])').waitFor();
      assert.equal(await hash(page), '#/parametres?section=interface');
      assert.equal(await focused(page), 'pr-panel-interface');
      await frames(page);
      assert.equal(await announced(page, 'Section Interface'), 1);
      assert.deepEqual(await engineCalls(page), []);
    } finally { await page.close(); }
  });

  await check('Brouillon : conservé entre les sections, pastille et tuile, aucun appel moteur', async () => {
    const page = await openPage();
    try {
      await page.evaluate(() => { document.querySelector('main').firstElementChild.dataset.mount = 'first'; });
      const randomNames = await page.locator('main [name="randomNames"]').isChecked();
      await page.locator('main [name="prefix"]').fill('222222');
      await page.locator('main [name="randomNames"]').setChecked(!randomNames);
      for (const id of ['configuration', 'mises-a-jour', 'interface', 'annuaire', 'interface']) await openSection(page, id);
      assert.equal(await page.evaluate(() => document.querySelector('main').firstElementChild.dataset.mount), 'first');
      assert.equal(await page.locator('main [name="prefix"]').inputValue(), '222222');
      assert.equal(await page.locator('main [data-badge="annuaire"]').isVisible(), true);
      assert.equal(await page.locator('main [data-pulse="brouillon"] .pr-pulse-v').textContent(), 'Modifié');
      assert.match(await page.locator('main .pr-nav-item[data-section="annuaire"]').evaluate((el) => el.textContent), /modifications non enregistrées/);
      assert.deepEqual(await engineCalls(page), []);
      // The Brouillon tile leads to the first section changed.
      await page.locator('main [data-pulse="brouillon"]').click();
      assert.deepEqual(await shown(page), ['annuaire']);
      assert.equal(await hash(page), '#/parametres');
      // Back to the saved value: no badge, the tile says so.
      await page.locator('main [name="prefix"]').fill('111301');
      assert.equal(await page.locator('main [data-badge="annuaire"]').isVisible(), true);
      await page.locator('main [name="randomNames"]').setChecked(randomNames);
      assert.equal(await page.locator('main [data-badge="annuaire"]').isHidden(), true);
      assert.equal(await page.locator('main [data-pulse="brouillon"] .pr-pulse-v').textContent(), 'Enregistré');
      assert.deepEqual(await engineCalls(page), []);
    } finally { await page.close(); }
  });

  await check('Refus du moteur simulé : Annuaire s’ouvre et le motif est sous les sites', async () => {
    const page = await openPage();
    try {
      // The browser simulation accepts at most eight characters; the form allows ten: the engine refuses.
      await page.locator('main [name="prefix"]').fill('ABCDEFGHI');
      await openSection(page, 'interface');
      await page.getByRole('button', { name: 'Enregistrer', exact: true }).click();
      const dialog = page.getByRole('alertdialog', { name: 'Enregistrer les paramètres' });
      await dialog.waitFor();
      await dialog.getByRole('button', { name: 'Enregistrer', exact: true }).click();
      await page.waitForFunction(() => !document.querySelector('main [data-slot="sites-msg"]').hidden);
      assert.deepEqual(await shown(page), ['annuaire']);
      assert.equal(await hash(page), '#/parametres');
      assert.match(await page.locator('main [data-slot="sites-msg"]').innerText(), /Le préfixe doit contenir de 1 à 8 caractères alphanumériques\./);
      assert.equal(await page.locator('main [data-slot="sites-msg"]').isVisible(), true);
      assert.equal(await page.locator('main [name="prefix"]').inputValue(), 'ABCDEFGHI');
      assert.deepEqual(await engineCalls(page), ['settings.save']);
      assert.equal(await announced(page, 'Section Annuaire'), 0);
    } finally { await page.close(); }
  });

  await check('Entrée « Paramètres » du menu depuis une autre section : Annuaire sur place, sans remontage, garde ni appel', async () => {
    const page = await openPage();
    try {
      const mount = () => page.evaluate(() => document.querySelector('main').firstElementChild.dataset.mount);
      await page.evaluate(() => { document.querySelector('main').firstElementChild.dataset.mount = 'first'; });
      await page.locator('main [name="prefix"]').fill('222222');
      await openSection(page, 'interface');
      assert.equal(await hash(page), '#/parametres?section=interface');
      await page.locator('.nav-item[data-id="parametres"]').click();
      await page.locator('main [data-section-panel="annuaire"]:not([hidden])').waitFor();
      await frames(page);
      assert.equal(await hash(page), '#/parametres');
      assert.deepEqual(await shown(page), ['annuaire']);
      assert.deepEqual(await current(page), ['annuaire']);
      assert.equal(await focused(page), 'pr-panel-annuaire');
      assert.equal(await mount(), 'first');
      assert.equal(await page.locator('main [name="prefix"]').inputValue(), '222222');
      assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
      assert.equal(await announced(page, 'Section Annuaire'), 1);
      // Already on Annuaire, as in 2.0.14: nothing happens.
      await page.locator('.nav-item[data-id="parametres"]').click();
      await frames(page);
      assert.equal(await announced(page, 'Section Annuaire'), 1);
      assert.equal(await mount(), 'first');
      assert.deepEqual(await engineCalls(page), []);
      // Another entry of the menu still leaves through the guard of the draft.
      await page.locator('.nav-item[data-id="accueil"]').click();
      const guard = page.locator('.k-dlg-layer:not(.leaving) .k-dlg').last();
      await guard.waitFor();
      assert.equal(await guard.locator('h2').innerText(), 'Quitter les paramètres');
      await guard.locator('[data-id="cancel"]').click(); await guard.waitFor({ state: 'hidden' });
      assert.equal(await hash(page), '#/parametres');
      assert.equal(await mount(), 'first');
      assert.equal(await page.locator('main [name="prefix"]').inputValue(), '222222');
    } finally { await page.close(); }
  });

  await check('Recherche d’un réglage sans contrôle actif : le focus suit le bloc éclairé, jamais le champ sorti de la vue', async () => {
    const page = await openPage({ width: 900, height: 900 });
    try {
      const where = () => page.evaluate(() => {
        const el = document.activeElement;
        const view = document.querySelector('main').getBoundingClientRect();
        const box = el.getBoundingClientRect();
        return { tag: el.tagName, setting: el.dataset.setting ?? null, actions: [...el.querySelectorAll('[data-maint]')].map((b) => [b.dataset.maint, b.disabled]),
          tabindex: el.getAttribute('tabindex'), inView: box.top >= view.top - 1 && box.bottom <= view.bottom + 1 };
      });
      // Every maintenance action is disabled in the demonstration.
      await page.locator('main').focus();
      await page.keyboard.press('/');
      await page.keyboard.type('zip');
      await page.keyboard.press('Enter');
      assert.deepEqual(await shown(page), ['mises-a-jour']);
      assert.deepEqual(await where(), { tag: 'DIV', setting: null, actions: [['zip', true], ['folder', true]], tabindex: '-1', inView: true });
      assert.deepEqual((await flashed(page)).at(-1), ['zip', 'folder']);
      // The borrowed tabindex leaves with the focus.
      await page.keyboard.press('Tab');
      assert.equal(await page.locator('main .row-actions[tabindex]').count(), 0);
      // A note without control.
      await page.locator('main').focus();
      await page.keyboard.press('/');
      await page.keyboard.type('theme');
      await page.keyboard.press('Enter');
      assert.deepEqual(await shown(page), ['interface']);
      assert.deepEqual(await where(), { tag: 'P', setting: 'theme', actions: [], tabindex: '-1', inView: true });
      assert.deepEqual((await engineCalls(page)).filter((op) => op !== 'settings.get'), []);
    } finally { await page.close(); }
  });

  await check('Fenêtre étroite : une tuile ramène sa section à l’écran et lui donne un focus visible', async () => {
    const page = await openPage({ width: 900, height: 760 });
    try {
      const head = () => page.evaluate(() => {
        const view = document.querySelector('main').getBoundingClientRect();
        const box = document.querySelector('main [data-section-panel="interface"] .pr-sec-head').getBoundingClientRect();
        return box.top >= view.top - 1 && box.bottom <= view.bottom + 1;
      });
      await keyboardFocus(page, 'main [data-pulse="demonstration"]');
      await page.keyboard.press('Enter');
      await page.locator('main [data-section-panel="interface"]:not([hidden])').waitFor();
      assert.equal(await focused(page), 'pr-panel-interface');
      assert.equal(await head(), true);
      assert.match(await outline(page, 'main [data-section-panel="interface"]'), /^solid 3px /);
      // In a wide window the panel is already in view: nothing scrolls.
      await page.setViewportSize({ width: 1440, height: 1000 });
      await openSection(page, 'annuaire');
      await page.evaluate(() => { document.querySelector('main').scrollTop = 0; });
      await page.locator('main [data-pulse="demonstration"]').click();
      await page.locator('main [data-section-panel="interface"]:not([hidden])').waitFor();
      assert.equal(await page.evaluate(() => document.querySelector('main').scrollTop), 0);
      assert.equal(await head(), true);
      // A click gives the focus without the keyboard ring.
      assert.equal(await outline(page, 'main [data-section-panel="interface"]').then((value) => value.split(' ')[0]), 'none');
    } finally { await page.close(); }
  });

  await check('Couleurs forcées : focus de l’élément courant distinct, résultat actif marqué, icônes visibles', async () => {
    const page = await openPage({ forced: true });
    try {
      assert.equal(await page.evaluate(() => matchMedia('(forced-colors: active)').matches), true);
      const state = await outline(page, 'main .pr-nav-item[aria-current="true"]');
      await keyboardFocus(page, 'main .pr-nav-item[aria-current="true"]');
      assert.notEqual(await outline(page, 'main .pr-nav-item[aria-current="true"]'), state);
      assert.match(await outline(page, 'main .pr-nav-item[aria-current="true"]'), /^solid 3px /);
      // System colors as this browser paints them (a probe left to the page’s own colors).
      const system = await page.evaluate(() => Object.fromEntries(['Highlight', 'HighlightText', 'Canvas'].map((name) => {
        const probe = document.createElement('i');
        probe.style.setProperty('forced-color-adjust', 'none'); probe.style.setProperty('color', name);
        document.body.append(probe); const value = getComputedStyle(probe).color; probe.remove();
        return [name, value];
      })));
      assert.notEqual(system.Highlight, system.Canvas);
      // Icons on a gradient (the gradient is dropped) keep a Highlight plate with HighlightText, never white on Canvas.
      const plates = await page.locator('main .pr-nav-item[aria-current="true"] .pr-nav-ico, main [data-section-panel="annuaire"] .pr-sec-icon')
        .evaluateAll((nodes) => nodes.map((node) => { const css = getComputedStyle(node); return [css.backgroundColor, css.color]; }));
      assert.deepEqual(plates, [[system.Highlight, system.HighlightText], [system.Highlight, system.HighlightText]]);
      await page.locator('main').focus();
      await page.keyboard.press('/');
      await page.keyboard.type('mise a jour');
      await page.keyboard.press('ArrowDown');
      await frames(page);
      // On a loaded Windows runner the new selection may not be painted yet after two frames: wait for it (5 s at most),
      // then read. The assertions below stay exact; a selection that never turns Highlight still fails.
      await page.waitForFunction((highlight) => {
        const li = document.querySelector('main #pr-search-list li[aria-selected="true"]');
        return Boolean(li) && getComputedStyle(li).backgroundColor === highlight;
      }, system.Highlight, { timeout: 5000 }).catch(() => {});
      const options = await page.locator('main #pr-search-list li[data-hit]').evaluateAll((nodes) => nodes.map((node) => [node.getAttribute('aria-selected'), getComputedStyle(node).backgroundColor]));
      // The active result is painted Highlight; the others keep the list’s own background.
      assert.deepEqual(options.map((o) => o[0]), ['false', 'true', 'false']);
      assert.equal(options[1][1], system.Highlight);
      assert.notEqual(options[0][1], system.Highlight); assert.notEqual(options[2][1], system.Highlight);
      assert.equal(await page.locator('main #pr-search-list').evaluate((el) => getComputedStyle(el).backdropFilter), 'none');
    } finally { await page.close(); }
  });

  await check('Aucune erreur de module ou de console, ni requête externe', async () => assert.deepEqual(errors, []));
} finally {
  await browser?.close();
  await new Promise((done) => server.close(done));
}
console.log(`\n${checks - failures}/${checks} contrôles du rail des paramètres réussis (simulation Chromium, sans qualification native).`);
process.exitCode = failures || checks === 0 ? 1 : 0;
