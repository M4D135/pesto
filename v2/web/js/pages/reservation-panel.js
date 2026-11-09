// Durable reservation recovery. Loading this panel reads local receipts only; every directory inspection and
// every action is an explicit click. A prepared action is confirmed by its exact name and sent once.
import { icon } from '../icons.js';
import { esc, applyVars, errorText, announce, formatDateTime } from '../ui.js';
import { refusal } from '../refusal.js';
import { confirmWrite, pill } from '../kit/index.js';
import { receiptMarkup } from '../writeflow.js';

const labels = {
  pending: 'À vérifier', reserved: 'Compte réservé', taken: 'Nom déjà occupé', failed: 'Réservation non aboutie',
  uncertain: 'Résultat incertain', kept: 'Compte conservé', consumed: 'Réservation utilisée',
  released: 'Retrait confirmé', gone: 'Absence confirmée',
};
const identity = ['id', 'name', 'computer', 'domain', 'dc', 'targetOU'];
const sameIdentity = (a, b) => identity.every((key) => typeof a?.[key] === 'string' && a[key] === b?.[key]);

export function reservationMarkup() {
  return `<section class="card reveal spot" data-reservations hidden>
    <div class="card-head"><span class="card-icon">${icon('shield')}</span><h3>Réservations AD conservées</h3>
      <span class="meta"><button class="btn ghost sm" type="button" data-reservation-refresh>${icon('refresh')}Relire les reçus</button></span></div>
    <p class="muted small">Une réservation conservée se vérifie avant toute reprise. Fermer Pesto ou annuler une confirmation ne supprime aucun compte.</p>
    <div data-reservation-list aria-live="polite"><p class="muted">Lecture des reçus locaux…</p></div>
    <p class="muted small" data-reservation-status role="status"></p>
  </section>`;
}

function card(record) {
  const state = String(record.state ?? '').toLowerCase();
  const tone = ['uncertain', 'kept', 'pending'].includes(state) || record.needsReview ? 'warn' : 'off';
  return `<article class="reservation-entry" data-reservation="${esc(record.id)}">
    <div class="row-actions"><strong class="mono">${esc(record.name)}</strong>${pill(tone, labels[state] ?? record.state ?? 'État inconnu')}</div>
    <div class="kv-grid">
      <span class="k">Reçu</span><span class="v mono">${esc(record.id)}</span>
      <span class="k">Poste lors de la réservation</span><span class="v mono">${esc(record.computer)}</span>
      <span class="k">Domaine · contrôleur</span><span class="v mono">${esc(record.domain)} · ${esc(record.dc)}</span>
      <span class="k">OU</span><span class="v mono">${esc(record.targetOU)}</span>
      <span class="k">État lu</span><span class="v">${esc(record.message ?? '')}</span>
    </div>
    <div class="row-actions">
      <button class="btn sm" type="button" data-reservation-action="inspect">${icon('eye')}Inspecter dans AD</button>
      <button class="btn sm" type="button" data-reservation-action="resumeJoin"${record.canResume === true ? '' : ' disabled'}>Préparer la reprise de jonction</button>
      <button class="btn ghost sm" type="button" data-reservation-action="release"${record.canRelease === true ? '' : ' disabled'}>Préparer le retrait</button>
    </div>
    ${record.canResume !== true && record.canRelease !== true ? '<p class="muted small">Inspectez ce compte pour connaître les actions encore autorisées. Aucun résultat absent ou incertain ne permet un retrait.</p>' : ''}
  </article>`;
}

export function mountReservations(main, ctx) {
  const host = main.querySelector('[data-reservations]');
  if (!host || ctx.session()?.mode !== 'live') return () => {};
  host.hidden = false;
  let alive = true, busy = false, revision = 0;
  const records = new Map();
  const list = host.querySelector('[data-reservation-list]');
  const status = host.querySelector('[data-reservation-status]');

  function message(text, failed = false) {
    status.textContent = text;
    status.setAttribute('role', failed ? 'alert' : 'status');
    announce(text, { assertive: failed });
  }
  function render() {
    list.innerHTML = records.size ? [...records.values()].map(card).join('') : '<p class="muted">Aucune réservation conservée dans les reçus locaux.</p>';
    applyVars(host);
  }
  function lock(value) {
    busy = value; host.setAttribute('aria-busy', String(value));
    host.querySelector('[data-reservation-refresh]').disabled = value;
    for (const button of list.querySelectorAll('button[data-reservation-action]')) {
      const record = records.get(button.closest('[data-reservation]').dataset.reservation);
      button.disabled = value || (button.dataset.reservationAction === 'resumeJoin' && record?.canResume !== true)
        || (button.dataset.reservationAction === 'release' && record?.canRelease !== true);
    }
  }
  async function load() {
    if (busy) return;
    const current = ++revision; lock(true);
    try {
      const result = await ctx.call('reservations.list', {});
      if (!alive || current !== revision) return;
      if (!Array.isArray(result?.items) || result.items.some((record) => !identity.every((key) => typeof record?.[key] === 'string'))) {
        throw refusal('La liste des réservations ne contient pas les identités attendues. Aucun compte n’est ciblé.');
      }
      if (new Set(result.items.map((record) => record.id)).size !== result.items.length) throw refusal('Des identifiants de réservation sont répétés. Aucun compte n’est ciblé.');
      records.clear(); result.items.forEach((record) => records.set(record.id, record)); render();
      message(result.message || 'Reçus locaux relus. L’annuaire n’a pas été interrogé.');
    } catch (error) {
      if (alive && current === revision) message(errorText(error), true);
    } finally { if (alive && current === revision) lock(false); }
  }

  async function act(id, action) {
    const record = records.get(id);
    if (busy || !record || ctx.session()?.mode !== 'live') return;
    if (action === 'resumeJoin' && record.canResume !== true || action === 'release' && record.canRelease !== true) return;
    const current = revision;
    const stale = () => !alive || current !== revision || !host.isConnected || ctx.session()?.mode !== 'live';
    lock(true);
    try {
      if (action === 'inspect') {
        message('Lecture du GUID, du marqueur et de l’état du compte…');
        const result = await ctx.call('reservations.inspect', { id });
        if (stale()) return;
        const inspected = result?.reservation ?? result;
        if (!sameIdentity(record, inspected)) throw refusal('L’inspection ne correspond plus à cette réservation. Relisez les reçus locaux.');
        records.set(id, inspected); render(); message(inspected.message || 'Inspection terminée ; consultez l’état retourné.');
        return;
      }
      message('Préparation en lecture seule de l’action demandée…');
      const plan = await ctx.call('reservations.prepare', { id, action });
      if (stale()) return;
      if (plan?.mode !== 'live' || plan.reservationId !== id || plan.action !== action || typeof plan.planId !== 'string' || !plan.planId
        || plan.confirmationName !== record.name || ![record.computer, record.name].includes(plan.computer)
        || !['name', 'domain', 'dc', 'targetOU'].every((key) => plan[key] === record[key])
        || !Number.isFinite(Date.parse(plan.expiresAt)) || Date.parse(plan.expiresAt) <= Date.now()) {
        throw refusal('Le plan ne correspond pas à la réservation inspectée ou a expiré. Aucune exécution n’a été demandée.');
      }
      const answer = await confirmWrite({
        title: action === 'release' ? 'Confirmer le retrait du compte réservé' : 'Confirmer la reprise de jonction',
        message: action === 'release'
          ? 'Seul le compte réservé identifié par ce reçu sera retiré, après une dernière vérification du GUID, du marqueur et de son absence d’utilisation.'
          : 'La jonction reprendra exclusivement le compte réservé de ce reçu. Le moteur relira les preuves avant l’envoi ; aucun redémarrage ne sera déclenché.',
        target: record.name, targetKind: 'le nom du compte réservé', targetDetail: record.targetOU,
        changes: [
          { label: 'Poste local relu', after: plan.computer }, { label: 'Compte réservé', after: record.name },
          { label: 'Domaine', after: record.domain }, { label: 'Contrôleur', after: record.dc }, { label: 'OU', after: record.targetOU },
        ],
        details: `Valide jusqu’à ${formatDateTime(plan.expiresAt)}.\n${(plan.steps ?? []).map((step) => typeof step === 'string' ? step : `${step.label ?? ''} : ${step.detail ?? ''}`).join('\n')}\n${(plan.warnings ?? []).join('\n')}`,
        confirmLabel: action === 'release' ? 'Retirer ce compte réservé' : 'Reprendre cette jonction',
        typed: false,
      });
      if (stale()) return;
      if (answer !== 'confirm') { message('Confirmation annulée : aucune modification AD envoyée.'); return; }
      if (plan.confirmationName !== record.name || Date.parse(plan.expiresAt) <= Date.now()) throw refusal('La confirmation est incomplète ou le plan a expiré. Préparez un nouveau plan.');
      const result = await ctx.call('reservations.execute', { planId: plan.planId, confirmationName: plan.confirmationName });
      if (stale()) return;
      if (!sameIdentity(record, result?.reservation)) throw refusal('Le résultat ne permet pas de confirmer l’identité de la réservation. Inspectez-la avant toute autre action.');
      if (result.receipt) {
        const receipt = result.receipt;
        if (action !== 'resumeJoin' || receipt.kind !== 'join' || receipt.computer !== plan.computer || receipt.newName !== record.name
          || receipt.targetOU !== record.targetOU || typeof receipt.mode !== 'string' || !(receipt.mode === 'live' || receipt.mode.startsWith('live · '))) {
          throw refusal('Le reçu de jonction ne correspond pas à la réservation. Aucun succès n’est confirmé.');
        }
      }
      records.set(id, result.reservation); render();
      if (result.receipt) {
        const receipt = result.receipt;
        const detail = document.createElement('div'); detail.innerHTML = receiptMarkup(receipt); list.appendChild(detail); applyVars(detail);
      }
      message(result.reservation.message || 'Réponse reçue ; consultez le statut durable avant toute autre action.');
    } catch (error) { if (!stale()) message(errorText(error), true); }
    finally { if (!stale()) lock(false); }
  }

  host.querySelector('[data-reservation-refresh]').addEventListener('click', load);
  main.addEventListener('pesto-reservations-changed', load);
  list.addEventListener('click', (event) => {
    const button = event.target instanceof Element ? event.target.closest('button[data-reservation-action]') : null;
    if (!button || button.disabled) return;
    const row = button.closest('[data-reservation]');
    if (row && ['inspect', 'resumeJoin', 'release'].includes(button.dataset.reservationAction)) act(row.dataset.reservation, button.dataset.reservationAction);
  });
  load();
  return () => { alive = false; revision++; main.removeEventListener('pesto-reservations-changed', load); };
}
