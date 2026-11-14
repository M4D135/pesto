// Explicit actions attached to one immutable business receipt. No implicit retry, reboot, or success projection.
import { icon } from '../icons.js';
import { esc, formatDateTime } from '../ui.js';
import { refusal } from '../refusal.js';
import { confirmWrite } from '../kit/index.js';

const phases = new Set(['Running', 'PendingRestart', 'Partial', 'MoveReady', 'Protection', 'Uncertain']);
const realMode = (mode) => mode === 'live' || (typeof mode === 'string' && mode.startsWith('live · '));
const v1Mode = (mode) => typeof mode === 'string' && mode.startsWith('V1 · ');
const hasText = (value) => typeof value === 'string' && value.length > 0;
const same = (left, right) => (left ?? null) === (right ?? null);

export function canAcknowledgeReceipt(receipt, session) {
  const capability = session?.capabilities?.find(item => item.id === 'acknowledge');
  const permitted = capability ? capability.enabled === true : session?.readOnly === false;
  return session?.mode === 'live' && permitted && (realMode(receipt?.mode) || v1Mode(receipt?.mode))
    && receipt.readable !== false && receipt.acknowledged !== true && !receipt.resolutionChildReceiptId
    && receipt.kind !== 'offlineJoin'
    && ['pendingRestart', 'uncertain'].includes(receipt.status);
}

export function canRestartReceipt(receipt, session) {
  const code = String(receipt?.code);
  const partial = receipt?.kind === 'renameMove' && code === '89';
  const accepted = receipt?.kind === 'join' && code === '10' || receipt?.kind === 'rename' && code === '20'
    || receipt?.kind === 'renameMove' && code === '77';
  return canAcknowledgeReceipt(receipt, session) && session.readOnly === false && realMode(receipt.mode)
    && (partial || accepted && receipt.status === 'pendingRestart') && receipt.restartRequired === true
    && !['requested', 'accepted', 'uncertain'].includes(receipt.restartRequest?.status);
}

export function receiptActionsMarkup(receipt, session) {
  const ack = canAcknowledgeReceipt(receipt, session), restart = canRestartReceipt(receipt, session);
  const evidence = receipt.acknowledgement;
  return `${ack || restart ? `<div class="row-actions">
    ${restart ? `<button class="btn sm" type="button" data-act="prepare-restart">${icon('power')}Préparer le redémarrage</button>` : ''}
    ${ack ? `<button class="btn ghost sm" type="button" data-act="prepare-acknowledgement">${icon('eye')}Acquitter sans valider</button>` : ''}</div>` : ''}
    ${ack ? '<p class="muted small">L’acquittement enregistre votre décision motivée. Il conserve le résultat réel, sans relancer ni valider l’opération.</p>' : ''}
    ${ack && v1Mode(receipt.mode) ? '<p class="muted small">Pour ce reçu V1, seule la décision Pesto V2 est enregistrée. Le fichier V1 et les barrières de l’ancien Pesto restent inchangés.</p>' : ''}
    ${evidence ? `<p class="muted small" data-acknowledgement>Acquittement du ${esc(formatDateTime(evidence.utc) ?? 'date inconnue')} par ${esc(evidence.by)} : ${esc(evidence.reason)}</p>` : ''}
    ${receipt.restartRequest ? `<p class="muted small" data-restart-request>Demande de redémarrage ${esc(receipt.restartRequest.id)} : ${esc({ accepted: 'acceptée', refused: 'refusée', uncertain: 'incertaine', requested: 'consignée' }[receipt.restartRequest.status] ?? 'à vérifier')}. Le résultat métier reste en attente de vérification après redémarrage.</p>` : ''}`;
}

function originalResultMatches(result, original) {
  return result && (realMode(result.mode) || (v1Mode(original.mode) && result.mode === original.mode)) && result.readable !== false
    && ['id', 'kind', 'computer', 'newName', 'targetOU', 'status', 'message', 'restartRequired', 'parentReceiptId', 'resolutionChildReceiptId']
      .every((key) => same(result[key], original[key])) && String(result.code) === String(original.code);
}

function validPlan(plan, receipt, action, session) {
  return plan?.action === action && plan.mode === 'live' && hasText(plan.planId) && plan.receiptId === receipt.id
    && plan.computer === receipt.computer && same(plan.newName, receipt.newName) && plan.domain === session?.domain
    && hasText(plan.confirmationName) && Date.parse(plan.expiresAt) > Date.now();
}

function staleError() { return refusal('Le contexte a changé : relisez le reçu et préparez une nouvelle action.'); }

export async function acknowledgeReceipt(receipt, context) {
  const { call, session, isCurrent } = context;
  if (!isCurrent() || !canAcknowledgeReceipt(receipt, session())) throw staleError();
  const plan = await call('receipts.prepareAcknowledgement', { id: receipt.id });
  if (!isCurrent()) return null;
  if (!validPlan(plan, receipt, 'acknowledge', session()) || !phases.has(plan.phase)
    || String(plan.code) !== String(receipt.code) || plan.confirmationName !== (receipt.newName || receipt.computer))
    throw refusal('Le plan d’acquittement ne correspond pas au reçu affiché. Aucune décision envoyée.');
  let reason = '';
  const answer = await confirmWrite({
    title: 'Acquitter sans valider l’opération', badge: 'Décision consignée dans le registre',
    message: 'Vous assumez la clôture administrative de cette alerte. Le statut, le code et les effets de l’opération restent inchangés. Aucune commande AD ni aucun redémarrage ne seront relancés. Les réservations et les tâches encore actives restent bloquantes.',
    target: plan.confirmationName, targetKind: 'le poste du reçu', targetDetail: plan.domain,
    changes: [{ label: 'Reçu', after: receipt.id }, { label: 'État conservé', after: `${receipt.status} · ${plan.phase} · code ${receipt.code}` }],
    warnings: [...(plan.warnings ?? []), ...(v1Mode(receipt.mode) ? ['Décision enregistrée dans Pesto V2 ; le reçu V1 et la barrière de l’ancien exécutable V1 restent inchangés.'] : [])],
    details: `Plan ${plan.planId} · expiration ${formatDateTime(plan.expiresAt)}`,
    reason: { label: 'Motif de l’acquittement', minLength: 3, maxLength: 500 },
    onReason: (value) => { reason = value; },
    typed: false,
    confirmLabel: 'Enregistrer l’acquittement',
  });
  if (answer !== 'confirm') return null;
  if (!isCurrent() || !canAcknowledgeReceipt(receipt, session()) || !(Date.parse(plan.expiresAt) > Date.now())) throw staleError();
  const result = await call('receipts.acknowledge', { planId: plan.planId, confirmationName: plan.confirmationName, reason });
  if (!isCurrent()) return null;
  const event = result?.acknowledgement;
  if (!originalResultMatches(result?.receipt, receipt) || result.receipt.acknowledged !== true || !event
    || !hasText(event.id) || !hasText(event.by) || !Number.isFinite(Date.parse(event.utc))
    || event.reason !== reason || event.phase !== plan.phase || String(event.code) !== String(receipt.code))
    throw refusal('La réponse ne prouve pas un acquittement lié au résultat original. Relisez les interventions avant toute nouvelle action.');
  return { receipt: { ...result.receipt, acknowledgement: event },
    message: 'Acquittement enregistré. Le résultat et les effets de l’opération restent inchangés.' };
}

export async function restartFromReceipt(receipt, context) {
  const { call, session, isCurrent } = context;
  if (!isCurrent() || !canRestartReceipt(receipt, session())) throw staleError();
  const plan = await call('receipts.prepareRestart', { id: receipt.id });
  if (!isCurrent()) return null;
  if (!validPlan(plan, receipt, 'restart', session()) || ![receipt.computer, receipt.newName].includes(plan.targetComputer)
    || !hasText(plan.targetComputer) || plan.confirmationName !== plan.targetComputer)
    throw refusal('Le plan ne prouve pas la cible du redémarrage. Aucune demande envoyée.');
  const answer = await confirmWrite({
    title: 'Confirmer le redémarrage du poste', badge: 'Redémarrage Windows explicite',
    message: 'Enregistrez votre travail et prévenez les utilisateurs du poste. Pesto demandera maintenant son redémarrage, sans forcer la fermeture des applications. Une demande acceptée ne prouve pas que le poste a redémarré ; son état devra être vérifié ensuite.'
      + (String(receipt.code) === '89' ? ' Le résultat partiel 89 reste conservé. Ce redémarrage ne relance pas le déplacement.' : ''),
    target: plan.targetComputer, targetKind: 'le poste à redémarrer maintenant', targetDetail: plan.domain,
    changes: [{ label: 'Reçu concerné', after: receipt.id }, { label: 'Nom actuellement prouvé', after: plan.targetComputer },
      { label: 'Nom demandé par l’opération', after: receipt.newName || receipt.computer }],
    warnings: plan.warnings ?? [], details: `Plan ${plan.planId} · expiration ${formatDateTime(plan.expiresAt)}`,
    typed: false, confirmLabel: 'Demander le redémarrage',
  });
  if (answer !== 'confirm') return null;
  if (!isCurrent() || !canRestartReceipt(receipt, session()) || !(Date.parse(plan.expiresAt) > Date.now())) throw staleError();
  const result = await call('receipts.restart', { planId: plan.planId, confirmationName: plan.confirmationName });
  if (!isCurrent()) return null;
  const restart = result?.restart;
  if (!originalResultMatches(result?.receipt, receipt) || !restart || !hasText(restart.id)
    || restart.computer !== plan.targetComputer || !['accepted', 'refused', 'uncertain'].includes(restart.status)
    || !Number.isFinite(Date.parse(restart.utc)))
    throw refusal('La réponse ne confirme pas l’état de la demande de redémarrage. Aucun nouvel envoi automatique ; relisez les interventions.');
  const message = restart.status === 'accepted'
    ? 'Demande de redémarrage acceptée. Vérifiez le poste après son retour ; l’opération reste en attente.'
    : restart.status === 'refused' ? 'Demande de redémarrage refusée. Consultez la raison avant toute nouvelle préparation.'
      : 'Demande de redémarrage incertaine. Aucun nouvel envoi : vérifiez le poste et conservez les preuves.';
  return { receipt: { ...result.receipt, restartRequest: restart }, message: message + (result.message ? ' ' + result.message : '') };
}
