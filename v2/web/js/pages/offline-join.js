import { icon } from '../icons.js';
import { esc, applyVars, reveal, errorText, announce, formatDateTime } from '../ui.js';
import { field, confirmWrite, pill } from '../kit/index.js';
import { receiptMarkup, refusalMarkup } from '../writeflow.js';

export const meta = { label: 'Jonction hors ligne', icon: 'power' };
const states = { Importing: 'Import incomplet', Imported: 'Import protégé', Requested: 'Application engagée', PendingRestart: 'Redémarrage requis', Uncertain: 'Résultat incertain', Verified: 'Jonction vérifiée', Unreadable: 'Journal illisible' };
const invalid = message => Object.assign(new Error(message), { code: 'ui.offlineJoin' });
const equal = (a, b) => typeof a === 'string' && typeof b === 'string' && a.toLowerCase() === b.toLowerCase();

export function render(main, ctx) {
  main.innerHTML = `<div class="page"><header class="page-header reveal"><div class="head-row"><span class="page-icon">${icon('power')}</span>
    <div class="titles"><h1 class="gradient-text">Jonction hors ligne</h1><p class="subtitle">Appliquer une seule fois un blob provisionné pour le nom actuel de ce PC, puis vérifier la jonction après redémarrage.</p></div></div>
    <div class="actions"><button class="btn" type="button" data-refresh>${icon('refresh')}Relire l’état local</button></div></header>
    <section class="card reveal spot" data-local aria-live="polite"><p class="muted">Lecture locale…</p></section>
    <section class="card reveal spot"><div class="card-head"><span class="card-icon">${icon('file')}</span><h3>Importer un blob local</h3></div>
      <p class="muted">Indiquez les références fournies lors du provisionnement. Leur présence dans AD n’est pas vérifiée à l’import. Le fichier est choisi dans une fenêtre Windows ; son contenu reste hors de l’interface.</p>
      <form class="k-form" data-import-form>
        ${field({ name: 'objectGuid', label: 'GUID AD déclaré du compte provisionné', required: true, maxLength: 36, mono: true, placeholder: '11111111-2222-3333-4444-555555555555' })}
        ${field({ name: 'targetOU', label: 'OU AD déclarée', required: true, maxLength: 2048, mono: true, placeholder: 'OU=Postes,DC=exemple,DC=local' })}
      </form><div class="row-actions"><button class="btn primary" type="button" data-import disabled>${icon('file')}Choisir et importer un blob…</button></div>
      <div data-import-result role="status"></div></section>
    <section class="card reveal spot"><div class="card-head"><span class="card-icon">${icon('activity')}</span><h3>Imports et reçus locaux</h3></div><div data-items aria-live="polite"></div></section>
    <section class="card reveal spot" data-plan hidden aria-live="polite"></section><section data-result aria-live="polite"></section>
    <p class="muted small">Aucun renommage et aucun redémarrage implicite. Dès l’intention d’application consignée, le blob ne peut plus être rejoué, même après une interruption. Un contrôle incomplet conserve l’état incertain.</p></div>`;
  applyVars(main); const stop = reveal(main);
  const localZone = main.querySelector('[data-local]'), itemsZone = main.querySelector('[data-items]');
  const planZone = main.querySelector('[data-plan]'), resultZone = main.querySelector('[data-result]');
  const importForm = main.querySelector('[data-import-form]'), importButton = main.querySelector('[data-import]');
  const refreshButton = main.querySelector('[data-refresh]'), importResult = main.querySelector('[data-import-result]');
  let alive = true, busy = false, revision = 0, current = null, selected = null;
  function paintBusy(value) {
    busy = value; refreshButton.disabled = value;
    importButton.disabled = value || current?.available !== true;
    importForm.querySelectorAll('input').forEach(el => { el.disabled = value || current?.available !== true; });
    itemsZone.querySelectorAll('button').forEach(el => { el.disabled = value || el.dataset.allowed !== 'true'; });
    planZone.querySelectorAll('button').forEach(el => { el.disabled = value || !selected; });
  }
  function clearPlan() { selected = null; planZone.hidden = true; planZone.innerHTML = ''; }
  function publicItem(item) {
    if (!item || typeof item.id !== 'string' || item.replayAllowed !== false) throw invalid('Le registre local n’a pas renvoyé une identité de blob non rejouable.');
    return item;
  }
  async function load() {
    if (busy) return; revision++; clearPlan(); paintBusy(true);
    try {
      if (ctx.session()?.mode !== 'offline' || ctx.session()?.localOnly !== true) throw invalid('Ouvrez la fenêtre locale avec le bouton Jonction hors ligne ou Pesto.exe --offline-join.');
      const status = await ctx.call('offlineJoin.list'); if (!alive) return;
      if (!status?.local || !Array.isArray(status.items) || typeof status.available !== 'boolean') throw invalid('État local incomplet. Aucune application proposée.');
      status.items.forEach(publicItem); current = status; const local = status.local;
      localZone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('monitor')}</span><h3>Ce PC : ${esc(local.computer || 'inconnu')}</h3></div>
        <div class="kv-grid">${[['Nom Windows actif', local.activeName], ['Nom Windows configuré', local.configuredName], ['Identité machine', local.machineId],
        ['Appartenance locale', local.partOfDomain === true ? `Domaine : ${local.domain}` : local.partOfDomain === false ? `Groupe de travail : ${local.domain}` : 'Inconnue'],
        ['Démarrage observé', formatDateTime(local.bootUtc)], ['Administrateur local', local.administrator === true ? 'Confirmé' : 'Non confirmé']]
        .map(([k,v]) => `<span class="k">${esc(k)}</span><span class="v mono">${esc(v || 'inconnu')}</span>`).join('')}</div>
        ${status.reason ? `<p class="muted" role="status">${esc(status.reason)}</p>` : '<p class="muted small">L’import est disponible. La jonction exigera encore un plan et votre confirmation.</p>'}`;
      itemsZone.innerHTML = status.items.length ? status.items.map(item => `<article class="offline-item" data-item="${esc(item.id)}"><div class="card-head"><h3>${esc(item.computer || 'Import à examiner')}</h3>
        <span class="meta">${pill(item.state === 'Verified' ? 'ok' : item.state === 'Imported' ? 'info' : 'warn', states[item.state] || 'État inconnu')}</span></div>
        <div class="kv-grid">${[['Identifiant du blob', item.id], ['Domaine', item.domain], [item.identityDeclared ? 'GUID AD déclaré, non vérifié' : 'GUID AD vérifié', item.expectedAdGuid],
        [item.identityDeclared ? 'OU déclarée, non vérifiée' : 'OU vérifiée', item.targetOU], ['Import valable jusqu’à', formatDateTime(item.expiresAt)], ['Reçu', item.receiptId || 'Aucune application']]
        .map(([k,v]) => `<span class="k">${esc(k)}</span><span class="v mono">${esc(v || 'inconnu')}</span>`).join('')}</div><p class="muted small">${esc(item.message)}</p>
        <div class="row-actions">${item.canPrepare ? `<button class="btn primary" type="button" data-prepare="${esc(item.id)}" data-allowed="${status.available === true}">Préparer l’application locale</button>` : ''}
        ${item.canObserve ? `<button class="btn" type="button" data-observe="${esc(item.id)}" data-allowed="true">Observer après redémarrage — accès AD</button>` : ''}</div></article>`).join('') : '<p class="muted">Aucun blob importé sur cette machine.</p>';
      applyVars(main);
    } catch (error) { if (alive) { current = null; localZone.innerHTML = refusalMarkup(error); } }
    finally { if (alive) paintBusy(false); }
  }
  importButton.addEventListener('click', async () => {
    if (busy || current?.available !== true || !importForm.reportValidity()) return;
    const computer = current.local.computer, mine = revision;
    const fields = () => ({ objectGuid: importForm.elements.objectGuid.value.trim(), targetOU: importForm.elements.targetOU.value.trim() });
    const input = fields();
    const answer = await confirmWrite({ title: 'Importer un blob pour ce PC', badge: 'Copie locale protégée — aucun accès AD', target: computer, targetKind: 'le nom Windows actuel',
      message: 'L’import conserve une copie protégée du blob. Il n’applique aucune jonction. Le GUID et l’OU ci-dessous sont vos références déclarées, qui seront contrôlées dans AD après redémarrage.',
      changes: [{ label: 'Nom local conservé', after: computer }, { label: 'GUID AD déclaré', after: input.objectGuid }, { label: 'OU déclarée', after: input.targetOU }],
      typed: false, confirmLabel: 'Choisir le fichier et importer' });
    if (answer !== 'confirm' || !alive) return;
    if (revision !== mine || current?.available !== true || JSON.stringify(fields()) !== JSON.stringify(input)) {
      importResult.innerHTML = refusalMarkup(invalid('Le contexte ou les références ont changé. Recommencez l’import.')); return;
    }
    paintBusy(true); clearPlan();
    try {
      const result = await ctx.call('offlineJoin.import', { ...input, confirmed: true });
      if (!alive) return;
      if (result?.status === 'cancelled') importResult.textContent = 'Sélection annulée : aucun blob importé.';
      else if (result?.status === 'imported' && publicItem(result.item).computer === computer) importResult.textContent = result.message || 'Blob importé ; aucune application demandée.';
      else throw invalid('Import non confirmé. Relisez le registre local avant de recommencer.');
    } catch (error) { if (alive) importResult.innerHTML = refusalMarkup(error); }
    finally { if (alive) { paintBusy(false); await load(); } }
  });
  function validatePlan(plan, item) {
    if (!plan?.planId || plan.id !== item.id || plan.kind !== 'offlineJoin' || plan.mode !== 'offline' || plan.identityDeclared !== true || plan.requiresConfirmation !== true
      || plan.computer !== item.computer || plan.newName !== item.computer || plan.confirmationName !== item.computer || plan.computer !== current?.local.computer
      || plan.domain !== item.domain || !equal(plan.expectedAdGuid, item.expectedAdGuid) || plan.targetOU !== item.targetOU || !(Date.parse(plan.expiresAt) > Date.now()))
      throw invalid('La préparation ne correspond plus à cet import et au nom local. Aucun blob appliqué.');
  }
  function showResult(result, item, applying) {
    const receipt = result?.receipt, next = publicItem(result?.item);
    if (next.id !== item.id || next.computer !== item.computer || next.domain !== item.domain || next.targetOU !== item.targetOU
      || !equal(next.expectedAdGuid, item.expectedAdGuid) || next.receiptId !== receipt?.id || !receipt?.id || receipt.kind !== 'offlineJoin' || receipt.computer !== item.computer
      || receipt.newName !== item.computer || receipt.targetOU !== item.targetOU || receipt.mode !== 'live'
      || (item.receiptId && receipt.id !== item.receiptId) || (applying && receipt.status === 'succeeded')
      || (receipt.status === 'succeeded' && (next.state !== 'Verified' || next.identityDeclared !== false || receipt.restartRequired === true))
      || (result.verified === true && receipt.status !== 'succeeded'))
      throw invalid('La réponse ne prouve pas le résultat de ce blob. Consultez le registre local ; aucun nouvel envoi automatique.');
    resultZone.innerHTML = (result.verified === false && receipt.status === 'succeeded'
      ? `<p role="status">Le contrôle actuel n’a pas confirmé la jonction. La preuve historique reste conservée dans le registre local.</p>`
      : receiptMarkup(receipt)) + `<p class="muted" role="status">${esc(result.message)}</p>`;
    applyVars(resultZone); announce(result.message || 'Reçu de jonction hors ligne conservé.');
  }
  itemsZone.addEventListener('click', async event => {
    const button = event.target.closest('button[data-prepare],button[data-observe]');
    if (!button || button.disabled || busy || !current) return;
    const id = button.dataset.prepare || button.dataset.observe, item = current.items.find(entry => entry.id === id);
    if (!item) return; const mine = revision; clearPlan(); paintBusy(true);
    try {
      if (button.dataset.observe) {
        const result = await ctx.call('offlineJoin.observe', { id });
        if (alive && mine === revision) showResult(result, item, false);
      } else {
        if (current.available !== true || item.canPrepare !== true) return;
        const plan = await ctx.call('offlineJoin.prepare', { id });
        if (!alive || revision !== mine) return; validatePlan(plan, item); selected = plan;
        planZone.hidden = false; planZone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('shield')}</span><h3>Application préparée pour ${esc(plan.computer)}</h3></div>
          <p>Le nom reste <strong class="mono">${esc(plan.computer)}</strong>. Domaine : <strong>${esc(plan.domain)}</strong>.</p>
          <p class="muted small">GUID déclaré : ${esc(plan.expectedAdGuid)} · OU déclarée : ${esc(plan.targetOU)} · expiration : ${esc(formatDateTime(plan.expiresAt))}</p>
          ${(plan.warnings ?? []).map(w => `<p class="muted small">${esc(w)}</p>`).join('')}<button class="btn primary" type="button" data-apply>Confirmer et appliquer le blob</button>`;
        planZone.querySelector('[data-apply]').addEventListener('click', async () => {
          if (busy || selected !== plan) return;
          const answer = await confirmWrite({ title: 'Appliquer une jonction hors ligne réelle', badge: 'Modification locale de la jonction Windows', target: plan.confirmationName, targetKind: 'le nom actuel de ce PC',
            message: 'Cette demande modifie la configuration de jonction Windows de ce PC. Le blob est consommé dès l’intention durable. Le résultat final exigera un redémarrage manuel puis une observation AD explicite.',
            changes: [{ label: 'Poste local, sans renommage', after: plan.computer }, { label: 'Domaine prévu', after: plan.domain }, { label: 'GUID AD déclaré', after: plan.expectedAdGuid }, { label: 'OU déclarée', after: plan.targetOU }],
            warnings: plan.warnings ?? [], details: `Blob ${item.id} · plan ${plan.planId}`, typed: false, confirmLabel: 'Appliquer une seule fois' });
          if (answer !== 'confirm' || !alive) return;
          try {
            if (revision !== mine || selected !== plan) throw invalid('Le contexte local a changé ; préparez de nouveau.');
            validatePlan(plan, item); selected = null; paintBusy(true);
            const result = await ctx.call('offlineJoin.apply', { planId: plan.planId, confirmationName: plan.confirmationName, confirmed: true });
            if (alive) showResult(result, item, true);
          } catch (error) { if (alive) resultZone.innerHTML = refusalMarkup(error); }
          finally { if (alive) { clearPlan(); paintBusy(false); await load(); } }
        });
      }
    } catch (error) { if (alive) resultZone.innerHTML = refusalMarkup(error); }
    finally { if (alive) { paintBusy(false); if (button.dataset.observe) await load(); } }
  });
  importForm.addEventListener('submit', event => event.preventDefault());
  refreshButton.addEventListener('click', load);
  load();
  return () => { alive = false; revision++; stop(); };
}
