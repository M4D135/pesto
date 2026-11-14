// Demonstration controls use only the closed bridge. The native host owns the isolated window/profile.
import { openDialog, confirmDialog } from './kit/index.js';
import { esc, errorText, toast } from './ui.js';
import { refusal } from './refusal.js';
import { confirmAndExecute, receiptFeedback } from './writeflow.js';

export async function openDemonstration({ call, session, changed }) {
  try {
    if (session()?.mode !== 'simulation') {
      const opened = await call('demo.open');
      if (opened?.opened !== true) throw refusal('Le moteur n’a pas confirmé l’ouverture de la démonstration.');
      toast('Démonstration ouverte dans une fenêtre isolée. Votre contexte normal est conservé.');
      return;
    }
    const status = await call('demo.status');
    if (status?.mode !== 'simulation') throw refusal('Le moteur n’a pas confirmé le mode démonstration.');
    const body = document.createElement('div');
    const scenarios = Array.isArray(status.scenarios) ? status.scenarios : [];
    body.innerHTML = `<p class="k-dlg-text">${esc(status.message)}</p>
      <label class="field demo-scenario-label">Scénario
        <select class="input" name="demoScenario" aria-label="Scénario de démonstration">${scenarios.map((s) =>
          `<option value="${esc(s.id)}"${s.id === status.scenario ? ' selected' : ''}>${esc(s.label)}</option>`).join('')}</select>
      </label>
      <p class="muted small" data-demo-description></p>
      <p class="muted small">Poste fictif : <strong>${esc(status.localComputer)}</strong> · ${Number(status.pendingRestart) || 0} redémarrage(s) en attente.</p>
      <p class="muted small">Changer de scénario ou remettre à zéro efface uniquement le monde fictif de cette fenêtre. Les anciens plans restent invalides.</p>
      ${(status.remainingMoves ?? []).map((r) => `<section class="demo-remaining">
        <strong>Déplacement restant fictif · ${esc(r.newName)}</strong>
        <p class="muted small mono">${esc(r.targetOU)}</p>
        <button class="btn sm" type="button" data-demo-move="${esc(r.id)}"${r.restartRequired ? ' disabled' : ''}>Préparer le déplacement restant fictif</button>
        ${r.restartRequired ? '<p class="muted small">Effectuez d’abord le redémarrage fictif, puis rouvrez Scénarios.</p>' : ''}
      </section>`).join('')}`;
    const select = body.querySelector('[name="demoScenario"]');
    const describe = () => { body.querySelector('[data-demo-description]').textContent = scenarios.find((s) => s.id === select.value)?.description ?? ''; };
    select.addEventListener('change', describe); describe();
    const dialog = openDialog({
      title: 'Piloter la démonstration', subtitle: 'Aucun effet réel', icon: 'sparkles', size: 'lg', body,
      actions: [
        { id: 'close', label: 'Fermer', safe: true },
        { id: 'reset', label: 'Remettre à zéro' },
        { id: 'restart', label: 'Redémarrage fictif', disabled: !(status.pendingRestart > 0) },
        { id: 'scenario', label: 'Charger le scénario', primary: true },
      ],
    });
    let remaining = null;
    body.addEventListener('click', (event) => {
      const button = event.target.closest?.('[data-demo-move]');
      if (!button || button.disabled) return;
      remaining = status.remainingMoves.find((r) => r.id === button.dataset.demoMove);
      if (remaining) dialog.close('move');
    });
    const action = await dialog.result;
    if (action === 'move' && remaining) {
      const plan = await call('demo.prepareMove', { id: remaining.id });
      if (plan?.mode !== 'simulation' || plan.kind !== 'move' || plan.parentReceiptId !== remaining.id
        || plan.computer !== remaining.newName || plan.newName !== remaining.newName || plan.targetOU !== remaining.targetOU)
        throw refusal('Le plan fictif ne correspond pas au déplacement restant.');
      const outcome = await confirmAndExecute(call, plan, {
        title: 'Confirmer le déplacement fictif restant',
        message: 'Le nom fictif est conservé. Seule l’OU du monde de démonstration changera.',
        confirmLabel: 'Simuler ce déplacement',
      });
      if (outcome.ok) {
        const feedback = receiptFeedback(outcome.receipt);
        toast(feedback.text, { tone: feedback.tone });
        await changed('interventions');
      } else if (outcome.reason !== 'cancelled') throw outcome.error;
      return;
    }
    if (!['scenario', 'reset', 'restart'].includes(action)) return;
    const target = action === 'scenario' ? scenarios.find((s) => s.id === select.value) : null;
    if (action === 'scenario' && !target) throw refusal('Choisissez un scénario existant.');
    const confirmed = await confirmDialog({
      title: action === 'restart' ? 'Redémarrage fictif' : action === 'reset' ? 'Remettre la démonstration à zéro' : `Charger « ${target.label} »`,
      message: action === 'restart'
        ? 'Terminer les redémarrages en attente dans cette démonstration ? Aucun ordinateur réel ne redémarrera. Les résultats incertains restent incertains.'
        : 'Les opérations, reçus et paramètres fictifs de cette fenêtre seront réinitialisés. Votre session et votre configuration réelles sont conservées.',
      confirmLabel: action === 'restart' ? 'Simuler le redémarrage' : action === 'reset' ? 'Remettre à zéro' : 'Charger le scénario',
    });
    if (!confirmed) return;
    let result;
    if (action === 'restart') result = await call('demo.restart', { confirmed: true });
    else if (action === 'reset') result = await call('demo.reset', { confirmed: true });
    else result = await call('demo.scenario', { id: target.id, confirmed: true });
    await changed(action === 'restart' ? 'interventions' : result.page ?? 'accueil');
    toast(action === 'restart' ? 'Redémarrage fictif effectué ; aucun effet sur Windows.' : 'Le monde fictif est prêt. Les anciens plans ont été invalidés.');
  } catch (error) {
    toast(errorText(error, 'La démonstration n’a pas pu être mise à jour.'), { tone: 'alert' });
  }
}
