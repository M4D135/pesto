import { openDialog } from './kit/index.js';
import { esc, errorText, toast } from './ui.js';

const LABELS = { CONF: 'Domaine et règles de fonctionnement', OUBase: 'Périmètres d’annuaire', OUSite: 'Structure des sites',
  TAGS: 'Correspondances des sites', POLICY: 'Politique des opérations', NamingConvention: 'Convention de nommage',
  NameCatalogue: 'Catalogue des services', V2DirectorySites: 'Sites et OU explicites', ReferenceData: 'Référentiel versionné', Configured: 'État de configuration' };
const valueText = (value) => value == null ? 'Absent' : typeof value === 'object' ? JSON.stringify(value, null, 2) : String(value);

export function configurationDifferences(plan) {
  const changes = Array.isArray(plan?.differences) ? plan.differences : [];
  return `<p class="k-dlg-text">${changes.length} rubrique(s) modifiée(s). ${plan.backupRequired ? 'La configuration actuelle sera sauvegardée avant son remplacement atomique.' : 'Une configuration sera créée dans votre profil Windows.'}</p>
    ${changes.length ? changes.map((change) => `<details class="config-difference"><summary>${esc(LABELS[change.field] ?? change.field)}</summary>
      <div class="config-compare"><div><strong>Actuel</strong><pre>${esc(valueText(change.before))}</pre></div>
      <div><strong>Proposé</strong><pre>${esc(valueText(change.after))}</pre></div></div></details>`).join('') : '<p>Aucune différence de paramètres.</p>'}
    <p class="muted small">Les aperçus et les plans précédents seront invalidés. Les reçus d’opérations, les secrets et l’historique ne font pas partie de cet échange.</p>`;
}

export async function confirmConfiguration(plan, { title = 'Importer la configuration', confirmLabel = 'Remplacer la configuration', isActive = () => true } = {}) {
  if (!plan?.planId || !isActive()) return false;
  const dialog = openDialog({ title, subtitle: `Version ${plan.version}`, icon: 'settings', size: 'lg',
    body: configurationDifferences(plan), actions: [
      { id: 'cancel', label: 'Annuler', safe: true }, { id: 'apply', label: confirmLabel, danger: true },
    ] });
  return await dialog.result === 'apply' && isActive();
}

export async function showConfigurationNotice({ call, refreshSession, isActive = () => true }) {
  const route = location.hash;
  const current = () => isActive() && location.hash === route;
  try {
    if (!current()) return;
    const status = await call('configuration.status');
    const plan = status?.pendingDistribution;
    if (!current() || !status?.requiresDecision || !plan?.planId) return;
    const dialog = openDialog({
      title: 'Une nouvelle configuration accompagne ce pack', subtitle: `Version distribuée ${plan.version}`,
      icon: 'settings', size: 'lg', body: configurationDifferences(plan),
      actions: [{ id: 'keep', label: 'Conserver mes paramètres', safe: true }, { id: 'replace', label: 'Remplacer', danger: true }],
    });
    const choice = await dialog.result;
    if (!current() || !['keep', 'replace'].includes(choice)) return;
    await call('configuration.decideDistribution', { planId: plan.planId, replace: choice === 'replace', confirmed: true });
    if (!current()) return;
    if (choice === 'replace') {
      await refreshSession?.();
      window.dispatchEvent(new CustomEvent('pesto-configuration-changed'));
    }
    toast(choice === 'replace' ? 'Configuration remplacée et sauvegarde conservée.' : 'Vos paramètres sont conservés. Ce choix est mémorisé pour cette version et ce profil.', { tone: 'ok' });
  } catch (error) {
    // A missing service in an older preview is not a claim that the configuration has been accepted.
    if (current() && error.code !== 'operation.unknown') toast(errorText(error), { tone: 'warn' });
  }
}
