// The configured registry is never probed merely by mounting this panel. Testing and preparation are explicit.
import { icon } from '../icons.js';
import { esc, errorText, announce, formatDateTime } from '../ui.js';
import { refusal } from '../refusal.js';
import { confirmWrite } from '../kit/index.js';

export function coordinationMarkup() {
  return `<section class="card reveal spot" data-coordination hidden>
    <div class="card-head"><span class="card-icon">${icon('lock')}</span><h3>Registre de coordination</h3></div>
    <div data-coordination-info class="kv-grid"></div>
    <p class="muted small">Enregistrez d’abord les paramètres. Le dossier ne sera contacté qu’à votre demande ; les verrous existants restent conservés.</p>
    <div class="row-actions">
      <button class="btn" type="button" data-coordination-action="inspect" disabled>${icon('eye')}Tester le registre</button>
      <button class="btn" type="button" data-coordination-action="prepare" disabled>Préparer ce dossier</button>
    </div>
    <p class="muted small" data-coordination-status role="status"></p>
  </section>`;
}

export function mountCoordination(main, ctx) {
  const host = main.querySelector('[data-coordination]');
  if (!host || ctx.session()?.mode !== 'live') return { refresh() {}, dispose() {} };
  host.hidden = false;
  let alive = true, busy = false, current = null, revision = 0;
  const status = host.querySelector('[data-coordination-status]');
  const info = host.querySelector('[data-coordination-info]');
  function message(text, failed = false) {
    status.textContent = text; status.setAttribute('role', failed ? 'alert' : 'status');
    announce(text, { assertive: failed });
  }
  function lock(value) {
    busy = value; host.setAttribute('aria-busy', String(value));
    host.querySelectorAll('button[data-coordination-action]').forEach((button) => { button.disabled = value || current?.configured !== true || ctx.session()?.configurationOnly === true; });
  }
  async function refresh() {
    const token = ++revision;
    lock(true);
    try {
      const value = await ctx.call('coordination.status', {});
      if (!alive || token !== revision) return;
      if (typeof value?.configured !== 'boolean' || typeof value.root !== 'string' || typeof value.domain !== 'string') throw refusal('Statut du registre incomplet. Aucune préparation ne peut être confirmée.');
      current = value;
      info.innerHTML = `<span class="k">Dossier enregistré</span><span class="v mono">${esc(value.root || 'Aucun')}</span>
        <span class="k">Domaine</span><span class="v mono">${esc(value.domain || 'Non configuré')}</span>
        <span class="k">Politique</span><span class="v">${value.required === true ? 'Coordination exigée' : 'Coordination appliquée lorsqu’un dossier est configuré'}</span>`;
      message(value.message || 'Paramètres locaux relus. Aucun partage n’a été interrogé.');
    } catch (error) { if (alive && token === revision) { current = null; message(errorText(error), true); } }
    finally { if (alive && token === revision) lock(false); }
  }
  async function act(action) {
    if (busy || current?.configured !== true || ctx.session()?.mode !== 'live' || ctx.session()?.configurationOnly === true) return;
    const token = revision, expected = current;
    const stale = () => !alive || token !== revision || !host.isConnected || ctx.session()?.mode !== 'live';
    const matches = (value) => value?.root === expected.root && value.domain === expected.domain;
    lock(true);
    try {
      if (action === 'inspect') {
        message('Inspection explicite du registre configuré…');
        const value = await ctx.call('coordination.inspect', {});
        if (stale()) return;
        if (!matches(value)) throw refusal('La configuration du registre a changé. Relisez les paramètres.');
        message(value.message || (value.prepared === true ? 'Registre relu et prêt.' : 'Registre incomplet ; préparez le dossier si nécessaire.'));
        return;
      }
      const plan = await ctx.call('coordination.prepare', {});
      if (stale()) return;
      if (!matches(plan) || typeof plan.planId !== 'string' || !plan.planId || plan.requiresConfirmation !== true
        || !Number.isFinite(Date.parse(plan.expiresAt)) || Date.parse(plan.expiresAt) <= Date.now()) {
        throw refusal('L’aperçu du registre est absent, périmé ou ne correspond plus aux paramètres. Aucune création demandée.');
      }
      const answer = await confirmWrite({
        title: 'Préparer le dossier de coordination', target: plan.root, targetKind: 'Dossier configuré', typed: false,
        message: 'Créer les éléments manquants du registre dans ce dossier. Aucun partage, droit Windows ou verrou existant ne sera modifié.',
        badge: 'Préparation du dossier partagé',
        changes: [{ label: 'Domaine', after: plan.domain }, ...(plan.actions ?? []).map((action) => ({ label: 'Création prévue', after: action }))],
        details: `Valide jusqu’à ${formatDateTime(plan.expiresAt)}.\n${(plan.warnings ?? []).join('\n')}`,
        confirmLabel: 'Confirmer la préparation',
      });
      if (stale()) return;
      if (answer !== 'confirm') { message('Préparation annulée : aucun élément créé.'); return; }
      if (Date.parse(plan.expiresAt) <= Date.now()) throw refusal('Cet aperçu a expiré. Préparez un nouveau plan.');
      const result = await ctx.call('coordination.apply', { planId: plan.planId, confirmed: true });
      if (stale()) return;
      if (!matches(result) || result.prepared !== true || !['prepared', 'unchanged'].includes(result.status)) {
        throw refusal('La préparation du registre n’est pas confirmée. Inspectez son état avant toute nouvelle demande.');
      }
      message(result.message || 'Registre préparé et relu.');
    } catch (error) { if (!stale()) message(errorText(error), true); }
    finally { if (!stale()) lock(false); }
  }
  host.addEventListener('click', (event) => {
    const button = event.target instanceof Element ? event.target.closest('button[data-coordination-action]') : null;
    if (button && !button.disabled && ['inspect', 'prepare'].includes(button.dataset.coordinationAction)) act(button.dataset.coordinationAction);
  });
  refresh();
  return { refresh, dispose() { alive = false; revision++; } };
}
