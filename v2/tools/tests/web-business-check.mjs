// Actual Chromium interactions with Pesto modules, using an explicit in-memory native-channel fixture.
// Never calls Windows/AD. No browser installation/download. Same PESTO_* environment as web-dom-check.mjs.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, extname, isAbsolute, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
// « Un poste » reads this PC on arrival (fictitious NOUVEAU-PC, absent from the directory): read counts below
// leave that first read aside. It targets this PC by default: searching another computer starts with that explicit choice.
const pickRemote = async (page) => { const remote = page.locator('[data-form="target"] input[value="remote"]'); if (await remote.count()) await remote.check(); };
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
  const makePage = async (route, kind = 'rename', status = 'succeeded', options = {}) => {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    page.setDefaultTimeout(5000);
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    await page.addInitScript(({ kind, status, options }) => {
      localStorage.setItem('pesto.prefs.v1', JSON.stringify({ theme: 'light', motion: 'reduced' }));
      window.fixture = { kind, status, sessionComputer: options.sessionComputer ?? null, localJoined: 'localJoined' in options ? options.localJoined : 'unset', reserveInAd: false, holdPreview: false, holdInspect: false, holdPrepare: false,
        holdSites: false, holdQueueAdd: false, sitesError: null, previewError: null, siteAsCode: true, inspectionPatch: {}, releases: {}, calls: [], ...options };
      let receive;
      window.chrome ??= {};
      window.chrome.webview = {
        addEventListener(type, fn) { if (type === 'message') receive = fn; },
        async postMessage(request) {
          const control = window.fixture;
          control.calls.push({ op: request.op, args: request.args });
          try {
            const { browserSimulation } = await import('/js/simulation.js');
            if (request.op === control.raceAt && !control.nameClaimed) {
              control.nameClaimed = true;
              throw Object.assign(new Error('Le nom a été pris entre-temps.'), { code: 'name.taken' });
            }
            const fixtureSite = ['directory.services', 'names.preview'].includes(request.op)
              ? control.siteItems?.find(site => site.id === request.args.site) : null;
            const args = fixtureSite ? { ...request.args, site: fixtureSite.code } : { ...request.args };
            if (request.op === 'names.preview' && control.nameClaimed) args.alternative = true;
            const stagingOu = 'OU=Staging,OU=Postes,DC=example,DC=local';
            const staging = control.preprod && request.args.purpose === 'join';
            const data = request.op === 'reservations.list' ? { items: [] }
              : staging && request.op === 'directory.sites' ? { locked: true, items: [{ id: 'PREPROD', name: 'Préproduction', code: 'PR', selector: stagingOu, ou: stagingOu }] }
              : staging && request.op === 'directory.services' ? { locked: true, items: [{ code: '765', name: '765' }] }
              : staging && request.op === 'names.preview' ? { complete: true, previewId: 'preprod-preview', name: 'P111301PR765001', ou: stagingOu, expiresAt: '2099-01-01T00:00:00Z' }
              : await browserSimulation.invoke(request.op, args);
            if (request.op === 'session.info') { data.mode = 'live'; data.readOnly = false; }
            // Deliberately stale capability in this fixture: the UI must also guard the local membership fact.
            if (request.op === 'session.info' && control.localJoined !== 'unset') data.localJoined = control.localJoined;
            if (request.op === 'session.info' && control.sessionComputer) {
              data.computer = control.sessionComputer;
              if (control.localJoined === 'unset') delete data.localJoined;
              data.capabilities = data.capabilities.map((c) => c.id === 'join' ? { ...c, enabled: true, reason: null } : c);
            }
            if (request.op === 'directory.sites') {
              if (control.holdSites) await new Promise((done) => { control.releases.sites = done; });
              if (control.sitesError) throw Object.assign(new Error(control.sitesError), { code: 'directory.unavailable' });
              if (control.siteItems) data.items = structuredClone(control.siteItems);
            }
            if (request.op === 'directory.services' && control.emptyServices) data.items = [];
            if (request.op === 'computer.inspect') {
              if (control.siteAsCode) data.site = { paris: 'PA', lyon: 'LY' }[data.site] ?? data.site;
              Object.assign(data, control.inspectionPatch);
            }
            if (request.op === 'names.preview' && control.previewError) throw Object.assign(new Error(control.previewError), { code: 'names.unavailable' });
            if (request.op === 'operation.prepare') data.mode = 'live';
            if (request.op === 'queue.prepare') data.items = data.items.map(plan => ({ ...plan, mode: 'live' }));
            if (request.op === 'names.preview' && control.holdPreview) await new Promise((done) => { control.releases.preview = done; });
            if (request.op === 'computer.inspect' && control.holdInspect) await new Promise((done) => { control.releases[request.args.computer] = done; });
            if (request.op === 'operation.prepare' && request.args.kind === 'join' && control.reserveInAd) data.reservationRequired = true;
            if (request.op === 'operation.prepare' && control.holdPrepare) await new Promise((done) => { control.releases.prepare = done; });
            if (request.op === 'queue.add' && control.holdQueueAdd) await new Promise((done) => { control.releases.queueAdd = done; });
            if (request.op === 'operation.execute') {
              data.mode = 'live · test navigateur';
              data.status = data.kind === control.kind ? control.status : 'succeeded';
              data.restartRequired = data.status === 'pendingRestart';
              if (control.operationReceiptPatch) Object.assign(data, control.operationReceiptPatch);
              if (control.receiptIdentityLowerCase) for (const field of ['computer', 'newName', 'targetOU']) data[field] = data[field]?.toLowerCase();
            }
            if (request.op === 'queue.execute') {
              data.receipts = data.receipts.map((receipt) => ({ ...receipt, mode: 'live · test navigateur', status: control.status, restartRequired: control.status === 'pendingRestart' }));
              if (control.queueReceiptFault === 'missing') data.receipts = data.receipts.slice(0, 1);
              if (control.queueReceiptFault === 'duplicate') data.receipts = [data.receipts[0], structuredClone(data.receipts[0])];
              if (control.queueReceiptFault === 'foreign') data.receipts[1].newName = 'OTHER-PC';
              if (control.receiptIdentityLowerCase) for (const receipt of data.receipts) for (const field of ['computer', 'newName', 'targetOU']) receipt[field] = receipt[field]?.toLowerCase();
              data.stopped = false; // A transport result alone must never make an unconfirmed receipt successful.
            }
            receive({ data: { id: request.id, kind: 'result', data } });
          } catch (e) { receive({ data: { id: request.id, kind: 'error', error: { code: e.code || 'fixture', message: e.message } } }); }
        },
      };
    }, { kind, status, options });
    await page.goto(`http://127.0.0.1:${server.address().port}/#/${route}`);
    if (options.holdSites) {
      await page.locator('[data-form="target"] input[value="remote"]').waitFor({ state: 'attached' });
      await pickRemote(page); await page.locator('[data-form="search"] [name="query"]').waitFor();
    }
    else await page.waitForFunction((route) => document.documentElement.dataset.ready === route, route);
    return page;
  };
  for (const localJoined of [true, null]) {
    await check(`Jonction V1 : appartenance ${localJoined}, aucun formulaire ni calcul proposé`, async () => {
      const page = await makePage('ajouter', 'join', 'succeeded', { localJoined });
      try {
        await page.locator('[data-zone="join-block"]').waitFor();
        assert.equal(await page.locator('[data-zone="join-controls"]').isVisible(), false);
        assert.equal(await page.locator('[data-act="add"]').isEnabled(), false);
        assert.equal(await page.locator('[data-zone="offline-entry"]').isVisible(), false);
        assert.match(await page.locator('[data-join-reason]').innerText(), localJoined ? /déjà membre/ : /inconnue/);
        const calls = await page.evaluate(() => window.fixture.calls);
        assert.equal(calls.filter(c => ['directory.sites', 'names.preview', 'join.precreated.preview', 'operation.prepare'].includes(c.op)).length, 0);
        if (localJoined === null) {
          await page.evaluate(() => { window.fixture.localJoined = false; });
          await page.locator('[data-act="reread-membership"]').click();
          await page.locator('main .name-preview .name').waitFor();
          assert.equal(await page.locator('[data-act="add"]').isEnabled(), true);
        }
      } finally { await page.close(); }
    });
  }
  await check('Jonction V1 : préproduction impose seul site et service jusque dans l’aperçu', async () => {
    const page = await makePage('ajouter', 'join', 'succeeded', { preprod: true, localJoined: false });
    try {
      await page.locator('main .name-preview .name').waitFor();
      assert.equal(await page.locator('[name="site"] option').count(), 1);
      assert.equal(await page.locator('[name="site"]').isEnabled(), false);
      assert.equal(await page.locator('[name="service"] + datalist option').count(), 0);
      assert.equal(await page.locator('[name="service"]').inputValue(), '765');
      assert.equal(await page.locator('[name="service"]').isEnabled(), false);
      assert.match(await page.locator('[data-zone="preview"]').innerText(), /OU=Staging/);
      assert.equal(await page.locator('[data-act="add"]').isEnabled(), true);
      const calls = await page.evaluate(() => window.fixture.calls);
      for (const op of ['directory.sites', 'directory.services', 'names.preview']) assert.equal(calls.find(c => c.op === op).args.purpose, 'join');
    } finally { await page.close(); }
  });
  const selectComputer = async (page, name = 'P111301PAINF001') => {
    await pickRemote(page);
    await page.locator('[data-form="search"] [name="query"]').fill(name);
    await page.locator('[data-form="search"] [name="query"]').press('Enter');
    await page.locator(`[data-pick="${name}"]`).click();
    await page.locator('[data-form="rename"] [name="service"] + datalist option[value="INF"]').waitFor({ state: 'attached' });
  };
  const preview = async (page, form) => {
    await page.locator(`[data-form="${form}"] button[type="submit"]`).click();
    await page.locator('main .name-preview .name').waitFor();
  };
  const confirm = async (page, act, { typed = false } = {}) => {
    await page.locator(`[data-act="${act}"]`).click();
    const dialog = page.locator('.k-dlg'); await dialog.waitFor();
    if (typed) {
      const target = await dialog.locator('.k-cw-target b').innerText();
      await dialog.locator('.k-cw-typed input').pressSequentially(target);
    } else assert.equal(await dialog.locator('.k-cw-typed').count(), 0);
    await dialog.locator('[data-id="confirm"]').click();
    await dialog.waitFor({ state: 'hidden' });
  };
  for (const [route, kind] of [['ajouter', 'join'], ['unposte', 'rename'], ['noms', 'preview']]) {
    await check(`${kind} : le changement de service recalcule le nom en direct sans clic ni écriture`, async () => {
      const page = await makePage(route, kind);
      try {
        if (kind === 'rename') await selectComputer(page);
        const service = page.locator(`[data-form="${kind}"] [name="service"]`);
        await page.locator(`[data-form="${kind}"] [name="service"] + datalist option`).first().waitFor({ state: 'attached' });
        const next = await page.locator(`[data-form="${kind}"] [name="service"] + datalist option`).first().getAttribute('value');
        await service.fill(next);
        await page.waitForFunction(code => document.querySelector('main .name-preview .name')?.textContent.includes(code), next);
        const calls = await page.evaluate(() => window.fixture.calls);
        assert.equal(calls.filter(c => c.op === 'names.preview').at(-1).args.service, next);
        assert.equal(calls.filter(c => c.op === 'operation.prepare' || c.op === 'operation.execute').length, 0);
      } finally { await page.close(); }
    });
  }

  for (const kind of ['rename', 'join']) for (const raceAt of ['operation.prepare', 'operation.execute']) {
    await check(`${kind} : nom pris à ${raceAt}, l'interface montre un nouvel aperçu sans rejouer l'opération`, async () => {
      const page = await makePage(kind === 'join' ? 'ajouter' : 'unposte', kind, 'succeeded', { raceAt });
      try {
        if (kind === 'rename') await selectComputer(page);
        await preview(page, kind);
        const before = await page.locator('main .name-preview .name').innerText();
        const act = kind === 'join' ? 'add' : 'apply';
        if (raceAt === 'operation.prepare') await page.locator(`[data-act="${act}"]`).click();
        else await confirm(page, act);
        await page.waitForFunction(old => {
          const newName = document.querySelector('main .name-preview .name')?.textContent;
          return newName && newName !== old;
        }, before);
        const requests = await page.evaluate(() => window.fixture.calls.map(call => call.op));
        assert.equal(requests.filter(op => op === 'operation.prepare').length, 1);
        assert.equal(requests.filter(op => op === 'operation.execute').length, raceAt === 'operation.execute' ? 1 : 0);
        assert.equal(await page.locator('.k-dlg').count(), 0);
      } finally { await page.close(); }
    });
  }

  for (const kind of ['join', 'rename', 'move']) for (const status of ['succeeded', 'pendingRestart', 'uncertain', 'refused']) {
    await check(`${kind}/${status} : message métier exact et aucune suite sur résultat non confirmé`, async () => {
      const page = await makePage(kind === 'join' ? 'ajouter' : 'unposte', kind, status);
      try {
        if (kind !== 'join') await selectComputer(page);
        await preview(page, kind === 'join' ? 'join' : 'rename');
        await confirm(page, kind === 'join' ? 'add' : 'apply');
        if (kind === 'move') {
          await page.locator('[data-act="domove"]').waitFor();
          await confirm(page, 'domove');
        }
        await page.waitForFunction(({ kind, status }) => {
          const card = document.querySelector('[data-zone="receipt"] .receipt-card');
          return card?.dataset.status === status && card.querySelector('h3')?.textContent.startsWith({ join: 'Jonction', rename: 'Renommage', move: 'Déplacement' }[kind]);
        }, { kind, status });
        const toasts = await page.locator('.toasts').innerText();
        assert.doesNotMatch(toasts, /terminé/);
        if (status === 'pendingRestart') assert.match(toasts, /redémarrage à planifier/);
        if (status === 'uncertain') assert.match(toasts, /résultat incertain/);
        if (status === 'refused') assert.match(toasts, /refusé/);
        if (kind === 'rename' && status !== 'succeeded') {
          assert.equal(await page.locator('[data-act="domove"]').count(), 0);
          assert.equal(await page.evaluate(() => window.fixture.calls.filter((c) => (c.op === 'computer.inspect' && c.args.computer !== 'NOUVEAU-PC')).length), 1);
        }
        if (kind === 'join' && status !== 'succeeded') assert.equal(await page.evaluate(() => window.fixture.calls.filter((c) => c.op === 'session.info').length), 1);
        assert.equal(await page.evaluate(() => window.fixture.calls.filter((c) => c.op === 'operation.execute').length), kind === 'move' ? 2 : 1);
      } finally { await page.close(); }
    });
  }
  for (const [kind, label, operationReceiptPatch] of [
    ['join', 'poste étranger', { computer: 'OTHER-PC' }],
    ['rename', 'nom final étranger', { newName: 'OTHER-PC' }],
    ['rename', 'OU étrangère', { targetOU: 'OU=Other,DC=example,DC=local' }],
    ['rename', 'mode différent', { mode: 'simulation' }],
    ['rename', 'identifiant absent', { id: '' }],
  ]) await check(`Reçu isolé incohérent (${label}) : aucun succès ni lecture suivante`, async () => {
    const page = await makePage(kind === 'join' ? 'ajouter' : 'unposte', kind, 'succeeded', { operationReceiptPatch });
    try {
      if (kind !== 'join') await selectComputer(page);
      await preview(page, kind === 'join' ? 'join' : 'rename');
      await confirm(page, kind === 'join' ? 'add' : 'apply');
      const zone = page.locator(kind === 'join' ? '[data-zone="receipt"]' : '[data-zone="rpreview"]');
      await zone.locator('[role="alert"]').waitFor();
      assert.match(await zone.innerText(), /reçu.*plan confirmé/i);
      assert.equal(await page.locator('[data-zone="receipt"] .receipt-card').count(), 0);
      assert.doesNotMatch(await page.locator('.toasts').innerText(), /confirmé.{0,4} par le moteur/);
      const calls = await page.evaluate(() => window.fixture.calls);
      assert.equal(calls.filter(c => c.op === 'operation.execute').length, 1);
      assert.equal(calls.filter(c => (c.op === 'computer.inspect' && c.args.computer !== 'NOUVEAU-PC')).length, kind === 'join' ? 0 : 1);
      assert.equal(calls.filter(c => c.op === 'session.info').length, 1);
    } finally { await page.close(); }
  });
  for (const [status, code] of [['succeeded', '0'], ['pendingRestart', '20'], ['uncertain', '89']])
    await check(`Reçu isolé ${status}/${code} : casse AD acceptée et état partiel conservé`, async () => {
      const page = await makePage('unposte', 'rename', status, { receiptIdentityLowerCase: true, operationReceiptPatch: { code } });
      try {
        await selectComputer(page); await preview(page, 'rename'); await confirm(page, 'apply');
        await page.locator(`[data-zone="receipt"] [data-status="${status}"]`).waitFor();
        const summary = await page.locator('.toasts').innerText();
        if (status === 'succeeded') assert.match(summary, /confirmé par le moteur/);
        else {
          assert.doesNotMatch(summary, /confirmé par le moteur/);
          assert.equal(await page.locator('[data-act="domove"]').count(), 0);
          assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => (c.op === 'computer.inspect' && c.args.computer !== 'NOUVEAU-PC')).length), 1);
        }
        assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'operation.execute').length), 1);
      } finally { await page.close(); }
    });
  await check('Jonction avec réservation AD : création annoncée dans la confirmation, annulation sans envoi', async () => {
    const page = await makePage('ajouter', 'join', 'pendingRestart');
    try {
      await page.evaluate(() => { window.fixture.reserveInAd = true; });
      await preview(page, 'join');
      const expected = await page.locator('main .name-preview .name').innerText();
      await page.locator('[data-act="add"]').click();
      const modal = page.locator('.k-dlg'); await modal.waitFor();
      assert.match(await modal.innerText(), /créera le compte ordinateur réservé/);
      assert.match(await modal.innerText(), /compte et son reçu seront conservés/);
      assert.equal(await modal.locator('.k-cw-target b').innerText(), expected);
      assert.equal(await page.evaluate(() => window.fixture.calls.filter((c) => c.op === 'operation.execute').length), 0);
      await modal.locator('[data-id="cancel"]').click(); await modal.waitFor({ state: 'hidden' });
      assert.equal(await page.evaluate(() => window.fixture.calls.filter((c) => c.op === 'operation.execute').length), 0);
    } finally { await page.close(); }
  });
  for (const status of ['succeeded', 'pendingRestart', 'uncertain', 'refused']) await check(`queue/${status} : synthèse du lot fondée sur chaque reçu`, async () => {
    const page = await makePage('plusieurspostes', 'queue', status);
    try {
      await page.locator('[name="list"]').fill('P111301PAINF001');
      await page.getByRole('button', { name: 'Analyser la liste', exact: true }).click();
      await page.getByRole('button', { name: 'Ajouter à la file', exact: true }).click();
      await page.getByRole('button', { name: 'Préparer le lot', exact: true }).click();
      await confirm(page, 'execute', { typed: true });
      await page.locator(`[data-zone="receipt"] [data-status="${status}"]`).waitFor();
      const summary = await page.locator('.toasts').innerText();
      if (status === 'succeeded') assert.match(summary, /Lot confirmé/);
      else { assert.match(summary, /Lot à vérifier/); assert.doesNotMatch(summary, /Lot confirmé/); }
      assert.equal(await page.evaluate(() => window.fixture.calls.filter((c) => c.op === 'queue.execute').length), 1);
    } finally { await page.close(); }
  });
  await check('Lot : casse Windows/AD équivalente des reçus acceptée', async () => {
    const page = await makePage('plusieurspostes', 'queue', 'succeeded', { receiptIdentityLowerCase: true });
    try {
      await page.locator('[name="list"]').fill('P111301PAINF001\nS111301PAADM001');
      await page.getByRole('button', { name: 'Analyser la liste', exact: true }).click();
      await page.locator('[data-act="addqueue"]').click(); await page.locator('[data-act="prepare"]').click();
      await confirm(page, 'execute', { typed: true });
      await page.locator('[data-zone="receipt"] [data-status="succeeded"]').first().waitFor();
      assert.match(await page.locator('.toasts').innerText(), /Lot confirmé : 2 reçu/);
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'queue.execute').length), 1);
    } finally { await page.close(); }
  });
  for (const [name, type] of [['P111301PAINF001', 'P'], ['V111301LYINF001', 'V']]) {
    await check(`Lot terrain : type natif ${type} conservé sans modèle matériel`, async () => {
      const page = await makePage('plusieurspostes', 'queue', 'succeeded', { inspectionPatch: { type, model: null } });
      try {
        await page.locator('[name="list"]').fill(name);
        await page.getByRole('button', { name: 'Analyser la liste', exact: true }).click();
        await page.locator('[data-act="addqueue"]').click();
        await page.waitForFunction(() => window.fixture.calls.some(c => c.op === 'queue.add') && !document.querySelector('[data-act="prepare"]').disabled);
        const calls = await page.evaluate(() => window.fixture.calls);
        assert.equal(calls.find(c => c.op === 'names.preview').args.type, type);
        assert.equal(calls.filter(c => c.op === 'queue.add').length, 1);
        assert.match(await page.locator('[data-zone="queue-list"]').innerText(), new RegExp(`→\\s*${type}111301`));
        assert.equal(calls.filter(c => c.op === 'queue.execute').length, 0);
      } finally { await page.close(); }
    });
  }
  for (const queueReceiptFault of ['missing', 'duplicate', 'foreign']) await check(`Lot terrain : reçus ${queueReceiptFault} ne confirment pas le lot complet`, async () => {
    const page = await makePage('plusieurspostes', 'queue', 'succeeded', { queueReceiptFault });
    try {
      await page.locator('[name="list"]').fill('P111301PAINF001\nS111301PAADM001');
      await page.getByRole('button', { name: 'Analyser la liste', exact: true }).click();
      await page.locator('[data-act="addqueue"]').click(); await page.locator('[data-act="prepare"]').click();
      await confirm(page, 'execute', { typed: true });
      await page.locator('[data-zone="receipt"] [role="alert"]').waitFor();
      assert.match(await page.locator('.toasts').innerText(), /Lot à vérifier/);
      assert.doesNotMatch(await page.locator('.toasts').innerText(), /Lot confirmé/);
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'queue.execute').length), 1);
      assert.equal(await page.locator('[data-act="execute"]').count(), 0);
    } finally { await page.close(); }
  });
  await check('Lot terrain : identité incomplète corrigée en réimportant le CSV du poste sélectionné', async () => {
    const page = await makePage('plusieurspostes', 'queue', 'succeeded', { inspectionPatch: { type: null, model: null, site: null, service: null } });
    try {
      await page.locator('[name="list"]').fill('P111301PAINF001');
      await page.getByRole('button', { name: 'Analyser la liste', exact: true }).click(); await page.locator('[data-act="addqueue"]').click();
      await page.waitForFunction(() => document.querySelector('[data-zone="add-report"]').textContent.includes('Identité incomplète'));
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'names.preview' || c.op === 'queue.add').length), 0);
      await page.locator('[data-act="csvfile"]').setInputFiles({ name: 'postes.csv', mimeType: 'text/csv', buffer: Buffer.from('name;type;site;service\nP111301PAINF001;P;PA;INF') });
      await page.waitForFunction(() => document.querySelector('[data-zone="csv-report"]').textContent.includes('1 mise(s) à jour'));
      assert.match(await page.locator('[data-zone="sel-list"]').innerText(), /CSV · type P · site PA · service INF/);
      assert.equal(await page.locator('[data-drop]').count(), 1);
      await page.locator('[data-act="addqueue"]').click();
      await page.waitForFunction(() => window.fixture.calls.some(c => c.op === 'queue.add') && !document.querySelector('[data-act="prepare"]').disabled);
      const calls = await page.evaluate(() => window.fixture.calls);
      assert.deepEqual(calls.find(c => c.op === 'names.preview').args, { type: 'P', site: 'PA', service: 'INF', computer: 'P111301PAINF001' });
      assert.equal(calls.filter(c => c.op === 'queue.add').length, 1);
      assert.equal(calls.filter(c => c.op === 'queue.execute').length, 0);
    } finally { await page.close(); }
  });
  await check('Lot terrain : réimport partiel conserve les indications CSV non renseignées', async () => {
    const page = await makePage('plusieurspostes', 'queue');
    try {
      const input = page.locator('[data-act="csvfile"]');
      await input.setInputFiles({ name: 'postes.csv', mimeType: 'text/csv', buffer: Buffer.from('name;type;site;service\nP111301PAINF001;P;PA;INF') });
      await page.locator('[data-drop]').waitFor();
      await input.setInputFiles({ name: 'correction.csv', mimeType: 'text/csv', buffer: Buffer.from('name;type;site;service\nP111301PAINF001;;;ADM') });
      await page.waitForFunction(() => document.querySelector('[data-zone="sel-list"]').textContent.includes('service ADM'));
      assert.match(await page.locator('[data-zone="sel-list"]').innerText(), /type P · site PA · service ADM/);
      assert.equal(await page.locator('[data-drop]').count(), 1);
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => (c.op === 'computer.inspect' && c.args.computer !== 'NOUVEAU-PC') || c.op === 'names.preview' || c.op === 'queue.add').length), 0);
    } finally { await page.close(); }
  });
  await check('Lot terrain : ajout en cours verrouille ses sources et invalide le lot précédent immédiatement', async () => {
    const page = await makePage('plusieurspostes', 'queue');
    try {
      const paste = page.locator('[name="list"]');
      await paste.fill('P111301PAINF001'); await page.getByRole('button', { name: 'Analyser la liste', exact: true }).click();
      await page.locator('[data-act="addqueue"]').click(); await page.locator('[data-act="prepare"]').click();
      await page.locator('[data-act="execute"]').waitFor();
      await paste.fill('V111301LYINF001'); await page.getByRole('button', { name: 'Analyser la liste', exact: true }).click();
      await page.evaluate(() => { window.fixture.holdQueueAdd = true; }); await page.locator('[data-act="addqueue"]').click();
      await page.waitForFunction(() => typeof window.fixture.releases.queueAdd === 'function');
      assert.equal(await page.locator('[data-act="execute"]').count(), 0);
      for (const selector of ['[name="list"]', '[data-act="csvfile"]', '[data-form="search"] input', '[data-act="clearsel"]'])
        assert.equal(await page.locator(selector).isDisabled(), true);
      await page.evaluate(() => { const input = document.querySelector('[name="list"]'); input.value = 'S111301PAADM001'; input.form.requestSubmit(); });
      assert.doesNotMatch(await page.locator('[data-zone="sel-list"]').innerText(), /S111301PAADM001/);
      await page.evaluate(() => window.fixture.releases.queueAdd());
      await page.waitForFunction(() => !document.querySelector('[name="list"]').disabled);
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'queue.add').length), 2);
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'queue.execute').length), 0);
    } finally { await page.close(); }
  });
  await check('Lot terrain : lecture CSV en cours termine avant toute préparation ou ajout', async () => {
    const page = await makePage('plusieurspostes', 'queue');
    try {
      await page.locator('[name="list"]').fill('P111301PAINF001'); await page.getByRole('button', { name: 'Analyser la liste', exact: true }).click();
      await page.evaluate(() => { const NativeReader = window.FileReader; window.FileReader = class extends NativeReader {
        readAsText(...args) { window.fixture.releaseFile = () => super.readAsText(...args); }
      }; });
      await page.locator('[data-act="csvfile"]').setInputFiles({ name: 'postes.csv', mimeType: 'text/csv', buffer: Buffer.from('name;type;site;service\nP111301PAINF001;V;LY;INF') });
      await page.waitForFunction(() => typeof window.fixture.releaseFile === 'function');
      assert.equal(await page.locator('[data-act="addqueue"]').isDisabled(), true);
      await page.locator('[data-act="addqueue"]').dispatchEvent('click');
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => (c.op === 'computer.inspect' && c.args.computer !== 'NOUVEAU-PC')).length), 0);
      await page.evaluate(() => window.fixture.releaseFile());
      await page.waitForFunction(() => !document.querySelector('[data-act="addqueue"]').disabled);
      assert.match(await page.locator('[data-zone="sel-list"]').innerText(), /type V · site LY · service INF/);
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'queue.add').length), 0);
    } finally { await page.close(); }
  });
  for (const [route, form, action] of [['ajouter', 'join', 'add'], ['unposte', 'rename', 'apply']]) {
    await check(`${route} : type, service et site désactivent l’écriture jusqu’au nouvel aperçu`, async () => {
      const page = await makePage(route);
      try {
        if (route === 'unposte') await selectComputer(page);
        for (const field of ['type', 'service', 'site']) {
          await preview(page, form);
          const host = page.locator(`[data-form="${form}"]`);
          await page.evaluate(() => { window.fixture.holdPreview = true; delete window.fixture.releases.preview; });
          if (field === 'type') await host.locator('[name="type"][value="S"]').check();
          else if (field === 'service') await host.locator('[name="service"]').fill('ADM');
          else await host.locator('[name="site"]').selectOption('lyon');
          assert.equal(await page.locator(`[data-act="${action}"]`).isEnabled(), false);
          assert.equal(await page.locator('main .name-preview').count(), 0);
          await page.waitForFunction(() => typeof window.fixture.releases.preview === 'function');
          await page.evaluate(() => { window.fixture.holdPreview = false; window.fixture.releases.preview(); });
          await page.locator('main .name-preview .name').waitFor();
        }
        assert.equal(await page.evaluate(() => window.fixture.calls.filter((c) => c.op === 'operation.prepare').length), 0);
      } finally { await page.close(); }
    });
    await check(`${route} : réponse d’aperçu tardive ignorée après changement du choix`, async () => {
      const page = await makePage(route);
      try {
        if (route === 'unposte') await selectComputer(page);
        await page.evaluate(() => { window.fixture.holdPreview = true; });
        await page.locator(`[data-form="${form}"] button[type="submit"]`).click();
        await page.waitForFunction(() => typeof window.fixture.releases.preview === 'function');
        await page.evaluate(() => { window.fixture.holdPreview = false; window.fixture.oldPreview = window.fixture.releases.preview; });
        await page.locator(`[data-form="${form}"] [name="site"]`).selectOption('lyon');
        const current = page.locator('main .name-preview .name');
        await page.waitForFunction(() => document.querySelector('main .name-preview .name')?.textContent.includes('LY'));
        const freshName = await current.innerText();
        await page.evaluate(() => window.fixture.oldPreview());
        await page.waitForFunction(() => !document.querySelector('main [aria-busy="true"]'));
        assert.equal(await current.innerText(), freshName);
        assert.equal(await page.locator(`[data-act="${action}"]`).isEnabled(), true);
      } finally { await page.close(); }
    });
    await check(`${route} : préparation tardive abandonnée si les choix ont changé`, async () => {
      const page = await makePage(route);
      try {
        if (route === 'unposte') await selectComputer(page);
        await preview(page, form);
        await page.evaluate(() => { window.fixture.holdPrepare = true; });
        await page.locator(`[data-act="${action}"]`).click();
        await page.waitForFunction(() => typeof window.fixture.releases.prepare === 'function');
        await page.locator(`[data-form="${form}"] [name="type"][value="S"]`).check();
        await page.evaluate(() => window.fixture.releases.prepare());
        await page.waitForFunction(() => !document.querySelector('.busy-line.on'));
        assert.equal(await page.locator('.k-dlg').count(), 0);
        assert.equal(await page.evaluate(() => window.fixture.calls.filter((c) => c.op === 'operation.execute').length), 0);
      } finally { await page.close(); }
    });
  }
  for (const kind of ['rename', 'move']) await check(`Un poste/${kind} : choix modifié pendant la confirmation refuse tout envoi`, async () => {
    const page = await makePage('unposte', kind);
    try {
      await selectComputer(page);
      if (kind === 'rename') await preview(page, 'rename');
      await page.locator(`[data-act="${kind === 'rename' ? 'apply' : 'domove'}"]`).click();
      const dialog = page.locator('.k-dlg'); await dialog.waitFor();
      assert.equal(await dialog.locator('.k-cw-typed').count(), 0);
      await page.evaluate(kind => {
        const select = document.querySelector(`[data-form="${kind === 'rename' ? 'rename' : 'move'}"] [name="site"]`);
        select.value = kind === 'rename' ? 'lyon' : '';
        select.dispatchEvent(new Event('change', { bubbles: true }));
      }, kind);
      await dialog.locator('[data-id="confirm"]').click(); await dialog.waitFor({ state: 'hidden' });
      await page.locator(`[data-zone="${kind}"] [role="alert"]`).waitFor();
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'operation.execute').length), 0);
    } finally { await page.close(); }
  });
  await check('Déplacement annulé : aucun envoi ni faux refus', async () => {
    const page = await makePage('unposte', 'move');
    try {
      await selectComputer(page); await page.locator('[data-act="domove"]').click();
      const dialog = page.locator('.k-dlg'); await dialog.waitFor();
      await dialog.locator('[data-id="cancel"]').click(); await dialog.waitFor({ state: 'hidden' });
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'operation.execute').length), 0);
      assert.equal(await page.locator('[data-zone="move"] [role="alert"]').count(), 0);
    } finally { await page.close(); }
  });
  await check('Un poste en mode réel : ce poste joint est lu d’office, même quand la jonction reste autorisée', async () => {
    const page = await makePage('unposte', 'rename', 'succeeded', { sessionComputer: 'P111301PAINF001', localJoined: true });
    try {
      assert.equal(await page.locator('[data-form="target"] input[value="local"]').isChecked(), true);
      await page.locator('[data-zone="identity"] .kv-grid').waitFor();
      assert.match(await page.locator('[data-zone="identity"]').innerText(), /P111301PAINF001/);
      assert.doesNotMatch(await page.locator('[data-zone="identity"]').innerText(), /pas encore dans l’annuaire/);
      await page.locator('[data-form="rename"]').waitFor();
      const inspected = await page.evaluate(() => window.fixture.calls.filter((c) => c.op === 'computer.inspect').map((c) => c.args.computer));
      assert.deepEqual(inspected, ['P111301PAINF001']);
    } finally { await page.close(); }
  });

  for (const [label, inspectionPatch, reason] of [
    ['hors racine', { inManagedScope: false }, /hors de la racine gérée/i],
    ['périmètre inconnu', { inManagedScope: null }, /périmètre de ce poste n’est pas confirmé/i],
    ['état inconnu', { inManagedScope: true, status: 'unknown' }, /état de ce poste n’est pas confirmé/i],
  ]) await check(`Un poste en lecture seule (${label}) : aperçu permis, écritures bloquées après chaque inspection`, async () => {
    const local = 'P111301PAINF001', remote = 'S111301PAADM001';
    const page = await makePage('unposte', 'rename', 'succeeded', { sessionComputer: local, localJoined: true, inspectionPatch });
    async function verifyReadOnly() {
      await page.locator('[data-form="rename"] [name="service"] + datalist option[value="INF"]').waitFor({ state: 'attached' });
      const calculate = page.locator('[data-form="rename"] button[type="submit"]');
      assert.equal(await calculate.isEnabled(), true);
      await preview(page, 'rename');
      assert.equal(await page.locator('[data-act="apply"]').isDisabled(), true);
      assert.equal(await page.locator('[data-act="domove"]').isDisabled(), true);
      for (const zone of ['rename', 'move']) assert.match(await page.locator(`[data-zone="${zone}"]`).innerText(), reason);
      // Even a synthetic click on the disabled control cannot prepare an out-of-scope plan.
      for (const action of ['apply', 'domove']) await page.locator(`[data-act="${action}"]`).dispatchEvent('click');
    }
    try {
      await verifyReadOnly();
      await page.evaluate(() => { window.fixture.inspectionPatch = { inManagedScope: true, status: 'known' }; });
      await selectComputer(page, remote);
      await preview(page, 'rename');
      assert.equal(await page.locator('[data-act="apply"]').isEnabled(), true);
      assert.equal(await page.locator('[data-act="domove"]').isEnabled(), true);
      await page.locator('[data-act="apply"]').click();
      const dialog = page.locator('.k-dlg'); await dialog.waitFor();
      await dialog.locator('[data-id="cancel"]').click(); await dialog.waitFor({ state: 'hidden' });
      await page.evaluate(patch => { window.fixture.inspectionPatch = patch; }, inspectionPatch);
      await page.locator('[data-form="target"] input[value="local"]').check();
      await verifyReadOnly();
      const calls = await page.evaluate(() => window.fixture.calls);
      assert.deepEqual(calls.filter(c => c.op === 'computer.inspect').map(c => c.args.computer), [local, remote, local]);
      assert.deepEqual(calls.filter(c => c.op === 'operation.prepare').map(c => c.args.computer), [remote]);
      assert.equal(calls.filter(c => c.op === 'operation.execute').length, 0);
    } finally { await page.close(); }
  });

  await check('Un poste en mode réel : un poste hors domaine n’est pas lu dans l’annuaire, la jonction est indiquée', async () => {
    const page = await makePage('unposte', 'rename', 'succeeded', { sessionComputer: 'P111301PAINF001', localJoined: false });
    try {
      await page.locator('[data-zone="identity"] [role="status"]').waitFor();
      assert.match(await page.locator('[data-zone="identity"]').innerText(), /n’est pas membre du domaine.*Ajouter ce PC au domaine/);
      assert.equal(await page.locator('[data-form="rename"]').count(), 0);
      assert.equal(await page.evaluate(() => window.fixture.calls.filter((c) => c.op === 'computer.inspect').length), 0);
    } finally { await page.close(); }
  });
  await check('Un poste en mode réel : un poste membre absent de l’annuaire n’est jamais renvoyé vers la jonction', async () => {
    const page = await makePage('unposte', 'rename', 'succeeded', { sessionComputer: 'P111301PAINF999', localJoined: true });
    try {
      await page.locator('[data-zone="identity"] [role="alert"]').waitFor();
      const text = await page.locator('[data-zone="identity"]').innerText();
      assert.match(text, /membre d’un domaine.*P111301PAINF999.*supprimé ou renommé/s);
      assert.doesNotMatch(text, /Ajouter ce PC au domaine/);
      assert.equal(await page.locator('[data-form="rename"]').count(), 0);
      assert.deepEqual(await page.evaluate(() => window.fixture.calls.filter((c) => c.op === 'computer.inspect').map((c) => c.args.computer)), ['P111301PAINF999']);
    } finally { await page.close(); }
  });

  await check('Un poste : sites tardifs initialisent les choix sans perdre la recherche ni relire le poste', async () => {
    const page = await makePage('unposte', 'rename', 'succeeded', { holdSites: true, siteAsCode: true });
    try {
      await pickRemote(page);
      const search = page.locator('[data-form="search"] [name="query"]');
      await search.fill('V111301LYINF001'); await search.press('Enter');
      await page.locator('[data-pick="V111301LYINF001"]').click();
      await page.locator('[data-zone="identity"] .kv-grid').waitFor();
      assert.match(await page.locator('[data-zone="rename"]').innerText(), /Chargement des sites/);
      assert.equal(await page.locator('[data-form="rename"], [data-form="move"]').count(), 0);
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'directory.services').length), 0);
      await search.fill('recherche en cours');
      await page.waitForFunction(() => typeof window.fixture.releases.sites === 'function');
      await page.evaluate(() => window.fixture.releases.sites());
      await page.locator('[data-form="rename"] [name="service"] + datalist option[value="INF"]').waitFor({ state: 'attached' });
      assert.equal(await search.inputValue(), 'recherche en cours');
      assert.equal(await page.locator('[data-form="rename"] [name="site"]').inputValue(), 'lyon');
      assert.equal(await page.locator('[data-form="rename"] [name="type"]:checked').inputValue(), 'V');
      const calls = await page.evaluate(() => window.fixture.calls);
      assert.equal(calls.filter(c => (c.op === 'computer.inspect' && c.args.computer !== 'NOUVEAU-PC')).length, 1);
      assert.deepEqual(calls.filter(c => c.op === 'directory.services').map(c => c.args.site), ['lyon']);
      assert.equal(calls.filter(c => c.op === 'operation.prepare' || c.op === 'operation.execute').length, 0);
    } finally { await page.close(); }
  });
  await check('Un poste : sites tardifs respectent la dernière sélection', async () => {
    const page = await makePage('unposte', 'rename', 'succeeded', { holdSites: true });
    try {
      await pickRemote(page);
      const search = page.locator('[data-form="search"] [name="query"]');
      await search.fill('111301'); await search.press('Enter');
      await page.locator('[data-pick="P111301PAINF001"]').click();
      await page.locator('[data-zone="identity"] .kv-grid').waitFor();
      await page.locator('[data-pick="V111301LYINF001"]').click();
      await page.waitForFunction(() => document.querySelector('[data-zone="identity"] .kv-grid')?.textContent.includes('V111301LYINF001'));
      await page.evaluate(() => window.fixture.releases.sites());
      await page.locator('[data-form="rename"] [name="service"] + datalist option[value="INF"]').waitFor({ state: 'attached' });
      assert.match(await page.locator('[data-zone="rename"] h3').innerText(), /V111301LYINF001/);
      assert.equal(await page.locator('[data-form="rename"] [name="site"]').inputValue(), 'lyon');
      assert.deepEqual(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'directory.services').map(c => c.args.site)), ['lyon']);
    } finally { await page.close(); }
  });
  await check('Un poste : échec du catalogue visible et nouvelle lecture uniquement sur Réessayer', async () => {
    const page = await makePage('unposte', 'rename', 'succeeded', { sitesError: 'Contrôleur momentanément indisponible.' });
    try {
      await pickRemote(page);
      const search = page.locator('[data-form="search"] [name="query"]');
      await search.fill('P111301PAINF001'); await search.press('Enter');
      await page.locator('[data-pick="P111301PAINF001"]').click();
      await page.locator('[data-zone="rename"] [role="alert"]').waitFor();
      assert.match(await page.locator('[data-zone="rename"] [role="alert"]').innerText(), /Contrôleur momentanément indisponible/);
      assert.equal(await page.locator('[data-form="rename"], [data-form="move"]').count(), 0);
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'directory.sites').length), 1);
      await page.evaluate(() => { window.fixture.sitesError = null; });
      await page.locator('[data-zone="rename"] [data-retry-sites]').click();
      await page.locator('[data-form="rename"] [name="service"] + datalist option[value="INF"]').waitFor({ state: 'attached' });
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'directory.sites').length), 2);
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => (c.op === 'computer.inspect' && c.args.computer !== 'NOUVEAU-PC')).length), 1);
    } finally { await page.close(); }
  });
  await check('Un poste : catalogue vide expliqué sans appel service invalide', async () => {
    const page = await makePage('unposte', 'rename', 'succeeded', { siteItems: [] });
    try {
      await pickRemote(page);
      const search = page.locator('[data-form="search"] [name="query"]');
      await search.fill('P111301PAINF001'); await search.press('Enter');
      await page.locator('[data-pick="P111301PAINF001"]').click();
      await page.locator('[data-zone="identity"] .kv-grid').waitFor();
      assert.match(await page.locator('[data-zone="rename"]').innerText(), /Aucun site configuré/);
      assert.equal(await page.locator('[data-form="rename"], [data-form="move"]').count(), 0);
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'directory.services').length), 0);
    } finally { await page.close(); }
  });
  for (const route of ['noms', 'ajouter']) {
    for (const noSites of [true, false]) {
      await check(`${route} : la lecture terminée indique le choix absent (${noSites ? 'site' : 'service'})`, async () => {
        const page = await makePage(route, 'rename', 'succeeded', noSites ? { siteItems: [] } : { emptyServices: true });
        try {
          const field = noSites ? 'site' : 'service';
          const label = noSites ? 'Aucun site trouvé' : 'Aucun service trouvé';
          if (noSites) await page.waitForFunction(label => document.querySelector('select[name="site"]')?.selectedOptions[0]?.textContent === label, label);
          else await page.locator('[data-form="' + (route === 'ajouter' ? 'join' : 'preview') + '"] [name="service"]').waitFor();
          if (!noSites) assert.match(await page.locator('.k-field[data-name="service"] .k-msg').innerText(), /Aucun service connu|saisissez le code manuellement/i);
          const ops = await page.evaluate(() => window.fixture.calls.map(call => call.op));
          assert.equal(ops.includes('directory.services'), !noSites);
          assert.equal(ops.includes('names.preview'), false);
        } finally { await page.close(); }
      });
    }
  }
  await check('Un poste : motif du calcul refusé conservé, aperçu invalide et aucun plan envoyé', async () => {
    const page = await makePage('unposte', 'rename', 'succeeded', { previewError: 'Inventaire incomplet : aucun nom fiable.' });
    try {
      await selectComputer(page);
      await page.locator('[data-form="rename"] button[type="submit"]').click();
      await page.locator('[data-zone="rpreview"] [role="alert"]').waitFor();
      assert.match(await page.locator('[data-zone="rpreview"]').innerText(), /Inventaire incomplet : aucun nom fiable/);
      assert.equal(await page.locator('[data-act="apply"]').isDisabled(), true);
      assert.equal(await page.locator('main .name-preview').count(), 0);
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'operation.prepare').length), 0);
      await page.evaluate(() => { window.fixture.previewError = null; });
      await page.locator('[data-form="rename"] [name="service"]').fill('ADM');
      await page.locator('[data-zone="rpreview"] .name-preview .name').waitFor();
      assert.match(await page.locator('[data-zone="rpreview"] .name-preview .name').innerText(), /ADM/);
      assert.equal(await page.locator('[data-zone="rpreview"] [role="alert"]').count(), 0);
      assert.equal(await page.locator('[data-act="apply"]').isEnabled(), true);
    } finally { await page.close(); }
  });
  for (const [name, type, code, site] of [['P111301PAINF001', 'P', 'PA', 'paris'], ['V111301LYINF001', 'V', 'LY', 'lyon']]) {
    await check(`Un poste : identité native ${type}/${code} conserve le type et distingue code et identifiant du site`, async () => {
      const page = await makePage('unposte', 'rename', 'succeeded', { siteAsCode: true, inspectionPatch: { model: null, type } });
      try {
        await selectComputer(page, name);
        const form = page.locator('[data-form="rename"]');
        assert.equal(await form.locator('[name="site"]').inputValue(), site);
        assert.equal(await form.locator('[name="type"]:checked').inputValue(), type);
        assert.equal(await page.locator(`[data-form="move"] option[value="OU=${site === 'paris' ? 'Paris' : 'Lyon'},OU=Postes,DC=example,DC=local"]`).count(), 0);
        await preview(page, 'rename'); await page.locator('[data-act="apply"]').click();
        const dialog = page.locator('.k-dlg'); await dialog.waitFor();
        assert.equal(await page.evaluate(() => window.fixture.calls.find(c => c.op === 'operation.prepare').args.kind), 'rename');
        await dialog.locator('[data-id="cancel"]').click(); await dialog.waitFor({ state: 'hidden' });
        await form.locator('[name="site"]').selectOption(site === 'paris' ? 'lyon' : 'paris');
        await form.locator('[name="service"] + datalist option[value="INF"]').waitFor({ state: 'attached' });
        await preview(page, 'rename'); await page.locator('[data-act="apply"]').click(); await dialog.waitFor();
        assert.deepEqual(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'operation.prepare').map(c => c.args.kind)), ['rename', 'renameMove']);
        await dialog.locator('[data-id="cancel"]').click();
        assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'operation.execute').length), 0);
      } finally { await page.close(); }
    });
  }
  await check('Un poste : site et type inconnus exigent des choix explicites', async () => {
    const page = await makePage('unposte', 'rename', 'succeeded', { inspectionPatch: { site: 'INCONNU', type: 'X', model: null } });
    try {
      await pickRemote(page);
      const search = page.locator('[data-form="search"] [name="query"]');
      await search.fill('P111301PAINF001'); await search.press('Enter');
      await page.locator('[data-pick="P111301PAINF001"]').click();
      const form = page.locator('[data-form="rename"]'); await form.waitFor();
      assert.equal(await form.locator('[name="site"]').inputValue(), '');
      assert.equal(await form.locator('[name="type"]:checked').count(), 0);
      assert.equal(await page.locator('[data-form="move"] [name="site"]').inputValue(), '');
      await form.locator('button[type="submit"]').click();
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'directory.services' || c.op === 'names.preview').length), 0);
      await form.locator('[name="type"][value="P"]').check(); await form.locator('[name="site"]').selectOption('paris');
      await form.locator('[name="service"] + datalist option[value="INF"]').waitFor({ state: 'attached' });
      await preview(page, 'rename');
    } finally { await page.close(); }
  });
  await check('Un poste : un identifiant semblable à un code natif inconnu ne change jamais le site implicitement', async () => {
    const page = await makePage('unposte', 'rename', 'succeeded', {
      inspectionPatch: { site: 'PA', type: 'P', model: null },
      siteItems: [{ id: 'PA', name: 'Lyon', code: 'LY', ou: 'OU=Lyon,OU=Postes,DC=example,DC=local' }],
    });
    try {
      await pickRemote(page);
      const search = page.locator('[data-form="search"] [name="query"]');
      await search.fill('P111301PAINF001'); await search.press('Enter');
      await page.locator('[data-pick="P111301PAINF001"]').click();
      const form = page.locator('[data-form="rename"]'); await form.waitFor();
      assert.equal(await form.locator('[name="site"]').inputValue(), '');
      assert.equal(await page.locator('[data-form="move"] [name="site"]').inputValue(), '');
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'directory.services').length), 0);
      await form.locator('[name="site"]').selectOption('PA');
      await form.locator('[name="service"] + datalist option[value="INF"]').waitFor({ state: 'attached' });
      await preview(page, 'rename');
      assert.match(await page.locator('main .name-preview .name').innerText(), /LY/);
      await page.locator('[data-act="apply"]').click();
      const dialog = page.locator('.k-dlg'); await dialog.waitFor();
      assert.equal(await page.evaluate(() => window.fixture.calls.find(c => c.op === 'operation.prepare').args.kind), 'renameMove');
      await dialog.locator('[data-id="cancel"]').click();
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'operation.execute').length), 0);
    } finally { await page.close(); }
  });
  await check('Un poste : code de site ambigu sans OU correspondante reste à choisir', async () => {
    const page = await makePage('unposte', 'rename', 'succeeded', {
      inspectionPatch: { site: 'LY', ou: 'OU=Archives,DC=example,DC=local', type: 'V', model: null },
      siteItems: [
        { id: 'lyon', name: 'Lyon', code: 'LY', ou: 'OU=Lyon,OU=Postes,DC=example,DC=local' },
        { id: 'lyon-bis', name: 'Lyon annexe', code: 'LY', ou: 'OU=LyonAnnexe,OU=Postes,DC=example,DC=local' },
      ],
    });
    try {
      await pickRemote(page);
      const search = page.locator('[data-form="search"] [name="query"]');
      await search.fill('V111301LYINF001'); await search.press('Enter');
      await page.locator('[data-pick="V111301LYINF001"]').click();
      const form = page.locator('[data-form="rename"]'); await form.waitFor();
      assert.equal(await form.locator('[name="site"]').inputValue(), '');
      assert.equal(await page.locator('[data-act="domove"]').isDisabled(), true);
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'directory.services').length), 0);
      await form.locator('button[type="submit"]').click();
      assert.equal(await page.evaluate(() => window.fixture.calls.filter(c => c.op === 'names.preview' || c.op === 'operation.prepare').length), 0);
    } finally { await page.close(); }
  });
  await check('Un poste : deux inspections hors ordre gardent le dernier choix', async () => {
    const page = await makePage('unposte');
    try {
      await page.evaluate(() => { window.fixture.holdInspect = true; });
      await pickRemote(page);
      const search = page.locator('[data-form="search"] [name="query"]');
      await search.fill('111301'); await search.press('Enter');
      await page.locator('[data-pick="P111301PAINF001"]').click();
      await page.waitForFunction(() => typeof window.fixture.releases.P111301PAINF001 === 'function');
      await page.locator('[data-pick="S111301PAADM001"]').click();
      await page.waitForFunction(() => typeof window.fixture.releases.S111301PAADM001 === 'function');
      await page.evaluate(() => window.fixture.releases.S111301PAADM001());
      await page.locator('[data-zone="rename"] h3').waitFor();
      assert.match(await page.locator('[data-zone="rename"] h3').innerText(), /S111301PAADM001/);
      await page.evaluate(() => window.fixture.releases.P111301PAINF001());
      await page.waitForFunction(() => !document.querySelector('.busy-line.on'));
      assert.match(await page.locator('[data-zone="rename"] h3').innerText(), /S111301PAADM001/);
    } finally { await page.close(); }
  });
  await check('Déplacement seul après navigation et rechargement : inspection puis un seul plan move, aucun renommage', async () => {
    const page = await makePage('unposte', 'move', 'succeeded');
    try {
      await selectComputer(page);
      await page.locator('.nav-item[data-id="journal"]').click();
      await page.waitForFunction(() => document.documentElement.dataset.ready === 'journal');
      await page.locator('.nav-item[data-id="unposte"]').click();
      await page.waitForFunction(() => document.documentElement.dataset.ready === 'unposte');
      await page.reload();
      await page.waitForFunction(() => document.documentElement.dataset.ready === 'unposte');
      await selectComputer(page);
      await confirm(page, 'domove');
      await page.locator('[data-zone="receipt"] [data-status="succeeded"]').waitFor();
      const calls = await page.evaluate(() => window.fixture.calls);
      assert.deepEqual(calls.filter((c) => c.op === 'operation.prepare').map((c) => c.args.kind), ['move']);
      assert.equal(calls.filter((c) => c.op === 'operation.execute').length, 1);
      assert.equal(calls.filter((c) => c.op === 'names.preview').length, 0);
      assert(calls.find((c) => c.op === 'computer.inspect'));
    } finally { await page.close(); }
  });
  await check('Aucune erreur JavaScript/console', async () => assert.deepEqual(errors, []));
} finally { await browser?.close(); await new Promise((done) => server.close(done)); }
console.log(`\n${checks - failures}/${checks} contrôles métier navigateur réussis (fixtures explicites, sans Windows/AD).`);
process.exitCode = failures ? 1 : 0;
