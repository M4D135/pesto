import { icon } from '../icons.js';
import { esc, applyVars, reveal, errorText, announce, formatDateTime } from '../ui.js';
import { field, confirmWrite, confirmDialog, pill } from '../kit/index.js';
import { receiptMarkup, receiptFeedback, refusalMarkup } from '../writeflow.js';

export const meta = { label: 'Attributs AD', icon: 'file' };
const labels = { description: 'Description', location: 'Emplacement', managedBy: 'Géré par — DN complet' };
const keys = Object.keys(labels);
const guid = value => typeof value === 'string' && /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(value) && !/^0{8}-0{4}-0{4}-0{4}-0{12}$/.test(value);
const invalid = message => Object.assign(new Error(message), { code: 'ui.attributes' });
const display = value => value === '' ? 'Valeur vide — effacement' : value;
const fresh = value => Number.isFinite(Date.parse(value)) && Date.parse(value) > Date.now();
const sameGuid = (a, b) => guid(a) && guid(b) && a.toLowerCase() === b.toLowerCase();
const sameRequested = (key, a, b) => key === 'managedBy' && typeof a === 'string' && typeof b === 'string' ? a.toLowerCase() === b.toLowerCase() : a === b;

export function attributeObservationMatches(observation, source, changes) {
  return sameGuid(observation?.computerGuid, source.computerGuid) && observation.computer === source.computer
    && observation.domain === source.domain && observation.dc === source.dc && observation.ou === source.ou
    && Array.isArray(changes) && changes.length > 0 && new Set(changes.map(c => c.attribute)).size === changes.length
    && Array.isArray(observation.changes) && observation.changes.length === changes.length
    && new Set(observation.changes.map(c => c.attribute)).size === changes.length
    && changes.every(c => observation.changes.some(o => o.attribute === c.attribute && o.expected === c.after
      && o.observed === c.after && o.matches === true)
      && (c.attribute !== 'managedBy' || (c.after === '' ? !observation.managedByReferenceGuid : sameGuid(c.referenceGuid, observation.managedByReferenceGuid))));
}

export function attributeChangesMarkup(changes) {
  if (!Array.isArray(changes) || !changes.length) return '';
  return `<div class="table-wrap"><table class="data-table attribute-diff"><thead><tr><th>Attribut</th><th>Avant</th><th>Demandé</th></tr></thead><tbody>${changes.map(c =>
    `<tr><th>${esc(labels[c.attribute] ?? c.attribute)}</th><td><code>${esc(display(c.before))}</code></td><td><code>${esc(display(c.after))}</code>${c.referenceGuid ? `<p class="muted small">GUID référencé : ${esc(c.referenceGuid)}</p>` : ''}</td></tr>`).join('')}</tbody></table></div>`;
}

export function render(main, ctx) {
  const computer = String(ctx.params?.computer ?? '').toUpperCase();
  main.innerHTML = `<div class="page"><header class="page-header reveal"><div class="head-row"><span class="page-icon">${icon('file')}</span>
    <div class="titles"><h1 class="gradient-text">Attributs AD</h1><p class="subtitle">Description, emplacement et responsable : aperçu exact, confirmation du poste et relecture après écriture.</p></div></div>
    <div class="actions"><a class="btn ghost" href="#/unposte">${icon('arrow-left')}Retour à Un poste</a><button class="btn" type="button" data-read>${icon('refresh')}Relire les attributs</button></div></header>
    <section class="card reveal spot" data-identity aria-live="polite"><p class="muted">Lecture du poste…</p></section>
    <section class="card reveal spot"><div class="card-head"><span class="card-icon">${icon('file')}</span><h3>Valeurs à modifier</h3></div>
      <p class="muted small">Cochez uniquement les attributs à modifier. Une valeur vide cochée demande un effacement. Les espaces sont conservés ; aucun renommage ni déplacement ne sera demandé.</p>
      <form class="k-form" data-values></form><div class="row-actions"><button class="btn primary" data-prepare type="button" disabled>${icon('eye')}Préparer le diff</button></div>
      <div data-plan aria-live="polite"></div></section><section data-result aria-live="polite"></section></div>`;
  applyVars(main); const stop = reveal(main);
  const identity = main.querySelector('[data-identity]'), form = main.querySelector('[data-values]');
  const readButton = main.querySelector('[data-read]'), prepareButton = main.querySelector('[data-prepare]');
  const planZone = main.querySelector('[data-plan]'), resultZone = main.querySelector('[data-result]');
  let alive = true, busy = false, revision = 0, inspection = null, plan = null, inspectionSession = null;
  let cleanDraft = null, discardPending = false;
  const cap = ctx.capability('attributes');
  const writable = () => ctx.session()?.mode === 'live' && ctx.session()?.readOnly !== true && ctx.capability('attributes').enabled === true;
  const sessionStamp = () => {
    const s = ctx.session() ?? {};
    return JSON.stringify([s.mode, s.readOnly, s.domain, s.dc, s.computer, s.account, ctx.capability('attributes').enabled]);
  };
  const values = () => Object.fromEntries(keys.filter(k => form.querySelector(`[name="edit-${k}"]`)?.checked)
    .map(k => [k, form.querySelector(`[name="${k}"]`).value]));
  const draft = () => JSON.stringify(keys.map(k => [form.querySelector(`[name="edit-${k}"]`)?.checked ?? false,
    form.querySelector(`[name="${k}"]`)?.value ?? '']));
  const dirty = () => inspection !== null && cleanDraft !== null && draft() !== cleanDraft;
  async function discardDraft(title) {
    if (!dirty()) return true;
    if (discardPending) return false;
    discardPending = true;
    try {
      return await confirmDialog({ title, message: 'Les valeurs et les choix d’attributs non appliqués seront abandonnés.',
        confirmLabel: 'Abandonner le brouillon', danger: true });
    } finally { discardPending = false; }
  }
  const stopGuard = ctx.guardLeave?.(() => discardDraft('Quitter les attributs AD'));
  function paintBusy(value) {
    busy = value; readButton.disabled = value;
    form.querySelectorAll('input').forEach(input => { input.disabled = value || !writable(); });
    prepareButton.disabled = value || !inspection || !writable() || !Object.keys(values()).length;
    planZone.querySelectorAll('button').forEach(button => { button.disabled = value || !writable(); });
  }
  function discardPlan() { revision++; plan = null; planZone.innerHTML = ''; paintBusy(busy); }
  function requirePlan(candidate, source, requested) {
    const changed = Object.keys(requested).filter(k => !sameRequested(k, requested[k], source.values[k]));
    if (candidate?.kind !== 'attributes' || candidate.mode !== 'live' || !candidate.planId || candidate.computer !== source.computer
      || candidate.computerGuid?.toLowerCase() !== source.computerGuid.toLowerCase() || candidate.domain !== source.domain || candidate.dc !== source.dc
      || candidate.sourceOU !== source.ou || candidate.targetOU !== source.ou || candidate.confirmationName !== source.computer || !fresh(candidate.expiresAt)
      || !Array.isArray(candidate.changes) || !changed.length || candidate.changes.length !== changed.length
      || new Set(candidate.changes.map(c => c.attribute)).size !== changed.length
      || candidate.changes.some(c => !changed.includes(c.attribute) || c.before !== source.values[c.attribute] || !sameRequested(c.attribute, c.after, requested[c.attribute])
        || (c.attribute === 'managedBy' && c.after !== '' ? !guid(c.referenceGuid) : !!c.referenceGuid)))
      throw invalid('Le diff ne correspond pas exactement aux valeurs et à l’identité affichées. Relisez le poste ; aucune écriture envoyée.');
  }
  function requireReceipt(result, source, changes) {
    const receipt = result?.receipt;
    if (!receipt?.id || receipt.kind !== 'attributes' || receipt.computer !== source.computer || !(receipt.mode === 'live' || receipt.mode?.startsWith('live · '))
      || receipt.targetOU !== source.ou || receipt.restartRequired === true || (receipt.newName && receipt.newName !== source.computer))
      throw invalid('La réponse ne contient pas le reçu attendu. Consultez les interventions avant toute nouvelle action.');
    if (receipt.status === 'succeeded' && (String(receipt.code) !== '30' || !attributeObservationMatches(result.observation, source, changes)))
      throw invalid('Le résultat ne prouve pas la relecture exacte de tous les attributs. Aucun succès affiché ; consultez le reçu durable.');
    return receipt;
  }
  function paintResult(result, source, changes) {
    const receipt = requireReceipt(result, source, changes);
    resultZone.innerHTML = receiptMarkup(receipt) + attributeChangesMarkup(changes)
      + `<div class="row-actions"><button class="btn" type="button" data-observe>${icon('refresh')}Observer les valeurs sans les modifier</button><a class="btn ghost" href="#/interventions?query=${encodeURIComponent(receipt.id)}">Ouvrir les interventions</a></div><p data-observation role="status"></p>`;
    applyVars(resultZone);
    resultZone.querySelector('[data-observe]').addEventListener('click', async event => {
      if (busy || !alive) return; const button = event.currentTarget; button.disabled = true; paintBusy(true);
      try {
        const observation = await ctx.call('attributes.observe', { id: receipt.id });
        if (!alive) return;
        if (observation.targetReadOnly !== true || observation.replayAllowed !== false || observation.receipt?.id !== receipt.id) throw invalid('Observation non liée au reçu affiché.');
        const next = requireReceipt(observation, source, changes);
        if (observation.verified === true && next.status !== 'succeeded') throw invalid('La vérification ne possède pas de reçu de succès durable. Le résultat reste non confirmé.');
        if (observation.verified === true && next.status === 'succeeded') paintResult(observation, source, changes);
        resultZone.querySelector('[data-observation]').textContent = observation.verified === true
          ? 'Valeurs confirmées par observation et preuve durable. Aucune commande de modification rejouée.'
          : observation.reason || 'État non confirmé. Le reçu et ses barrières sont conservés.';
      } catch (error) { if (alive) resultZone.querySelector('[data-observation]').textContent = errorText(error); }
      finally { if (alive) { paintBusy(false); if (button.isConnected) button.disabled = false; } }
    });
    announce(receiptFeedback(receipt).text);
  }
  async function read() {
    if (busy) return;
    if (!await discardDraft('Relire les attributs du poste') || !alive || busy) return;
    const mine = ++revision, session = sessionStamp(); inspection = null; inspectionSession = null; plan = null; form.innerHTML = ''; planZone.innerHTML = ''; paintBusy(true);
    try {
      if (ctx.session()?.mode !== 'live' || !/^[A-Z0-9][A-Z0-9-]{0,14}$/.test(computer)) throw invalid('Ouvrez ce parcours depuis un poste réel sélectionné dans Un poste.');
      const source = await ctx.call('attributes.inspect', { computer });
      if (!alive || revision !== mine) return;
      if (sessionStamp() !== session) throw invalid('La session a changé pendant la lecture. Relisez le poste.');
      if (!source?.inspectionId || source.complete !== true || source.mode !== 'live' || source.computer.toUpperCase() !== computer
        || !guid(source.computerGuid) || !fresh(source.expiresAt) || keys.some(k => typeof source.values?.[k] !== 'string'))
        throw invalid('La lecture des attributs est incomplète ; aucune préparation proposée.');
      inspection = source; inspectionSession = session;
      identity.innerHTML = `<div class="card-head"><span class="card-icon">${icon('shield')}</span><h3>${esc(source.computer)}</h3><span class="meta">${pill('info', 'Identité relue')}</span></div>
        <div class="kv-grid">${[['GUID AD', source.computerGuid], ['OU', source.ou], ['Domaine', source.domain], ['Contrôleur', source.dc], ['Lecture', formatDateTime(source.collectedAt)]].map(([k,v]) => `<span class="k">${esc(k)}</span><span class="v mono">${esc(v)}</span>`).join('')}</div>`;
      form.innerHTML = keys.map(k => field({ name: `edit-${k}`, label: `Modifier ${labels[k]}`, type: 'switch' })
        + field({ name: k, label: labels[k], value: source.values[k], maxLength: 1024, mono: k === 'managedBy' })).join('');
      cleanDraft = draft();
      if (!writable()) planZone.innerHTML = `<p class="muted">${esc(cap.reason || 'Cette session permet uniquement la lecture des attributs.')}</p>`;
      applyVars(form);
    } catch (error) { if (alive && revision === mine) identity.innerHTML = refusalMarkup(error); }
    finally { if (alive) paintBusy(false); }
  }
  async function prepare() {
    if (busy || !inspection || !writable()) return;
    const source = inspection, requested = values(), fingerprint = JSON.stringify(requested), mine = revision, session = sessionStamp();
    plan = null; planZone.innerHTML = '<p aria-busy="true">Préparation et relecture des valeurs…</p>'; paintBusy(true);
    try {
      if (session !== inspectionSession) throw invalid('La session a changé depuis la lecture. Relisez le poste.');
      const candidate = await ctx.call('attributes.prepare', { inspectionId: source.inspectionId, values: requested });
      if (!alive || revision !== mine || inspection !== source || JSON.stringify(values()) !== fingerprint) return;
      if (sessionStamp() !== session) throw invalid('La session a changé pendant la préparation. Relisez le poste.');
      requirePlan(candidate, source, requested); plan = candidate;
      planZone.innerHTML = attributeChangesMarkup(candidate.changes) + `<p class="muted small">Expiration : ${esc(formatDateTime(candidate.expiresAt))}. Les champs non cochés restent inchangés.</p><button class="btn primary" type="button" data-apply>${icon('check')}Confirmer ce diff</button>`;
      planZone.querySelector('[data-apply]').addEventListener('click', async () => {
        if (busy || plan !== candidate || !writable()) return;
        const answer = await confirmWrite({ title: 'Confirmer les attributs AD', target: candidate.confirmationName, targetKind: 'le poste à modifier',
          message: 'Seuls les attributs affichés seront modifiés. Une valeur vide est un effacement explicite. Aucun changement du nom, de l’OU, des droits ni redémarrage.',
          changes: candidate.changes.map(c => ({ label: labels[c.attribute], before: display(c.before), after: display(c.after) })),
          warnings: candidate.warnings ?? [], details: `GUID ${source.computerGuid} · ${source.dc} · plan ${candidate.planId} · expire ${formatDateTime(candidate.expiresAt)}`,
          typed: false, confirmLabel: 'Appliquer ces attributs' });
        if (answer !== 'confirm' || !alive) return;
        try {
          if (plan !== candidate || revision !== mine || inspection !== source || JSON.stringify(values()) !== fingerprint || sessionStamp() !== session || !writable()) throw invalid('Le contexte ou les valeurs ont changé. Préparez un nouveau diff.');
          requirePlan(candidate, source, requested); plan = null; paintBusy(true); planZone.innerHTML = '<p aria-busy="true">Demande confirmée ; attente du reçu durable…</p>';
          const result = await ctx.call('attributes.apply', { planId: candidate.planId, confirmationName: candidate.confirmationName });
          if (!alive) return; inspection = null; form.innerHTML = ''; planZone.innerHTML = ''; paintResult(result, source, candidate.changes);
        } catch (error) { if (alive) { plan = null; planZone.innerHTML = refusalMarkup(error); } }
        finally { if (alive) paintBusy(false); }
      });
    } catch (error) { if (alive && revision === mine) planZone.innerHTML = refusalMarkup(error); }
    finally { if (alive) paintBusy(false); }
  }
  form.addEventListener('submit', event => event.preventDefault());
  form.addEventListener('input', discardPlan); form.addEventListener('change', discardPlan);
  readButton.addEventListener('click', read); prepareButton.addEventListener('click', prepare);
  read();
  return () => { alive = false; revision++; stopGuard?.(); stop(); };
}
