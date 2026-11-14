// Paramètres : lecture (settings.get) et enregistrement (settings.save) auprès du moteur, autorité unique de
// validation. Rien n'est validé « à la légère » ici : le moteur refuse et renvoie une raison, affichée telle quelle.
// Enregistrer invalide aperçus, plans et file (documenté dans BRIDGE.md) : c'est annoncé avant l'envoi. Le mode et
// les écritures réelles ne sont pas modifiables ici (refusés par le moteur), seulement affichés.
// Écran façon Domenia 2 (12/11/2026, 2.0.15) : bandeau d’état, rail de sections, une section visible à la fois, recherche
// « / » et adresse #/parametres?section=… (coque : parametres/shell.js, registre : parametres/sections.js). Toutes les
// sections restent montées : changer de section ne touche ni le brouillon, unique, ni le moteur.
import { openDemonstration } from '../demo.js';
import { state, setPrefs, on } from '../shell/store.js';
import { icon } from '../icons.js';
import { esc, applyVars, reveal, errorText, announce, toast } from '../ui.js';
import { field, createForm, pill, confirmDialog, count, focusables } from '../kit/index.js';
import { maintenanceMarkup, mountMaintenance } from './maintenance.js';
import { confirmConfiguration } from '../configuration-notice.js';
import { coordinationMarkup, mountCoordination } from './coordination-panel.js';
import { shellMarkup, mountShell } from './parametres/shell.js';

const LEAD = 'Annuaire, politiques, configuration à partager, mises à jour et interface, une section à la fois. Le moteur valide chaque champ ; aucune écriture AD.';
// Section of each maintenance card of maintenance.js; a card added later falls in Configuration.
const MAINTENANCE_HOME = { configuration: 'configuration', references: 'configuration', updates: 'mises-a-jour' };
// Switches counted by the Politiques tile (options of the operation policies that are on).
const POLICY_SWITCHES = ['coordinationRequired', 'reserveNamesInAd', 'auditEventLogEnabled', 'blockJoinOnClockSkew', 'allowPrecreatedJoin', 'allowOfflineJoin', 'unattendedJoinEnabled', 'unattendedOperationsEnabled'];
const DRAFT_BADGE = { mark: '•', label: 'modifications non enregistrées', tone: 'accent' };
const INVALID_BADGE = { mark: '!', label: 'configuration invalide', tone: 'alert' };
// A result written while its section is hidden (an action answered after the operator opened another section) is marked
// on the rail until that section is shown again: never a silent outcome. The texts of maintenance.js are unchanged.
const RESULT_BADGE = { mark: '•', label: 'nouveau résultat', tone: 'warn' };
const VERDICT_ICONS = { ok: 'check', warn: 'alert', alert: 'alert', info: 'info' };
const FINGERPRINT_SHOWN = 12;

function layout(live) {
  const summary = `<section class="card reveal spot" data-config-summary aria-labelledby="pr-config-summary-title">
            <div class="card-head"><span class="card-icon">${icon('eye')}</span><h3 id="pr-config-summary-title">Configuration en vigueur</h3></div>
            <div class="pr-verdict" data-setting="config-summary" data-tone="info">
              <span class="pr-verdict-ico">${icon('info')}</span><b data-summary-title>Lecture…</b><span data-summary-text></span></div>
            <dl class="pr-facts">
              <div class="pr-fact"><dt>Domaine</dt><dd data-fact="domain">—</dd></div>
              <div class="pr-fact"><dt>Préfixe</dt><dd data-fact="prefix">—</dd></div>
              <div class="pr-fact"><dt>Sites</dt><dd data-fact="sites">—</dd></div>
              <div class="pr-fact"><dt>Empreinte</dt><dd class="mono" data-fact="fingerprint">—</dd></div>
            </dl>
          </section>`;
  const panels = {
    annuaire: `<section class="card reveal spot">
            <div class="card-head"><span class="card-icon">${icon('shield')}</span><h3>Annuaire et nommage</h3></div>
            <div class="k-form" data-fields="annuaire"></div>
          </section>
          <section class="card reveal spot">
            <div class="card-head"><span class="card-icon">${icon('server')}</span><h3>Sites</h3>
              <span class="meta">une ligne par site : id, nom, code (2 lettres), OU</span></div>
            <textarea class="input mono" name="sites" rows="6" spellcheck="false" aria-label="Sites, un par ligne : id;nom;code;OU"></textarea>
            <p class="k-hint">Format par ligne : <span class="mono">paris;Paris;PA;OU=Paris,OU=Postes,DC=example,DC=local</span>.
              L’OU doit finir par le DC du domaine.</p>
            <p class="k-hint">Si des sites explicites sont configurés, seules leurs lignes apparaissent ici. Les règles de découverte importées sont conservées lorsque ces lignes restent inchangées ; une configuration mixte se remplace par l’import de configuration.</p>
            <p class="k-msg" data-slot="sites-msg" hidden></p>
          </section>`,
    politiques: live ? `<section class="card reveal spot">
            <div class="card-head"><span class="card-icon">${icon('lock')}</span><h3>Politiques des opérations</h3></div>
            <div class="k-form" data-fields="politiques"></div>
          </section>
          ${coordinationMarkup()}` : '',
    configuration: `<div data-slot="cards">${summary}</div>`,
    'mises-a-jour': '<div data-slot="cards"></div>',
    interface: `<section class="card reveal spot" aria-labelledby="interface-heading">
            <div class="card-head"><span class="card-icon">${icon('sparkles')}</span><h3 id="interface-heading">Interface et démonstration</h3></div>
            <div class="k-form">
              ${field({ name: 'interfaceMotion', label: 'Animations', type: 'select', width: 'half', options: [
                { value: 'full', label: 'Complètes' }, { value: 'reduced', label: 'Réduites' }, { value: 'system', label: 'Suivre Windows' }
              ], hint: 'Appliqué immédiatement et mémorisé pour ce mode.' })}
              <div class="k-field w-half"><span class="k-label">Démonstration</span>
                <div><button class="btn demo-trigger" type="button">${icon('sparkles')}<span>Démonstration</span></button></div>
                <p class="k-hint" data-demo-hint></p>
              </div>
              <p class="k-hint w-full" data-setting="theme">Le thème (clair, sombre, contraste élevé ou suivi de Windows) se choisit dans la barre supérieure.</p>
            </div>
          </section>`,
  };
  const tiles = [
    { id: 'configuration', label: 'Configuration', icon: 'settings', section: 'configuration' },
    { id: 'nommage', label: 'Nommage', icon: 'star', section: 'annuaire' },
    live ? { id: 'politiques', label: 'Politiques', icon: 'lock', section: 'politiques' }
      : { id: 'demonstration', label: 'Démonstration', icon: 'sparkles', section: 'interface' },
    { id: 'brouillon', label: 'Brouillon', icon: 'edit', section: 'annuaire' },
  ];
  return shellMarkup({ live, lead: LEAD, panels, tiles });
}

export function render(main, ctx) {
  const live = ctx.session()?.mode !== 'simulation';
  main.innerHTML = layout(live);
  // The maintenance cards are markup of maintenance.js, unchanged: each one goes to its section, before any wiring.
  const parts = document.createElement('template');
  parts.innerHTML = maintenanceMarkup();
  for (const card of [...parts.content.querySelectorAll('[data-maintenance]')]) {
    main.querySelector(`[data-section-panel="${MAINTENANCE_HOME[card.dataset.maintenance] ?? 'configuration'}"] [data-slot="cards"]`).append(card);
  }
  applyVars(main);
  const stops = [reveal(main)];
  const shell = mountShell(main, ctx, { live });
  stops.push(() => shell.destroy());
  const motion = main.querySelector('[name="interfaceMotion"]');
  const paintMotion = () => { motion.value = state.prefs.motion; };
  paintMotion(); stops.push(on('prefs', paintMotion));
  motion.addEventListener('change', () => { setPrefs({ motion: motion.value }); announce('Préférence d’animations enregistrée.'); });
  const demo = main.querySelector('.demo-trigger');
  const simulation = ctx.session()?.mode === 'simulation';
  demo.setAttribute('aria-label', simulation ? 'Piloter la démonstration' : 'Ouvrir la démonstration');
  demo.querySelector('span').textContent = simulation ? 'Scénarios de démonstration' : 'Ouvrir la démonstration';
  main.querySelector('[data-demo-hint]').textContent = simulation
    ? 'Choisir un scénario, remettre à zéro ou simuler un redémarrage.'
    : 'Une fenêtre indépendante avec des données fictives. Votre session et votre brouillon restent ouverts.';
  demo.addEventListener('click', () => openDemonstration({ call: ctx.call, session: ctx.session,
    changed: async (page) => {
      await ctx.refreshSession?.();
      if (page) ctx.navigate(page); else ctx.navigate('parametres', { section: 'interface' });
    } }));
  let alive = true;
  let loaded = null;
  let loadSequence = 0, saving = false, cleanDraft = null;
  // Changing the section rewrites the address (ctx.replaceParams): the screen stays current until it is left.
  const isActive = () => alive && (ctx.isCurrent ? ctx.isCurrent() : location.hash.split('?')[0] === '#/parametres');
  const coordination = mountCoordination(main, ctx);
  stops.push(() => coordination.dispose());

  const formHost = main.querySelector('[data-form="settings"]');
  formHost.querySelector('[data-fields="annuaire"]').innerHTML = [
    field({ name: 'domain', label: 'Domaine', required: true, mono: true, width: 'half', placeholder: 'example.local', pattern: '[a-z0-9.-]+', patternMessage: 'Nom DNS complet attendu.' }),
    field({ name: 'dc', label: 'Contrôleur (facultatif)', mono: true, width: 'half', placeholder: 'dc01.example.local' }),
    field({ name: 'prefix', label: 'Préfixe de nommage', required: true, mono: true, width: 'third', maxLength: 10, pattern: '[A-Za-z0-9]{1,10}', patternMessage: '1 à 10 caractères alphanumériques.' }),
    field({ name: 'namingPattern', label: 'Convention de nommage', required: true, mono: true, width: 'full', value: '{type}{prefix}{site}{service}{number:3}', hint: 'type, prefix, site, service et number:1 à 6, une fois chacun ; site:1 à 4 et service:1 à 6 sont configurables. Les paramètres réels sont enregistrés dans votre profil Windows, avec sauvegarde atomique.' }),
    ...(live ? [field({ name: 'rootOu', label: 'OU racine du parc géré', required: true, mono: true, width: 'full', placeholder: 'OU=Postes,DC=example,DC=local' }),
      field({ name: 'preprodOu', label: 'OU de préproduction', mono: true, width: 'half', hint: 'Obligatoire si l’environnement de production est désactivé.' }),
      field({ name: 'preprodSite', label: 'Code de service de préproduction', mono: true, width: 'half', maxLength: 6 })] : []),
    field({ name: 'production', label: 'Environnement de production', type: 'switch', width: 'half' }),
    field({ name: 'randomNames', label: 'Tirer un nom au hasard parmi les libres', type: 'switch', width: 'half' }),
  ].join('');
  if (live) {
    formHost.querySelector('[data-fields="politiques"]').innerHTML = [
      field({ name: 'coordinationRoot', label: 'Dossier de coordination partagé', mono: true, width: 'full', maxLength: 240, hint: 'Dossier local ou UNC approuvé. Testez ou préparez explicitement ce dossier après enregistrement ; aucun partage ni droit d’accès n’est créé automatiquement.' }),
      field({ name: 'coordinationRequired', label: 'Exiger la coordination partagée', type: 'switch', width: 'half', hint: 'Un dossier doit être renseigné. Dès qu’un dossier est configuré, son indisponibilité bloque les opérations concernées.' }),
      field({ name: 'reserveNamesInAd', label: 'Réserver le nom dans AD lors de la jonction', type: 'switch', width: 'half', hint: 'Le compte est créé uniquement après confirmation du plan. En cas d’interruption, la réservation est conservée pour inspection et décision explicites.' }),
      field({ name: 'allowPrecreatedJoin', label: 'Autoriser un compte ordinateur précréé', type: 'switch', width: 'half', hint: 'Choix explicite dans Ajouter ce PC, avec nom, GUID et OU relus. Aucun propriétaire ni droit AD n’est modifié ; les règles Windows de réutilisation du compte restent applicables.' }),
      field({ name: 'allowOfflineJoin', label: 'Autoriser la jonction hors ligne locale', type: 'switch', width: 'half', hint: 'Blob provisionné pour le nom actuel du PC en workgroup. Import local, confirmation séparée, preuve après redémarrage ; aucun rejeu du blob.' }),
      field({ name: 'unattendedJoinEnabled', label: 'Autoriser la jonction par CLI', type: 'switch', width: 'half', hint: 'Le lancement explicite --execute avec plan préparé et clé idempotente reste obligatoire. Aucun redémarrage automatique.' }),
      field({ name: 'unattendedOperationsEnabled', label: 'Autoriser renommage et déplacement par CLI', type: 'switch', width: 'half', hint: 'Plans liés aux identités, à la configuration et au profil. Les restrictions HKLM et accords de campagne restent applicables.' }),
      field({ name: 'entraPolicy', label: 'Retrait Entra avant un renommage hybride', type: 'select', width: 'half', options: [{ value: 'Disabled', label: 'Désactivé — refuser le poste hybride' }, { value: 'HybridOnly', label: 'Autoriser après confirmation explicite' }], hint: 'Le plan doit prouver l’état hybride, annoncer le retrait et demander votre accord. La réinscription hybride reste à vérifier séparément. Aucun retrait lors de l’enregistrement.' }),
      field({ name: 'auditEventLogEnabled', label: 'Exporter l’audit dans le journal Windows', type: 'switch', width: 'half', hint: 'La source Pesto du journal Application doit être préparée par l’administrateur. Un échec d’export est signalé ; les reçus durables restent la preuve de l’opération.' }),
      field({ name: 'blockJoinOnClockSkew', label: 'Contrôler l’écart d’horloge avant la jonction', type: 'switch', width: 'half', hint: 'Bloque un écart mesuré d’au moins cinq minutes. Une mesure indisponible reste un avertissement ; aucune correction d’heure n’est effectuée.' }),
      field({ name: 'excludedGroupGuids', label: 'Groupes AD exclus, identifiants GUID', type: 'textarea', mono: true, width: 'full', maxLength: 8000, hint: 'Un GUID par ligne, 200 au maximum. Les appartenances directes et imbriquées sont contrôlées ; une lecture incomplète refuse l’opération.' }),
    ].join('');
  }
  const form = createForm(formHost);
  const sitesBox = main.querySelector('[name="sites"]');
  const sitesMsg = main.querySelector('[data-slot="sites-msg"]');
  const modeZone = main.querySelector('[data-zone="mode"]');
  const settingsStatus = main.querySelector('[data-settings-status]');
  const saveButton = main.querySelector('[data-act="save"]');
  const reloadButton = main.querySelector('[data-act="reload"]');
  const draft = () => JSON.stringify({ values: form.values(), sites: sitesBox.value });
  // Protect typing that starts before the first settings response as well.
  cleanDraft = draft();
  const dirty = () => cleanDraft !== null && draft() !== cleanDraft;
  if (ctx.guardLeave) stops.push(ctx.guardLeave(async () => !dirty() || await confirmDialog({
    title: 'Quitter les paramètres', message: 'Les modifications non enregistrées de ce formulaire seront abandonnées.',
    confirmLabel: 'Abandonner le brouillon', danger: true,
  })));
  const preserveDraft = () => { settingsStatus.textContent = 'Brouillon conservé : les champs ont été modifiés. Relire permet de reprendre la configuration enregistrée après confirmation.'; };
  function refreshButtons() {
    saveButton.disabled = saving || !loaded || loaded.configurationState === 'invalid';
    reloadButton.disabled = saving;
    saveButton.innerHTML = saving ? 'Préparation ou enregistrement en cours…' : `${icon('check')}Enregistrer`;
  }
  refreshButtons();
  if (live) {
    formHost.querySelector('[name="dc"]').readOnly = true;
    formHost.querySelector('[name="dc"]').placeholder = 'Découvert par Windows lors de la connexion';
  }
  // Every field, the coordination card and the maintenance cards are in place: first section from the address.
  shell.start();

  // ----- State tiles, « Configuration en vigueur » and badges of the rail: what was read (loaded), never a new call -----

  const summaryCard = main.querySelector('[data-config-summary]');
  function paintVerdict(tone, title, text) {
    const verdict = summaryCard.querySelector('.pr-verdict');
    if (verdict.dataset.tone !== tone) { verdict.dataset.tone = tone; applyVars(verdict); }
    verdict.querySelector('.pr-verdict-ico').innerHTML = icon(VERDICT_ICONS[tone] ?? 'info');
    verdict.querySelector('[data-summary-title]').textContent = title;
    verdict.querySelector('[data-summary-text]').textContent = text;
  }
  function paintFact(name, text, title = '') {
    const dd = summaryCard.querySelector(`[data-fact="${name}"]`);
    dd.textContent = text;
    if (title) dd.title = title; else dd.removeAttribute('title');
  }
  // Badges of the sections holding maintenance statuses: « configuration invalide » first, then « nouveau résultat ».
  const unseen = new Set();
  const resultSections = [...new Set(Object.values(MAINTENANCE_HOME))];
  function paintResults() {
    if (!alive) return;
    for (const id of resultSections) {
      const invalid = id === 'configuration' && live && loaded?.configurationState === 'invalid';
      shell.setBadge(id, invalid ? INVALID_BADGE : unseen.has(id) ? RESULT_BADGE : null);
    }
  }
  // err: the first read failed (nothing was read yet); after a failed re-read the last values read stay shown.
  function paintSummary(err = null) {
    const thirdTile = live ? 'politiques' : 'demonstration';
    if (!loaded) {
      const value = err ? 'Non lue' : 'Lecture…';
      const tone = err ? 'warn' : 'info';
      for (const id of ['configuration', 'nommage', thirdTile, 'brouillon']) shell.setTile(id, { value, sub: '', tone });
      paintVerdict(tone, value, err ? errorText(err) : '');
      return;
    }
    const s = loaded;
    const configurationState = s.configurationState ?? 'valid';
    if (!live) {
      shell.setTile('configuration', { value: 'Démonstration', sub: 'Monde fictif', tone: 'info' });
      paintVerdict('info', 'Configuration de démonstration', 'Paramètres du monde fictif en mémoire. Aucun effet réel.');
    } else if (configurationState === 'invalid') {
      shell.setTile('configuration', { value: 'Invalide', sub: 'Import requis', tone: 'alert' });
      paintVerdict('alert', 'Configuration invalide', main.dataset.configurationDiagnostic ?? '');
    } else if (configurationState === 'missing') {
      shell.setTile('configuration', { value: 'Absente', sub: 'À créer ou importer', tone: 'warn' });
      paintVerdict('warn', 'Aucune configuration enregistrée', 'Renseignez l’annuaire et les sites, ou importez une configuration.');
    } else {
      shell.setTile('configuration', { value: 'Valide', sub: 'Profil Windows', tone: 'ok' });
      paintVerdict('ok', 'Configuration valide', 'Paramètres validés par le moteur et enregistrés dans votre profil Windows.');
    }
    shell.setTile('nommage', { value: s.prefix || '—', sub: s.namingPattern || 'Convention non définie', tone: 'info' });
    if (live) shell.setTile('politiques', { value: `${POLICY_SWITCHES.filter((key) => s[key] === true).length} sur ${POLICY_SWITCHES.length}`, sub: 'options activées', tone: 'accent' });
    else shell.setTile('demonstration', { value: 'Active', sub: 'Aucun effet réel', tone: 'info' });
    paintResults();
    paintFact('domain', s.domain || 'Non configuré');
    paintFact('prefix', s.prefix || '—');
    paintFact('sites', count(Array.isArray(s.sites) ? s.sites.length : 0, 'site', 'sites'));
    const fingerprint = typeof s.fingerprint === 'string' ? s.fingerprint : '';
    paintFact('fingerprint', !fingerprint ? 'Aucune'
      : fingerprint.length > FINGERPRINT_SHOWN ? `${fingerprint.slice(0, FINGERPRINT_SHOWN)}…` : fingerprint, fingerprint);
  }

  // Badges « modifications non enregistrées » of Annuaire and Politiques, and the Brouillon tile, from the single draft.
  const panelFields = (id) => [...(main.querySelector(`[data-section-panel="${id}"]`)?.querySelectorAll('.k-field[data-name]') ?? [])]
    .map((box) => box.dataset.name);
  function paintDraft() {
    if (!alive) return;
    const clean = cleanDraft === null ? null : JSON.parse(cleanDraft);
    const values = form.values();
    const changed = clean ? ['annuaire', ...(live ? ['politiques'] : [])].filter((id) =>
      panelFields(id).some((name) => JSON.stringify(values[name]) !== JSON.stringify(clean.values?.[name]))
      || (id === 'annuaire' && sitesBox.value !== clean.sites)) : [];
    shell.setBadge('annuaire', changed.includes('annuaire') ? DRAFT_BADGE : null);
    if (live) shell.setBadge('politiques', changed.includes('politiques') ? DRAFT_BADGE : null);
    if (!loaded) return;
    shell.setTile('brouillon', changed.length
      ? { value: 'Modifié', sub: 'Enregistrer pour appliquer', tone: 'accent', section: changed[0] }
      : { value: 'Enregistré', sub: 'Aucune modification en attente', tone: 'ok', section: 'annuaire' });
  }
  const onDraftInput = (e) => { if (e.target !== sitesBox) paintDraft(); };
  formHost.addEventListener('input', onDraftInput);
  formHost.addEventListener('change', onDraftInput);

  function paintMode(s) {
    if (s.configurationState === 'invalid') {
      modeZone.innerHTML = pill('warn', 'Configuration invalide · aucun paramètre actif', { icon: 'alert' });
      return;
    }
    if (ctx.session()?.configurationOnly) {
      modeZone.innerHTML = pill('accent', 'Configuration locale · annuaire non connecté', { icon: 'settings' });
      return;
    }
    modeZone.innerHTML = [
      s.simulation ? pill('info', 'Simulation', { icon: 'sparkles', tip: 'Le moteur est un monde fictif en mémoire.' }) : pill('ok', 'Annuaire réel', { icon: 'shield' }),
      (!s.simulation && ctx.session()?.readOnly === false) ? pill('warn', 'Actions réelles soumises à confirmation', { icon: 'alert' }) : pill('accent', live ? 'Configuration locale · connexion à vérifier' : 'Aucun effet réel', { icon: 'lock' }),
    ].join('');
  }

  function setSitesError(text, tone = 'error') {
    sitesMsg.hidden = !text;
    sitesMsg.className = `k-msg ${tone}`;
    sitesMsg.innerHTML = text ? `${icon(tone === 'ok' ? 'check' : 'alert')}<span>${esc(text)}</span>` : '';
  }

  function sitesToText(sites) {
    return (sites ?? []).map((s) => `${s.id};${s.name};${s.code};${s.ou}`).join('\n');
  }

  function sitesFromText(text) {
    const items = [];
    for (const line of String(text ?? '').split('\n')) {
      if (!line.trim()) continue;
      const parts = line.split(';');
      if (parts.length !== 4) return { error: `Ligne à quatre champs séparés par « ; » attendue : ${line.trim()}` };
      const [id, name, code, ou] = parts.map((p) => p.trim());
      if (!id || !name || !code || (!ou && !(live && loaded?.sites?.length && loaded.sites.every((s) => !s.ou)))) return { error: `Champ vide sur la ligne : ${line.trim()}` };
      items.push({ id, name, code: code.toUpperCase(), ou });
    }
    if (!items.length && !(live && loaded?.configured && loaded?.sites?.length === 0)) return { error: 'Au moins un site est nécessaire.' };
    return { items };
  }

  async function load({ discard = false } = {}) {
    if (!isActive()) return;
    if (dirty() && !discard) { preserveDraft(); return; }
    const sequence = ++loadSequence, before = draft();
    settingsStatus.textContent = 'Lecture des paramètres…';
    settingsStatus.setAttribute('aria-busy', 'true');
    try {
      const s = live ? await ctx.call('configuration.settings') : await ctx.call('settings.get');
      if (!isActive() || sequence !== loadSequence) return;
      if (draft() !== before) { preserveDraft(); return; }
      const reload = loaded !== null;
      loaded = s;
      const invalid = s.configurationState === 'invalid';
      const diagnostic = invalid ? s.diagnostic || 'La configuration existante est illisible. Utilisez Importer pour préparer un remplacement explicite avec sauvegarde du fichier original.' : '';
      main.dataset.configurationState = s.configurationState ?? 'valid';
      main.dataset.configurationDiagnostic = diagnostic;
      const warning = main.querySelector('[data-configuration-invalid]');
      warning.hidden = !invalid;
      warning.querySelector('[data-configuration-diagnostic]').textContent = diagnostic;
      formHost.querySelectorAll('input,select,textarea').forEach((control) => { control.disabled = invalid; });
      sitesBox.disabled = invalid;
      refreshButtons();
      main.dispatchEvent(new CustomEvent('pesto-configuration-state'));
      formHost.querySelector('[name="domain"]').value = s.domain ?? '';
      formHost.querySelector('[name="dc"]').value = live ? ctx.session()?.dc ?? '' : s.dc ?? '';
      formHost.querySelector('[name="prefix"]').value = s.prefix ?? '';
      formHost.querySelector('[name="namingPattern"]').value = s.namingPattern ?? '';
      formHost.querySelector('[name="production"]').checked = !!s.production;
      formHost.querySelector('[name="randomNames"]').checked = !!s.randomNames;
      if (live) for (const key of ['rootOu', 'preprodOu', 'preprodSite']) formHost.querySelector(`[name="${key}"]`).value = s[key] ?? '';
      if (live) {
        formHost.querySelector('[name="coordinationRoot"]').value = s.coordinationRoot ?? '';
        for (const key of ['coordinationRequired', 'reserveNamesInAd', 'auditEventLogEnabled', 'blockJoinOnClockSkew', 'allowPrecreatedJoin', 'allowOfflineJoin', 'unattendedJoinEnabled', 'unattendedOperationsEnabled'])
          formHost.querySelector(`[name="${key}"]`).checked = s[key] === true;
        formHost.querySelector('[name="entraPolicy"]').value = invalid ? '' : ['Disabled', 'HybridOnly'].includes(s.entraPolicy) ? s.entraPolicy : 'Disabled';
        formHost.querySelector('[name="excludedGroupGuids"]').value = (s.excludedGroupGuids ?? []).join('\n');
      }
      sitesBox.value = sitesToText(s.sites);
      cleanDraft = draft();
      setSitesError(null);
      paintMode(s);
      paintSummary();
      paintDraft();
      if (reload) coordination.refresh();
      announce('Paramètres relus.');
      settingsStatus.textContent = 'Paramètres relus.';
    } catch (err) {
      if (!isActive() || sequence !== loadSequence) return;
      settingsStatus.textContent = errorText(err);
      toast(errorText(err), { tone: 'alert', life: 7000 });
      if (loaded === null) paintSummary(err);
    } finally {
      if (isActive() && sequence === loadSequence) settingsStatus.removeAttribute('aria-busy');
    }
  }

  async function reload() {
    if (saving || !isActive()) return;
    if (dirty() && !await confirmDialog({ title: 'Relire les paramètres enregistrés',
      message: 'Les modifications non enregistrées de ce formulaire seront remplacées par la configuration du profil.',
      confirmLabel: 'Abandonner le brouillon et relire' })) return;
    if (isActive()) await load({ discard: true });
  }

  async function save() {
    if (saving || !isActive()) return;
    if (!loaded) { toast('Paramètres non lus : attendez la lecture en cours ou relisez-les.', { tone: 'warn' }); return; }
    // A read begun before this save must not restore its old snapshot afterwards.
    ++loadSequence;
    settingsStatus.removeAttribute('aria-busy');
    saving = true; refreshButtons();
    try { await saveDraft(); }
    finally { saving = false; if (isActive()) refreshButtons(); }
  }

  async function saveDraft() {
    if (loaded.configurationState === 'invalid') { toast('Importez une configuration valide : le fichier invalide sera conservé jusqu’à votre confirmation, puis sauvegardé.', { tone: 'warn' }); return; }
    const parsed = sitesFromText(sitesBox.value);
    if (parsed.error) {
      // The message sits under the Sites card, often below the fold: show Annuaire, bring it into view and say it once.
      shell.show('annuaire', { quiet: true });
      setSitesError(parsed.error);
      announce(parsed.error, { assertive: true });
      sitesMsg.scrollIntoView({ block: 'nearest' });
      sitesBox.focus({ preventScroll: true });
      return;
    }
    setSitesError(null);
    if (!form.validate()) {
      // validate() focuses the first field in error only when it is shown: its section is opened, then the field focused.
      const bad = formHost.querySelector('.k-field.is-error');
      const id = bad?.closest('[data-section-panel]')?.dataset.sectionPanel;
      if (id && id !== shell.current()) { shell.show(id, { quiet: true }); focusables(bad)[0]?.focus(); }
      return;
    }
    const v = form.values();
    const submitted = draft();
    if (live) {
      const groups = String(v.excludedGroupGuids ?? '').split(/[\s,;]+/).filter(Boolean).map((value) => value.toLowerCase());
      if (groups.length > 200 || groups.some((value) => !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value) || /^0{8}-0{4}-0{4}-0{4}-0{12}$/.test(value))
        || new Set(groups).size !== groups.length) {
        shell.show('politiques', { quiet: true });
        form.setMessage('excludedGroupGuids', 'Saisissez au plus 200 GUID distincts et non nuls, un par ligne.', 'error');
        formHost.querySelector('[name="excludedGroupGuids"]').focus();
        return;
      }
      form.setMessage('excludedGroupGuids', null);
      try {
        const plan = await ctx.call('configuration.previewSettings', {
          domain: v.domain, dc: '', prefix: v.prefix, rootOu: v.rootOu, preprodOu: v.preprodOu || '', preprodSite: v.preprodSite || '',
          namingPattern: v.namingPattern, production: !!v.production, randomNames: !!v.randomNames, sites: parsed.items,
          fingerprint: loaded.fingerprint ?? '',
          coordinationRoot: v.coordinationRoot || '', coordinationRequired: !!v.coordinationRequired,
          reserveNamesInAd: !!v.reserveNamesInAd, auditEventLogEnabled: !!v.auditEventLogEnabled,
          blockJoinOnClockSkew: !!v.blockJoinOnClockSkew, excludedGroupGuids: groups,
          entraPolicy: v.entraPolicy, allowPrecreatedJoin: !!v.allowPrecreatedJoin, allowOfflineJoin: !!v.allowOfflineJoin,
          unattendedJoinEnabled: !!v.unattendedJoinEnabled, unattendedOperationsEnabled: !!v.unattendedOperationsEnabled,
        });
        if (!isActive()) return;
        if (draft() !== submitted) { preserveDraft(); return; }
        if (!await confirmConfiguration(plan, { title: 'Enregistrer les paramètres', confirmLabel: 'Enregistrer dans mon profil',
          isActive: () => isActive() && draft() === submitted })) return;
        const result = await ctx.call('configuration.applyImport', { planId: plan.planId, confirmed: true });
        if (!isActive()) return;
        // Keep the submitted baseline, never bind an unsaved draft to a different concurrent document.
        loaded = { ...loaded, fingerprint: plan.fingerprint };
        cleanDraft = submitted;
        paintDraft();
        await load();
        await ctx.refreshSession?.();
        if (!isActive()) return;
        toast((result.backup ? 'Configuration enregistrée avec sauvegarde.' : 'Configuration enregistrée dans votre profil.')
          + ' Utilisez « Reconnecter Pesto » après la première configuration ou un changement de compte.', { tone: 'ok', life: 9000 });
      } catch (err) { if (isActive()) { shell.show('annuaire', { quiet: true }); setSitesError(errorText(err)); announce(errorText(err), { assertive: true }); sitesMsg.scrollIntoView({ block: 'nearest' }); } }
      return;
    }
    const ok = await confirmDialog({
      title: 'Enregistrer les paramètres',
      message: 'Le moteur valide chaque champ. Les aperçus, plans et la file en cours seront invalidés : les écritures devront être re-préparées et re-confirmées.',
      confirmLabel: 'Enregistrer',
      danger: true,
      icon: 'settings',
    });
    if (!ok || !isActive() || draft() !== submitted) return;
    try {
      const s = await ctx.call('settings.save', {
        domain: v.domain, dc: v.dc || '', prefix: v.prefix, production: !!v.production,
        namingPattern: v.namingPattern, randomNames: !!v.randomNames, sites: parsed.items,
      });
      if (!isActive()) return;
      loaded = s;
      cleanDraft = submitted;
      paintMode(s);
      paintSummary();
      paintDraft();
      toast('Paramètres enregistrés ; aperçus, plans et file invalidés.', { tone: 'ok' });
      announce('Paramètres enregistrés.');
    } catch (err) {
      if (!alive) return;
      shell.show('annuaire', { quiet: true });
      setSitesError(errorText(err));
      announce(`Refus du moteur : ${errorText(err)}`, { assertive: true });
      sitesMsg.scrollIntoView({ block: 'nearest' });
    }
  }

  reloadButton.addEventListener('click', reload);
  main.querySelector('[data-act="save"]').addEventListener('click', save);
  sitesBox.addEventListener('input', () => { setSitesError(null); paintDraft(); });

  ctx.setScreenCommands([
    { id: 'parametres-reload', kind: 'command', label: 'Relire les paramètres', icon: 'refresh', group: 'Paramètres', effect: 'read', available: true, detailText: 'Relit la configuration auprès du moteur.', run: reload },
    { id: 'parametres-save', kind: 'command', label: 'Enregistrer les paramètres', icon: 'check', group: 'Paramètres', effect: 'write', available: true, detailText: 'Valide et enregistre ; invalide aperçus, plans et file.', run: () => save() },
  ]);

  load();
  stops.push(mountMaintenance(main, ctx, load));
  // Statuses of the maintenance cards, observed once their own first texts are written (simulation notice included).
  const statuses = [...main.querySelectorAll('[data-maint-status]')];
  const statusText = new Map(statuses.map((el) => [el, el.textContent]));
  const results = new MutationObserver(() => {
    const now = shell.current();
    let changed = unseen.delete(now);
    for (const el of statuses) {
      if (el.textContent === statusText.get(el)) continue;
      statusText.set(el, el.textContent);
      const id = el.closest('[data-section-panel]')?.dataset.sectionPanel;
      if (id && id !== now && !unseen.has(id)) { unseen.add(id); changed = true; }
    }
    if (changed) paintResults();
  });
  for (const el of statuses) results.observe(el, { childList: true, characterData: true, subtree: true });
  for (const panel of main.querySelectorAll('[data-section-panel]')) results.observe(panel, { attributes: true, attributeFilter: ['hidden'] });
  stops.push(() => results.disconnect());
  window.addEventListener('pesto-configuration-changed', load);
  stops.push(() => window.removeEventListener('pesto-configuration-changed', load));
  return () => { alive = false; form.destroy(); ctx.setScreenCommands([]); stops.forEach((stop) => stop()); };
}
