// Shared write pipeline for every screen (mission Pesto v2) : aperçu → préparation → confirmation du plan affiché →
// exécution → reçu. The engine is the authority: this module only sequences the bridge calls, never retries a refusal,
// never reuses a consumed plan and never invents a name. A collision after preparation always goes back through a new
// preview and a new click — never a new automatic write.
import { icon } from './icons.js';
import { esc, errorText, announce, formatDateTime } from './ui.js';
import { pill, confirmWrite } from './kit/index.js';

export const KIND_LABEL = { join: 'Jonction', rename: 'Renommage', move: 'Déplacement', renameMove: 'Renommage + déplacement', attributes: 'Attributs AD', offlineJoin: 'Jonction hors ligne' };

// Errors that mean « the world moved after the preview » : the operator must compute a new preview and click again.
const COLLISION_CODES = ['name.taken', 'identity.changed', 'plan.stale', 'preview.changed', 'preview.identity'];
export function isCollision(err) {
  return COLLISION_CODES.includes(String(err?.code ?? ''));
}

// French wording of receipt states, shared with every screen that lists receipts (never the raw engine code).
export const STATUS_LABEL = { simulated: 'Simulé', succeeded: 'Réussi', pendingRestart: 'Redémarrage en attente', refused: 'Refusé', uncertain: 'Incertain' };

const STATUS_PILL = {
  simulated: () => pill('info', 'Simulé', { icon: 'sparkles', tip: 'Action appliquée en mémoire seulement.' }),
  succeeded: () => pill('ok', 'Réussi', { icon: 'check', tip: 'Relu après écriture : l’état attendu est confirmé.' }),
  pendingRestart: () => pill('warn', 'Redémarrage en attente', { icon: 'power', tip: 'Le nom prendra effet après un redémarrage planifié manuellement.' }),
  refused: () => pill('alert', 'Refusé', { icon: 'x', tip: 'Le moteur a refusé la demande. Consultez les effets consignés dans le reçu.' }),
  uncertain: () => pill('warn', 'Incertain', { icon: 'eye', tip: 'Résultat inconnu : jamais rejoué automatiquement, à vérifier.' }),
};

// Always injected after the page's one reveal() pass, so it uses the self-ending `pop` entrance:
// a `.reveal` card would never receive `.in` and would stay at opacity 0 (blank receipt).
export function receiptMarkup(r) {
  if (!r || typeof r !== 'object') return '<p class="muted">Aucun reçu.</p>';
  const status = (STATUS_PILL[r.status] ?? (() => pill('off', String(r.status ?? 'inconnu'))))();
  const simulated = r.mode === 'simulation';
  return `<article class="card receipt-card pop spot" data-receipt="${esc(r.id)}" data-status="${esc(r.status)}" data-mode="${esc(r.mode)}">
    <div class="card-head"><span class="card-icon">${icon(simulated ? 'sparkles' : 'shield')}</span>
      <h3>${esc(KIND_LABEL[r.kind] ?? r.kind)} · ${esc(r.computer)}${r.newName && r.newName !== r.computer ? ` → ${esc(r.newName)}` : ''}</h3>
      <span class="meta">${status}</span></div>
    <div class="kv-grid">
      <span class="k">Reçu</span><span class="v mono">${esc(r.id)}</span>
      <span class="k">Heure</span><span class="v">${esc(formatDateTime(r.time ?? r.utc) ?? 'inconnue')}</span>
      <span class="k">Mode</span><span class="v">${simulated ? 'Simulation (aucun effet réel)' : esc(r.mode ?? 'inconnu')}</span>
      <span class="k">OU du plan</span><span class="v mono">${esc(r.targetOU || '—')}</span>
      <span class="k">Message</span><span class="v">${esc(r.message ?? '')}</span>
    </div>
    ${r.restartRequired ? `<p class="muted small">${icon('power')} Redémarrage requis pour terminer l’opération : Pesto ne redémarre aucun poste implicitement.</p>` : ''}
  </article>`;
}

// Receiving a receipt is not proof that the operation succeeded. Only these states allow a next action.
export function receiptFeedback(receipt) {
  const action = KIND_LABEL[receipt?.kind] || 'Opération';
  const ending = ['renameMove', 'attributes'].includes(receipt?.kind) ? 's' : ['rename', 'move'].includes(receipt?.kind) ? '' : 'e';
  if (receipt?.mode === 'simulation' && receipt.status === 'simulated') return { confirmed: true, tone: 'info', text: `${action} simulé${ending} : aucun effet réel.` };
  if (receipt?.status === 'succeeded' && receipt.restartRequired !== true) return { confirmed: true, tone: 'ok', text: `${action} confirmé${ending} par le moteur.` };
  if (receipt?.status === 'pendingRestart' || (receipt?.status === 'succeeded' && receipt.restartRequired === true)) return { confirmed: false, tone: 'warn', text: `${action} accepté${ending} : redémarrage à planifier, puis état à vérifier dans Interventions.` };
  if (receipt?.status === 'refused') return { confirmed: false, tone: 'alert', text: `${action} refusé${ending}. Consultez le reçu avant toute nouvelle action.` };
  return { confirmed: false, tone: 'warn', text: `${action} : résultat incertain. Vérifiez l’état dans Interventions ; aucune suite automatique.` };
}

// Receipt identity follows Windows/AD case-insensitive names, while operation and execution mode
// remain exact contracts. Status/code are deliberately not interpreted here: partial and pending
// outcomes must remain visible without becoming a success or triggering another operation.
export function receiptMatchesPlan(receipt, plan) {
  const same = (a, b) => typeof a === 'string' && typeof b === 'string' && a.toUpperCase() === b.toUpperCase();
  return !!plan && typeof receipt?.id === 'string' && !!receipt.id.trim() && receipt.kind === plan.kind
    && same(receipt.computer, plan.computer) && same(receipt.newName || receipt.computer, plan.newName || plan.computer)
    && same(receipt.targetOU || '', plan.targetOU || '')
    && (plan.mode === 'simulation' ? receipt.mode === 'simulation'
      : plan.mode === 'live' && typeof receipt.mode === 'string' && (receipt.mode === 'live' || receipt.mode.startsWith('live · ')));
}

// A required Entra withdrawal is a separately disclosed effect. Missing/contradictory metadata never
// authorizes it; the adapter owns the actual token and revalidates it after this user confirmation.
export function entraConfirmation(plan) {
  const invalid = () => { throw Object.assign(new Error('Le plan ne prouve pas le retrait Entra proposé. Préparez une nouvelle opération.'), { code: 'plan.entra' }); };
  if (plan?.entraLeaveRequired !== undefined && typeof plan.entraLeaveRequired !== 'boolean') invalid();
  if (plan?.entraLeaveRequired !== true) {
    if (plan?.entraState === 'hybrid' || (plan?.entraState != null && plan.entraState !== 'adOnly')) invalid();
    return { required: false, checks: [], changes: [], message: '' };
  }
  if (plan.mode !== 'live' || !['rename', 'renameMove'].includes(plan.kind)
    || plan.entraState !== 'hybrid' || plan.entraPolicy !== 'HybridOnly'
    || !Number.isFinite(Date.parse(plan.entraObservedAt)) || !(Date.parse(plan.entraExpiresAt) > Date.now())) invalid();
  return {
    required: true,
    checks: [{ id: 'entraLeave', label: 'J’autorise le retrait Entra de ce poste avant son renommage et je vérifierai séparément sa réinscription hybride.' }],
    changes: [{ label: 'Retrait Entra avant renommage', after: plan.computer }],
    message: ' Ce poste est hybride : Pesto demandera son retrait Entra avant le renommage. La réinscription hybride devra être vérifiée séparément. Aucun redémarrage automatique.',
  };
}

/**
 * Explicit confirmation of a prepared plan, then the single execute call. Returns:
 *   { ok: true, receipt }                       — the engine answered with a receipt ;
 *   { ok: false, reason: 'cancelled' }          — the operator withdrew (nothing was sent) ;
 *   { ok: false, reason: 'collision', error }   — target or name moved : new preview + new click, never automatic ;
 *   { ok: false, reason: 'error', error, sent }  — any other engine refusal : nothing is replayed ; sent = execute was
 *                                                 called, so the write may have happened despite the error.
 * The operator confirms the name already shown. That confirmationName is re-sent to the engine, which checks it again.
 */
export async function confirmAndExecute(call, plan, { title, message, targetKind, changes, confirmLabel } = {}) {
  if (!plan?.planId || typeof plan.confirmationName !== 'string' || !plan.confirmationName) {
    return { ok: false, reason: 'error', error: Object.assign(new Error('Plan sans nom à confirmer.'), { code: 'plan.invalid' }) };
  }
  let entra;
  try { entra = entraConfirmation(plan); }
  catch (error) { return { ok: false, reason: 'error', error }; }
  let entraConfirmed = false;
  const answer = await confirmWrite({
    title: title ?? `Confirmer — ${KIND_LABEL[plan.kind] ?? plan.kind}`,
    message: (message ?? 'Vérifiez chaque ligne. Cette confirmation autorise une seule exécution du plan affiché.') + entra.message,
    target: plan.confirmationName,
    targetKind: targetKind ?? 'le nom à appliquer',
    targetDetail: plan.targetOU || undefined,
    changes: [...(changes ?? [
      { label: 'Poste', before: plan.computer, after: plan.newName || plan.computer },
      ...(plan.kind === 'rename' || plan.kind === 'renameMove' ? [{ label: 'Nom', after: plan.newName }] : []),
      ...(plan.kind === 'move' || plan.kind === 'renameMove' || plan.kind === 'join' ? [{ label: 'OU de destination', after: plan.targetOU }] : []),
    ]), ...entra.changes],
    checks: entra.checks,
    onChecks: (ids) => { entraConfirmed = ids.includes('entraLeave'); },
    details: `planId ${plan.planId} · mode ${plan.mode ?? 'inconnu'} · expire ${formatDateTime(plan.expiresAt) ?? '?'}`
      + (plan.warnings?.length ? `\n${plan.warnings.join('\n')}` : ''),
    confirmLabel: confirmLabel ?? 'Confirmer l’écriture',
    badge: plan.mode === 'simulation' ? 'Démonstration · aucun effet réel' : undefined,
    typed: false,
  });
  if (answer !== 'confirm') return { ok: false, reason: 'cancelled' };
  const confirmationName = plan.confirmationName;
  let sent = false;
  try {
    entraConfirmation(plan);
    if (entra.required && !entraConfirmed) throw Object.assign(new Error('Le retrait Entra n’a pas été confirmé.'), { code: 'plan.entraConfirmation' });
    sent = true;
    const receipt = await call('operation.execute', { planId: plan.planId, confirmationName,
      ...(entra.required ? { entraLeaveConfirmed: true } : {}) });
    // A transport response is not proof about the confirmed target. Refuse a foreign or incomplete
    // receipt before showing success or letting the screen inspect the purported new name.
    if (!receiptMatchesPlan(receipt, plan))
      throw Object.assign(new Error('Le reçu retourné ne correspond pas au plan confirmé. Consultez les interventions avant toute nouvelle action.'), { code: 'receipt.identity' });
    announce(`Reçu ${receipt?.id ?? ''} : ${receipt?.status ?? 'état inconnu'}.`);
    return { ok: true, receipt };
  } catch (err) {
    if (isCollision(err)) return { ok: false, reason: 'collision', error: err };
    return { ok: false, reason: 'error', error: err, sent };
  }
}

/** Refusal line shown after a failed execute: collision wording is explicit (new preview + new click). */
export function refusalMarkup(err, { collision = false } = {}) {
  const text = errorText(err, 'Le moteur a refusé la demande.');
  return `<p class="muted" role="alert">${icon('alert')} ${esc(text)}
    ${collision ? ' Aucun ajout automatique : calculez un nouvel aperçu, puis cliquez de nouveau.' : ' Rien n’est rejoué automatiquement : consultez les interventions avant toute nouvelle action.'}</p>`;
}
