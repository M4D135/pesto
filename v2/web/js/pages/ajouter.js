// Ajouter ce PC au domaine — jonction locale uniquement (mission Pesto v2). L'identité locale vient des faits lus
// (session.info, diagnostics.read), jamais d'une supposition. Le bouton « Ajouter » reste désactivé tant qu'un nom
// libre ou précréé n'a pas été vérifié par son aperçu dédié ; une lecture incomplète reste « inconnu ». Le circuit
// d'écriture est celui du pont : préparation sans mutation, confirmation du plan affiché, exécution unique, reçu.
// Aucune action de redémarrage ni de retrait Entra n'est demandée ici.
import { icon } from '../icons.js';
import { esc, applyVars, reveal, errorText, announce, toast, formatDateTime } from '../ui.js';
import { refusal } from '../refusal.js';
import { field, createForm, pill, bindCopy } from '../kit/index.js';
import { confirmAndExecute, refusalMarkup, receiptMarkup, receiptFeedback } from '../writeflow.js';
import { reservationMarkup, mountReservations } from './reservation-panel.js';

const joinRequestedText = (receipt) => receipt?.status === 'uncertain'
  ? 'Jonction demandée, résultat incertain : vérifiez l’état dans Interventions avant toute nouvelle demande.'
  : 'Jonction déjà demandée pour ce poste : redémarrez, puis vérifiez dans Interventions.';

const TYPES = [
  { value: 'P', label: 'Portable' },
  { value: 'S', label: 'Fixe' },
  { value: 'V', label: 'Virtuel' },
];

function layout() {
  return `<div class="page">
    <header class="page-header reveal">
      <div class="head-row"><span class="page-icon">${icon('power')}</span>
        <div class="titles"><h1 class="gradient-text">Ajouter ce PC au domaine</h1>
          <p class="subtitle">Jonction locale uniquement : ce poste, jamais un poste distant. Aucun redémarrage implicite.</p></div></div>
    </header>
    <div class="grid">
      <section class="card span-5 reveal spot" data-zone="identity">
        <div class="card-head"><span class="card-icon">${icon('monitor')}</span><h3>Identité locale lue</h3></div>
        <p class="muted">Lecture de la session…</p>
      </section>
      <section class="card span-7 reveal spot" data-zone="join-block" hidden>
        <h3>Jonction indisponible</h3><p role="status" data-join-reason></p>
        <div class="row-actions"><a class="btn" href="#/unposte">Ouvrir Un poste</a>
          <button class="btn" type="button" data-act="reread-membership">Relire la session</button></div>
      </section>
      <section class="card span-7 reveal spot" data-zone="join-controls">
        <div class="card-head"><span class="card-icon">${icon('star')}</span><h3>Nom de jonction vérifié avant activation</h3></div>
        <div data-zone="join-mode"></div>
        <form class="k-form" novalidate data-form="join"></form>
        <form class="k-form" novalidate data-form="precreated" hidden></form>
        <div data-zone="preview" aria-live="polite"><p class="muted">Aucun aperçu calculé : le bouton d’ajout reste désactivé.</p></div>
        <div class="row-actions">
          <button class="btn primary" type="button" data-act="add" disabled>${icon('power')}Ajouter ce PC au domaine</button>
          <span data-slot="add-hint" class="muted small">Calculez d’abord un nom réellement libre.</span>
        </div>
      </section>
    </div>
    <section class="card reveal spot" data-zone="receipt">
      <div class="card-head"><span class="card-icon">${icon('file')}</span><h3>Reçu de la dernière demande</h3></div>
      <p class="muted">Aucune demande envoyée dans cette session.</p>
    </section>
    ${reservationMarkup()}
    <section class="card reveal spot" data-zone="offline-entry" hidden>
      <div class="card-head"><span class="card-icon">${icon('power')}</span><h3>Jonction hors ligne</h3></div>
      <p class="muted">Vous disposez d’un blob provisionné pour le nom actuel de ce PC ? Ouvrez le parcours local séparé ; cette session et ses plans restent conservés.</p>
      <button class="btn" type="button" data-act="offline-open">Ouvrir la jonction hors ligne</button>
      <p class="muted small">Sur un PC isolé, lancez directement Pesto.exe --offline-join. Le démarrage local ne découvre pas de contrôleur AD.</p><p data-offline-status role="status"></p>
    </section>
    <p class="muted small reveal">${icon('shield')} Garde-fous : plan lié à la configuration et à l’aperçu, expiration,
      confirmation exacte, consommation unique, mutations sérialisées. En mode réel le reçu est écrit avant l’envoi et
      relué après ; un résultat incertain n’est jamais rejoué automatiquement.</p>
  </div>`;
}

export function render(main, ctx) {
  main.innerHTML = layout();
  applyVars(main);
  const stops = [reveal(main), mountReservations(main, ctx)];
  let alive = true;
  let preview = null;
  let busy = false;
  let computeToken = 0;
  let lastValues = null;
  let servicesToken = 0;
  let sitesToken = 0;
  let expiryTimer = 0;
  let joinRequested = null;
  let preprodLocked = false;

  const identity = main.querySelector('[data-zone="identity"]');
  const previewZone = main.querySelector('[data-zone="preview"]');
  const receiptZone = main.querySelector('[data-zone="receipt"]');
  const addButton = main.querySelector('[data-act="add"]');
  const addHint = main.querySelector('[data-slot="add-hint"]');
  let cap = ctx.capability('join');
  const precreatedCap = ctx.capability('joinPrecreated');
  const live = ctx.session()?.mode === 'live';
  const membershipReason = () => !live || ctx.session()?.localJoined === false ? null
    : ctx.session()?.localJoined === true
      ? 'Ce PC est déjà membre d’un domaine. Utilisez « Un poste » pour le renommer ou le déplacer.'
      : 'L’appartenance de ce PC à un domaine est inconnue. Relisez la session avant toute jonction.';
  const offlineEntry = main.querySelector('[data-zone="offline-entry"]');
  offlineEntry.hidden = !live;
  offlineEntry.querySelector('[data-act="offline-open"]').addEventListener('click', async event => {
    if (!live || !alive) return; const button = event.currentTarget; button.disabled = true;
    try {
      const opened = await ctx.call('offlineJoin.open');
      if (!alive) return;
      offlineEntry.querySelector('[data-offline-status]').textContent = opened?.opened === true
        ? 'Fenêtre locale ouverte. L’import et l’application y demandent chacun votre confirmation.' : 'Ouverture non confirmée.';
    } catch (error) { if (alive) offlineEntry.querySelector('[data-offline-status]').textContent = errorText(error); }
    finally { if (alive) button.disabled = false; }
  });
  const modeZone = main.querySelector('[data-zone="join-mode"]');
  modeZone.innerHTML = live ? field({ name: 'usePrecreated', label: 'Utiliser un compte ordinateur déjà créé dans AD', type: 'switch', disabled: !precreatedCap.enabled,
    hint: precreatedCap.enabled ? 'Le nom et l’OU du compte seront vérifiés avant activation. Aucun compte ni droit AD ne sera créé ou modifié par cet aperçu.' : precreatedCap.reason || 'La politique de jonction sur compte précréé est désactivée.' }) : '';
  const modeInput = modeZone.querySelector('[name="usePrecreated"]');
  const precreated = () => live && precreatedCap.enabled === true && modeInput?.checked === true;

  function paintIdentity() {
    const s = ctx.session();
    if (!s) { identity.querySelector('p').textContent = 'Session inconnue : le moteur n’a pas encore répondu.'; return; }
    const rows = [
      ['Poste local', s.computer ?? 'inconnu'],
      ['Compte de session', s.account ?? 'inconnu'],
      ['Appartenance locale', s.localJoined === true ? 'Déjà membre d’un domaine' : s.localJoined === false ? 'Hors domaine' : 'Inconnue'],
      ['Domaine configuré', s.domain ?? 'non connecté'],
      ['Contrôleur', s.dc ?? 'inconnu'],
      ['Mode', s.mode === 'simulation' ? 'Simulation (aucun effet réel)' : s.readOnly ? 'Lecture seule' : 'Annuaire réel'],
    ];
    identity.innerHTML = `<div class="card-head"><span class="card-icon">${icon('monitor')}</span><h3>Identité locale lue</h3>
      <span class="meta">${s.mode === 'simulation' ? pill('info', 'Simulation', { icon: 'sparkles' }) : pill(s.localJoined == null ? 'warn' : 'ok', s.localJoined == null ? 'Lecture incomplète' : 'Faits lus', { icon: 'shield' })}</span></div>
      <div class="kv-grid">${rows.map(([k, v]) => `<span class="k">${esc(k)}</span><span class="v mono">${esc(v)}</span>`).join('')}</div>`;
  }

  function setPreview(p) {
    clearTimeout(expiryTimer);
    preview = !membershipReason() && p && p.complete === true && typeof p.name === 'string' && !!p.name && typeof p.previewId === 'string' && !!p.previewId
      && typeof p.ou === 'string' && !!p.ou && Date.parse(p.expiresAt) > Date.now()
      && (precreated() ? p.joinAccountMode === 'precreated' && p.existingAccount === true && p.computer === ctx.session()?.computer
        && typeof p.computerGuid === 'string' && !!p.computerGuid : p.existingAccount !== true) ? p : null;
    updateCommands();
    if (!preview) {
      previewZone.innerHTML = '<p class="muted">Aucun aperçu calculé : le bouton d’ajout reste désactivé.</p>';
      addButton.disabled = true;
      addHint.textContent = joinRequested ? joinRequestedText(joinRequested)
        : precreated() ? 'Vérifiez d’abord le compte AD précréé.' : 'Calculez d’abord un nom réellement libre.';
      return;
    }
    previewZone.innerHTML = `<div class="name-preview">
      <b class="name mono">${esc(preview.name)}</b>
      <div class="kv-grid">
        <span class="k">OU de destination</span><span class="v mono">${esc(preview.ou ?? '—')}</span>
        <span class="k">Source</span><span class="v">${esc(preview.source ?? 'inconnue')}</span>
        ${preview.joinAccountMode === 'precreated' ? `<span class="k">Compte AD</span><span class="v">Précréé · GUID <span class="mono">${esc(preview.computerGuid)}</span></span>` : ''}
        <span class="k">Valide jusqu’à</span><span class="v">${esc(formatDateTime(preview.expiresAt) ?? 'inconnue')}</span>
      </div>
      ${(preview.warnings ?? []).map((warning) => `<p class="muted small">${esc(warning)}</p>`).join('')}
      ${preview.joinAccountMode !== 'precreated' ? `<div class="row-actions"><button class="btn" type="button" data-act="other">${icon('sparkles')}Autre nom</button></div>` : ''}</div>`;
    bindCopy(previewZone);
    previewZone.querySelector('[data-act="other"]')?.addEventListener('click', () => { if (lastValues) compute(lastValues, true); });
    addButton.disabled = !cap.enabled;
    addHint.textContent = cap.enabled ? (preview.joinAccountMode === 'precreated'
      ? `Le compte précréé ${preview.name} et son OU ont été relus par le moteur.` : `Le nom ${preview.name} est confirmé libre par le moteur.`) : cap.reason;
    expiryTimer = setTimeout(() => { if (alive) { computeToken++; setPreview(null); addHint.textContent = 'L’aperçu a expiré : vérifiez de nouveau le nom avant l’ajout.'; } },
      Math.min(2_147_483_647, Math.max(1, Date.parse(preview.expiresAt) - Date.now())));
  }

  const formHost = main.querySelector('[data-form="join"]');
  formHost.innerHTML = [
    field({ name: 'type', label: 'Type de poste', type: 'radio', options: TYPES, value: 'P', required: true, width: 'full' }),
    field({ name: 'site', label: 'Site', type: 'select', options: [], placeholder: 'Chargement des sites…', required: true, width: 'half' }),
    field({ name: 'service', label: 'Service', type: 'text', placeholder: 'Code service (3 caractères)', required: true,
      maxLength: 3, pattern: '[A-Za-z0-9]{3}', patternMessage: 'Saisissez un code service de trois caractères.',
      hint: 'Suggestions AD disponibles ; vous pouvez aussi saisir un nouveau code.', width: 'half' }),
    '<div class="row-actions"><button class="btn" type="submit">' + icon('sparkles') + 'Calculer le nom libre</button></div>',
  ].join('');
  const form = createForm(formHost, { onSubmit: (values) => compute(values, false) });
  const serviceInput = formHost.querySelector('[name="service"]');
  const serviceList = document.createElement('datalist');
  serviceList.id = 'pesto-join-service-suggestions';
  serviceInput.setAttribute('list', serviceList.id);
  serviceInput.insertAdjacentElement('afterend', serviceList);
  serviceInput.addEventListener('input', () => {
    const start = serviceInput.selectionStart, end = serviceInput.selectionEnd;
    const normalized = serviceInput.value.toUpperCase();
    if (normalized !== serviceInput.value) {
      serviceInput.value = normalized;
      serviceInput.setSelectionRange(start, end);
    }
  });
  const precreatedHost = main.querySelector('[data-form="precreated"]');
  precreatedHost.innerHTML = field({ name: 'existingName', label: 'Nom exact du compte AD précréé', required: true, mono: true, maxLength: 15,
    pattern: '[A-Za-z0-9][A-Za-z0-9-]{0,14}', patternMessage: 'Nom Windows de 1 à 15 caractères attendu.',
    hint: 'Saisissez le nom prévu dans AD. Le moteur vérifie la convention, le GUID, l’OU et le périmètre ; Windows décide ensuite si sa réutilisation est autorisée.' })
    + '<div class="row-actions"><button class="btn" type="submit">' + icon('search') + 'Vérifier le compte précréé</button></div>';
  const precreatedForm = createForm(precreatedHost, { onSubmit: computeExisting });
  modeInput?.addEventListener('change', () => {
    computeToken++; lastValues = null; formHost.hidden = precreated(); precreatedHost.hidden = !precreated(); setPreview(null);
  });
  precreatedHost.addEventListener('input', () => { computeToken++; lastValues = null; setPreview(null); });

  // A failed read must not leave « Chargement… » forever: both lists say « Indisponible » and a retry is offered,
  // as on Un poste. The token drops a slower earlier attempt.
  async function loadSites() {
    const token = ++sitesToken;
    servicesToken++;
    formHost.querySelector('[data-zone="sites-retry"]')?.remove();
    formHost.querySelector('[name="site"]').innerHTML = '<option value="">Chargement des sites…</option>';
    serviceList.replaceChildren();
    form.setMessage('site', null);
    form.setMessage('service', null);
    try {
      const { items, locked } = await ctx.call('directory.sites', { purpose: 'join' });
      if (!alive || token !== sitesToken) return;
      const select = formHost.querySelector('[name="site"]');
      preprodLocked = locked === true;
      select.disabled = preprodLocked;
      if (preprodLocked) form.setMessage('site', 'Préproduction : destination imposée par la configuration.', 'info');
      select.innerHTML = (items ?? []).map((s) => `<option value="${esc(s.selector ?? s.id)}">${esc(s.name === s.code || !s.name ? s.code : s.name + ' (' + s.code + ')')}</option>`).join('') || '<option value="">Aucun site trouvé</option>';
      if (!items?.length) {
        form.setMessage('site', 'Aucun site de la configuration n’a été trouvé. Vérifiez les OU dans Paramètres.', 'warn');
        serviceList.replaceChildren();
        return;
      }
      loadServices(true);
    } catch (err) {
      if (!alive || token !== sitesToken) return;
      formHost.querySelector('[name="site"]').innerHTML = '<option value="">Indisponible</option>';
      serviceList.replaceChildren();
      form.setMessage('site', errorText(err), 'error');
      formHost.querySelector('[type="submit"]').parentElement.insertAdjacentHTML('beforebegin',
        '<div class="row-actions" data-zone="sites-retry"><button class="btn" type="button" data-retry-sites>' + icon('refresh') + 'Réessayer le chargement des sites</button></div>');
    }
  }
  formHost.addEventListener('click', (e) => {
    if (!e.target.closest('[data-retry-sites]')) return;
    formHost.querySelector('[name="site"]').focus(); // the button is removed: keep the keyboard focus in the form
    loadSites();
  });

  async function loadServices(calculate = false) {
    const token = ++servicesToken;
    const site = formHost.querySelector('[name="site"]')?.value;
    if (!site) return;
    serviceInput.disabled = preprodLocked;
    form.setMessage('service', null);
    serviceList.replaceChildren();
    try {
      const { items } = await ctx.call('directory.services', { site, purpose: 'join' });
      if (!alive || token !== servicesToken) return;
      serviceInput.disabled = preprodLocked;
      serviceList.innerHTML = (items ?? []).map((s) => `<option value="${esc(s.code)}" label="${esc(s.name === s.code || !s.name ? s.code : s.name + ' (' + s.code + ')')}"></option>`).join('');
      if (!(items ?? []).length) form.setMessage('service', 'Aucun service connu : saisissez le code manuellement.', 'warn');
      if (calculate && serviceInput.value.trim()) await compute(form.values(), false);
    } catch (err) {
      if (!alive || token !== servicesToken) return;
      // Les suggestions ne sont pas une condition de saisie : un code valide reste utilisable.
      form.setMessage('service', 'Suggestions AD indisponibles : vous pouvez saisir le code manuellement.', 'warn');
    }
  }

  formHost.addEventListener('change', (e) => {
    if (!['type', 'site', 'service'].includes(e.target.name)) return;
    computeToken++;
    lastValues = null;
    setPreview(null);
    if (e.target.name === 'site') loadServices(true);
    else if (['type', 'service'].includes(e.target.name) && formHost.querySelector('[name="service"]').value)
      compute(form.values(), false);
  });

  async function compute(values, alternative) {
    if (membershipReason() || joinRequested || precreated() || !form.validate()) return;
    const token = ++computeToken;
    lastValues = { ...values, accountMode: 'new' };
    setPreview(null);
    previewZone.innerHTML = '<p class="muted" aria-busy="true">Recherche d’un nom libre…</p>';
    try {
      const p = await ctx.call('names.preview', {
        purpose: 'join', type: values.type, site: values.site, service: values.service, alternative: alternative || undefined,
      });
      if (!alive || token !== computeToken) return;
      if (p?.complete !== true) {
        previewZone.innerHTML = `<p class="muted" role="status">${icon('alert')} Lecture incomplète : le nom reste inconnu,
          l’ajout n’est pas proposé. Réessayez plus tard ou vérifiez la configuration.</p>`;
        addButton.disabled = true;
        addHint.textContent = 'Aucun nom confirmé libre : ajout désactivé.';
        announce('Lecture incomplète : aucun nom confirmé.', { assertive: true });
        return;
      }
      setPreview(p);
      announce(`Nom libre calculé : ${p.name}.`);
    } catch (err) {
      if (!alive || token !== computeToken) return;
      setPreview(null);
      previewZone.innerHTML = refusalMarkup(err);
    }
  }

  async function computeExisting(values) {
    if (membershipReason() || joinRequested || !precreated() || !precreatedForm.validate()) return;
    const token = ++computeToken;
    const name = String(values.existingName ?? '').trim().toUpperCase();
    lastValues = { accountMode: 'precreated', name };
    setPreview(null);
    previewZone.innerHTML = '<p class="muted" aria-busy="true">Vérification du compte AD précréé et de son OU…</p>';
    try {
      const p = await ctx.call('join.precreated.preview', { name });
      if (!alive || token !== computeToken || !precreated()) return;
      if (p?.name !== name) throw refusal('Le moteur n’a pas renvoyé le compte demandé. Aucun ajout proposé.');
      setPreview(p);
      if (!preview) throw refusal('Le compte précréé n’est pas confirmé par un aperçu complet et encore valide.');
      announce(`Compte précréé vérifié : ${p.name}.`);
    } catch (error) {
      if (!alive || token !== computeToken) return;
      setPreview(null); previewZone.innerHTML = refusalMarkup(error);
    }
  }

  function paintReceipt(html, tone) {
    receiptZone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('file')}</span><h3>Reçu de la dernière demande</h3></div>${html}`;
    if (tone) applyVars(receiptZone);
  }

  async function add() {
    if (membershipReason() || !cap.enabled || !preview || busy || joinRequested) return;
    const values = form.values();
    if (!lastValues || (precreated() ? lastValues.accountMode !== 'precreated'
      || String(precreatedForm.values().existingName ?? '').trim().toUpperCase() !== lastValues.name
      : lastValues.accountMode !== 'new' || ['type', 'site', 'service'].some((key) => values[key] !== lastValues[key]))) {
      computeToken++; setPreview(null); announce('Les choix ont changé : calculez un nouvel aperçu.'); return;
    }
    const token = computeToken;
    const previewId = preview.previewId;
    const chosen = preview;
    async function replaceTakenPreview(error) {
      if (token !== computeToken || preview?.previewId !== previewId || precreated()) return;
      paintReceipt(refusalMarkup(error, { collision: true }));
      await compute(values, false);
      if (alive && preview) addHint.textContent = chosen.name + ' a été pris. Vérifiez le nouveau nom puis confirmez la jonction.';
    }
    busy = true;
    addButton.disabled = true;
    try {
      const plan = await ctx.call('operation.prepare', { kind: 'join', previewId });
      if (!alive || token !== computeToken || preview?.previewId !== previewId) return;
      if (plan?.kind !== 'join' || plan.newName !== chosen.name || plan.confirmationName !== chosen.name || plan.targetOU !== chosen.ou
        || (chosen.joinAccountMode === 'precreated' && (plan.joinAccountMode !== 'precreated' || plan.computerGuid !== chosen.computerGuid || plan.reservationRequired !== false)))
        throw refusal('Le plan ne correspond plus au nom et au compte affichés. Préparez un nouvel aperçu.');
      const guardedCall = (op, args) => {
        if (!alive || token !== computeToken || preview?.previewId !== previewId) throw refusal('Le contexte a changé : relisez le compte avant une nouvelle demande.');
        return ctx.call(op, args);
      };
      const outcome = await confirmAndExecute(guardedCall, plan, {
        title: 'Confirmer la jonction de ce PC',
        message: plan.joinAccountMode === 'precreated'
          ? 'Ce poste rejoindra le domaine avec le compte AD précréé affiché, dans son OU actuelle. Aucun nouveau compte, changement de propriétaire ou de droits ne sera demandé. Les règles Windows de réutilisation du compte restent applicables. Aucun redémarrage automatique.'
          : plan.reservationRequired === true
          ? 'Après cette confirmation, Pesto créera le compte ordinateur réservé dans l’OU indiquée, puis joindra ce poste avec ce nom. Si la jonction reste incertaine, le compte et son reçu seront conservés pour inspection. Aucun redémarrage automatique.'
          : 'Le poste local rejoindra le domaine configuré avec le nom confirmé. Une seule exécution, sans redémarrage automatique.',
        targetKind: 'le nom du poste',
        confirmLabel: 'Confirmer la jonction',
      });
      if (!alive) return;
      if (outcome.ok) {
        paintReceipt(receiptMarkup(outcome.receipt), true);
        main.dispatchEvent(new Event('pesto-reservations-changed'));
        const result = receiptFeedback(outcome.receipt);
        toast(result.text, { tone: result.tone });
        // An accepted join (even pending restart or uncertain) closes this screen for the session: the engine
        // would refuse a second join and that refusal would replace this receipt.
        if (outcome.receipt?.status !== 'refused') lockAfterJoin(outcome.receipt);
        setPreview(null);
        // Only a confirmed result is re-read: an unconfirmed one triggers no follow-up call (identity changes at restart).
        if (result.confirmed) ctx.refreshSession().then(() => {
          if (!alive) return;
          cap = ctx.capability('join');
          paintIdentity();
          updateCommands();
        }).catch(() => {});
      } else if (outcome.reason === 'collision' && outcome.error?.code === 'name.taken' && !precreated()) {
        await replaceTakenPreview(outcome.error);
      } else if (outcome.reason === 'collision') {
        paintReceipt(refusalMarkup(outcome.error, { collision: true }));
        setPreview(null);
        toast('Le nom vient d’être pris : nouvel aperçu puis nouveau clic.', { tone: 'warn' });
      } else if (outcome.reason === 'error') {
        paintReceipt(refusalMarkup(outcome.error));
        setPreview(null);
      }
    } catch (err) {
      if (!alive || token !== computeToken || preview?.previewId !== previewId) return;
      if (err?.code === 'name.taken' && !precreated()) await replaceTakenPreview(err);
      else { paintReceipt(refusalMarkup(err)); setPreview(null); }
    } finally {
      busy = false;
      if (alive) addButton.disabled = !!joinRequested || !preview || !cap.enabled;
    }
  }

  function lockAfterJoin(receipt) {
    joinRequested = receipt ?? {};
    computeToken++;
    for (const button of main.querySelectorAll('[data-form="join"] [type="submit"], [data-form="precreated"] [type="submit"]')) button.disabled = true;
    if (modeInput) modeInput.disabled = true;
  }

  addButton.addEventListener('click', () => { add(); });

  function updateCommands() {
    if (membershipReason()) { ctx.setScreenCommands([]); return; }
    ctx.setScreenCommands([
    { id: 'ajouter-compute', kind: 'command', label: precreated() ? 'Vérifier le compte précréé' : 'Calculer le nom libre', icon: 'sparkles', group: 'Ajouter ce PC', effect: 'read', available: !joinRequested, reason: joinRequested ? joinRequestedText(joinRequested) : undefined, detailText: 'Vérifie le nom à utiliser avant activation.', run: () => (precreated() ? precreatedHost : formHost).requestSubmit() },
    { id: 'ajouter-join', kind: 'command', label: 'Ajouter ce PC au domaine', icon: 'power', group: 'Ajouter ce PC', effect: 'write', available: !joinRequested && cap.enabled && !!preview, reason: joinRequested ? joinRequestedText(joinRequested) : preview ? cap.reason : 'Calculez d’abord un nom réellement libre.', detailText: 'Jonction : préparation sans mutation, confirmation exacte, reçu.', run: () => { if (!addButton.disabled) add(); } },
    ]);
  }
  updateCommands();

  if (!cap.enabled) toast(cap.reason, { tone: 'warn' });
  function paintMembership() {
    paintIdentity();
    const reason = membershipReason();
    main.querySelector('[data-zone="join-controls"]').hidden = !!reason;
    main.querySelector('[data-zone="join-block"]').hidden = !reason;
    main.querySelector('[data-join-reason]').textContent = reason ?? '';
    offlineEntry.hidden = !live || !!reason;
    if (reason) { computeToken++; setPreview(null); addButton.disabled = true; }
    updateCommands();
    return !reason;
  }
  main.querySelector('[data-act="reread-membership"]').addEventListener('click', async event => {
    const button = event.currentTarget; button.disabled = true;
    try {
      await ctx.refreshSession();
      if (!alive) return;
      cap = ctx.capability('join');
      if (paintMembership()) loadSites();
    } catch (error) { if (alive) main.querySelector('[data-join-reason]').textContent = errorText(error); }
    finally { if (alive) button.disabled = false; }
  });
  if (paintMembership()) loadSites();
  return () => { alive = false; clearTimeout(expiryTimer); form.destroy(); precreatedForm.destroy(); ctx.setScreenCommands([]); stops.forEach((stop) => stop()); };
}
