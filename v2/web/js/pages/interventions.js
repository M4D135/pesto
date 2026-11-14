// Interventions : reçus de la session via receipts.list / receipts.get. Un reçu est une preuve lue du moteur, jamais
// une invention de l'interface : statut, mode et message sont affichés tels que reçus. Le paramètre ?query= filtre
// depuis la palette ou le shell. Une vérification explicite relit un état en attente/incertain, sans aucun rejeu.
import { icon } from '../icons.js';
import { esc, applyVars, reveal, errorText, announce, formatDateTime } from '../ui.js';
import { refusal } from '../refusal.js';
import { pill, copyButton, bindCopy } from '../kit/index.js';
import { KIND_LABEL, confirmAndExecute, receiptFeedback } from '../writeflow.js';
import { reservationMarkup, mountReservations } from './reservation-panel.js';
import { receiptActionsMarkup, canAcknowledgeReceipt, canRestartReceipt, acknowledgeReceipt, restartFromReceipt } from './receipt-actions.js';
import { attributeChangesMarkup, attributeObservationMatches } from './attributs.js';

const STATUS = {
  simulated: ['info', 'Simulé', 'sparkles'],
  succeeded: ['ok', 'Réussi', 'check'],
  pendingRestart: ['warn', 'Redémarrage en attente', 'power'],
  refused: ['alert', 'Refusé', 'x'],
  uncertain: ['warn', 'Incertain', 'eye'],
};

// receipts.list matches internal codes only, while cards show French labels: a typed label (or the start of one of
// its words, accents ignored) is resolved here against these same tables, so the filter finds what is displayed.
const fold = (text) => String(text ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
const labelMatches = (label, q) => { const l = fold(label); return l.startsWith(q) || l.includes(` ${q}`); };

function labelFilter(query) {
  const q = fold(query);
  if (q.length < 3) return null;
  const statuses = Object.keys(STATUS).filter((code) => labelMatches(STATUS[code][1], q));
  const kinds = Object.keys(KIND_LABEL).filter((code) => labelMatches(KIND_LABEL[code], q));
  return statuses.length || kinds.length ? { statuses, kinds } : null;
}

function canPrepareRemainingMove(r, liveSession, moveEnabled) {
  return liveSession && moveEnabled && r?.readable !== false && typeof r?.mode === 'string' && r.mode !== 'simulation'
    && r.kind === 'renameMove' && String(r.code) === '89' && ['pendingRestart', 'uncertain'].includes(r.status)
    && r.resolutionChildReceiptId == null && typeof r.newName === 'string' && !!r.newName && typeof r.targetOU === 'string' && !!r.targetOU;
}

function remainingMovePlanMatches(plan, parent) {
  return plan?.kind === 'move' && plan.mode === 'live' && plan.parentReceiptId === parent.id
    && plan.computer === parent.newName && plan.newName === parent.newName && plan.confirmationName === parent.newName
    && plan.targetOU === parent.targetOU;
}

function receiptCard(r, liveSession = false, moveEnabled = false, session = null) {
  const [tone, label, ic] = STATUS[r.status] ?? ['off', String(r.status ?? 'inconnu'), 'info'];
  if (r.readable === false) {
    return `<article class="card reveal spot" data-receipt="${esc(r.id)}" data-tone="alert">
      <div class="card-head"><span class="card-icon">${icon('alert')}</span>
        <h3>Fichier de reçu illisible · ${esc(r.computer)}</h3>
        <span class="meta">${pill('alert', 'Illisible', { icon: 'alert' })}</span></div>
      <div class="kv-grid">
        <span class="k">Fichier</span><span class="v mono">${esc(r.id)}</span>
        <span class="k">Consigne</span><span class="v">${esc(r.message ?? '')}</span>
      </div>
    </article>`;
  }
  const legacyAttributes = r.kind === 'attributes' && r.mode !== 'live' && !r.mode?.startsWith('live · ');
  const canVerify = liveSession && r.mode !== 'simulation' && r.kind !== 'offlineJoin' && !legacyAttributes && ['pendingRestart', 'uncertain'].includes(r.status) && !r.resolutionChildReceiptId;
  const canPrepareMove = canPrepareRemainingMove(r, liveSession, moveEnabled);
  const ack = r.acknowledged ? ` ${pill('off', 'Acquittée', { icon: 'eye' })}` : '';
  return `<article class="card reveal spot" data-receipt="${esc(r.id)}" data-status="${esc(r.status)}" data-mode="${esc(r.mode)}">
    <div class="card-head"><span class="card-icon">${icon(r.mode === 'simulation' ? 'sparkles' : 'shield')}</span>
      <h3>${esc(KIND_LABEL[r.kind] ?? r.kind)} · ${esc(r.computer)}${r.newName && r.newName !== r.computer ? ` → ${esc(r.newName)}` : ''}</h3>
      <span class="meta">${pill(tone, label, { icon: ic })}${ack}</span></div>
    <div class="kv-grid">
      <span class="k">Reçu</span><span class="v mono">${esc(r.id)}</span>
      <span class="k">Heure</span><span class="v">${esc(formatDateTime(r.time) ?? 'inconnue')}</span>
      <span class="k">Mode</span><span class="v">${r.mode === 'simulation' ? 'Simulation (aucun effet réel)' : esc(r.mode ?? 'inconnu')}</span>
      <span class="k">OU</span><span class="v mono">${esc(r.targetOU || '—')}</span>
      <span class="k">Message</span><span class="v">${esc(r.message ?? '')}</span>
    </div>
    ${r.kind === 'attributes' ? attributeChangesMarkup(r.attributeChanges) : ''}
    ${legacyAttributes ? '<p class="muted small">Ce reçu attributs V1 reste consultable. La vérification V2 ne transforme pas une preuve historique V1.</p>' : ''}
    <div class="row-actions">${copyButton(r.id, { label: 'Copier l’identifiant' })}
      <button class="btn ghost sm" type="button" data-act="detail">Détail moteur</button>
      ${canVerify ? `<button class="btn sm" type="button" data-act="verify">${icon('refresh')}Vérifier l’état</button>` : ''}</div>
    ${liveSession && r.kind === 'offlineJoin' ? `<div class="row-actions"><button class="btn" type="button" data-act="offline-open">${icon('power')}Ouvrir la vérification hors ligne</button></div><p class="muted small">Après redémarrage, observez explicitement cette jonction depuis sa fenêtre locale. Aucun blob n’est rejoué.</p>` : ''}
    ${canVerify ? '<p class="muted small">Relit l’état observé. Aucune opération n’est relancée et aucun redémarrage n’est déclenché.</p>' : ''}
    ${canPrepareMove ? `<div class="row-actions"><button class="btn sm" type="button" data-act="prepare-move">${icon('folder')}Préparer le déplacement restant</button></div>
      <p class="muted small">Vérifie que le renommage et le redémarrage sont achevés, puis propose uniquement le déplacement vers la destination prévue. Vous devrez confirmer le nouveau plan.</p>` : ''}
    ${r.parentReceiptId ? `<p class="muted small">Suite du reçu <span class="mono">${esc(r.parentReceiptId)}</span>.</p>` : ''}
    ${r.resolutionChildReceiptId ? `<p class="muted small" data-resolution>Déplacement restant confirmé par le reçu <span class="mono">${esc(r.resolutionChildReceiptId)}</span>. Le reçu initial conserve son historique.</p>` : ''}
    ${receiptActionsMarkup(r, session)}
  </article>`;
}

function persistentNote(meta) {
  if (!meta) return '';
  const bits = [];
  if (meta.persistent) bits.push(`Historique durable : ${meta.persistent}`);
  if (meta.invalidCount) bits.push(`${meta.invalidCount} fichier(s) illisible(s) isolé(s) sous leur nom — aucun verrou levé`);
  if (meta.truncated) bits.push('liste tronquée à la borne v1 de 5 000 fichiers par dossier');
  return bits.length ? `<p class="muted small">${esc(bits.join(' · '))}</p>` : '';
}

function layout(query) {
  return `<div class="page">
    <header class="page-header reveal">
      <div class="head-row"><span class="page-icon">${icon('activity')}</span>
        <div class="titles"><h1 class="gradient-text">Interventions</h1>
          <p class="subtitle">Reçus lus du moteur. Un résultat incertain n’est jamais rejoué automatiquement.</p></div></div>
      <div class="actions"><button class="btn" type="button" data-act="refresh">${icon('refresh')}Rafraîchir</button></div>
    </header>
    <section class="card reveal spot">
      <div class="card-head"><span class="card-icon">${icon('search')}</span><h3>Filtrer</h3></div>
      <form class="k-form" novalidate data-form="q">
        <div class="k-field"><input class="input mono" type="search" name="query" placeholder="nom, reçu, statut…" value="${esc(query)}" aria-label="Filtrer les interventions"></div>
      </form>
    </section>
    <div data-zone="list" aria-busy="true" aria-live="polite"><p class="muted">Lecture des reçus…</p></div>
    ${reservationMarkup()}
  </div>`;
}

export function render(main, ctx) {
  main.innerHTML = layout(ctx.params?.query ?? '');
  applyVars(main);
  const stops = [reveal(main), mountReservations(main, ctx)];
  let alive = true;
  let latest = 0;
  const receiptsById = new Map();
  const focusRecords = new WeakMap();
  const list = main.querySelector('[data-zone="list"]');

  async function load(query) {
    const my = ++latest;
    list.setAttribute('aria-busy', 'true');
    try {
      const byLabel = query ? labelFilter(query) : null;
      const result = await ctx.call('receipts.list', query && !byLabel ? { query } : {});
      let items = result?.items;
      if (byLabel && Array.isArray(items)) {
        const q = query.toLowerCase();
        items = items.filter((r) => byLabel.statuses.includes(r.status) || byLabel.kinds.includes(r.kind)
          || `${r.computer} ${r.newName} ${r.status} ${r.id} ${r.message ?? ''}`.toLowerCase().includes(q));
      }
      if (!alive || my !== latest) return;
      receiptsById.clear();
      for (const receipt of items ?? []) receiptsById.set(receipt.id, receipt);
      if (!items?.length) {
        list.innerHTML = `<p class="muted">Aucun reçu pour ce filtre. Les écritures de la session et les reçus durables relus apparaîtront ici, marqués selon leur mode.</p>${persistentNote(result)}`;
      } else {
        list.innerHTML = items.map((r) => receiptCard(r, ctx.session()?.mode === 'live', ctx.capability('move').enabled === true, ctx.session())).join('') + persistentNote(result);
        bindCopy(list);
      }
      list.removeAttribute('aria-busy');
      applyVars(main);
      stops.push(reveal(main));
    } catch (err) {
      if (!alive || my !== latest) return;
      list.innerHTML = `<p class="muted" role="alert">${icon('alert')} ${esc(errorText(err))}</p>`;
      list.removeAttribute('aria-busy');
    }
  }

  function feedback(card, text, failed = false) {
    card.querySelector('[data-verification]')?.remove();
    const message = document.createElement('p');
    message.className = 'muted small';
    message.dataset.verification = '';
    message.setAttribute('role', failed ? 'alert' : 'status');
    message.textContent = text;
    card.appendChild(message);
    announce(text, { assertive: failed });
  }

  function replaceCard(card, receipt) {
    receiptsById.set(receipt.id, receipt);
    const template = document.createElement('template');
    template.innerHTML = receiptCard(receipt, ctx.session()?.mode === 'live', ctx.capability('move').enabled === true, ctx.session()).trim();
    const next = template.content.firstElementChild;
    // Swapping the article drops keyboard focus to <body>: keep it on the same action, or inside the new card.
    // Disabled buttons already lost focus to <body> while the engine answered, so the click handler's record counts too,
    // unless the user has since moved focus elsewhere.
    const active = document.activeElement;
    const held = card.contains(active) ? active.dataset?.act ?? '' : null;
    const recorded = focusRecords.get(card);
    const act = held ?? (recorded !== undefined && (!active || active === document.body) ? recorded : null);
    card.replaceWith(next);
    bindCopy(next);
    applyVars(next);
    stops.push(reveal(list));
    if (act !== null) {
      const target = (act && next.querySelector(`button[data-act="${CSS.escape(act)}"]`)) || next.querySelector('button') || next;
      if (target === next) next.tabIndex = -1;
      target.focus({ preventScroll: true });
    }
    return next;
  }

  async function prepareRemainingMove(card, parent, revision) {
    const stale = () => !alive || revision !== latest || !card.isConnected;
    feedback(card, 'Vérification du renommage et préparation du déplacement restant…');
    const plan = await ctx.call('receipts.prepareMove', { id: parent.id });
    if (stale()) return;
    if (!remainingMovePlanMatches(plan, parent)) {
      feedback(card, 'Le moteur n’a pas renvoyé un plan de déplacement lié à ce reçu. Aucune exécution n’a été demandée.', true);
      return;
    }
    const guardedCall = (op, args) => {
      if (stale() || !canPrepareRemainingMove(parent, ctx.session()?.mode === 'live', ctx.capability('move').enabled === true)) {
        throw refusal('Le contexte a changé. Relisez le reçu avant de préparer un nouveau déplacement.');
      }
      return ctx.call(op, args);
    };
    const outcome = await confirmAndExecute(guardedCall, plan, {
      title: 'Confirmer le déplacement restant',
      message: 'Le nom est conservé. Vérifiez la destination : seul cet objet sera déplacé.',
      targetKind: 'le nom actuel du poste',
      changes: [{ label: 'Poste', after: plan.computer }, { label: 'OU de destination', after: plan.targetOU }],
      confirmLabel: 'Confirmer le déplacement',
    });
    if (stale()) return;
    if (!outcome.ok) {
      feedback(card, outcome.reason === 'cancelled' ? 'Confirmation annulée : aucun déplacement envoyé.' : errorText(outcome.error), outcome.reason !== 'cancelled');
      return;
    }
    const child = outcome.receipt;
    if (!child?.id || child.id === parent.id || child.parentReceiptId !== parent.id || child.kind !== 'move'
      || typeof child.mode !== 'string' || child.mode === 'simulation' || child.computer !== plan.computer || child.newName !== plan.newName || child.targetOU !== plan.targetOU) {
      feedback(card, 'Le résultat reçu ne permet pas de relier le déplacement au reçu initial. Son état reste inchangé ; relisez les interventions.', true);
      return;
    }
    const template = document.createElement('template');
    template.innerHTML = receiptCard(child, true, ctx.capability('move').enabled === true, ctx.session()).trim();
    const childCard = template.content.firstElementChild;
    card.after(childCard);
    receiptsById.set(child.id, child);
    bindCopy(childCard); applyVars(childCard); stops.push(reveal(list));
    const result = receiptFeedback(child);
    feedback(card, result.text, child.status === 'refused');
    if (!result.confirmed || child.status !== 'succeeded' || child.restartRequired !== false) return;
    // A successful child receipt does not rewrite its parent: only a fresh server link resolves the remaining move.
    try {
      const refreshed = await ctx.call('receipts.get', { id: parent.id });
      if (stale()) return;
      if (refreshed?.id === parent.id && refreshed.readable !== false && refreshed.mode !== 'simulation'
        && refreshed.computer === parent.computer && refreshed.newName === parent.newName && refreshed.targetOU === parent.targetOU
        && refreshed.kind === 'renameMove' && String(refreshed.code) === '89'
        && ['pendingRestart', 'uncertain'].includes(refreshed.status) && refreshed.resolutionChildReceiptId === child.id) {
        const next = replaceCard(card, refreshed);
        feedback(next, `Déplacement restant confirmé par le reçu ${child.id}.`);
      } else {
        feedback(card, 'Le déplacement a renvoyé un reçu confirmé. Le lien avec le reçu initial reste à vérifier.');
      }
    } catch (err) {
      if (!stale()) feedback(card, `Le déplacement a renvoyé un reçu confirmé, mais le reçu initial n’a pas pu être relu. ${errorText(err)}`, true);
    }
  }

  // Delegation keeps actions usable after a receipt is re-read or replaced by a verified result.
  list.addEventListener('click', async (event) => {
    const button = event.target instanceof Element ? event.target.closest('button[data-act]') : null;
    if (!button || button.disabled || !['detail', 'verify', 'prepare-move', 'prepare-acknowledgement', 'prepare-restart', 'offline-open'].includes(button.dataset.act)) return;
    const card = button.closest('[data-receipt]');
    if (!card || card.getAttribute('aria-busy') === 'true') return;
    const id = card.dataset.receipt;
    const verifying = button.dataset.act === 'verify';
    const preparingMove = button.dataset.act === 'prepare-move';
    const parent = receiptsById.get(id);
    const acknowledging = button.dataset.act === 'prepare-acknowledgement';
    const restarting = button.dataset.act === 'prepare-restart';
    if ((acknowledging && !canAcknowledgeReceipt(parent, ctx.session())) || (restarting && !canRestartReceipt(parent, ctx.session()))) return;
    if (preparingMove && (list.getAttribute('aria-busy') === 'true'
      || !canPrepareRemainingMove(parent, ctx.session()?.mode === 'live', ctx.capability('move').enabled === true))) return;
    if (verifying && (ctx.session()?.mode !== 'live' || card.dataset.mode === 'simulation' || !['pendingRestart', 'uncertain'].includes(card.dataset.status))) return;
    const revision = latest;
    const controls = [...card.querySelectorAll('button')].map((el) => [el, el.disabled]);
    // Record focus before disabling: Chromium then moves the focused, now disabled button's focus to <body>.
    if (card.contains(document.activeElement)) focusRecords.set(card, document.activeElement.dataset?.act ?? '');
    controls.forEach(([el]) => { el.disabled = true; });
    card.setAttribute('aria-busy', 'true');
    if (verifying) feedback(card, 'Vérification de l’état en cours…');
    try {
      if (button.dataset.act === 'offline-open') {
        if (ctx.session()?.mode !== 'live' || parent?.kind !== 'offlineJoin') return;
        await ctx.call('offlineJoin.open');
        if (alive && card.isConnected) feedback(card, 'Fenêtre locale demandée. La vérification après redémarrage reste à lancer explicitement dans cette fenêtre.');
        return;
      }
      if (acknowledging || restarting) {
        feedback(card, acknowledging ? 'Vérification des preuves pour l’acquittement…' : 'Vérification du poste avant proposition de redémarrage…');
        const context = { call: ctx.call, session: ctx.session,
          isCurrent: () => alive && revision === latest && card.isConnected && list.getAttribute('aria-busy') !== 'true' };
        const result = await (acknowledging ? acknowledgeReceipt(parent, context) : restartFromReceipt(parent, context));
        if (context.isCurrent()) {
          if (result) { const next = replaceCard(card, result.receipt); feedback(next, result.message); }
          else feedback(card, 'Confirmation annulée : aucune action envoyée.');
        }
        return;
      }
      if (preparingMove) { await prepareRemainingMove(card, parent, revision); return; }
      if (verifying && parent?.kind === 'attributes') {
        if (parent.mode !== 'live' && !parent.mode?.startsWith('live · ')) throw Object.assign(new Error('Ce reçu historique ne possède pas de plan attributs V2 vérifiable.'), { code: 'ui.attributes' });
        const observed = await ctx.call('attributes.observe', { id });
        if (!alive || revision !== latest || !card.isConnected) return;
        const next = observed?.receipt;
        if (observed?.targetReadOnly !== true || observed.replayAllowed !== false || next?.id !== id || next.kind !== 'attributes'
          || next.computer !== parent.computer || next.targetOU !== parent.targetOU || next.restartRequired === true
          || (next.mode !== 'live' && !next.mode?.startsWith('live · ')) || (next.newName && next.newName !== parent.computer))
          throw Object.assign(new Error('La réponse ne correspond pas à l’observation de ce reçu attributs.'), { code: 'ui.attributes' });
        const exact = Array.isArray(parent.attributeChanges) && Array.isArray(next.attributeChanges)
          && next.attributeChanges.length === parent.attributeChanges.length
          && new Set(next.attributeChanges.map(c => c.attribute)).size === next.attributeChanges.length
          && parent.attributeChanges.every(c => next.attributeChanges.some(n => n.attribute === c.attribute && n.before === c.before && n.after === c.after
            && (n.referenceGuid ?? '').toLowerCase() === (c.referenceGuid ?? '').toLowerCase()))
          && attributeObservationMatches(observed.observation, { computer: parent.computer, computerGuid: parent.computerGuid,
            domain: parent.domain, dc: parent.dc, ou: parent.targetOU }, parent.attributeChanges);
        if (observed.verified === true && (next.status !== 'succeeded' || String(next.code) !== '30' || !exact))
          throw Object.assign(new Error('L’observation ne prouve pas l’identité et le diff complets de ce reçu. Aucun succès affiché.'), { code: 'ui.attributes' });
        if (observed.verified === true && exact) {
          const changed = replaceCard(card, next); feedback(changed, 'Attributs confirmés par observation durable. Aucune modification AD rejouée.');
        } else feedback(card, observed.reason || 'Valeurs non confirmées ; le reçu et les barrières restent inchangés.');
        return;
      }
      const receipt = verifying ? await ctx.call('receipts.reconcile', { id }) : await ctx.call('receipts.get', { id });
      if (!alive || revision !== latest || !card.isConnected) return;
      if (!receipt || receipt.id !== id) {
        feedback(card, 'Le moteur n’a pas renvoyé le reçu attendu. Le reçu affiché reste inchangé.', true);
        return;
      }
      if (!verifying) {
        const same = JSON.stringify(receiptsById.get(id)) === JSON.stringify(receipt);
        const next = replaceCard(card, receipt);
        feedback(next, same ? 'Reçu relu auprès du moteur : aucun changement.' : 'Reçu relu auprès du moteur : affichage mis à jour.');
      } else if (receipt.verified === false) {
        feedback(card, `État non confirmé. ${receipt.reason || 'La lecture reste incomplète ; le reçu conserve son état.'}`);
      } else if (receipt.verified === true && ctx.session()?.mode === 'live' && receipt.mode !== 'simulation' && receipt.status === 'succeeded' && receipt.restartRequired === false) {
        const next = replaceCard(card, receipt);
        feedback(next, `État confirmé. ${receipt.reason || 'Le moteur a relu l’état attendu ; le reçu est mis à jour.'}`);
      } else {
        feedback(card, 'La vérification n’a pas renvoyé un état confirmé exploitable. Le reçu affiché reste inchangé.', true);
      }
    } catch (err) {
      if (alive && revision === latest && card.isConnected) feedback(card, errorText(err), true);
    } finally {
      const act = focusRecords.get(card);
      focusRecords.delete(card);
      if (card.isConnected) {
        card.removeAttribute('aria-busy');
        controls.forEach(([el, disabled]) => { el.disabled = disabled; });
        // The card was kept: give focus back to the re-enabled action if nothing else took it meanwhile.
        const back = act ? card.querySelector(`button[data-act="${CSS.escape(act)}"]`) : null;
        if (back && !back.disabled && (!document.activeElement || document.activeElement === document.body)) back.focus({ preventScroll: true });
      }
    }
  });

  const qInput = main.querySelector('[name="query"]');
  main.querySelector('[data-form="q"]').addEventListener('submit', (e) => { e.preventDefault(); load(qInput.value.trim()); });
  let deb = 0;
  qInput.addEventListener('input', () => { clearTimeout(deb); deb = setTimeout(() => load(qInput.value.trim()), 350); });
  main.querySelector('[data-act="refresh"]').addEventListener('click', () => load(qInput.value.trim()));

  ctx.setScreenCommands([
    { id: 'interventions-refresh', kind: 'command', label: 'Relire les interventions', icon: 'refresh', group: 'Interventions', effect: 'read', available: true, detailText: 'Relit les reçus auprès du moteur.', run: () => load(qInput.value.trim()) },
  ]);

  load(qInput.value.trim());
  return () => { alive = false; latest++; clearTimeout(deb); ctx.setScreenCommands([]); stops.forEach((stop) => stop()); };
}
