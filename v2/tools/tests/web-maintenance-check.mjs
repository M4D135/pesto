// Actual Pesto forms/dialogs in Chromium, with a declared native-host fixture.
// This exercises payloads and confirmation order; it never accesses Windows/AD, the network or SMB.
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
assert(executablePath && existsSync(executablePath), 'Chromium local requis, aucun téléchargement automatique.');
const server = createServer(async (req, res) => {
  if (req.url === '/favicon.ico') { res.writeHead(204); res.end(); return; }
  try {
    const pathname = new URL(req.url, 'http://localhost').pathname;
    const file = resolve(web, `.${pathname === '/' ? '/index.html' : pathname}`);
    if (!file.startsWith(web + sep)) throw Error('path');
    const body = await readFile(file);
    res.writeHead(200, { 'Content-Type': { '.js': 'text/javascript', '.html': 'text/html', '.css': 'text/css' }[extname(file)] || 'application/octet-stream' });
    res.end(body);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise((done) => server.listen(0, '127.0.0.1', done));
const origin = `http://127.0.0.1:${server.address().port}`;
let browser, checks = 0, failures = 0;
const errors = [];
const filter = process.argv[2] ? new RegExp(process.argv[2], 'i') : null;
const check = async (label, run) => {
  if (filter && !filter.test(label)) return;
  checks++;
  try { await run(); console.log(`  ok   ${label}`); }
  catch (error) { failures++; console.error(`  FAIL ${label} — ${error.message}`); }
};

try {
  browser = await chromium.launch({ headless: true, executablePath });
  async function makePage({ fresh = false, distribution = false, local = false, invalid = false, pendingSettings = false, failSettings = false, session = {}, address = '#/parametres' } = {}) {
    const page = await browser.newPage({ viewport: { width: 1500, height: 1100 } });
    page.setDefaultTimeout(6000);
    page.on('pageerror', (error) => errors.push(error.message));
    // net::ERR_NO_BUFFER_SPACE is socket exhaustion on the Windows runner (run 40936590562), not a page error;
    // every other console error, and every external request, still fails the suite.
    page.on('console', (message) => { if (message.type() === 'error' && !message.text().includes('net::ERR_NO_BUFFER_SPACE')) errors.push(message.text()); });
    await page.route('**/*', async (route) => {
      if (route.request().url().startsWith(origin + '/')) await route.continue();
      else { errors.push('Unexpected external request: ' + route.request().url()); await route.abort(); }
    });
    await page.addInitScript(({ fresh, distribution, local, invalid, pendingSettings, failSettings, session }) => {
      localStorage.setItem('pesto.prefs.v1', JSON.stringify({ theme: 'light', motion: 'reduced' }));
      const saved = {
        configured: true, configurationExists: true, configurationState: 'valid', diagnostic: null,
        domain: 'example.local', dc: '', prefix: '111301', rootOu: 'OU=Postes,DC=example,DC=local', preprodOu: '', preprodSite: '',
        production: true, randomNames: true, namingPattern: '{type}{prefix}{site}{service}{number:3}',
        coordinationRoot: '', coordinationRequired: false, reserveNamesInAd: false, auditEventLogEnabled: false,
        blockJoinOnClockSkew: false, excludedGroupGuids: [], entraPolicy: 'HybridOnly', allowPrecreatedJoin: false,
        sites: [{ id: 'paris', name: 'Paris', code: 'PA', ou: 'OU=Paris,OU=Postes,DC=example,DC=local' }],
        simulation: false, liveExecutionEnabled: false, fingerprint: 'a'.repeat(64),
      };
      const empty = { ...saved, configured: false, configurationExists: false, configurationState: 'missing',
        domain: '', prefix: '', rootOu: '', sites: [], fingerprint: null, entraPolicy: 'Disabled' };
      const damaged = { configured: false, configurationExists: true, configurationState: 'invalid', diagnostic: 'La configuration existante est invalide ou illisible. Aucun paramètre par défaut n’a été appliqué. Importez explicitement une configuration valide pour préparer son remplacement avec sauvegarde du fichier original.',
        fingerprint: null, sites: [], simulation: false, liveExecutionEnabled: false };
      const differences = [{ field: 'CONF', before: [{ Domaine: 'example.local', Prefixe: '111301' }], after: [{ Domaine: 'example.local', Prefixe: '222222' }] }];
      const plan = (id, source) => ({ planId: id, source, version: 'entreprise.2', fingerprint: 'b'.repeat(64),
        expiresAt: '2099-10-25T12:15:00Z', differences, backupRequired: !fresh, requiresConfirmation: true });
      window.fixture = {
        calls: [], settings: invalid ? damaged : fresh ? empty : saved, pendingDistribution: distribution, sequence: 0,
        // failSettings: the very first read of the settings is refused (nothing was ever read on this screen).
        configPlan: null, fail: failSettings ? 'configuration.settings' : null, ...(failSettings ? { failCode: 'fixture', failMessage: 'Lecture refusée' } : {}),
        cancelImport: false, cancelUpdateSource: false, pendingRecovery: false, canRollback: true,
        hold: pendingSettings ? 'configuration.settings' : null, releases: [], delivered: 0, packWindows: null,
        // wad\defaults\configuration.json of this installation, as InstallationDefaults.Inspect describes it.
        installationDefault: { state: 'missing', path: 'wad\\defaults\\configuration.json', version: null, fingerprint: null, sha256: null },
        defaultUnchanged: false, candidateDefaults: false, rollbackVersion: '2.0.14', recoveryVersion: '2.0.14', decisionSaved: true,
        // InstallationDefaults.DescribeReturn of the transaction a rollback or a recovery would use.
        rollbackDefaults: 'kept', recoveryDefaults: 'kept',
      };
      let receive;
      window.chrome ??= {};
      window.chrome.webview = {
        addEventListener(type, fn) { if (type === 'message') receive = fn; },
        async postMessage(request) {
          const state = window.fixture;
          state.calls.push({ op: request.op, args: structuredClone(request.args) });
          let data;
          try {
            if (state.fail === request.op) throw Object.assign(new Error(state.failMessage ?? 'Refus contrôlé de la fixture : aucun succès confirmé.'), { code: state.failCode ?? 'fixture.refused' });
            switch (request.op) {
              case 'session.info': data = { version: '2.0.0-dev', mode: 'live', configurationOnly: local,
                domain: fresh || invalid || local ? null : 'example.local', dc: fresh || invalid || local ? null : 'dc01.example.local',
                account: 'EXAMPLE\\operateur', computer: 'POSTE-TEST', readOnly: fresh || invalid || local,
                capabilities: ['join', 'rename', 'move', 'renameMove', 'queue'].map((id) => ({ id, enabled: !fresh && !invalid && !local, reason: local ? 'Aucun annuaire connecté.' : fresh ? 'Configuration initiale requise.' : null })), ...session }; break;
              case 'configuration.settings': data = structuredClone(state.settings); break;
              case 'coordination.status': data = { configured: !!state.settings.coordinationRoot, root: state.settings.coordinationRoot,
                domain: state.settings.domain, required: state.settings.coordinationRequired, message: 'Paramètres locaux ; aucun registre contacté.' }; break;
              case 'configuration.status': data = { configured: state.settings.configured, configurationState: state.settings.configurationState,
                configurationExists: state.settings.configurationExists, diagnostic: state.settings.diagnostic, requiresDecision: state.pendingDistribution,
                pendingDistribution: state.pendingDistribution ? { ...plan('distributed-1', 'distribution'), requiresDecision: true } : null,
                installationDefault: structuredClone(state.installationDefault) }; break;
              case 'configuration.previewSettings':
                state.configPlan = structuredClone(request.args);
                data = plan('settings-' + (++state.sequence), 'settings'); break;
              case 'configuration.previewImport': data = state.cancelImport ? { status: 'cancelled' } : state.settings.configurationState === 'invalid'
                ? { ...plan('recovery-1', 'import'), replacesInvalidConfiguration: true, backupRequired: true,
                  differences: [{ field: 'Configuration existante invalide', before: 'Fichier invalide : son contenu n’est pas affiché. Ses octets originaux seront sauvegardés avant le remplacement confirmé.',
                    after: { CONF: [{ Domaine: 'example.local', Prefixe: '111301' }] } }] }
                : plan('import-1', 'import'); break;
              case 'configuration.applyImport':
                if (request.args.planId === 'recovery-1') state.settings = { ...saved, fingerprint: 'b'.repeat(64) };
                else if (request.args.planId.startsWith('settings-')) state.settings = { ...state.settings, ...state.configPlan,
                  configured: true, configurationExists: true, configurationState: 'valid', fingerprint: 'b'.repeat(64) };
                data = { status: 'applied', changed: true, backup: fresh ? null : 'C:\\Users\\operator\\AppData\\Local\\Pesto\\backups\\cfg.bak', fingerprint: 'b'.repeat(64) }; break;
              case 'configuration.decideDistribution':
                state.pendingDistribution = false;
                if (request.args.replace) state.settings = { ...state.settings, prefix: '222222', fingerprint: 'b'.repeat(64) };
                data = { status: request.args.replace ? 'applied' : 'kept', changed: request.args.replace }; break;
              case 'configuration.export': data = { status: 'exported', file: 'C:\\Export\\Pesto-configuration.json', fingerprint: 'a'.repeat(64) }; break;
              case 'configuration.setDefault': {
                // Result shape of ProfileConfigurationService.WriteInstallationDefault: written in place, pack unchanged.
                const current = state.installationDefault;
                const previous = current.state === 'local' ? { version: current.version, fingerprint: current.fingerprint, sha256: current.sha256 } : null;
                const written = !state.defaultUnchanged;
                data = { status: written ? 'written' : 'unchanged', path: 'wad\\defaults\\configuration.json',
                  file: 'C:\\Pesto\\PROD\\wad\\defaults\\configuration.json', version: written ? request.args.version ?? '20261112-101500' : current.version,
                  fingerprint: 'a'.repeat(64), sha256: written ? 'e'.repeat(64) : current.sha256, replaced: written && !!previous, previous,
                  backup: written && previous ? 'C:\\Users\\operator\\AppData\\Local\\Pesto\\backups\\installation-default.20261112-101500.' + '0'.repeat(32) + '.json' : null,
                  distribution: 'official', official: true, packFingerprint: 'f'.repeat(64), decisionSaved: state.decisionSaved };
                break;
              }
              case 'references.preview': data = {
                planId: 'references-1', version: 'referentiel.2', additions: 1, conflictCount: 2, unchanged: 0,
                conflicts: [
                  { key: 'site:PARIS*', kind: 'site', current: { Site: 'Paris*', Tag: 'PA' }, incoming: { Site: 'Paris*', Tag: 'PR' } },
                  { key: 'service:PA:INF', kind: 'service', current: { Site: 'PA', Service: 'INF', Name: 'INF' }, incoming: { Site: 'PA', Service: 'INF', Name: 'Informatique' } },
                ],
                changes: [{ key: 'service:PA:002', incoming: { Site: 'PA', Service: '002', Name: 'Accueil' } }], requiresConfirmation: true,
              }; break;
              case 'references.apply': data = { status: 'applied', changed: true, backup: 'C:\\Profile\\backups\\cfg.bak' }; break;
              case 'updates.inspect': data = state.cancelUpdateSource ? { status: 'cancelled' }
                : request.args.kind === 'zip' ? { candidateId: 'zip-candidate', version: '2.0.1', source: 'local', name: 'Pesto_V2_PRODLIGHT_2.0.1.zip', channel: 'PROD', distribution: 'official' }
                : state.candidateDefaults ? { candidateId: 'local-candidate', version: '2.0.1', source: 'local', distribution: 'official', channel: 'PROD', configurationIncluded: false, localConfiguration: true }
                : { candidateId: 'local-candidate', version: '2.0.1', source: 'local', distribution: 'custom', channel: 'PROD', configurationIncluded: true, localConfiguration: false }; break;
              case 'updates.prepare': data = { preparedId: 'prepared-' + request.args.candidateId, version: '2.0.1', channel: 'PROD',
                source: 'local', distribution: request.args.candidateId === 'zip-candidate' || state.candidateDefaults ? 'official' : 'custom',
                localConfiguration: request.args.candidateId !== 'zip-candidate' && state.candidateDefaults,
                // InstallationDefaults.DescribeInstall: the installation's own default is kept, otherwise the pack's is adopted.
                installDefaults: ['local', 'sealed'].includes(state.installationDefault.state) ? 'kept'
                  : request.args.candidateId !== 'zip-candidate' ? 'adopted' : null,
                message: 'Copie vérifiée ; aucune installation effectuée.' }; break;
              case 'updates.install': data = { status: 'closing', transactionId: 'transaction-1', message: 'Fermeture demandée. Le résultat reste à confirmer par le contrôle de santé.' }; break;
              case 'updates.status': data = { version: '2.0.0', channel: 'PROD', distribution: 'custom', message: 'Le résultat reste consigné dans la transaction.',
                pendingRecovery: state.pendingRecovery, canRollback: state.canRollback, rollbackVersion: state.canRollback ? state.rollbackVersion : null,
                recoveryVersion: state.pendingRecovery ? state.recoveryVersion : null,
                rollbackDefaults: state.canRollback ? state.rollbackDefaults : null, recoveryDefaults: state.pendingRecovery ? state.recoveryDefaults : null,
                localConfiguration: structuredClone(state.installationDefault) }; break;
              case 'updates.windows': data = state.packWindows ?? { windows: [], token: '' }; break;
              case 'updates.rollback': case 'updates.recover': case 'host.reconnect': data = { status: 'closing', message: 'Fermeture demandée.' }; break;
              default: throw Object.assign(new Error('Opération de fixture non déclarée : ' + request.op), { code: 'operation.unknown' });
            }
            if (state.hold === request.op) await new Promise(resolve => state.releases.push(resolve));
            receive({ data: { id: request.id, kind: 'result', data } });
            state.delivered++;
          } catch (error) { receive({ data: { id: request.id, kind: 'error', error: { code: error.code || 'fixture', message: error.message } } }); }
        },
      };
    }, { fresh, distribution, local, invalid, pendingSettings, failSettings, session });
    // Boxes lit up by the settings page from the start of the document (the flash itself lasts 1.7 s).
    await page.addInitScript(() => {
      window.flashed = [];
      new MutationObserver((records) => {
        for (const r of records) {
          const el = r.target;
          if (!(el instanceof Element) || !el.classList.contains('pr-flash') || String(r.oldValue ?? '').split(/\s+/).includes('pr-flash')) continue;
          window.flashed.push([...el.querySelectorAll('[data-maint], [name]')].map((n) => n.dataset.maint || n.getAttribute('name')));
        }
      }).observe(document, { subtree: true, attributes: true, attributeFilter: ['class'], attributeOldValue: true });
    });
    await page.goto(origin + (local ? `/?configuration=local${address}` : `/${address}`));
    if (pendingSettings) await page.waitForFunction(() => window.fixture.releases.length === 1);
    else await page.waitForFunction(() => document.documentElement.dataset.ready === 'parametres');
    await page.waitForFunction(() => window.fixture.calls.some((call) => call.op === 'configuration.settings'));
    return page;
  }
  const calls = (page, op) => page.evaluate((op) => window.fixture.calls.filter((call) => call.op === op), op);
  const dialog = (page) => page.locator('.k-dlg-layer:not(.leaving) .k-dlg').last();
  const closeDialog = async (page, action) => { const host = dialog(page); await host.locator(`[data-id="${action}"]`).click(); await host.waitFor({ state: 'hidden' }); };
  // Paramètres shows one section at a time (2.0.15): an action is clicked once its section is open, by the rail.
  const SECTION_OF_ACTION = { export: 'configuration', import: 'configuration', default: 'configuration', distribution: 'configuration',
    reconnect: 'configuration', references: 'configuration', zip: 'mises-a-jour', folder: 'mises-a-jour', source: 'mises-a-jour',
    status: 'mises-a-jour', rollback: 'mises-a-jour' };
  const openSection = async (page, id) => {
    await page.locator(`main .pr-nav-item[data-section="${id}"]`).click();
    await page.locator(`main [data-section-panel="${id}"]:not([hidden])`).waitFor();
  };
  const click = async (page, action) => { await openSection(page, SECTION_OF_ACTION[action]); await page.locator(`[data-maint="${action}"]`).click(); };
  const shownSections = (page) => page.locator('main [data-section-panel]:not([hidden])').evaluateAll((nodes) => nodes.map((node) => node.dataset.sectionPanel));
  const hash = (page) => page.evaluate(() => location.hash);
  const frames = (page) => page.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))));
  const waitCall = (page, operation, count = 1) => page.waitForFunction(({ operation, count }) => window.fixture.calls.filter((call) => call.op === operation).length >= count, { operation, count });

  const release = async page => {
    await page.evaluate(async () => {
      window.fixture.hold = null;
      window.fixture.releases.splice(0).forEach(resolve => resolve());
      await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    });
  };
  const leaveSettings = async (page, discard = false) => {
    await page.evaluate(() => { location.hash = '#/aide'; });
    if (discard) { await dialog(page).waitFor(); await closeDialog(page, 'ok'); }
    await page.locator('main[data-page="aide"]').waitFor();
  };

  await check('Session : un seul indicateur, cible et contrôleur distingués, détails réunis', async () => {
    for (const dc of ['dc01.labo.local', null]) {
      const page = await makePage({ session: { domain: 'labo.local', dc, account: 'LABO\\operateur' } });
      try {
        assert.equal(await page.locator('.topbar .live').count(), 0);
        const chip = page.locator('.mode-chip');
        assert.equal(await chip.count(), 1);
        assert.equal(await chip.getAttribute('data-mode'), 'live');
        assert.equal(await chip.getAttribute('data-state'), dc ? 'discovered' : 'targeted');
        await chip.locator('.txt').waitFor({ state: 'visible' });
        assert.equal(await chip.locator('.txt').innerText(), 'Annuaire · labo.local');
        assert.match(await chip.getAttribute('data-tip'), dc ? /Contrôleur découvert/ : /Contrôleur non confirmé/);
        assert.equal(await chip.isEnabled(), true);
        await chip.click();
        const menu = page.getByRole('menu', { name: 'Session', exact: true });
        for (const label of ['Mode', 'Domaine', 'Contrôleur', 'Écritures', 'Compte', 'Poste', 'Version du moteur'])
          assert.match(await menu.innerText(), new RegExp(label));
        await page.keyboard.press('Escape');
        await page.evaluate(() => { window.fixture.fail = 'configuration.settings'; window.fixture.failCode = 'bridge.unavailable'; });
        await page.locator('[data-act="reload"]').click();
        await page.waitForFunction(() => document.querySelector('.mode-chip .txt').textContent === 'Moteur injoignable');
        assert.equal(await chip.getAttribute('data-state'), 'offline');
        await page.evaluate(() => { window.fixture.fail = null; });
        await page.locator('[data-act="reload"]').click();
        await page.waitForFunction(() => document.querySelector('.mode-chip .txt').textContent.startsWith('Annuaire ·'));
      } finally { await page.close(); }
    }
  });

  await check('Session : lecture seule et actions suspendues restent explicites', async () => {
    for (const suspended of [false, true]) {
      const page = await makePage({ session: { domain: 'labo.local', readOnly: true,
        capabilities: [{ id: 'acknowledge', enabled: suspended }] } });
      try {
        const chip = page.locator('.mode-chip');
        assert.equal(await chip.getAttribute('data-mode'), 'readonly');
        assert.equal(await chip.locator('.txt').innerText(), `${suspended ? 'Actions AD suspendues' : 'Lecture seule'} · labo.local`);
        assert.equal(await chip.isEnabled(), true);
      } finally { await page.close(); }
    }
  });

  await check('Première lecture lente : une commande Enregistrer prématurée ne supprime pas la réponse attendue', async () => {
    const page = await makePage({ local: true, pendingSettings: true });
    try {
      // Dispatch the same save handler as the command palette, even though the ordinary button is disabled.
      await page.locator('[data-act="save"]').dispatchEvent('click');
      assert.equal((await calls(page, 'configuration.previewSettings')).length, 0);
      await release(page);
      await page.waitForFunction(() => !document.querySelector('[data-act="save"]').disabled);
      assert.equal(await page.locator('[name="prefix"]').inputValue(), '111301');
    } finally { await page.close(); }
  });

  await check('Saisie avant première lecture : Relire exige aussi un abandon confirmé du brouillon', async () => {
    const page = await makePage({ local: true, pendingSettings: true });
    try {
      await page.locator('[name="prefix"]').fill('333333');
      await release(page);
      assert.equal(await page.locator('[name="prefix"]').inputValue(), '333333');
      assert.equal(await page.locator('[data-act="save"]').isDisabled(), true);
      await page.locator('[data-act="reload"]').click(); await dialog(page).waitFor();
      await closeDialog(page, 'cancel');
      assert.equal(await page.locator('[name="prefix"]').inputValue(), '333333');
      assert.equal((await calls(page, 'configuration.settings')).length, 1);
      await page.locator('[data-act="reload"]').click(); await closeDialog(page, 'ok');
      await page.waitForFunction(() => !document.querySelector('[data-act="save"]').disabled);
      assert.equal(await page.locator('[name="prefix"]').inputValue(), '111301');
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
    } finally { await page.close(); }
  });

  for (const [action, operation] of [['import', 'configuration.previewImport'], ['rollback', 'updates.status'],
    ['status', 'updates.status'], ['distribution', 'configuration.status'], ['default', 'configuration.status']]) {
    await check(`Réponse tardive ${action} : quitter les paramètres interdit tout dialogue ou effet ultérieur`, async () => {
      const page = await makePage({ local: true });
      try {
        await page.evaluate(op => { Object.assign(window.fixture, { hold: op, pendingRecovery: true, pendingDistribution: true }); }, operation);
        await click(page, action);
        await page.waitForFunction(() => window.fixture.releases.length === 1);
        await leaveSettings(page); await release(page);
        assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
        for (const op of ['configuration.applyImport', 'configuration.decideDistribution', 'configuration.setDefault', 'updates.rollback', 'updates.recover'])
          assert.equal((await calls(page, op)).length, 0);
      } finally { await page.close(); }
    });
  }

  await check('Enregistrement lent : une seule préparation et aucun aperçu ancien après nouvelle saisie', async () => {
    const page = await makePage({ local: true });
    try {
      await page.locator('[name="prefix"]').fill('222222');
      await page.evaluate(() => { window.fixture.hold = 'configuration.previewSettings'; document.querySelector('[data-act="save"]').click(); document.querySelector('[data-act="save"]').click(); });
      await page.waitForFunction(() => window.fixture.releases.length > 0);
      assert.equal((await calls(page, 'configuration.previewSettings')).length, 1);
      assert.equal(await page.locator('[data-act="save"]').isDisabled(), true);
      await page.locator('[name="prefix"]').fill('333333');
      await release(page);
      assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
      assert.equal(await page.locator('[name="prefix"]').inputValue(), '333333');
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
    } finally { await page.close(); }
  });

  await check('Relecture lente : la saisie arrivée pendant la lecture reste intacte', async () => {
    const page = await makePage({ local: true });
    try {
      await page.evaluate(() => { window.fixture.hold = 'configuration.settings'; });
      await page.locator('[data-act="reload"]').click();
      await page.waitForFunction(() => window.fixture.releases.length === 1);
      await page.locator('[name="prefix"]').fill('333333');
      await release(page);
      assert.equal(await page.locator('[name="prefix"]').inputValue(), '333333');
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
    } finally { await page.close(); }
  });

  await check('Rafraîchissement de configuration : le brouillon existant est conservé', async () => {
    const page = await makePage({ local: true });
    try {
      await page.locator('[name="prefix"]').fill('333333');
      await page.evaluate(async () => {
        window.dispatchEvent(new CustomEvent('pesto-configuration-changed'));
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      });
      assert.equal(await page.locator('[name="prefix"]').inputValue(), '333333');
    } finally { await page.close(); }
  });

  await check('Relire un brouillon demande un choix, annuler conserve les champs', async () => {
    const page = await makePage({ local: true });
    try {
      await page.locator('[name="prefix"]').fill('333333');
      await page.locator('[data-act="reload"]').click(); await dialog(page).waitFor();
      await closeDialog(page, 'cancel');
      assert.equal(await page.locator('[name="prefix"]').inputValue(), '333333');
      await page.locator('[data-act="reload"]').click(); await closeDialog(page, 'ok');
      await page.waitForFunction(() => document.querySelector('[name="prefix"]').value === '111301');
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
    } finally { await page.close(); }
  });
  await check('Brouillon paramètres : navigation annulée conserve les saisies et la route affichée', async () => {
    const page = await makePage({ local: true });
    try {
      await page.locator('[name="prefix"]').fill('333333');
      await page.locator('.nav-item[data-id="aide"]').click(); await dialog(page).waitFor();
      assert.equal(await page.evaluate(() => location.hash), '#/parametres');
      assert.equal(await page.locator('main').getAttribute('data-page'), 'parametres');
      assert.match(await dialog(page).innerText(), /modifications non enregistrées/);
      await closeDialog(page, 'cancel');
      assert.equal(await page.locator('[name="prefix"]').inputValue(), '333333');
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
      await leaveSettings(page, true);
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
    } finally { await page.close(); }
  });
  await check('Brouillon paramètres : réponse en cours conservée pendant la confirmation de sortie', async () => {
    const page = await makePage({ local: true });
    try {
      await page.locator('[name="prefix"]').fill('222222');
      await page.locator('[data-act="save"]').click(); await dialog(page).waitFor();
      await page.evaluate(() => { window.fixture.hold = 'configuration.applyImport'; });
      await closeDialog(page, 'apply'); await page.waitForFunction(() => window.fixture.releases.length === 1);
      await page.locator('.nav-item[data-id="aide"]').click(); await dialog(page).waitFor();
      assert.equal(await page.evaluate(() => location.hash), '#/parametres');
      await release(page);
      await page.waitForFunction(() => !document.querySelector('[data-act="save"]').disabled);
      assert.equal(await page.locator('[name="prefix"]').inputValue(), '222222');
      assert.equal((await calls(page, 'configuration.settings')).length, 2);
      await closeDialog(page, 'cancel');
      assert.equal(await page.locator('main').getAttribute('data-page'), 'parametres');
      assert.equal((await calls(page, 'configuration.applyImport')).length, 1);
      await leaveSettings(page);
    } finally { await page.close(); }
  });

  await check('Deux relectures terminées en ordre inverse : seule la dernière est affichée', async () => {
    const page = await makePage({ local: true });
    try {
      await page.evaluate(() => { window.fixture.hold = 'configuration.settings'; });
      await page.locator('[data-act="reload"]').click();
      await page.waitForFunction(() => window.fixture.releases.length === 1);
      await page.evaluate(() => { window.fixture.hold = null; window.fixture.settings.prefix = '222222'; });
      await page.locator('[data-act="reload"]').click();
      await page.waitForFunction(() => document.querySelector('[name="prefix"]').value === '222222');
      await release(page);
      assert.equal(await page.locator('[name="prefix"]').inputValue(), '222222');
    } finally { await page.close(); }
  });

  await check('Enregistrement confirmé lent : une nouvelle saisie reste disponible pour la sauvegarde suivante', async () => {
    const page = await makePage({ local: true });
    try {
      await page.locator('[name="prefix"]').fill('222222');
      await page.locator('[data-act="save"]').click(); await dialog(page).waitFor();
      await page.evaluate(() => { window.fixture.hold = 'configuration.applyImport'; });
      await closeDialog(page, 'apply');
      await page.waitForFunction(() => window.fixture.releases.length === 1);
      await page.locator('[name="prefix"]').fill('333333');
      await release(page);
      await page.waitForFunction(() => !document.querySelector('[data-act="save"]').disabled);
      assert.equal(await page.locator('[name="prefix"]').inputValue(), '333333');
      await page.locator('[data-act="save"]').click(); await dialog(page).waitFor();
      const next = (await calls(page, 'configuration.previewSettings'))[1].args;
      assert.equal(next.prefix, '333333'); assert.equal(next.fingerprint, 'b'.repeat(64));
      await closeDialog(page, 'apply'); await waitCall(page, 'configuration.applyImport', 2);
      assert.equal((await calls(page, 'configuration.applyImport')).length, 2);
    } finally { await page.close(); }
  });

  await check('Enregistrement confirmé puis navigation : aucun retour tardif sur la page quittée', async () => {
    const page = await makePage({ local: true });
    try {
      await page.locator('[name="prefix"]').fill('222222');
      await page.locator('[data-act="save"]').click(); await dialog(page).waitFor();
      await page.evaluate(() => { window.fixture.hold = 'configuration.applyImport'; });
      await closeDialog(page, 'apply');
      await page.waitForFunction(() => window.fixture.releases.length === 1);
      await leaveSettings(page, true); await release(page);
      assert.equal(await page.locator('main').getAttribute('data-page'), 'aide');
      assert.equal((await calls(page, 'configuration.applyImport')).length, 1);
      assert.equal((await calls(page, 'configuration.settings')).length, 1);
      assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
    } finally { await page.close(); }
  });

  await check('Configuration locale : deux pages, bannière et échanges de paramètres sans aucun appel annuaire', async () => {
    const page = await makePage({ local: true });
    try {
      assert.deepEqual(await page.locator('nav a.nav-item').evaluateAll((nodes) => nodes.map((node) => node.dataset.id)), ['parametres', 'aide']);
      assert.equal(await page.locator('.sim-banner').isVisible(), true);
      assert.match(await page.locator('.sim-banner').innerText(), /CONFIGURATION LOCALE.*annuaire non connecté/);
      assert.equal(await page.locator('.nav-account-domain').innerText(), 'Annuaire non connecté');
      assert.doesNotMatch(await page.locator('[data-zone="mode"]').innerText(), /Annuaire réel/);
      for (const action of ['import', 'export', 'default']) assert.equal(await page.locator(`[data-maint="${action}"]`).isEnabled(), true);
      await click(page, 'export'); await waitCall(page, 'configuration.export');
      await click(page, 'import'); await dialog(page).waitFor(); await closeDialog(page, 'cancel');
      await click(page, 'default'); await dialog(page).waitFor(); await closeDialog(page, 'ok');
      await waitCall(page, 'configuration.setDefault');
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
      const recorded = await page.evaluate(() => window.fixture.calls.map((call) => call.op));
      assert.deepEqual(recorded.filter((op) => /^(directory\.|computer\.|names\.|operation\.|queue\.|dashboard\.)/.test(op)), []);
    } finally { await page.close(); }
  });

  await check('Configuration invalide : aucun faux réglage actif, remplacement explicite puis reprise des actions locales', async () => {
    const page = await makePage({ local: true, invalid: true });
    try {
      await page.locator('[data-configuration-invalid]').waitFor({ state: 'visible' });
      assert.match(await page.locator('[data-configuration-invalid]').innerText(), /invalide.*Aucun paramètre par défaut/s);
      assert.equal(await page.locator('[name="domain"]').inputValue(), '');
      assert.equal(await page.locator('[name="domain"]').isEnabled(), false);
      assert.equal(await page.locator('[data-act="save"]').isEnabled(), false);
      assert.equal(await page.locator('[data-maint="import"]').isEnabled(), true);
      for (const action of ['export', 'default', 'references', 'distribution', 'reconnect'])
        assert.equal(await page.locator(`[data-maint="${action}"]`).isEnabled(), false);
      await click(page, 'import'); await dialog(page).waitFor();
      assert.match(await dialog(page).innerText(), /Remplacer la configuration invalide/);
      await dialog(page).locator('summary').click();
      assert.match(await dialog(page).innerText(), /octets originaux seront sauvegardés/);
      assert.match(await dialog(page).innerText(), /example\.local/);
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
      await closeDialog(page, 'cancel');
      assert.equal(await page.locator('[data-maint="default"]').isEnabled(), false);
      await click(page, 'import'); await dialog(page).waitFor(); await closeDialog(page, 'apply');
      await waitCall(page, 'configuration.applyImport');
      assert.deepEqual((await calls(page, 'configuration.applyImport'))[0].args, { planId: 'recovery-1', confirmed: true });
      await page.waitForFunction(() => !document.querySelector('[data-act="save"]').disabled && document.querySelector('[name="domain"]').value === 'example.local');
      assert.equal(await page.locator('[data-configuration-invalid]').isVisible(), false);
      assert.equal(await page.locator('[data-maint="default"]').isEnabled(), true);
      assert.match(await page.locator('[data-maint-status="configuration"]').innerText(), /Sauvegarde/);
      const recorded = await page.evaluate(() => window.fixture.calls.map((call) => call.op));
      assert.deepEqual(recorded.filter((op) => /^(directory\.|computer\.|names\.|operation\.|queue\.|dashboard\.)/.test(op)), []);
    } finally { await page.close(); }
  });

  await check('Profil neuf : formulaire sans V1, aperçu puis application exacte après confirmation', async () => {
    const page = await makePage({ fresh: true });
    try {
      assert.equal(await page.locator('[name="domain"]').inputValue(), '');
      assert.equal(await page.locator('[name="dc"]').getAttribute('readonly'), '');
      await page.locator('[name="domain"]').fill('example.local');
      await page.locator('[name="prefix"]').fill('111301');
      await page.locator('[name="rootOu"]').fill('OU=Postes,DC=example,DC=local');
      await page.locator('[name="sites"]').fill('paris;Paris;PA;OU=Paris,OU=Postes,DC=example,DC=local');
      await page.locator('[data-act="save"]').click(); await dialog(page).waitFor();
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
      const first = (await calls(page, 'configuration.previewSettings'))[0];
      assert.equal(first.args.domain, 'example.local'); assert.equal(first.args.fingerprint, '');
      assert.equal(first.args.rootOu, 'OU=Postes,DC=example,DC=local');
      assert.deepEqual(first.args.sites, [{ id: 'paris', name: 'Paris', code: 'PA', ou: 'OU=Paris,OU=Postes,DC=example,DC=local' }]);
      await closeDialog(page, 'cancel');
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
      await page.locator('[data-act="save"]').click(); await dialog(page).waitFor();
      await closeDialog(page, 'apply'); await waitCall(page, 'configuration.applyImport');
      assert.deepEqual((await calls(page, 'configuration.applyImport'))[0].args, { planId: 'settings-2', confirmed: true });
      assert.equal((await calls(page, 'settings.save')).length, 0);
      assert.equal((await calls(page, 'operation.execute')).length, 0);
      await page.waitForFunction(() => document.querySelector('.toasts').textContent.includes('Reconnecter Pesto'));
    } finally { await page.close(); }
  });

  await check('Politiques : aperçu typé puis confirmation, sans contact du registre ou écriture AD', async () => {
    const page = await makePage();
    try {
      const coordinationRoot = String.raw`\\serveur\partage\coordination`;
      assert.equal(await page.locator('[name="entraPolicy"]').inputValue(), 'HybridOnly');
      await openSection(page, 'politiques');
      await page.locator('[name="entraPolicy"]').selectOption('Disabled');
      await page.locator('[name="coordinationRoot"]').fill(coordinationRoot);
      for (const key of ['coordinationRequired', 'reserveNamesInAd', 'auditEventLogEnabled', 'blockJoinOnClockSkew', 'allowPrecreatedJoin']) await page.locator('[name="' + key + '"]').check();
      await page.locator('[name="excludedGroupGuids"]').fill('AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\n11111111-2222-3333-4444-555555555555');
      await page.locator('[data-act="save"]').click(); await dialog(page).waitFor();
      const sent = (await calls(page, 'configuration.previewSettings'))[0].args;
      assert.equal(sent.coordinationRoot, coordinationRoot);
      assert.equal(sent.entraPolicy, 'Disabled');
      for (const key of ['coordinationRequired', 'reserveNamesInAd', 'auditEventLogEnabled', 'blockJoinOnClockSkew', 'allowPrecreatedJoin']) assert.equal(sent[key], true);
      assert.deepEqual(sent.excludedGroupGuids, ['aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', '11111111-2222-3333-4444-555555555555']);
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
      await closeDialog(page, 'apply'); await waitCall(page, 'configuration.applyImport');
      await page.waitForFunction(() => window.fixture.calls.filter((c) => c.op === 'configuration.settings').length === 2);
      assert.equal(await page.locator('[name="reserveNamesInAd"]').isChecked(), true);
      assert.equal(await page.locator('[name="allowPrecreatedJoin"]').isChecked(), true);
      assert.equal(await page.locator('[name="entraPolicy"]').inputValue(), 'Disabled');
      assert.equal(await page.locator('[name="excludedGroupGuids"]').inputValue(), sent.excludedGroupGuids.join('\n'));
      for (const op of ['coordination.inspect', 'coordination.prepare', 'coordination.apply', 'operation.execute']) assert.equal((await calls(page, op)).length, 0);
    } finally { await page.close(); }
  });

  await check('Groupes exclus : GUID invalide ou doublon refuse avant tout aperçu', async () => {
    const page = await makePage();
    try {
      await openSection(page, 'politiques');
      for (const value of ['invalide', '00000000-0000-0000-0000-000000000000',
        'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\naaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee']) {
        await page.locator('[name="excludedGroupGuids"]').fill(value);
        await page.locator('[data-act="save"]').click();
        await page.waitForFunction(() => document.querySelector('[name="excludedGroupGuids"]').getAttribute('aria-invalid') === 'true');
        assert.equal((await calls(page, 'configuration.previewSettings')).length, 0);
        assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
      }
    } finally { await page.close(); }
  });

  await check('Exporter transmet la version à la sélection native, sans application de configuration', async () => {
    const page = await makePage();
    try {
      await openSection(page, 'configuration');
      await page.locator('[name="configurationVersion"]').fill('entreprise.7'); await click(page, 'export');
      await waitCall(page, 'configuration.export');
      assert.deepEqual((await calls(page, 'configuration.export'))[0].args, { version: 'entreprise.7' });
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
      await page.waitForFunction(() => document.querySelector('[data-maint-status="configuration"]').textContent.includes('exportée'));
    } finally { await page.close(); }
  });

  await check('Import : différences visibles, annulation sans écriture puis plan confirmé exact', async () => {
    const page = await makePage();
    try {
      await click(page, 'import'); await dialog(page).waitFor();
      assert.match(await dialog(page).innerText(), /sauvegardée avant son remplacement atomique/);
      await dialog(page).locator('summary').click();
      assert.match(await dialog(page).innerText(), /111301/); assert.match(await dialog(page).innerText(), /222222/);
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
      await closeDialog(page, 'cancel');
      await click(page, 'import'); await dialog(page).waitFor(); await closeDialog(page, 'apply');
      await waitCall(page, 'configuration.applyImport');
      assert.deepEqual((await calls(page, 'configuration.applyImport'))[0].args, { planId: 'import-1', confirmed: true });
    } finally { await page.close(); }
  });

  await check('Sélection d’import annulée : aucun dialogue de remplacement ni faux succès', async () => {
    const page = await makePage();
    try {
      await page.evaluate(() => { window.fixture.cancelImport = true; });
      await click(page, 'import'); await waitCall(page, 'configuration.previewImport');
      await page.waitForFunction(() => !document.querySelector('[data-maint="import"]').disabled);
      assert.equal(await page.locator('.k-dlg').count(), 0); assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
      assert.doesNotMatch(await page.locator('.toasts').innerText(), /appliquée|importée|remplacée/);
    } finally { await page.close(); }
  });

  const DEFAULT_PATH = String.raw`wad\defaults\configuration.json`;
  const configurationStatus = (page) => page.locator('[data-maint-status="configuration"]').innerText();
  const localDefault = { state: 'local', path: DEFAULT_PATH, version: 'entreprise.2', fingerprint: 'c'.repeat(64), sha256: 'd'.repeat(64) };

  await check('Configuration par défaut : textes de la carte sur place, sans pack personnalisé ni destination', async () => {
    const page = await makePage();
    try {
      const card = await page.locator('[data-maintenance="configuration"]').innerText();
      assert.match(card, /ou les définir comme configuration par défaut de cette installation\./);
      assert.equal(await configurationStatus(page), `La configuration par défaut est écrite dans ${DEFAULT_PATH} de cette installation. Secrets, sessions, reçus, historique et caches sont exclus. Ce fichier contient le domaine et les OU : diffusez ce dossier comme un fichier privé.`);
      assert.doesNotMatch(card, /pack personnalisé|pack complet|destination/i);
      assert.equal(await page.locator('[data-maint="default"]').innerText(), 'Définir comme configuration par défaut');
    } finally { await page.close(); }
  });

  await check('Définir par défaut : état relu, confirmation sur place, annulation sans appel puis écriture exacte', async () => {
    const page = await makePage();
    try {
      await openSection(page, 'configuration');
      await page.locator('[name="configurationVersion"]').fill('entreprise.3');
      const before = (await calls(page, 'configuration.status')).length;
      await click(page, 'default'); await dialog(page).waitFor();
      assert.equal((await calls(page, 'configuration.status')).length, before + 1);
      assert.equal((await calls(page, 'configuration.setDefault')).length, 0);
      assert.equal(await dialog(page).locator('h2').innerText(), 'Définir comme configuration par défaut');
      assert.equal(await dialog(page).locator('.k-dlg-text').innerText(), `Pesto va écrire la configuration partageable de ce profil dans ${DEFAULT_PATH} de cette installation. Aucun pack n’est recréé ; les fichiers du programme et leurs empreintes restent inchangés.`);
      const confirm = dialog(page).locator('[data-id="ok"]');
      assert.equal(await confirm.innerText(), 'Enregistrer comme défaut');
      assert.doesNotMatch(await confirm.getAttribute('class'), /danger/);
      assert.doesNotMatch(await dialog(page).innerText(), /personnalisé|destination|nouveau dossier|Il remplace/);
      await closeDialog(page, 'cancel');
      assert.equal((await calls(page, 'configuration.setDefault')).length, 0);
      assert.doesNotMatch(await configurationStatus(page), /Écriture|enregistrée/);
      await click(page, 'default'); await dialog(page).waitFor(); await closeDialog(page, 'ok');
      await waitCall(page, 'configuration.setDefault');
      assert.deepEqual((await calls(page, 'configuration.setDefault'))[0].args, { version: 'entreprise.3', expectedSha256: '', confirmed: true });
      const expected = `Configuration par défaut enregistrée dans cette installation : ${DEFAULT_PATH} (version entreprise.3).`;
      await page.waitForFunction((text) => document.querySelector('[data-maint-status="configuration"]').textContent === text, expected);
      await page.waitForFunction(() => document.querySelector('.toasts').textContent.includes('Configuration par défaut enregistrée.'));
      assert.doesNotMatch(await page.locator('.toasts').innerText(), /pack personnalisé|release officielle|prêt à diffuser/i);
      assert.equal((await calls(page, 'configuration.setDefault')).length, 1);
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
    } finally { await page.close(); }
  });

  await check('Défaut existant : version affichée, SHA-256 transmis, copie de l’ancienne annoncée', async () => {
    const page = await makePage();
    try {
      await page.evaluate((state) => { window.fixture.installationDefault = state; }, localDefault);
      await click(page, 'default'); await dialog(page).waitFor();
      const text = await dialog(page).locator('.k-dlg-text').innerText();
      assert.ok(text.includes(DEFAULT_PATH), text);
      assert.ok(text.endsWith(' Il remplace la configuration par défaut actuelle (version entreprise.2) ; une copie sera conservée dans votre profil.'), text);
      assert.match(await dialog(page).locator('[data-id="ok"]').getAttribute('class'), /danger/);
      assert.equal((await calls(page, 'configuration.setDefault')).length, 0);
      await closeDialog(page, 'ok'); await waitCall(page, 'configuration.setDefault');
      assert.deepEqual((await calls(page, 'configuration.setDefault'))[0].args, { expectedSha256: 'd'.repeat(64), confirmed: true });
      const backup = String.raw`C:\Users\operator\AppData\Local\Pesto\backups\installation-default.20261112-101500.` + '0'.repeat(32) + '.json';
      const expected = `Configuration par défaut enregistrée dans cette installation : ${DEFAULT_PATH} (version 20261112-101500). Copie de l’ancienne dans votre profil : ${backup}`;
      await page.waitForFunction((text) => document.querySelector('[data-maint-status="configuration"]').textContent === text, expected);
      await page.waitForFunction(() => document.querySelector('.toasts').textContent.includes('Configuration par défaut enregistrée.'));
    } finally { await page.close(); }
  });

  await check('Défaut déjà identique : aucun fichier modifié, version conservée, aucun toast de succès', async () => {
    const page = await makePage();
    try {
      await page.evaluate((state) => { Object.assign(window.fixture, { installationDefault: state, defaultUnchanged: true }); }, localDefault);
      await click(page, 'default'); await dialog(page).waitFor(); await closeDialog(page, 'ok');
      await waitCall(page, 'configuration.setDefault');
      assert.deepEqual((await calls(page, 'configuration.setDefault'))[0].args, { expectedSha256: 'd'.repeat(64), confirmed: true });
      const expected = 'Configuration par défaut déjà identique (version entreprise.2) : aucun fichier modifié.';
      await page.waitForFunction((text) => document.querySelector('[data-maint-status="configuration"]').textContent === text, expected);
      await page.waitForFunction(() => !document.querySelector('[data-maint="default"]').disabled);
      assert.doesNotMatch(await page.locator('.toasts').innerText(), /enregistrée/);
    } finally { await page.close(); }
  });

  for (const [code, message, local] of [
    ['config.default_readonly', 'Le dossier de cette installation n’est pas accessible en écriture : la configuration par défaut n’a pas été enregistrée. Lancez Pesto normalement depuis cette installation (autorisation administrateur), ou exportez la configuration et copiez le fichier sous wad\\defaults\\configuration.json.', false],
    ['config.default_readonly', 'Le dossier de cette installation n’est pas accessible en écriture : la configuration par défaut n’a pas été enregistrée. Lancez Pesto normalement depuis cette installation (autorisation administrateur), ou exportez la configuration et copiez le fichier sous wad\\defaults\\configuration.json.', true],
    ['config.default_changed', 'La configuration par défaut de l’installation a changé depuis son affichage. Rien n’a été modifié ; relisez l’état puis recommencez.', false],
    ['config.default_sealed', 'Cette installation provient d’un ancien pack personnalisé : sa configuration par défaut fait partie de l’inventaire du pack et ne peut pas être remplacée sur place. Installez le pack officiel dans un nouveau dossier, puis définissez-y la configuration par défaut. Rien n’a été modifié.', false],
  ]) {
    await check(`Refus ${code}${local ? ' (configuration locale)' : ''} : statut terminé par le motif, aucun « … » ni faux succès, aucune relance`, async () => {
      const page = await makePage({ local });
      try {
        await page.evaluate(({ code, message }) => Object.assign(window.fixture, { fail: 'configuration.setDefault', failCode: code, failMessage: message,
          installationDefault: code === 'config.default_sealed' ? { state: 'sealed', path: 'wad\\defaults\\configuration.json', version: 'ancien.1', fingerprint: 'c'.repeat(64), sha256: 'd'.repeat(64) }
            : { state: 'missing', path: 'wad\\defaults\\configuration.json', version: null, fingerprint: null, sha256: null } }), { code, message });
        await click(page, 'default'); await dialog(page).waitFor();
        // Only a local file is announced as replaced: a sealed legacy file is refused by the engine, never replaced.
        assert.doesNotMatch(await dialog(page).locator('.k-dlg-text').innerText(), /Il remplace/);
        assert.doesNotMatch(await dialog(page).locator('[data-id="ok"]').getAttribute('class'), /danger/);
        await closeDialog(page, 'ok');
        await waitCall(page, 'configuration.setDefault');
        const expected = `Configuration par défaut non enregistrée : ${message}`;
        await page.waitForFunction((text) => document.querySelector('[data-maint-status="configuration"]').textContent === text, expected);
        await page.waitForFunction((text) => document.querySelector('.toasts').textContent.includes(text), message);
        await page.waitForFunction(() => !document.querySelector('[data-maint="default"]').disabled);
        assert.equal((await calls(page, 'configuration.setDefault')).length, 1);
        assert.doesNotMatch(await configurationStatus(page), /…|Écriture de la configuration/);
        assert.doesNotMatch(await page.locator('.toasts').innerText(), /Configuration par défaut enregistrée/);
      } finally { await page.close(); }
    });
  }

  for (const unchanged of [false, true]) {
    await check(`Choix de l’auteur non mémorisé (${unchanged ? 'défaut identique' : 'défaut écrit'}) : résultat conservé, relance possible annoncée`, async () => {
      const page = await makePage();
      try {
        await page.evaluate(({ state, unchanged }) => Object.assign(window.fixture, { decisionSaved: false, defaultUnchanged: unchanged, installationDefault: state }),
          { state: localDefault, unchanged });
        await click(page, 'default'); await dialog(page).waitFor(); await closeDialog(page, 'ok');
        await waitCall(page, 'configuration.setDefault');
        const note = ' Votre choix n’a pas pu être mémorisé dans votre profil : au prochain démarrage, Pesto pourra vous proposer cette configuration.';
        const expected = unchanged ? `Configuration par défaut déjà identique (version entreprise.2) : aucun fichier modifié.${note}`
          : `Configuration par défaut enregistrée dans cette installation : ${DEFAULT_PATH} (version 20261112-101500). Copie de l’ancienne dans votre profil : `
            + String.raw`C:\Users\operator\AppData\Local\Pesto\backups\installation-default.20261112-101500.` + '0'.repeat(32) + `.json${note}`;
        await page.waitForFunction((text) => document.querySelector('[data-maint-status="configuration"]').textContent === text, expected);
      } finally { await page.close(); }
    });
  }

  await check('Lecture de l’état refusée : aucune confirmation ni écriture, motif dans le statut', async () => {
    const page = await makePage();
    try {
      await page.evaluate(() => Object.assign(window.fixture, { fail: 'configuration.status', failCode: 'config.unavailable', failMessage: 'Le service de configuration n’est pas raccordé.' }));
      await click(page, 'default');
      await page.waitForFunction(() => document.querySelector('[data-maint-status="configuration"]').textContent === 'Configuration par défaut non enregistrée : Le service de configuration n’est pas raccordé.');
      await page.waitForFunction(() => !document.querySelector('[data-maint="default"]').disabled);
      assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
      assert.equal((await calls(page, 'configuration.setDefault')).length, 0);
    } finally { await page.close(); }
  });

  await check('Écriture lente puis navigation : une seule demande, aucun statut ni toast tardif', async () => {
    const page = await makePage({ local: true });
    try {
      await page.evaluate(() => { window.fixture.hold = 'configuration.setDefault'; });
      await click(page, 'default'); await dialog(page).waitFor(); await closeDialog(page, 'ok');
      await page.waitForFunction(() => window.fixture.releases.length === 1);
      assert.equal(await configurationStatus(page), 'Écriture de la configuration par défaut…');
      assert.equal(await page.locator('[data-maint="default"]').isDisabled(), true);
      await leaveSettings(page); await release(page);
      assert.equal((await calls(page, 'configuration.setDefault')).length, 1);
      assert.doesNotMatch(await page.locator('.toasts').innerText(), /Configuration par défaut enregistrée|non enregistrée/);
      assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
    } finally { await page.close(); }
  });

  await check('Référentiels : tous les conflits doivent être résolus avant une application unique', async () => {
    const page = await makePage();
    try {
      await click(page, 'references'); await dialog(page).waitFor();
      assert.equal(await dialog(page).locator('[data-id="apply"]').isEnabled(), false);
      assert.equal((await calls(page, 'references.apply')).length, 0);
      await dialog(page).locator('[data-conflict="0"]').selectOption('current');
      assert.equal(await dialog(page).locator('[data-id="apply"]').isEnabled(), false);
      await dialog(page).locator('[data-conflict="1"]').selectOption('incoming');
      assert.equal(await dialog(page).locator('[data-id="apply"]').isEnabled(), true);
      await closeDialog(page, 'apply'); await waitCall(page, 'references.apply');
      assert.deepEqual((await calls(page, 'references.apply'))[0].args, { planId: 'references-1',
        resolutions: [{ key: 'site:PARIS*', choice: 'current' }, { key: 'service:PA:INF', choice: 'incoming' }], confirmed: true });
      assert.equal((await calls(page, 'operation.execute')).length, 0);
    } finally { await page.close(); }
  });

  await check('Mise à jour par ZIP : inspecter, préparer, confirmer et demander l’installation sont distincts', async () => {
    const page = await makePage();
    try {
      assert.equal((await calls(page, 'updates.inspect')).length, 0);
      await click(page, 'zip'); await page.locator('[data-candidate]').waitFor();
      assert.equal((await calls(page, 'updates.prepare')).length, 0); assert.equal((await calls(page, 'updates.install')).length, 0);
      await page.locator('[data-candidate="0"]').click(); await page.locator('[data-install]').waitFor();
      assert.deepEqual((await calls(page, 'updates.prepare'))[0].args, { candidateId: 'zip-candidate' });
      assert.equal((await calls(page, 'updates.install')).length, 0);
      await page.locator('[data-install]').click(); await dialog(page).waitFor();
      assert.match(await dialog(page).innerText(), /Installer Pesto 2\.0\.1 \(PROD\) · Source locale — origine à vérifier/);
      assert.equal((await calls(page, 'updates.install')).length, 0); await closeDialog(page, 'cancel');
      await page.locator('[data-install]').click(); await dialog(page).waitFor(); await closeDialog(page, 'ok');
      await waitCall(page, 'updates.install');
      assert.deepEqual((await calls(page, 'updates.install'))[0].args, { preparedId: 'prepared-zip-candidate', confirmed: true });
      assert.equal((await calls(page, 'updates.install')).length, 1);
      assert.equal(await page.locator('[data-install]').count(), 0);
      assert.equal(await page.locator('[data-maint="zip"]').isDisabled(), true);
      assert.doesNotMatch(await page.locator('[data-maint-status="updates"]').innerText(), /installée avec succès/);
      assert.doesNotMatch(await page.locator('.toasts').innerText(), /installée|Mise à jour réussie/);
    } finally { await page.close(); }
  });

  await check('Nouvelle source au même numéro de version : aucune installation de l’ancien pack préparé', async () => {
    const page = await makePage();
    try {
      await click(page, 'zip'); await page.locator('[data-candidate]').click(); await page.locator('[data-install]').waitFor();
      await click(page, 'folder');
      await page.waitForFunction(() => document.querySelector('[data-maint-zone="candidates"]').textContent.includes('Pack personnalisé'));
      assert.equal(await page.locator('[data-install]').count(), 0);
      assert.equal(await page.locator('[data-maint-zone="prepared"]').innerText(), '');
      assert.equal((await calls(page, 'updates.install')).length, 0);
      await page.locator('[data-candidate]').click(); await page.locator('[data-install]').waitFor();
      assert.match(await page.locator('[data-maint-zone="prepared"]').innerText(), /PROD · Pack personnalisé/);
      await page.locator('[data-install]').click(); await dialog(page).waitFor();
      assert.match(await dialog(page).innerText(), /Installer Pesto 2\.0\.1 \(PROD\) · Pack personnalisé/);
      assert.doesNotMatch(await dialog(page).innerText(), /Source locale — origine à vérifier/);
      await closeDialog(page, 'ok'); await waitCall(page, 'updates.install');
      assert.deepEqual((await calls(page, 'updates.install')).map(c => c.args), [{ preparedId: 'prepared-local-candidate', confirmed: true }]);
    } finally { await page.close(); }
  });

  await check('Nouvelle préparation refusée : l’ancien bouton Installer disparaît et l’attente se termine', async () => {
    const page = await makePage();
    try {
      await click(page, 'zip'); await page.locator('[data-candidate]').click(); await page.locator('[data-install]').waitFor();
      await page.evaluate(() => { window.fixture.fail = 'updates.prepare'; });
      await page.locator('[data-candidate]').click();
      await page.waitForFunction(() => document.querySelector('[data-maint-status="updates"]').textContent.includes('Préparation refusée'));
      assert.equal((await calls(page, 'updates.prepare')).length, 2);
      assert.equal(await page.locator('[data-install]').count(), 0);
      assert.equal((await calls(page, 'updates.install')).length, 0);
      assert.doesNotMatch(await page.locator('[data-maint-status="updates"]').innerText(), /Préparation en cours/);
      assert.equal(await page.locator('[data-maint="status"]').isEnabled(), true);
    } finally { await page.close(); }
  });

  await check('Sélection de source annulée : la préparation existante reste liée à son origine affichée', async () => {
    const page = await makePage();
    try {
      await click(page, 'zip'); await page.locator('[data-candidate]').click(); await page.locator('[data-install]').waitFor();
      await page.evaluate(() => { window.fixture.cancelUpdateSource = true; });
      await click(page, 'folder'); await waitCall(page, 'updates.inspect');
      await page.waitForFunction(() => !document.querySelector('[data-maint="folder"]').disabled);
      assert.match(await page.locator('[data-maint-zone="prepared"]').innerText(), /PROD · Source locale — origine à vérifier/);
      assert.equal(await page.locator('[data-install]').isEnabled(), true);
      assert.equal((await calls(page, 'updates.prepare')).length, 1);
      assert.equal((await calls(page, 'updates.install')).length, 0);
    } finally { await page.close(); }
  });

  await check('Installation refusée : aucun bouton de rejeu, accès à État et reprise', async () => {
    const page = await makePage();
    try {
      await click(page, 'zip'); await page.locator('[data-candidate]').click(); await page.locator('[data-install]').waitFor();
      await page.evaluate(() => { window.fixture.fail = 'updates.install'; });
      await page.locator('[data-install]').click(); await dialog(page).waitFor(); await closeDialog(page, 'ok');
      await page.waitForFunction(() => document.querySelector('[data-maint-status="updates"]').textContent.includes('Installation non confirmée'));
      assert.equal((await calls(page, 'updates.install')).length, 1);
      assert.equal(await page.locator('[data-install]').count(), 0);
      assert.equal(await page.locator('[data-maint="status"]').isEnabled(), true);
      await click(page, 'status'); await waitCall(page, 'updates.status');
      assert.equal((await calls(page, 'updates.install')).length, 1);
      assert.doesNotMatch(await page.locator('.toasts').innerText(), /installée|Mise à jour réussie/);
    } finally { await page.close(); }
  });

  await check('Installation refusée faute de fermeture des autres fenêtres : non lancée, aucune reprise suggérée', async () => {
    const page = await makePage();
    try {
      await click(page, 'zip'); await page.locator('[data-candidate]').click(); await page.locator('[data-install]').waitFor();
      await page.evaluate(() => Object.assign(window.fixture, { fail: 'updates.install', failCode: 'update.running',
        failMessage: 'Ces fenêtres Pesto ne se sont pas fermées à temps : « Pesto v2 — PROD (processus 7) ». Aucun fichier n’a été remplacé.' }));
      await page.locator('[data-install]').click(); await dialog(page).waitFor(); await closeDialog(page, 'ok');
      await page.waitForFunction(() => document.querySelector('[data-maint-status="updates"]').textContent.includes('Installation non lancée'));
      await page.waitForFunction(() => document.querySelector('.toasts').textContent.includes('ne se sont pas fermées à temps'));
      assert.equal((await calls(page, 'updates.install')).length, 1);
      assert.doesNotMatch(await page.locator('[data-maint-status="updates"]').innerText(), /non confirmée|État et reprise/);
    } finally { await page.close(); }
  });

  await check('Relais d’installation en attente puis accepté : une seule demande et commandes maintenues fermées', async () => {
    const page = await makePage();
    try {
      await click(page, 'zip'); await page.locator('[data-candidate]').click(); await page.locator('[data-install]').waitFor();
      await page.evaluate(() => { window.fixture.hold = 'updates.install'; });
      await page.locator('[data-install]').click(); await dialog(page).waitFor(); await closeDialog(page, 'ok');
      await page.waitForFunction(() => window.fixture.releases.length === 1);
      assert.equal(await page.locator('[data-install]').count(), 0);
      assert.equal(await page.locator('[data-maint]:enabled,[data-candidate]:enabled').count(), 0);
      await release(page);
      await page.waitForFunction(() => document.querySelector('[data-maint-status="updates"]').textContent.includes('Fermeture demandée'));
      assert.equal(await page.locator('[data-maint]:enabled,[data-candidate]:enabled').count(), 0);
      await page.locator('[data-candidate]').dispatchEvent('click');
      assert.equal((await calls(page, 'updates.prepare')).length, 1);
      assert.equal((await calls(page, 'updates.install')).length, 1);
    } finally { await page.close(); }
  });

  for (const [action, args] of [['zip', { kind: 'zip' }], ['folder', { kind: 'folder' }], ['source', { source: '\\\\serveur\\partage\\Pesto-PROD' }]]) {
    await check(`Source ${action} : inspection seule, sélection correctement transmise`, async () => {
      const page = await makePage();
      try {
        if (action === 'source') { await openSection(page, 'mises-a-jour'); await page.locator('[name="updateSource"]').fill(args.source); }
        await click(page, action); await page.locator('[data-candidate]').waitFor();
        assert.deepEqual((await calls(page, 'updates.inspect'))[0].args, args);
        assert.equal((await calls(page, 'updates.prepare')).length, 0); assert.equal((await calls(page, 'updates.install')).length, 0);
        // The ZIP fixture carries an official manifest: still shown as a local source whose origin is not attested.
        assert.match(await page.locator('[data-maint-zone="candidates"]').innerText(), action === 'zip' ? /Source locale — origine à vérifier/ : /Pack personnalisé/);
      } finally { await page.close(); }
    });
  }

  for (const choice of ['keep', 'replace']) {
    await check(`Configuration distribuée : ${choice} exige le choix explicite avec différences`, async () => {
      const page = await makePage({ distribution: true });
      try {
        await dialog(page).waitFor();
        assert.match(await dialog(page).innerText(), /nouvelle configuration accompagne ce pack/);
        assert.equal((await calls(page, 'configuration.decideDistribution')).length, 0);
        await dialog(page).locator('summary').click();
        assert.match(await dialog(page).innerText(), /111301/); assert.match(await dialog(page).innerText(), /222222/);
        await closeDialog(page, choice); await waitCall(page, 'configuration.decideDistribution');
        assert.deepEqual((await calls(page, 'configuration.decideDistribution'))[0].args, { planId: 'distributed-1', replace: choice === 'replace', confirmed: true });
        assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
        if (choice === 'replace') await page.waitForFunction(() => document.querySelector('[name="prefix"]').value === '222222');
        else assert.equal(await page.locator('[name="prefix"]').inputValue(), '111301');
      } finally { await page.close(); }
    });
  }

  await check('Candidat avec configuration par défaut locale : mention visible jusqu’à la confirmation, conservation annoncée', async () => {
    const page = await makePage();
    try {
      await click(page, 'zip'); await page.locator('[data-candidate]').waitFor();
      assert.doesNotMatch(await page.locator('[data-maint-zone="candidates"]').innerText(), /configuration par défaut incluse/);
      await page.evaluate(() => { window.fixture.candidateDefaults = true; });
      await click(page, 'folder');
      await page.waitForFunction(() => document.querySelector('[data-maint-zone="candidates"]').textContent.includes('configuration par défaut incluse'));
      const candidate = await page.locator('[data-maint-zone="candidates"]').innerText();
      assert.match(candidate, /Source locale — origine à vérifier · configuration par défaut incluse · PROD/);
      assert.doesNotMatch(candidate, /Pack personnalisé/);
      await page.locator('[data-candidate]').click(); await page.locator('[data-install]').waitFor();
      assert.match(await page.locator('[data-maint-zone="prepared"]').innerText(), /PROD · Source locale — origine à vérifier · configuration par défaut incluse/);
      await page.locator('[data-install]').click(); await dialog(page).waitFor();
      const text = await dialog(page).innerText();
      assert.match(text, /Installer Pesto 2\.0\.1 \(PROD\) · Source locale — origine à vérifier · configuration par défaut incluse\./);
      assert.match(text, /Votre configuration reste dans votre profil\. La configuration par défaut du pack choisi sera adoptée par cette installation\./);
      assert.doesNotMatch(text, /est conservée/);
      await closeDialog(page, 'cancel');
      assert.equal((await calls(page, 'updates.install')).length, 0);
    } finally { await page.close(); }
  });

  await check('Ancien pack personnalisé : mention « Pack personnalisé » conservée, sans configuration incluse', async () => {
    const page = await makePage();
    try {
      await click(page, 'folder'); await page.locator('[data-candidate]').waitFor();
      const candidate = await page.locator('[data-maint-zone="candidates"]').innerText();
      assert.match(candidate, /Pack personnalisé — source locale · PROD/);
      assert.doesNotMatch(candidate, /configuration par défaut incluse/);
      await page.locator('[data-candidate]').click(); await page.locator('[data-install]').waitFor();
      await page.locator('[data-install]').click(); await dialog(page).waitFor();
      assert.match(await dialog(page).innerText(), /· Pack personnalisé — source locale\. .*La configuration par défaut du pack choisi sera adoptée par cette installation\./s);
      await closeDialog(page, 'cancel');
    } finally { await page.close(); }
  });

  for (const [current, expected] of [['local', 'La configuration par défaut de cette installation est conservée.'], ['missing', null]]) {
    await check(`Installation d’un pack sans configuration, défaut ${current} : ${expected ? 'conservation annoncée' : 'aucune promesse'}`, async () => {
      const page = await makePage();
      try {
        await page.evaluate((state) => { window.fixture.installationDefault = state; },
          current === 'local' ? localDefault : { state: 'missing', path: DEFAULT_PATH, version: null, fingerprint: null, sha256: null });
        await click(page, 'zip'); await page.locator('[data-candidate]').waitFor();
        await page.locator('[data-candidate]').click(); await page.locator('[data-install]').waitFor();
        await page.locator('[data-install]').click(); await dialog(page).waitFor();
        const text = await dialog(page).innerText();
        assert.equal(text.includes('La configuration par défaut de cette installation est conservée.'), expected !== null, text);
        assert.doesNotMatch(text, /sera adoptée/);
        await closeDialog(page, 'cancel');
      } finally { await page.close(); }
    });
  }

  const KEPT = 'La configuration par défaut de cette installation est conservée.';
  const SET_ASIDE = 'La version rétablie ne connaît pas la configuration par défaut de l’installation : elle sera mise de côté dans le dossier de la transaction.';
  const WITHDRAWN = 'La configuration par défaut apportée par la mise à jour, inchangée depuis, est retirée avec elle : la version rétablie retrouve son état d’avant la mise à jour.';
  const DELETED = 'La configuration par défaut supprimée depuis la mise à jour le reste.';
  const FATES = { kept: KEPT, setAside: SET_ASIDE, withdrawn: WITHDRAWN, deleted: DELETED };
  for (const fate of ['kept', 'setAside', 'withdrawn', 'deleted', null]) {
    await check(`Retour arrière, sort du défaut ${fate ?? 'non annoncé'} : la confirmation dit exactement ce que fera le moteur`, async () => {
      const page = await makePage();
      try {
        await page.evaluate((fate) => { window.fixture.rollbackDefaults = fate; }, fate);
        await click(page, 'rollback'); await dialog(page).waitFor();
        const text = await dialog(page).locator('.k-dlg-text').innerText();
        assert.ok(text.startsWith('Pesto va fermer les fenêtres et restaurer les anciens fichiers. Votre configuration actuelle sera conservée.'), text);
        for (const [name, sentence] of Object.entries(FATES)) assert.equal(text.includes(sentence), name === fate, `${sentence} : ${text}`);
        assert.match(text, /Le démarrage restauré sera contrôlé séparément\.$/);
        await closeDialog(page, 'cancel');
        assert.equal((await calls(page, 'updates.rollback')).length, 0);
      } finally { await page.close(); }
    });
  }

  await check('Rollback annulé puis confirmé : aucun envoi implicite et fermeture terminale', async () => {
    const page = await makePage();
    try {
      await click(page, 'rollback'); await dialog(page).waitFor();
      assert.equal((await calls(page, 'updates.rollback')).length, 0); await closeDialog(page, 'cancel');
      assert.equal((await calls(page, 'updates.rollback')).length, 0);
      await click(page, 'rollback'); await dialog(page).waitFor(); await closeDialog(page, 'ok');
      await waitCall(page, 'updates.rollback');
      assert.deepEqual((await calls(page, 'updates.rollback'))[0].args, { confirmed: true });
      assert.equal(await page.locator('[data-maint]:enabled').count(), 0);
      assert.equal((await calls(page, 'updates.recover')).length, 0);
    } finally { await page.close(); }
  });

  for (const fate of ['kept', 'setAside', 'withdrawn', null]) {
    await check(`Reprise interrompue, sort du défaut ${fate ?? 'non annoncé'} : la confirmation dit exactement ce que fera le moteur`, async () => {
      const page = await makePage();
      try {
        await page.evaluate((fate) => Object.assign(window.fixture, { pendingRecovery: true, recoveryDefaults: fate, rollbackDefaults: 'deleted' }), fate);
        await click(page, 'status'); await dialog(page).waitFor();
        const text = await dialog(page).locator('.k-dlg-text').innerText();
        for (const [name, sentence] of Object.entries(FATES)) assert.equal(text.includes(sentence), name === fate, `${sentence} : ${text}`);
        await closeDialog(page, 'cancel');
        assert.equal((await calls(page, 'updates.recover')).length, 0);
      } finally { await page.close(); }
    });
  }

  await check('Reprise interrompue annulée puis confirmée : fermeture sans rejeu d’installation', async () => {
    const page = await makePage();
    try {
      await page.evaluate(() => { window.fixture.pendingRecovery = true; });
      await click(page, 'status'); await dialog(page).waitFor();
      assert.equal((await calls(page, 'updates.recover')).length, 0); await closeDialog(page, 'cancel');
      assert.equal((await calls(page, 'updates.recover')).length, 0);
      await click(page, 'status'); await dialog(page).waitFor(); await closeDialog(page, 'ok');
      await waitCall(page, 'updates.recover');
      assert.deepEqual((await calls(page, 'updates.recover'))[0].args, { confirmed: true });
      assert.equal(await page.locator('[data-maint]:enabled').count(), 0);
      assert.equal((await calls(page, 'updates.install')).length, 0);
      assert.equal((await calls(page, 'updates.rollback')).length, 0);
    } finally { await page.close(); }
  });

  await check('Échec d’application : message de refus, aucun faux succès ni relance automatique', async () => {
    const page = await makePage();
    try {
      await page.evaluate(() => { window.fixture.fail = 'configuration.applyImport'; });
      await click(page, 'import'); await dialog(page).waitFor(); await closeDialog(page, 'apply');
      await waitCall(page, 'configuration.applyImport');
      await page.waitForFunction(() => document.querySelector('.toasts').textContent.includes('Refus contrôlé'));
      assert.equal((await calls(page, 'configuration.applyImport')).length, 1);
      assert.doesNotMatch(await page.locator('.toasts').innerText(), /Configuration appliquée|Configuration remplacée/);
    } finally { await page.close(); }
  });

  await check('Retour avec autre fenêtre fermable : la confirmation la nomme et transmet le jeton', async () => {
    const page = await makePage();
    try {
      await page.evaluate(() => { window.fixture.packWindows = { windows: [{ id: '1-100', label: 'Fenêtre de paramètres', closable: true, reason: null }], token: 'token-fermeture' }; });
      await click(page, 'rollback');
      await dialog(page).waitFor();
      assert.match(await dialog(page).innerText(), /Fenêtre de paramètres/);
      await closeDialog(page, 'ok');
      await waitCall(page, 'updates.rollback');
      assert.deepEqual((await calls(page, 'updates.rollback'))[0].args, { confirmed: true, closeWindows: 'token-fermeture' });
    } finally { await page.close(); }
  });

  await check('Retour avec fenêtre bloquée : aucune boîte de confirmation ni rollback, message visible', async () => {
    const page = await makePage();
    try {
      await page.evaluate(() => { window.fixture.packWindows = { windows: [{ id: '2-200', label: 'Fenêtre bloquée', closable: false, reason: 'ouverte dans une autre session Windows' }], token: 'ignored' }; });
      await click(page, 'rollback');
      await page.waitForFunction(() => document.querySelector('.toasts').textContent.includes('ne peut pas fermer'));
      assert.equal((await calls(page, 'updates.rollback')).length, 0);
      assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
    } finally { await page.close(); }
  });

  await check('Retour sans sauvegarde ou source vide : le motif est affiché, pas une erreur interne', async () => {
    const page = await makePage();
    try {
      await page.evaluate(() => { window.fixture.canRollback = false; });
      await click(page, 'rollback');
      await page.waitForFunction(() => document.querySelector('.toasts').textContent.includes('Aucune sauvegarde de mise à jour terminée'));
      assert.equal((await calls(page, 'updates.windows')).length, 0);
      assert.equal((await calls(page, 'updates.rollback')).length, 0);
      await click(page, 'source');
      await page.waitForFunction(() => document.querySelector('.toasts').textContent.includes('Indiquez un chemin de dossier'));
      assert.doesNotMatch(await page.locator('.toasts').innerText(), /Erreur interne/);
    } finally { await page.close(); }
  });

  await check('Installation avec autre fenêtre fermable : la confirmation la nomme et transmet le jeton', async () => {
    const page = await makePage();
    try {
      await click(page, 'zip');
      await page.locator('[data-candidate]').click();
      await page.locator('[data-install]').waitFor();
      await page.evaluate(() => { window.fixture.packWindows = { windows: [{ id: '3-300', label: 'Fenêtre d’installation', closable: true, reason: null }], token: 'token-install' }; });
      await page.locator('[data-install]').click();
      await dialog(page).waitFor();
      assert.match(await dialog(page).innerText(), /Fenêtre d’installation/);
      await closeDialog(page, 'ok');
      await waitCall(page, 'updates.install');
      assert.deepEqual((await calls(page, 'updates.install'))[0].args, { preparedId: 'prepared-zip-candidate', confirmed: true, closeWindows: 'token-install' });
    } finally { await page.close(); }
  });

  await check('Installation avec fenêtre bloquée : aucune boîte de confirmation ni installation, message visible', async () => {
    const page = await makePage();
    try {
      await click(page, 'zip');
      await page.locator('[data-candidate]').click();
      await page.locator('[data-install]').waitFor();
      await page.evaluate(() => { window.fixture.packWindows = { windows: [{ id: '4-400', label: 'Fenêtre bloquée', closable: false, reason: 'sans fenêtre : commande en ligne ou démarrage en cours' }], token: 'ignored' }; });
      await page.locator('[data-install]').click();
      await page.waitForFunction(() => document.querySelector('.toasts').textContent.includes('ne peut pas fermer'));
      assert.equal((await calls(page, 'updates.install')).length, 0);
      assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
    } finally { await page.close(); }
  });

  await check('Démonstration : configuration par défaut inaccessible, refus isolé même en appel direct', async () => {
    // No native fixture: the browser runs the in-memory demonstration, as the separate demo window does.
    const page = await browser.newPage({ viewport: { width: 1500, height: 1100 } });
    page.setDefaultTimeout(6000);
    page.on('pageerror', (error) => errors.push(error.message));
    page.on('console', (message) => { if (message.type() === 'error' && !message.text().includes('net::ERR_NO_BUFFER_SPACE')) errors.push(message.text()); });
    await page.route('**/*', async (route) => {
      if (route.request().url().startsWith(origin + '/')) await route.continue();
      else { errors.push('Unexpected external request: ' + route.request().url()); await route.abort(); }
    });
    try {
      await page.addInitScript(() => localStorage.setItem('pesto.prefs.v1', JSON.stringify({ theme: 'light', motion: 'reduced' })));
      await page.goto(origin + '/#/parametres');
      await page.waitForFunction(() => document.documentElement.dataset.ready === 'parametres');
      const button = page.locator('[data-maint="default"]');
      assert.equal(await button.isDisabled(), true);
      assert.equal(await page.locator('[data-maint-status="configuration"]').innerText(), 'Disponible dans la fenêtre normale. La démonstration ne lit ni fichier réel ni partage réseau.');
      await button.dispatchEvent('click');
      assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
      assert.doesNotMatch(await page.locator('[data-maint-status="configuration"]').innerText(), /Écriture|enregistrée/);
      const codes = await page.evaluate(async () => {
        const { browserSimulation } = await import('/js/simulation.js');
        const codes = [];
        for (const [op, args] of [['configuration.status', {}], ['configuration.setDefault', { expectedSha256: 'a'.repeat(64), confirmed: true }],
          ['configuration.setDefault', { version: 'demo.1', expectedSha256: '', confirmed: true }]]) {
          try { await browserSimulation.invoke(op, args); codes.push('accepted'); } catch (error) { codes.push(error.code); }
        }
        return codes;
      });
      assert.deepEqual(codes, ['demo.isolated', 'demo.isolated', 'demo.isolated']);
    } finally { await page.close(); }
  });

  // ----- 2.0.15 : rail de sections. Une section visible à la fois, adresse #/parametres?section=…, toutes montées une fois. -----
  const SETTING_NAMES = ['domain', 'dc', 'prefix', 'namingPattern', 'rootOu', 'preprodOu', 'preprodSite', 'production', 'randomNames',
    'coordinationRoot', 'coordinationRequired', 'reserveNamesInAd', 'allowPrecreatedJoin', 'allowOfflineJoin', 'unattendedJoinEnabled',
    'unattendedOperationsEnabled', 'entraPolicy', 'auditEventLogEnabled', 'blockJoinOnClockSkew', 'excludedGroupGuids',
    'sites', 'interfaceMotion', 'configurationVersion', 'updateSource'];
  const activeName = (page) => page.evaluate(() => document.activeElement?.getAttribute('name') ?? null);
  const engineCalls = (page) => page.evaluate(() => window.fixture.calls.length);

  await check('Rail réel : cinq sections dans l’ordre, Annuaire par défaut et adresse nue', async () => {
    const page = await makePage();
    try {
      assert.deepEqual(await page.locator('main .pr-nav-item').evaluateAll((nodes) => nodes.map((node) => node.dataset.section)),
        ['annuaire', 'politiques', 'configuration', 'mises-a-jour', 'interface']);
      assert.deepEqual(await page.locator('main .pr-nav-item[aria-current="true"]').evaluateAll((nodes) => nodes.map((node) => node.dataset.section)), ['annuaire']);
      assert.equal(await page.locator('main .pr-nav-item[aria-current="false"]').count(), 4);
      assert.equal(await page.locator('main .nav-item, main .nav-pill, main [aria-current="page"]').count(), 0);
      assert.deepEqual(await shownSections(page), ['annuaire']);
      assert.equal(await hash(page), '#/parametres');
      assert.equal(await page.locator('main [data-pulse="politiques"]').count(), 1);
      assert.equal(await page.locator('main [data-pulse="demonstration"]').count(), 0);
      // Hidden sections stay mounted: every field exists once, as the native benches and the demonstration snapshot read them.
      for (const name of SETTING_NAMES) assert.equal(await page.locator(`main [name="${name}"]`).count(), 1, name);
      assert.equal(await page.locator('main form[data-form="settings"].k-form-live').count(), 1);
      assert.equal(await page.locator('main h1').count(), 1);
    } finally { await page.close(); }
  });

  await check('Changement de section : même montage, aucun appel moteur, brouillon conservé', async () => {
    const page = await makePage();
    try {
      await page.evaluate(() => { document.querySelector('main').firstElementChild.__mark = 1; });
      await page.locator('[name="prefix"]').fill('222222');
      await frames(page);
      const before = await engineCalls(page);
      await openSection(page, 'politiques');
      assert.equal(await hash(page), '#/parametres?section=politiques');
      await page.locator('[name="reserveNamesInAd"]').check();
      await openSection(page, 'configuration');
      await frames(page);
      assert.equal(await page.evaluate(() => document.querySelector('main').firstElementChild.__mark), 1);
      assert.equal(await engineCalls(page), before);
      assert.equal(await page.locator('[name="prefix"]').inputValue(), '222222');
      assert.equal(await hash(page), '#/parametres?section=configuration');
      assert.deepEqual(await shownSections(page), ['configuration']);
      assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
      // One draft for every section: the rail and the Brouillon tile show it whatever the section shown.
      for (const id of ['annuaire', 'politiques']) {
        assert.equal(await page.locator(`main [data-badge="${id}"]`).isVisible(), true, id);
        assert.equal(await page.locator(`main [data-badge="${id}"] .visually-hidden`).textContent(), 'modifications non enregistrées');
      }
      assert.equal(await page.locator('main [data-pulse="brouillon"] .pr-pulse-v').innerText(), 'Modifié');
      await openSection(page, 'annuaire');
      assert.equal(await hash(page), '#/parametres');
      assert.equal(await engineCalls(page), before);
      // Saving from another section sends the whole draft, Annuaire and Politiques together.
      await openSection(page, 'interface');
      await page.locator('[data-act="save"]').click(); await dialog(page).waitFor();
      const sent = (await calls(page, 'configuration.previewSettings'))[0].args;
      assert.equal(sent.prefix, '222222'); assert.equal(sent.reserveNamesInAd, true);
      await closeDialog(page, 'cancel');
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
    } finally { await page.close(); }
  });

  await check('Réponse tardive puis changement de section : dialogue ouvert, statut final, jamais « … »', async () => {
    const page = await makePage();
    try {
      await page.evaluate(() => { window.fixture.hold = 'configuration.status'; });
      await click(page, 'default');
      await page.waitForFunction(() => window.fixture.releases.length === 1);
      await openSection(page, 'mises-a-jour'); await openSection(page, 'configuration');
      await release(page);
      await dialog(page).waitFor();
      assert.equal(await dialog(page).locator('h2').innerText(), 'Définir comme configuration par défaut');
      await closeDialog(page, 'cancel');
      assert.doesNotMatch(await configurationStatus(page), /…$/);
      assert.equal((await calls(page, 'configuration.setDefault')).length, 0);
      // The write itself, answered after two changes of section, ends with its exact result.
      await page.evaluate(() => { window.fixture.hold = 'configuration.setDefault'; });
      await click(page, 'default'); await dialog(page).waitFor(); await closeDialog(page, 'ok');
      await page.waitForFunction(() => window.fixture.releases.length === 1);
      assert.equal(await configurationStatus(page), 'Écriture de la configuration par défaut…');
      await openSection(page, 'interface'); await openSection(page, 'configuration');
      await release(page);
      const expected = `Configuration par défaut enregistrée dans cette installation : ${DEFAULT_PATH} (version 20261112-101500).`;
      await page.waitForFunction((text) => document.querySelector('[data-maint-status="configuration"]').textContent === text, expected);
      await page.waitForFunction(() => document.querySelector('.toasts').textContent.includes('Configuration par défaut enregistrée.'));
      assert.equal((await calls(page, 'configuration.setDefault')).length, 1);
      await page.waitForFunction(() => !document.querySelector('[data-maint="default"]').disabled);
    } finally { await page.close(); }
  });

  await check('Réponse tardive après changement de section puis départ : aucun dialogue ni écriture', async () => {
    for (const operation of ['configuration.status', 'updates.status']) {
      const page = await makePage({ local: true });
      try {
        await page.evaluate((op) => { Object.assign(window.fixture, { hold: op, pendingRecovery: true }); }, operation);
        await click(page, operation === 'updates.status' ? 'rollback' : 'default');
        await page.waitForFunction(() => window.fixture.releases.length === 1);
        await openSection(page, 'interface');
        assert.equal(await hash(page), '#/parametres?section=interface');
        await leaveSettings(page); await release(page);
        assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
        for (const op of ['configuration.setDefault', 'updates.rollback', 'updates.windows']) assert.equal((await calls(page, op)).length, 0, op);
      } finally { await page.close(); }
    }
  });

  await check('Résultat reçu dans une section masquée : pastille « nouveau résultat » jusqu’à l’ouverture de la section', async () => {
    const page = await makePage();
    try {
      const badge = page.locator('main [data-badge="configuration"]');
      const expected = 'Configuration par défaut déjà identique (version entreprise.2) : aucun fichier modifié.';
      await page.evaluate((state) => { Object.assign(window.fixture, { installationDefault: state, defaultUnchanged: true, hold: 'configuration.setDefault' }); }, localDefault);
      await click(page, 'default'); await dialog(page).waitFor(); await closeDialog(page, 'ok');
      await page.waitForFunction(() => window.fixture.releases.length === 1);
      await frames(page);
      // « Écriture… » is written while Configuration is shown: nothing to mark.
      assert.equal(await badge.isHidden(), true);
      await openSection(page, 'interface');
      await release(page);
      await page.waitForFunction((text) => document.querySelector('[data-maint-status="configuration"]').textContent === text, expected);
      await frames(page);
      // No toast for this outcome: the rail says a result is waiting in Configuration.
      assert.equal(await page.locator('[data-maint-status="configuration"]').isVisible(), false);
      assert.equal(await badge.isVisible(), true);
      assert.equal(await badge.locator('.visually-hidden').textContent(), 'nouveau résultat');
      assert.match(await page.locator('main .pr-nav-item[data-section="configuration"]').textContent(), /nouveau résultat/);
      assert.equal(await page.locator('main [data-badge="mises-a-jour"]').isHidden(), true);
      await openSection(page, 'configuration');
      await frames(page);
      assert.equal(await badge.isHidden(), true);
      assert.equal(await configurationStatus(page), expected);
      // A result read in its own section leaves no mark behind.
      await click(page, 'default'); await dialog(page).waitFor(); await closeDialog(page, 'ok');
      await waitCall(page, 'configuration.setDefault', 2);
      await page.waitForFunction(() => !document.querySelector('[data-maint="default"]').disabled);
      await frames(page);
      assert.equal(await badge.isHidden(), true);
      assert.equal(await hash(page), '#/parametres?section=configuration');
    } finally { await page.close(); }
  });

  await check('Relecture lente puis changement de section : la réponse relue est affichée', async () => {
    const page = await makePage();
    try {
      // The held answer is the profile as it is when read: another prefix and one more policy switched on.
      await page.evaluate(() => { Object.assign(window.fixture, { hold: 'configuration.settings', settings: { ...window.fixture.settings, prefix: '222222', reserveNamesInAd: true } }); });
      await page.locator('[data-act="reload"]').click();
      await page.waitForFunction(() => window.fixture.releases.length === 1);
      await openSection(page, 'politiques');
      assert.equal(await page.locator('[name="prefix"]').inputValue(), '111301');
      await release(page);
      await page.waitForFunction(() => document.querySelector('[name="prefix"]').value === '222222');
      assert.equal(await page.locator('[name="reserveNamesInAd"]').isChecked(), true);
      assert.equal(await page.locator('[data-settings-status]').innerText(), 'Paramètres relus.');
      assert.equal(await page.locator('main [data-pulse="nommage"] .pr-pulse-v').innerText(), '222222');
      assert.equal(await page.locator('main [data-pulse="politiques"] .pr-pulse-v').innerText(), '1 sur 8');
      assert.deepEqual(await shownSections(page), ['politiques']);
    } finally { await page.close(); }
  });

  await check('Validation : un champ requis vidé puis section quittée rouvre Annuaire et le focalise', async () => {
    const page = await makePage();
    try {
      await page.locator('[name="domain"]').fill('');
      await openSection(page, 'configuration');
      await page.locator('[data-act="save"]').click();
      await page.locator('main [data-section-panel="annuaire"]:not([hidden])').waitFor();
      assert.deepEqual(await shownSections(page), ['annuaire']);
      assert.equal(await hash(page), '#/parametres');
      assert.equal(await activeName(page), 'domain');
      assert.equal(await page.locator('[name="domain"]').getAttribute('aria-invalid'), 'true');
      // The kit says it once; opening the section says nothing more (quiet).
      assert.deepEqual(await page.locator('.live-assertive p').evaluateAll((nodes) => nodes.map((node) => node.textContent).filter((text) => /à corriger/.test(text))), ['1 champ à corriger.']);
      assert.equal(await page.locator('.live-polite p').evaluateAll((nodes) => nodes.filter((node) => node.textContent.startsWith('Section ')).length), 1);
      assert.equal((await calls(page, 'configuration.previewSettings')).length, 0);
      assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
    } finally { await page.close(); }
  });

  await check('GUID refusé : Politiques s’ouvre, champ en erreur et focalisé, aucun aperçu', async () => {
    const page = await makePage();
    try {
      await openSection(page, 'politiques');
      await page.locator('[name="excludedGroupGuids"]').fill('invalide');
      await openSection(page, 'annuaire');
      await page.locator('[data-act="save"]').click();
      await page.locator('main [data-section-panel="politiques"]:not([hidden])').waitFor();
      assert.deepEqual(await shownSections(page), ['politiques']);
      assert.equal(await hash(page), '#/parametres?section=politiques');
      assert.equal(await page.locator('[name="excludedGroupGuids"]').getAttribute('aria-invalid'), 'true');
      assert.equal(await activeName(page), 'excludedGroupGuids');
      assert.match(await page.locator('main [data-section-panel="politiques"]').innerText(), /Saisissez au plus 200 GUID distincts et non nuls, un par ligne\./);
      assert.equal((await calls(page, 'configuration.previewSettings')).length, 0);
    } finally { await page.close(); }
  });

  await check('Sites mal formés depuis une autre section : Annuaire s’ouvre, motif visible et focus sur les sites', async () => {
    const page = await makePage();
    try {
      await page.locator('[name="sites"]').fill('paris;Paris;PA');
      await openSection(page, 'interface');
      await page.locator('[data-act="save"]').click();
      await page.locator('main [data-section-panel="annuaire"]:not([hidden])').waitFor();
      const message = page.locator('[data-slot="sites-msg"]');
      assert.equal(await message.isVisible(), true);
      assert.equal((await message.innerText()).trim(), 'Ligne à quatre champs séparés par « ; » attendue : paris;Paris;PA');
      assert.equal(await activeName(page), 'sites');
      assert.equal(await hash(page), '#/parametres');
      assert.equal((await calls(page, 'configuration.previewSettings')).length, 0);
    } finally { await page.close(); }
  });

  await check('Refus du moteur à l’enregistrement : Annuaire s’ouvre, motif sous les sites, brouillon gardé', async () => {
    const page = await makePage();
    try {
      await openSection(page, 'politiques');
      await page.locator('[name="reserveNamesInAd"]').check();
      await openSection(page, 'mises-a-jour');
      await page.evaluate(() => Object.assign(window.fixture, { fail: 'configuration.previewSettings', failCode: 'config.invalid', failMessage: 'Le moteur refuse ce brouillon : OU hors du domaine.' }));
      await page.locator('[data-act="save"]').click();
      await page.locator('main [data-section-panel="annuaire"]:not([hidden])').waitFor();
      await page.waitForFunction(() => document.querySelector('[data-slot="sites-msg"]').textContent.includes('OU hors du domaine'));
      assert.equal(await page.locator('[data-slot="sites-msg"]').isVisible(), true);
      assert.equal(await hash(page), '#/parametres');
      assert.equal((await calls(page, 'configuration.previewSettings')).length, 1);
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
      assert.equal(await page.locator('[name="reserveNamesInAd"]').isChecked(), true);
      assert.equal(await page.locator('main [data-badge="politiques"]').isVisible(), true);
      assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
    } finally { await page.close(); }
  });

  await check('Garde de sortie avec section dans l’adresse : Annuler garde la section, l’adresse et la saisie', async () => {
    const page = await makePage();
    try {
      await openSection(page, 'politiques');
      await page.locator('[name="reserveNamesInAd"]').check();
      await page.locator('.nav-item[data-id="aide"]').click(); await dialog(page).waitFor();
      assert.equal(await hash(page), '#/parametres?section=politiques');
      assert.match(await dialog(page).innerText(), /modifications non enregistrées/);
      await closeDialog(page, 'cancel');
      assert.equal(await hash(page), '#/parametres?section=politiques');
      assert.equal(await page.locator('main').getAttribute('data-page'), 'parametres');
      assert.equal(await page.locator('[name="reserveNamesInAd"]').isChecked(), true);
      assert.deepEqual(await shownSections(page), ['politiques']);
      // The section still changes after the dialog; leaving asks again and restores nothing behind it.
      await openSection(page, 'configuration');
      assert.equal(await hash(page), '#/parametres?section=configuration');
      await leaveSettings(page, true);
      assert.equal(await hash(page), '#/aide');
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
    } finally { await page.close(); }
  });

  await check('Configuration invalide : alerte, pastille et accès direct à l’import', async () => {
    const page = await makePage({ invalid: true });
    try {
      const alert = page.locator('main [data-configuration-invalid]');
      await alert.waitFor({ state: 'visible' });
      assert.equal(await alert.getAttribute('role'), 'alert');
      assert.match(await alert.innerText(), /^Configuration invalide\s+La configuration existante est invalide ou illisible\./);
      assert.equal(await page.locator('main [data-badge="configuration"]').isVisible(), true);
      assert.equal(await page.locator('main [data-badge="configuration"] .visually-hidden').textContent(), 'configuration invalide');
      assert.equal(await page.locator('main [data-pulse="configuration"] .pr-pulse-v').innerText(), 'Invalide');
      assert.equal(await page.locator('main [data-setting="config-summary"] [data-summary-title]').innerText(), 'Configuration invalide');
      // The default section stays Annuaire, so the address stays stable; the alert shows the way.
      assert.deepEqual(await shownSections(page), ['annuaire']);
      assert.equal(await hash(page), '#/parametres');
      const before = await engineCalls(page);
      await alert.getByRole('button', { name: 'Aller à l’import', exact: true }).click();
      await page.locator('main [data-section-panel="configuration"]:not([hidden])').waitFor();
      assert.equal(await hash(page), '#/parametres?section=configuration');
      assert.equal(await page.evaluate(() => document.activeElement?.dataset.maint ?? null), 'import');
      await frames(page);
      // It shows the action, it never runs it.
      assert.equal(await engineCalls(page), before);
      assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
    } finally { await page.close(); }
  });

  await check('Tuiles : valeurs lues puis « Non lue » si la première lecture échoue', async () => {
    const page = await makePage();
    try {
      const tile = (id) => page.locator(`main [data-pulse="${id}"] .pr-pulse-v`).innerText();
      await page.waitForFunction(() => document.querySelector('main [data-pulse="configuration"] .pr-pulse-v').textContent === 'Valide');
      assert.equal(await tile('nommage'), '111301');
      assert.equal(await tile('politiques'), '0 sur 8');
      assert.equal(await tile('brouillon'), 'Enregistré');
      assert.equal(await page.locator('main [data-fact="domain"]').textContent(), 'example.local');
      assert.equal(await page.locator('main [data-fact="sites"]').textContent(), '1 site');
      assert.equal(await page.locator('main [data-fact="fingerprint"]').textContent(), `${'a'.repeat(12)}…`);
      assert.equal(await page.locator('main [data-fact="fingerprint"]').getAttribute('title'), 'a'.repeat(64));
      assert.equal(await page.locator('main [aria-busy="true"], main .skeleton').count(), 0);
      const before = await engineCalls(page);
      await page.locator('main [data-pulse="politiques"]').click();
      await page.locator('main [data-section-panel="politiques"]:not([hidden])').waitFor();
      assert.equal(await hash(page), '#/parametres?section=politiques');
      assert.equal(await engineCalls(page), before);
    } finally { await page.close(); }
    const failed = await makePage({ failSettings: true });
    try {
      // makePage waited for data-ready: a refused first read never leaves a busy tile behind.
      for (const id of ['configuration', 'nommage', 'politiques', 'brouillon'])
        assert.equal(await failed.locator(`main [data-pulse="${id}"] .pr-pulse-v`).innerText(), 'Non lue', id);
      assert.equal(await failed.locator('main [data-setting="config-summary"] [data-summary-title]').innerText(), 'Non lue');
      assert.match(await failed.locator('main [data-setting="config-summary"] [data-summary-text]').innerText(), /Lecture refusée/);
      assert.equal(await failed.locator('main [aria-busy="true"], main .skeleton').count(), 0);
      assert.equal(await failed.locator('[data-act="save"]').isDisabled(), true);
      assert.equal((await calls(failed, 'configuration.previewSettings')).length, 0);
    } finally { await failed.close(); }
  });

  await check('Adresse ouvrir= d’une action : section ouverte, bouton éclairé et focalisé, aucune action lancée', async () => {
    const page = await makePage({ address: '#/parametres?ouvrir=export' });
    try {
      assert.deepEqual(await shownSections(page), ['configuration']);
      assert.equal(await hash(page), '#/parametres?section=configuration');
      assert.equal(await page.evaluate(() => document.activeElement?.dataset.maint ?? null), 'export');
      const lit = await page.evaluate(() => window.flashed);
      assert.equal(lit.length, 1); assert.ok(lit[0].includes('export'), JSON.stringify(lit));
      assert.equal(await page.locator('[data-maint="export"]').isEnabled(), true);
      await frames(page);
      // Only the read of the mount: no export, no dialog.
      assert.deepEqual((await page.evaluate(() => window.fixture.calls.map((call) => call.op))).filter((op) => !['session.info', 'configuration.status', 'configuration.settings', 'coordination.status'].includes(op)), []);
      assert.equal(await page.locator('.k-dlg-layer:not(.leaving)').count(), 0);
    } finally { await page.close(); }
  });

  await check('Configuration locale : maintenance utilisable après changement de section', async () => {
    const page = await makePage({ local: true });
    try {
      await openSection(page, 'interface'); await openSection(page, 'politiques');
      await click(page, 'export'); await waitCall(page, 'configuration.export');
      await page.waitForFunction(() => document.querySelector('[data-maint-status="configuration"]').textContent === 'Configuration exportée : C:\\Export\\Pesto-configuration.json');
      assert.equal(await hash(page), '#/parametres?section=configuration');
      await click(page, 'zip'); await page.locator('[data-candidate]').waitFor();
      assert.equal(await hash(page), '#/parametres?section=mises-a-jour');
      assert.deepEqual((await calls(page, 'updates.inspect'))[0].args, { kind: 'zip' });
      assert.match(await page.locator('[data-maint-status="updates"]').innerText(), /Source inspectée/);
      assert.equal((await calls(page, 'updates.prepare')).length, 0); assert.equal((await calls(page, 'updates.install')).length, 0);
      assert.equal((await calls(page, 'configuration.applyImport')).length, 0);
    } finally { await page.close(); }
  });

  await check('Aucune erreur de module/console ni requête externe', async () => assert.deepEqual(errors, []));
} finally {
  if (browser) await browser.close();
  await new Promise((done) => server.close(done));
}
console.log(`${checks - failures}/${checks} contrôles maintenance Chromium réussis ; ${failures} échec(s).`);
if (failures || checks === 0) process.exitCode = 1;
