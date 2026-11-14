import { icon } from '../icons.js';
import { esc, errorText, toast } from '../ui.js';
import { refusal } from '../refusal.js';
import { openDialog, confirmDialog } from '../kit/index.js';
import { confirmConfiguration, showConfigurationNotice } from '../configuration-notice.js';

// Written in place, outside the pack identity (InstallationDefaults.DisplayPath). The title, button and statuses of the
// « default » action are read by the native qualification bench: keep them word for word.
const DEFAULT_PATH = 'wad\\defaults\\configuration.json';
// What installing, returning or recovering does with wad\defaults\configuration.json, as the engine computed it
// (InstallationDefaults.DescribeInstall / DescribeReturn): the confirmation never promises more than that.
const DEFAULTS_KEPT = ' La configuration par défaut de cette installation est conservée.';
const RETURN_DEFAULTS = {
  kept: DEFAULTS_KEPT,
  withdrawn: ' La configuration par défaut apportée par la mise à jour, inchangée depuis, est retirée avec elle : la version rétablie retrouve son état d’avant la mise à jour.',
  deleted: ' La configuration par défaut supprimée depuis la mise à jour le reste.',
  setAside: ' La version rétablie ne connaît pas la configuration par défaut de l’installation : elle sera mise de côté dans le dossier de la transaction.',
};
const INSTALL_DEFAULTS = { kept: DEFAULTS_KEPT, adopted: ' La configuration par défaut du pack choisi sera adoptée par cette installation.' };
// The file is written and verified; only the author's remembered choice is missing from the profile.
const DECISION_NOT_SAVED = ' Votre choix n’a pas pu être mémorisé dans votre profil : au prochain démarrage, Pesto pourra vous proposer cette configuration.';
// A source folder can carry a local default outside its identity; a sealed one stays « Pack personnalisé ».
const defaultsText = (item) => item?.localConfiguration === true ? ' · configuration par défaut incluse' : '';
const returnDefaults = (fate) => RETURN_DEFAULTS[fate] ?? '';

export function maintenanceMarkup() {
  return `<section class="card reveal spot" data-maintenance="configuration">
    <div class="card-head"><span class="card-icon">${icon('settings')}</span><h3>Configuration à partager</h3></div>
    <p class="muted">Exporter les paramètres, les importer après comparaison, ou les définir comme configuration par défaut de cette installation.</p>
    <label class="k-field">Version de configuration <input class="input" name="configurationVersion" maxlength="80" placeholder="Automatique si vide"></label>
    <div class="row-actions"><button class="btn" type="button" data-maint="export">Exporter</button>
      <button class="btn" type="button" data-maint="import">Importer</button>
      <button class="btn primary" type="button" data-maint="default">Définir comme configuration par défaut</button></div>
    <div class="row-actions"><button class="btn" type="button" data-maint="distribution">Comparer la configuration distribuée</button>
      <button class="btn" type="button" data-maint="reconnect">Reconnecter Pesto</button></div>
    <p class="muted small" data-maint-status="configuration">La configuration par défaut est écrite dans ${DEFAULT_PATH} de cette installation. Secrets, sessions, reçus, historique et caches sont exclus. Ce fichier contient le domaine et les OU : diffusez ce dossier comme un fichier privé.</p>
  </section>
  <section class="card reveal spot" data-maintenance="references">
    <div class="card-head"><span class="card-icon">${icon('server')}</span><h3>Référentiels sites et services</h3></div>
    <p class="muted">Comparer une mise à jour, choisir chaque résolution de conflit, puis appliquer le référentiel en une seule écriture avec sauvegarde.</p>
    <div class="row-actions"><button class="btn" type="button" data-maint="references">Importer une mise à jour des référentiels</button></div>
    <p class="muted small" data-maint-status="references">L’import ne crée ni OU ni objet dans l’annuaire. Les OU utilisées sont toujours relues avant une opération.</p>
  </section>
  <section class="card reveal spot" data-maintenance="updates">
    <div class="card-head"><span class="card-icon">${icon('refresh')}</span><h3>Mises à jour de Pesto</h3></div>
    <p class="muted">Archive ZIP, dossier local ou partage UNC. Chaque installation exige un pack vérifié, une préparation et votre confirmation.</p>
    <div class="row-actions"><button class="btn" type="button" data-maint="zip">Choisir un ZIP</button><button class="btn" type="button" data-maint="folder">Choisir un dossier</button></div>
    <label class="k-field">Dossier ou partage UNC <input class="input mono" name="updateSource" placeholder="\\\\serveur\\partage\\Pesto-PROD" autocomplete="off"></label>
    <div class="row-actions"><button class="btn" type="button" data-maint="source">Inspecter ce chemin</button>
      <button class="btn" type="button" data-maint="status">État et reprise</button>
      <button class="btn" type="button" data-maint="rollback">Revenir à la version précédente</button></div>
    <div data-maint-zone="candidates" aria-live="polite"></div><div data-maint-zone="prepared" aria-live="polite"></div>
    <p class="muted small" data-maint-status="updates">Pesto ne se connecte à aucun serveur pour ses mises à jour : il ne vérifie ni ne télécharge rien. Les releases V1 restent indépendantes.</p>
  </section>`;
}

export function mountMaintenance(main, ctx, reloaded) {
  let alive = true, busy = false, closing = false, preparedUpdate = null;
  // The settings page rewrites its own query (?section=) without leaving: only the screen counts, not the full address.
  const path = location.hash.split('?')[0];
  const isCurrent = typeof ctx.isCurrent === 'function' ? ctx.isCurrent : () => location.hash.split('?')[0] === path;
  const isActive = () => alive && isCurrent();
  const nativeCall = ctx.call;
  // A response may arrive after navigation. It must not open a confirmation on another screen,
  // or continue a multi-step action. An already sent operation is never cancelled or replayed here.
  const requireActive = () => { if (!isActive()) throw refusal('La page a été quittée.'); };
  ctx = { ...ctx, call: async (...args) => {
    requireActive();
    const result = await nativeCall(...args);
    requireActive();
    return result;
  } };
  const simulation = ctx.session()?.mode === 'simulation';
  const buttons = [...main.querySelectorAll('[data-maint]')];
  if (simulation) {
    for (const section of main.querySelectorAll('[data-maintenance]')) {
      section.querySelectorAll('button,input').forEach((control) => { control.disabled = true; });
      const status = section.querySelector('[data-maint-status]');
      if (status) status.textContent = 'Disponible dans la fenêtre normale. La démonstration ne lit ni fichier réel ni partage réseau.';
    }
  }
  const versionArgs = () => { const version = main.querySelector('[name="configurationVersion"]').value.trim(); return version ? { version } : {}; };
  const statusText = (kind, value) => { if (alive) main.querySelector(`[data-maint-status="${kind}"]`).textContent = value; };
  const feedback = (result) => {
    const message = result.backup ? `Configuration appliquée. Sauvegarde : ${result.backup}` : 'Configuration appliquée dans votre profil Windows.';
    statusText('configuration', message); toast(message, { tone: 'ok' });
    reloaded?.(); ctx.refreshSession?.().catch(() => {});
  };
  const invalidConfigurationActions = new Set(['export', 'default', 'distribution', 'references', 'reconnect']);
  function refreshButtons() {
    const invalid = main.dataset.configurationState === 'invalid';
    buttons.forEach((button) => { button.disabled = busy || closing || simulation || invalid && invalidConfigurationActions.has(button.dataset.maint); });
    main.querySelectorAll('[data-candidate],[data-install]').forEach((button) => { button.disabled = busy || closing || simulation; });
  }
  const configurationStateChanged = () => {
    refreshButtons();
    if (main.dataset.configurationState === 'invalid') statusText('configuration', main.dataset.configurationDiagnostic
      || 'Configuration invalide : seul un import valide, comparé et confirmé, peut préparer son remplacement avec sauvegarde.');
  };
  main.addEventListener('pesto-configuration-state', configurationStateChanged);
  configurationStateChanged();
  async function guard(action) {
    if (busy || closing || simulation || !isActive()) return;
    busy = true; refreshButtons();
    try { await action(); }
    catch (error) { if (isActive()) toast(errorText(error), { tone: 'alert', life: 9000 }); }
    finally { busy = false; if (alive) refreshButtons(); }
  }
  const originText = (item) => item.distribution === 'custom' ? 'Pack personnalisé — source locale' : 'Source locale — origine à vérifier';
  function discardPrepared() {
    preparedUpdate = null;
    main.querySelector('[data-maint-zone="prepared"]').replaceChildren();
  }
  function observeClosing(result, kind = 'updates') {
    if (result?.status !== 'closing') return;
    closing = true;
    discardPrepared();
    statusText(kind, result.message ?? 'Fermeture demandée. Attendez la fin du relais avant toute nouvelle action.');
    refreshButtons();
  }
  function showCandidates(items, message) {
    if (!alive) return;
    // A newly inspected source replaces the displayed choice. An older staged pack must not
    // remain installable beside it, especially when both packages carry the same version.
    discardPrepared();
    statusText('updates', message ?? (items.length ? 'Source inspectée. Choisissez le pack à préparer avant toute installation.'
      : 'Aucune mise à jour proposée. Aucune installation préparée.'));
    const zone = main.querySelector('[data-maint-zone="candidates"]');
    zone.innerHTML = items.map((item, index) => `<div class="config-candidate"><strong>Pesto ${esc(item.version)}</strong>
      <span class="muted small">${esc(originText(item) + defaultsText(item))} · ${esc(item.name ?? item.channel ?? '')}</span>
      <button class="btn" type="button" data-candidate="${index}">Préparer cette mise à jour</button></div>`).join('');
    zone.querySelectorAll('[data-candidate]').forEach((button) => button.addEventListener('click', () => guard(async () => {
      const selected = items[Number(button.dataset.candidate)];
      discardPrepared();
      statusText('updates', 'Préparation en cours : copie, puis vérification complète. Aucun fichier installé n’est remplacé.');
      let prepared;
      try { prepared = await ctx.call('updates.prepare', { candidateId: selected.candidateId }); }
      catch (error) { if (isActive()) statusText('updates', 'Préparation refusée. Aucun pack prêt à installer ; inspectez ou préparez de nouveau la source souhaitée.'); throw error; }
      if (!alive) return;
      preparedUpdate = prepared;
      const target = main.querySelector('[data-maint-zone="prepared"]');
      target.innerHTML = `<div class="config-candidate"><strong>Version ${esc(prepared.version)} prête</strong><span class="muted small">${esc(prepared.channel ?? selected.channel ?? '')} · ${esc(originText(prepared) + defaultsText(prepared))}</span><span class="muted small">${esc(prepared.message ?? 'Le pack a été préparé et vérifié.')}</span>
        <button class="btn primary" type="button" data-install>Installer et vérifier le démarrage</button></div>`;
      target.querySelector('[data-install]').addEventListener('click', () => guard(async () => {
        if (preparedUpdate !== prepared) return;
        const windows = await packWindows();
        if (!await confirmDialog({ title: 'Installer la mise à jour préparée', message: `Installer Pesto ${prepared.version}${prepared.channel ? ` (${prepared.channel})` : ''} · ${originText(prepared)}${defaultsText(prepared)}. Pesto va fermer ses fenêtres, conserver les anciens fichiers et installer ce pack. Un contrôle de santé isolé vérifiera son démarrage. En cas d’échec, la sauvegarde sera rétablie. Votre configuration reste dans votre profil.${INSTALL_DEFAULTS[prepared.installDefaults] ?? ''}${windows.text}`, confirmLabel: 'Fermer et installer', danger: true })) return;
        if (preparedUpdate !== prepared) return;
        // Once sent, the transaction owns the outcome. A lost response must not keep a replay button.
        discardPrepared();
        statusText('updates', 'Installation demandée : attente de la fermeture. Le résultat reste à vérifier dans la transaction.');
        try {
          const result = await ctx.call('updates.install', { preparedId: prepared.preparedId, confirmed: true, ...windows.args });
          observeClosing(result);
          statusText('updates', result.message ?? 'Fermeture demandée. Le résultat sera confirmé par le programme de mise à jour.');
        } catch (error) {
          // A refusal to release the other windows comes before any transaction: nothing was started.
          if (isActive()) statusText('updates', ['update.windows', 'update.running'].includes(error?.code)
            ? 'Installation non lancée : aucune transaction n’a été créée. Préparez de nouveau la mise à jour une fois les autres fenêtres fermées.'
            : 'Installation non confirmée. Consultez « État et reprise » avant toute nouvelle préparation.');
          throw error;
        }
      }));
      statusText('updates', 'Préparation terminée. L’installation attend votre confirmation.');
    })));
  }
  async function referenceImport() {
    const plan = await ctx.call('references.preview');
    if (!plan?.planId || !alive) return;
    const body = document.createElement('div');
    body.innerHTML = `<p class="k-dlg-text">Version ${esc(plan.version)} · ${Number(plan.additions) || 0} ajout(s), ${Number(plan.conflictCount) || 0} conflit(s), ${Number(plan.unchanged) || 0} entrée(s) identique(s).</p>
      ${(plan.conflicts ?? []).map((conflict, index) => `<section class="config-conflict"><strong>${esc(conflict.key)}</strong>
        <div class="config-compare"><div><b>Actuel</b><pre>${esc(JSON.stringify(conflict.current, null, 2))}</pre></div><div><b>Importé</b><pre>${esc(JSON.stringify(conflict.incoming, null, 2))}</pre></div></div>
        <label>Résolution <select class="input" data-conflict="${index}"><option value="">Choisir…</option><option value="current">Conserver l’actuel</option><option value="incoming">Prendre l’importé</option></select></label></section>`).join('')}
      <details><summary>Aperçu de toutes les entrées</summary><pre class="config-json">${esc(JSON.stringify(plan.changes ?? [], null, 2))}</pre></details>
      <p class="muted small">Toutes les résolutions seront validées ensemble. Aucune application partielle, aucun doublon ajouté.</p>`;
    const dialog = openDialog({ title: 'Comparer les référentiels', icon: 'server', size: 'lg', body,
      actions: [{ id: 'cancel', label: 'Annuler', safe: true }, { id: 'apply', label: 'Appliquer le référentiel', danger: true, disabled: (plan.conflicts?.length ?? 0) > 0 }] });
    const selects = [...body.querySelectorAll('[data-conflict]')];
    body.addEventListener('change', () => dialog.setDisabled('apply', selects.some((s) => !s.value)));
    if (await dialog.result !== 'apply') return;
    const resolutions = selects.map((select) => ({ key: plan.conflicts[Number(select.dataset.conflict)].key, choice: select.value }));
    const result = await ctx.call('references.apply', { planId: plan.planId, resolutions, confirmed: true });
    statusText('references', result.message ?? 'Référentiel appliqué atomiquement, avec sauvegarde.');
    feedback(result);
  }
  // Other Pesto windows of this pack keep its files in use: the replacement would wait, then refuse.
  // They are named in the confirmation and closed like with their own close button, never forced.
  async function packWindows() {
    const state = await ctx.call('updates.windows');
    const windows = Array.isArray(state?.windows) ? state.windows : [];
    const blocked = windows.filter((item) => item?.closable === false);
    if (blocked.length) {
      const details = blocked.map((item) => `« ${item.label ?? ''} » (${item.reason ?? ''})`).join(' ; ');
      throw Object.assign(new Error(`Pesto ne peut pas fermer lui-même : ${details}. Fermez-les puis recommencez ; rien n’a été modifié.`), { code: 'update.windows' });
    }
    if (!windows.length) return { text: '', args: {} };
    const names = windows.map((item) => `« ${item.label ?? ''} »`).join(', ');
    return {
      text: ` Autres fenêtres Pesto de ce pack, fermées comme avec leur bouton de fermeture : ${names}. Une opération en cours s’y termine et enregistre son reçu avant la fermeture.`,
      args: { closeWindows: state?.token ?? '' },
    };
  }
  async function updateStatus() {
    const state = await ctx.call('updates.status');
    statusText('updates', `Version ${state.version} · ${state.channel} · ${state.distribution === 'custom' ? 'pack personnalisé' : state.distribution === 'official' ? 'release officielle' : 'candidat de développement'}. ${state.message}`);
    if (state.pendingRecovery) {
      const windows = await packWindows();
      if (await confirmDialog({ title: 'Reprendre la mise à jour interrompue', message: state.message + returnDefaults(state.recoveryDefaults) + windows.text, confirmLabel: 'Fermer et reprendre', danger: true }))
        observeClosing(await ctx.call('updates.recover', { confirmed: true, ...windows.args }));
    }
  }
  const actions = {
    export: async () => { const result = await ctx.call('configuration.export', versionArgs()); if (result.status === 'exported') statusText('configuration', `Configuration exportée : ${result.file}`); },
    import: async () => {
      const plan = await ctx.call('configuration.previewImport');
      const options = plan?.replacesInvalidConfiguration ? { title: 'Remplacer la configuration invalide', confirmLabel: 'Sauvegarder et remplacer' } : {};
      if (plan?.planId && await confirmConfiguration(plan, options)) feedback(await ctx.call('configuration.applyImport', { planId: plan.planId, confirmed: true }));
    },
    default: async () => {
      try {
        // The file shown in the confirmation is the one the engine may replace: its SHA-256 goes with the request,
        // and a file changed in between is refused (config.default_changed). A sealed legacy file is refused there too,
        // so only a local file is announced as replaced.
        const state = (await ctx.call('configuration.status'))?.installationDefault ?? null;
        const present = state?.state === 'local';
        const replaced = present ? ` Il remplace la configuration par défaut actuelle (version ${state.version ?? 'non indiquée'}) ; une copie sera conservée dans votre profil.` : '';
        if (!await confirmDialog({ title: 'Définir comme configuration par défaut', message: `Pesto va écrire la configuration partageable de ce profil dans ${DEFAULT_PATH} de cette installation. Aucun pack n’est recréé ; les fichiers du programme et leurs empreintes restent inchangés.${replaced}`,
          confirmLabel: 'Enregistrer comme défaut', danger: present })) return;
        statusText('configuration', 'Écriture de la configuration par défaut…');
        const result = await ctx.call('configuration.setDefault', { ...versionArgs(), expectedSha256: state?.sha256 ?? '', confirmed: true });
        if (result?.status === 'written') {
          statusText('configuration', `Configuration par défaut enregistrée dans cette installation : ${DEFAULT_PATH} (version ${result.version}).${result.backup ? ` Copie de l’ancienne dans votre profil : ${result.backup}` : ''}${result.decisionSaved === false ? DECISION_NOT_SAVED : ''}`);
          toast('Configuration par défaut enregistrée.', { tone: 'ok' });
        } else if (result?.status === 'unchanged') statusText('configuration', `Configuration par défaut déjà identique (version ${result.version}) : aucun fichier modifié.${result.decisionSaved === false ? DECISION_NOT_SAVED : ''}`);
        // Never a success without a known result; the file may or may not have been written.
        else statusText('configuration', 'Réponse inattendue : l’enregistrement de la configuration par défaut n’est pas confirmé. Relisez l’état avant de recommencer.');
      } catch (error) {
        // A refusal ends the « … » status; guard() still shows the usual error toast.
        if (isActive()) statusText('configuration', `Configuration par défaut non enregistrée : ${errorText(error)}`);
        throw error;
      }
    },
    distribution: () => showConfigurationNotice({ call: ctx.call, refreshSession: ctx.refreshSession, isActive }),
    reconnect: async () => {
      if (await confirmDialog({ title: 'Reconnecter Pesto', message: 'Fermer cette session, relire la configuration du profil d’origine et choisir le compte de connexion AD ? Aucun poste ne redémarre et aucune opération AD ne sera rejouée.', confirmLabel: 'Fermer et reconnecter' }))
        observeClosing(await ctx.call('host.reconnect', { confirmed: true }), 'configuration');
    },
    references: referenceImport,
    zip: async () => { const result = await ctx.call('updates.inspect', { kind: 'zip' }); if (result.candidateId) showCandidates([result]); },
    folder: async () => { const result = await ctx.call('updates.inspect', { kind: 'folder' }); if (result.candidateId) showCandidates([result]); },
    source: async () => { const source = main.querySelector('[name="updateSource"]').value.trim(); if (!source) throw Object.assign(new Error('Indiquez un chemin de dossier ou de partage UNC.'), { code: 'update.source' }); const result = await ctx.call('updates.inspect', { source }); showCandidates([result]); },
    status: updateStatus,
    rollback: async () => {
      const state = await ctx.call('updates.status');
      if (!state.canRollback) throw Object.assign(new Error('Aucune sauvegarde de mise à jour terminée n’est disponible.'), { code: 'update.rollback' });
      const windows = await packWindows();
      if (await confirmDialog({ title: 'Revenir au programme précédent', message: 'Pesto va fermer les fenêtres et restaurer les anciens fichiers. Votre configuration actuelle sera conservée.' + returnDefaults(state.rollbackDefaults) + ' Le démarrage restauré sera contrôlé séparément.' + windows.text, confirmLabel: 'Fermer et restaurer', danger: true }))
        observeClosing(await ctx.call('updates.rollback', { confirmed: true, ...windows.args }));
    },
  };
  const click = (event) => { const button = event.target.closest('[data-maint]'); if (button && !button.disabled) guard(actions[button.dataset.maint]); };
  main.addEventListener('click', click);
  return () => { alive = false; main.removeEventListener('click', click); main.removeEventListener('pesto-configuration-state', configurationStateChanged); };
}
