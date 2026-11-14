// Plusieurs postes — collecte bornée, file et lot séquentiel (mission Pesto v2). Trois sources d'entrée, toutes
// bornées et validées ligne à ligne AVANT tout envoi : recherche annuaire (directory.search), liste collée et import
// CSV local lus côté web (csv.js, sans DOM) puis affichés tels quel. Chaque ajout à la file repasse par le circuit
// moteur : identité relue (computer.inspect), nom libre calculé (names.preview), queue.add (doublons refusés par le
// moteur). Le lot est préparé (queue.prepare), affiché en aperçu, exécuté une seule fois après confirmation exacte
// (queue.execute, confirmed:true), séquentiel, arrêté sur la première ligne qui échoue : rien n'est rejoué
// automatiquement, les lignes restantes restent dans la file. À site identique le moteur conserve l’OU ; un
// changement de site inclut son déplacement après renommage. La jonction reste hors de ce lot.
import { icon } from '../icons.js';
import { esc, applyVars, reveal, errorText, announce, toast, formatDateTime } from '../ui.js';
import { refusal } from '../refusal.js';
import { field, createForm, pill, bindCopy, confirmWrite } from '../kit/index.js';
import { refusalMarkup, receiptMarkup, receiptFeedback, receiptMatchesPlan, entraConfirmation, KIND_LABEL } from '../writeflow.js';
import { parsePastedList, parseQueueCsv, MAX_ROWS } from '../csv.js';

const CSV_MAX_BYTES = 256 * 1024;
// Queue-row states (not receipt states); an unknown value stays visible as sent by the engine.
const QUEUE_STATUS = { ready: 'Prêt' };

function guessType(c) {
  if (['P', 'S', 'V'].includes(c.type)) return c.type;
  const m = String(c.model ?? '').toLowerCase();
  if (m.includes('portable') || m.includes('laptop')) return 'P';
  if (m.includes('virtuel') || m.includes('virtual') || m.includes('vm')) return 'V';
  if (m.includes('fixe') || m.includes('desktop')) return 'S';
  return null;
}

function layout() {
  return `<div class="page">
    <header class="page-header reveal">
      <div class="head-row"><span class="page-icon">${icon('chip')}</span>
        <div class="titles"><h1 class="gradient-text">Plusieurs postes</h1>
          <p class="subtitle">Collecte bornée, file contrôlée, import CSV local : chaque ligne est validée et relue avant toute exécution.</p></div></div>
    </header>
    <div class="grid">
      <section class="card span-5 reveal spot">
        <div class="card-head"><span class="card-icon">${icon('search')}</span><h3>Recherche annuaire</h3></div>
        <form class="k-form" novalidate data-form="search"></form>
        <div data-zone="results" aria-live="polite"><p class="muted">Saisissez un nom ou un fragment.</p></div>
      </section>
      <section class="card span-7 reveal spot">
        <div class="card-head"><span class="card-icon">${icon('copy')}</span><h3>Liste collée</h3></div>
        <form class="k-form" novalidate data-form="paste"></form>
        <div data-zone="paste-report" aria-live="polite"></div>
      </section>
    </div>
    <div class="grid">
      <section class="card span-5 reveal spot">
        <div class="card-head"><span class="card-icon">${icon('file')}</span><h3>Import CSV local</h3></div>
        <p class="muted small">Colonnes admises : name${'·'}type${'·'}site${'·'}service (en-tête optionnel, « ; » ou « , »).
          Le fichier est lu côté interface, borné à 256 Ko et ${MAX_ROWS} lignes, validé ligne à ligne, affiché avant tout envoi.</p>
        <p class="muted small">Pour corriger un poste déjà sélectionné, réimportez son nom : les colonnes renseignées remplacent ses indications de type, site et service avant l’ajout à la file.</p>
        <input type="file" accept=".csv,text/csv" data-act="csvfile" aria-label="Fichier CSV de postes">
        <div data-zone="csv-report" aria-live="polite"></div>
      </section>
      <section class="card span-7 reveal spot" data-zone="selection">
        <div class="card-head"><span class="card-icon">${icon('check')}</span><h3>Sélection — aperçu avant envoi</h3>
          <span class="meta" data-slot="sel-count"></span></div>
        <div data-zone="sel-list"><p class="muted">Aucun poste sélectionné.</p></div>
        <div class="row-actions">
          <button class="btn primary" type="button" data-act="addqueue" disabled>${icon('chip')}Ajouter à la file</button>
          <button class="btn ghost" type="button" data-act="clearsel" disabled>${icon('trash')}Tout retirer</button>
          <span data-slot="addhint" class="muted small">La sélection est un aperçu : rien n’est envoyé avant ce bouton.</span>
        </div>
        <div data-zone="add-report" aria-live="polite"></div>
      </section>
    </div>
    <section class="card reveal spot" data-zone="queue">
      <div class="card-head"><span class="card-icon">${icon('server')}</span><h3>File d’attente</h3>
        <span class="meta" data-slot="queue-count"></span></div>
      <div data-zone="queue-list"><p class="muted">File vide.</p></div>
      <label class="small"><input type="checkbox" data-act="pilot"> Mode pilote : préparer et exécuter uniquement la première ligne</label>
      <div class="row-actions">
        <button class="btn" type="button" data-act="refreshqueue">${icon('refresh')}Rafraîchir</button>
        <button class="btn primary" type="button" data-act="prepare" disabled>${icon('sparkles')}Préparer le lot</button>
        <span class="muted small">Le moteur refuse les doublons, la jonction et au-delà de ${MAX_ROWS} postes.</span>
      </div>
    </section>
    <section class="card reveal spot" data-zone="batch">
      <div class="card-head"><span class="card-icon">${icon('play')}</span><h3>Lot préparé</h3></div>
      <p class="muted">Aucun lot préparé : la préparation calcule un plan par poste et sert d’aperçu avant exécution.</p>
    </section>
    <section class="card reveal spot" data-zone="receipt">
      <div class="card-head"><span class="card-icon">${icon('file')}</span><h3>Reçus du lot</h3></div>
      <p class="muted">Aucun lot exécuté dans cette session.</p>
    </section>
    <p class="muted small reveal">${icon('shield')} Garde-fous : un nom par poste vient de names.preview, jamais du CSV ;
      préparation avec lectures et, si nécessaire, tâches temporaires de diagnostic ; aucun changement AD avant confirmation ; arrêt sur la
      première ligne en échec ou incertaine ; aucune nouvelle exécution automatique. Le même site conserve l’OU
      actuelle ; un changement de site inclut le déplacement après renommage. Le déplacement seul et la jonction
      restent dans « Un poste » et « Ajouter ce PC ».</p>
  </div>`;
}

export function render(main, ctx) {
  main.innerHTML = layout();
  applyVars(main);
  const stops = [reveal(main)];
  let alive = true;
  let searchSequence = 0;
  const route = location.hash;
  const isActive = () => alive && location.hash === route;
  let busy = false;
  let csvReading = false, csvReader = null;
  let queueSequence = 0;
  let queueCount = 0;
  let lastBatch = null;
  let batchError = null;
  const selected = new Map(); // name → { type, site, service, source }

  const cap = ctx.capability('queue');
  const results = main.querySelector('[data-zone="results"]');
  const pasteReport = main.querySelector('[data-zone="paste-report"]');
  const csvReport = main.querySelector('[data-zone="csv-report"]');
  const selList = main.querySelector('[data-zone="sel-list"]');
  const selCount = main.querySelector('[data-slot="sel-count"]');
  const addBtn = main.querySelector('[data-act="addqueue"]');
  const clearBtn = main.querySelector('[data-act="clearsel"]');
  const addHint = main.querySelector('[data-slot="addhint"]');
  const addReport = main.querySelector('[data-zone="add-report"]');
  const queueList = main.querySelector('[data-zone="queue-list"]');
  const queueCountSlot = main.querySelector('[data-slot="queue-count"]');
  const refreshBtn = main.querySelector('[data-act="refreshqueue"]');
  const prepareBtn = main.querySelector('[data-act="prepare"]');
  const pilotInput = main.querySelector('[data-act="pilot"]');
  const batchZone = main.querySelector('[data-zone="batch"]');
  const receiptZone = main.querySelector('[data-zone="receipt"]');

  function setBusy(on) {
    busy = on;
    const blocked = on || csvReading;
    addBtn.disabled = blocked || !cap.enabled || !selected.size;
    prepareBtn.disabled = blocked || !cap.enabled || !queueCount;
    clearBtn.disabled = blocked || !selected.size;
    refreshBtn.disabled = blocked;
    pilotInput.disabled = blocked;
    main.querySelectorAll('[data-form="search"] input, [data-form="search"] button, [data-form="paste"] textarea, [data-form="paste"] button, [data-act="csvfile"], [data-pick], [data-qdrop], [data-drop]')
      .forEach(control => { control.disabled = blocked; });
    if (batchZone.querySelector('[data-act="execute"]')) {
      batchZone.querySelector('[data-act="execute"]').disabled = blocked || !cap.enabled || !lastBatch;
    }
  }

  function updateCommands() {
    ctx.setScreenCommands([
      { id: 'postes-add', kind: 'command', label: 'Ajouter la sélection à la file', icon: 'chip', group: 'Plusieurs postes', effect: 'write', available: cap.enabled && selected.size > 0 && !busy && !csvReading, reason: cap.enabled ? (selected.size ? '' : 'Sélectionnez d’abord des postes.') : cap.reason, detailText: 'Relit chaque identité, calcule le nom libre puis queue.add.', run: () => { if (!addBtn.disabled) addSelected(); } },
      { id: 'postes-prepare', kind: 'command', label: 'Préparer le lot', icon: 'sparkles', group: 'Plusieurs postes', effect: 'read', available: cap.enabled && queueCount > 0 && !busy && !csvReading, reason: cap.enabled ? (queueCount ? '' : 'File vide.') : cap.reason, detailText: 'queue.prepare : un plan par poste, aperçu avant exécution.', run: () => { if (!prepareBtn.disabled) prepareBatch(); } },
      { id: 'postes-execute', kind: 'command', label: 'Exécuter le lot préparé', icon: 'play', group: 'Plusieurs postes', effect: 'write', available: cap.enabled && !!lastBatch && !busy && !csvReading, reason: cap.enabled ? (lastBatch ? '' : 'Préparez d’abord le lot.') : cap.reason, detailText: 'Confirmation exacte de l’identifiant, exécution séquentielle unique.', run: () => { const b = batchZone.querySelector('[data-act="execute"]'); if (b && !b.disabled) executeBatch(); } },
    ]);
  }

  // ---------- selection (aperçu avant tout envoi) ----------

  function addSelection(names, overrides, source) {
    let added = 0, updated = 0;
    if (busy || csvReading || !isActive()) return { added, updated };
    for (const name of names) {
      const key = name.toUpperCase();
      const incoming = overrides?.get?.(key) ?? {};
      if (selected.has(key)) {
        const previous = selected.get(key);
        const supplied = Object.fromEntries(['type', 'site', 'service'].filter(field => incoming[field] != null && incoming[field] !== '')
          .map(field => [field, incoming[field]]));
        if (source === 'CSV' && Object.entries(supplied).some(([field, value]) => previous[field] !== value)) {
          selected.set(key, { ...previous, ...supplied, source }); updated++;
        }
        continue;
      }
      if (selected.size >= MAX_ROWS) { toast(`Sélection limitée à ${MAX_ROWS} postes (limite moteur de la file).`, { tone: 'warn' }); break; }
      selected.set(key, { ...incoming, source });
      added += 1;
    }
    if (added || updated) announce(`${added} poste(s) ajouté(s), ${updated} indication(s) de poste mise(s) à jour dans la sélection.`);
    paintSelection();
    return { added, updated };
  }

  function paintSelection() {
    if (!selected.size) {
      selList.innerHTML = '<p class="muted">Aucun poste sélectionné.</p>';
      selCount.textContent = '';
    } else {
      selList.innerHTML = `<ul class="result-list">${[...selected.entries()].map(([name, o]) => `<li>
        <span class="log-line"><span class="mono">${esc(name)}</span>
        <span class="muted small">${esc(o.source)}${o.type ? ` · type ${esc(o.type)}` : ''}${o.site ? ` · site ${esc(o.site)}` : ''}${o.service ? ` · service ${esc(o.service)}` : ''}</span>
        <button class="btn ghost xs" type="button" data-drop="${esc(name)}" aria-label="Retirer ${esc(name)} de la sélection">${icon('x')}</button></span></li>`).join('')}</ul>`;
      selCount.textContent = `${selected.size} / ${MAX_ROWS}`;
      selList.querySelectorAll('[data-drop]').forEach((b) => b.addEventListener('click', () => { if (busy || csvReading) return; selected.delete(b.dataset.drop); paintSelection(); }));
    }
    setBusy(busy);
    updateCommands();
  }

  function issuesMarkup(issues) {
    if (!issues.length) return '';
    return `<ul class="result-list">${issues.map((i) => `<li><span class="log-line">${icon('alert')}
      <span class="small">${i.line ? `ligne ${i.line} · ` : ''}<b>${esc(i.value || '(vide)')}</b> — ${esc(i.reason)}</span></span></li>`).join('')}</ul>`;
  }

  // ---------- search ----------

  const searchHost = main.querySelector('[data-form="search"]');
  searchHost.innerHTML = field({ name: 'query', label: 'Nom ou fragment', type: 'search', required: true, mono: true });
  createForm(searchHost, {
    onChange: () => { searchSequence++; results.innerHTML = ''; },
    onSubmit: async (values) => {
      if (!isActive()) return;
      const request = ++searchSequence;
      results.innerHTML = '<p class="muted" aria-busy="true">Recherche…</p>';
      try {
        const { items, complete } = await ctx.call('directory.search', { query: values.query, limit: 25 });
        if (!isActive() || request !== searchSequence) return;
        if (!items?.length) { results.innerHTML = '<p class="muted">Aucun poste trouvé pour cette recherche.</p>'; return; }
        results.innerHTML = `<ul class="result-list">${items.map((c) => `<li><button class="btn ghost sm" type="button" data-pick="${esc(c.name)}">
          ${icon('monitor')}<span class="mono">${esc(c.name)}</span><span class="muted small">${esc(c.site)} · ${esc(c.service)}</span></button></li>`).join('')}</ul>
          ${complete === false ? '<p class="muted small">Résultats tronqués : précisez la recherche.</p>' : ''}`;
        results.querySelectorAll('[data-pick]').forEach((b) => b.addEventListener('click', () => addSelection([b.dataset.pick], null, 'recherche')));
        setBusy(busy);
      } catch (err) {
        if (!isActive() || request !== searchSequence) return;
        results.innerHTML = `<p class="muted" role="alert">${esc(errorText(err))}</p>`;
      }
    },
  });

  // After a batch the listed names may no longer exist. No automatic re-query: the field may have been edited since.
  function staleResults() {
    searchSequence++;
    results.innerHTML = '<p class="muted" role="status">Un poste a changé : relancez la recherche.</p>';
  }

  // ---------- pasted list ----------

  const pasteHost = main.querySelector('[data-form="paste"]');
  pasteHost.innerHTML = [
    field({ name: 'list', label: `Un nom de poste par ligne (${MAX_ROWS} au plus)`, type: 'textarea', mono: true, required: true, maxLength: 4000 }),
    '<div class="row-actions"><button class="btn" type="submit">' + icon('check') + 'Analyser la liste</button></div>',
  ].join('');
  createForm(pasteHost, {
    onSubmit: (values) => {
      if (busy || csvReading || !isActive()) return;
      const { names, issues } = parsePastedList(values.list);
      const result = addSelection(names, null, 'liste collée');
      pasteReport.innerHTML = issuesMarkup(issues) + (names.length ? `<p class="muted small">${result.added} poste(s) ajouté(s) à la sélection ; ${names.length - result.added} déjà présent(s).</p>` : '');
    },
  });

  // ---------- local CSV (read side, bounded, line-by-line validation) ----------

  const fileInput = main.querySelector('[data-act="csvfile"]');
  fileInput.addEventListener('change', () => {
    const file = fileInput.files?.[0];
    fileInput.value = '';
    if (!file || busy || csvReading || !isActive()) return;
    if (file.size > CSV_MAX_BYTES) {
      csvReport.innerHTML = `<p class="muted" role="alert">${icon('alert')} Fichier refusé : ${esc(String(file.name))} dépasse 256 Ko.</p>`;
      return;
    }
    const reader = csvReader = new FileReader();
    csvReading = true; setBusy(busy); updateCommands();
    const finished = () => { if (csvReader !== reader) return; csvReader = null; csvReading = false; if (isActive()) { setBusy(busy); updateCommands(); } };
    reader.onerror = () => { finished(); if (isActive()) csvReport.innerHTML = `<p class="muted" role="alert">${icon('alert')} Lecture du fichier impossible.</p>`; };
    reader.onabort = finished;
    reader.onload = () => {
      finished();
      if (!isActive()) return;
      const { rows, issues } = parseQueueCsv(String(reader.result ?? ''));
      const overrides = new Map(rows.map((r) => [r.name, { type: r.type, site: r.site, service: r.service }]));
      const result = addSelection(rows.map((r) => r.name), overrides, 'CSV');
      csvReport.innerHTML = issuesMarkup(issues)
        + (rows.length ? `<ul class="result-list">${rows.map((r) => `<li><span class="log-line">${icon('file')}
            <span class="mono">${esc(r.name)}</span><span class="muted small">ligne ${r.line}${r.type ? ` · ${esc(r.type)}` : ''}${r.site ? ` · ${esc(r.site)}` : ''}${r.service ? ` · ${esc(r.service)}` : ''}</span></span></li>`).join('')}</ul>
          <p class="muted small">${rows.length} ligne(s) valide(s) : ${result.added} ajout(s), ${result.updated} mise(s) à jour — aperçu ci-contre avant tout envoi.</p>` : '');
    };
    reader.readAsText(file);
  });

  // ---------- queue ----------

  async function refreshQueue() {
    if (!isActive()) return;
    const request = ++queueSequence;
    try {
      const { items, count } = await ctx.call('queue.list');
      if (!isActive() || request !== queueSequence) return;
      queueCount = count ?? items?.length ?? 0;
      queueCountSlot.textContent = queueCount ? `${queueCount} / ${MAX_ROWS}` : '';
      if (!queueCount) { queueList.innerHTML = '<p class="muted">File vide.</p>'; }
      else {
        queueList.innerHTML = `<ul class="result-list">${(items ?? []).map((q) => `<li><span class="log-line">${icon('chip')}
          <span class="mono">${esc(q.computer)}</span>${q.newName && q.newName !== q.computer ? `<span>→</span><span class="mono">${esc(q.newName)}</span>` : ''}
          <span class="muted small">${esc(KIND_LABEL[q.kind] ?? q.kind)} · ${esc(q.targetOU || 'OU du poste')} · ${esc(QUEUE_STATUS[q.status] ?? q.status)}</span>
          <button class="btn ghost xs" type="button" data-qdrop="${esc(q.id)}" aria-label="Retirer ${esc(q.computer)} de la file">${icon('trash')}</button></span></li>`).join('')}</ul>`;
        queueList.querySelectorAll('[data-qdrop]').forEach((b) => b.addEventListener('click', async () => {
          if (busy || !isActive()) return;
          // A pending removal invalidates an earlier list and the prepared batch immediately.
          ++queueSequence; lastBatch = null; batchError = null; setBusy(true); paintBatch();
          try {
            await ctx.call('queue.remove', { id: b.dataset.qdrop });
            if (!isActive()) return;
            await refreshQueue();
          } catch (err) { if (isActive()) toast(errorText(err), { tone: 'alert' }); }
          finally { if (isActive()) { setBusy(false); updateCommands(); } }
        }));
      }
    } catch (err) {
      if (!isActive() || request !== queueSequence) return;
      queueList.innerHTML = `<p class="muted" role="alert">${esc(errorText(err))}</p>`;
    }
    setBusy(busy);
    updateCommands();
  }

  async function addSelected() {
    if (busy || csvReading || !selected.size || !isActive()) return;
    ++queueSequence; lastBatch = null; batchError = null; setBusy(true); paintBatch();
    const lines = [];
    for (const [name, ov] of [...selected.entries()]) {
      if (!isActive()) return;
      if (selected.get(name) !== ov) continue;
      try {
        const c = await ctx.call('computer.inspect', { computer: name });
        if (!isActive()) return;
        const site = ov.site ?? c.site ?? null;
        const service = ov.service ?? c.service ?? null;
        const type = ov.type ?? guessType(c);
        if (!type || !site || !service) {
          lines.push([name, 'warn', 'Identité incomplète (type, site ou service inconnu) : aucun nom calculé, rien n’a été envoyé. Précisez les colonnes manquantes dans le CSV puis réimportez le poste.']);
          continue;
        }
        const p = await ctx.call('names.preview', { type, site, service, computer: name });
        if (!isActive()) return;
        if (p?.complete !== true) {
          lines.push([name, 'warn', 'Lecture incomplète : le nom reste inconnu, poste non ajouté à la file.']);
          continue;
        }
        // The engine applies the same-site rule and normalizes to rename when appropriate. A CSV site change must
        // retain its move step; comparing a site id against an observed site code in the UI is not authoritative.
        await ctx.call('queue.add', { kind: 'renameMove', computer: name, previewId: p.previewId });
        if (!isActive()) return;
        if (selected.get(name) === ov) selected.delete(name);
        lines.push([name, 'ok', `En file sous le nom ${p.name}.`]);
      } catch (err) {
        if (!isActive()) return;
        const code = String(err?.code ?? '');
        if (code === 'queue.duplicate') { if (selected.get(name) === ov) selected.delete(name); lines.push([name, 'warn', errorText(err)]); continue; }
        lines.push([name, 'err', errorText(err)]);
        if (code === 'queue.limit') { lines.push(['—', 'err', `Limite de la file atteinte (${MAX_ROWS}) : ajout interrompu.`]); break; }
      }
    }
    lastBatch = null;
    addReport.innerHTML = lines.length ? `<ul class="result-list">${lines.map(([n, tone, msg]) => `<li><span class="log-line">${icon(tone === 'ok' ? 'check' : tone === 'warn' ? 'info' : 'alert')}
      <span class="small${tone === 'err' ? '' : ' muted'}">${n !== '—' ? `<b class="mono">${esc(n)}</b> — ` : ''}${esc(msg)}</span></span></li>`).join('')}</ul>` : '';
    paintSelection();
    await refreshQueue();
    if (!isActive()) return;
    setBusy(false);
    updateCommands();
    if (lines.some(([, t]) => t === 'ok')) toast('File mise à jour : préparez le lot pour l’aperçu.', { tone: 'ok' });
  }

  addBtn.addEventListener('click', () => { addSelected(); });
  clearBtn.addEventListener('click', () => { if (busy || csvReading) return; selected.clear(); addReport.innerHTML = ''; paintSelection(); });
  refreshBtn.addEventListener('click', () => { if (!busy && !csvReading) refreshQueue(); });

  // ---------- batch : préparation (aperçu) puis exécution unique ----------

  function paintBatch() {
    if (!lastBatch) {
      batchZone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('play')}</span><h3>Lot préparé</h3></div>
        ${batchError ? refusalMarkup(batchError)
          : '<p class="muted">Aucun lot préparé : la préparation calcule un plan par poste et sert d’aperçu avant exécution.</p>'}`;
      setBusy(busy);
      updateCommands();
      return;
    }
    const rows = (lastBatch.items ?? []).map((p) => `<li><span class="log-line">${icon('chip')}
      <span class="mono">${esc(p.computer)}</span><span>→</span><span class="mono">${esc(p.newName || p.computer)}</span>
      <span class="muted small">${esc(KIND_LABEL[p.kind] ?? p.kind)} · ${esc(p.targetOU || '—')}${p.entraLeaveRequired === true ? ' · retrait Entra à confirmer' : ''}</span></span></li>`).join('');
    batchZone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('play')}</span><h3>Lot préparé — aperçu avant exécution</h3>
      <span class="meta">${pill('info', `${lastBatch.items?.length ?? 0} plan(s)`, { icon: 'chip' })}</span></div>
      <ul class="result-list">${rows}</ul>
      ${lastBatch.pilot ? `<p class="note">Mode pilote : une seule ligne sera envoyée. ${esc(lastBatch.remainingCount ?? 0)} ligne(s) resteront dans la file pour une nouvelle préparation.</p>` : ''}
      <div class="kv-grid"><span class="k">Lot</span><span class="v mono">${esc(lastBatch.batchId)}</span>
        <span class="k">Valide jusqu’à</span><span class="v">${esc(formatDateTime(lastBatch.expiresAt) ?? 'inconnue')}</span></div>
      ${(lastBatch.warnings ?? []).map((w) => `<p class="muted small">${icon('info')} ${esc(w)}</p>`).join('')}
      <div class="row-actions">
        <button class="btn primary" type="button" data-act="execute" ${cap.enabled ? '' : 'disabled'}>${icon('play')}Exécuter le lot</button>
        <span class="muted small">Séquentiel, une seule fois, arrêté à la première ligne en échec ou incertaine.</span>
      </div>
      <div data-zone="batch-report"></div>`;
    applyVars(batchZone);
    bindCopy(batchZone);
    batchZone.querySelector('[data-act="execute"]').addEventListener('click', () => { executeBatch(); });
    setBusy(busy);
    updateCommands();
  }

  async function prepareBatch() {
    if (busy || csvReading || !queueCount) return;
    setBusy(true);
    lastBatch = null;
    batchError = null;
    batchZone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('play')}</span><h3>Lot préparé</h3></div>
      <p class="muted" aria-busy="true">Préparation en cours auprès du moteur…</p>`;
    try {
      const pilot = pilotInput.checked;
      const b = await ctx.call('queue.prepare', { pilot });
      if (!isActive()) return;
      if ((b.pilot === true) !== pilot || (pilot && b.items?.length !== 1)) throw refusal('Le lot reçu ne correspond pas au choix pilote. Aucune exécution autorisée ; préparez à nouveau.');
      lastBatch = b;
      announce(`Lot préparé : ${b.items?.length ?? 0} plan(s). Vérifiez l’aperçu avant exécution.`);
    } catch (err) {
      if (!isActive()) return;
      batchError = err;
    }
    paintBatch();
    setBusy(false);
    updateCommands();
  }

  async function executeBatch() {
    if (!lastBatch || busy || csvReading) return;
    const batch = lastBatch;
    const items = batch.items ?? [];
    let entraItems;
    try { entraItems = items.filter((plan) => entraConfirmation(plan).required); }
    catch (error) { lastBatch = null; batchError = error; paintBatch(); return; }
    const shown = items.slice(0, 12).map((p) => ({ label: p.computer, after: p.newName || p.computer }));
    if (items.length > shown.length) shown.push({ label: '…', after: `+${items.length - shown.length} autre(s)` });
    // Every target requiring this additional effect is displayed, including those beyond the compact name list.
    shown.push(...entraItems.map((plan) => ({ label: 'Retrait Entra avant renommage', after: plan.computer })));
    let entraConfirmed = false;
    const answer = await confirmWrite({
      title: batch.pilot ? 'Confirmer le poste pilote' : 'Confirmer l’exécution du lot',
      badge: items.every((p) => p.mode === 'simulation') ? 'Démonstration · aucun effet réel' : undefined,
      message: 'Chaque poste recevra le nom et le placement de son plan, dans l’ordre affiché, une seule fois. L’exécution s’arrête à la première ligne en échec ou incertaine : rien n’est rejoué automatiquement.'
        + (batch.pilot ? ' Mode pilote : seule la première ligne sera envoyée ; le reste de la file exige un nouveau plan et une nouvelle confirmation.' : '')
        + (entraItems.length ? ` Un retrait Entra est prévu pour ${entraItems.length} poste(s) hybride(s) listé(s) ci-dessous ; leur réinscription restera à vérifier séparément.` : ''),
      target: batch.batchId,
      targetKind: 'l’identifiant du lot',
      changes: shown,
      checks: entraItems.length ? [{ id: 'entraLeave', label: 'J’autorise le retrait Entra de tous les postes expressément listés et je vérifierai séparément leur réinscription hybride.' }] : [],
      onChecks: (ids) => { entraConfirmed = ids.includes('entraLeave'); },
      details: `batchId ${lastBatch.batchId} · mode ${items[0]?.mode ?? 'inconnu'} · expire ${formatDateTime(lastBatch.expiresAt) ?? '?'}`
        + (lastBatch.warnings?.length ? `\n${lastBatch.warnings.join('\n')}` : ''),
      confirmLabel: 'Exécuter le lot',
    });
    if (answer !== 'confirm' || !isActive() || lastBatch !== batch || (entraItems.length && !entraConfirmed)) return;
    setBusy(true);
    const batchId = batch.batchId;
    let sent = false;
    try {
      items.forEach(entraConfirmation);
      sent = true;
      const res = await ctx.call('queue.execute', { batchId, confirmed: true,
        ...(entraItems.length ? { entraLeaveConfirmed: true } : {}) });
      if (!isActive()) return;
      lastBatch = null;
      batchError = null;
      const receipts = res?.receipts ?? [];
      const complete = items.length > 0 && receipts.length === items.length
        && receipts.every(receipt => typeof receipt?.id === 'string' && receipt.id.length > 0)
        && new Set(receipts.map(receipt => receipt.id)).size === receipts.length
        && items.every(plan => receipts.filter(receipt => receiptMatchesPlan(receipt, plan)).length === 1);
      const confirmed = complete && receipts.every((receipt) => receiptFeedback(receipt).confirmed);
      const needsReview = !!res?.stopped || !confirmed;
      const head = `<div class="card-head"><span class="card-icon">${icon('file')}</span><h3>Reçus du lot</h3>
        <span class="meta">${needsReview ? pill('warn', res?.stopped ? 'Lot arrêté' : 'États à vérifier', { icon: 'alert' }) : pill('ok', `${receipts.length} reçu(s)`, { icon: 'check' })}</span></div>`;
      const stopLine = res?.stopped
        ? `<p class="muted" role="alert">${icon('alert')} ${esc(res.reason || 'Le lot a été arrêté.')} Les lignes restantes restent dans la file : rien n’est rejoué automatiquement, consultez les interventions.</p>`
        : '';
      const incompleteLine = !complete && !res?.stopped
        ? '<p class="muted" role="alert">Les reçus reçus ne correspondent pas à toutes les lignes du lot préparé. Le lot reste à vérifier dans les interventions ; aucune ligne n’est rejouée automatiquement.</p>' : '';
      receiptZone.innerHTML = head + stopLine + incompleteLine + receipts.map(receiptMarkup).join('');
      applyVars(receiptZone);
      const summary = needsReview ? 'Lot à vérifier : consultez chaque reçu avant toute nouvelle action.' : `Lot confirmé : ${receipts.length} reçu(s).`;
      announce(summary);
      toast(summary, { tone: needsReview ? 'warn' : 'ok' });
    } catch (err) {
      if (!isActive()) return;
      lastBatch = null;
      batchError = err; // plan expiré ou consommé, file modifiée : nouveau lot à préparer, aucun rejeu automatique
    }
    // Even a stopped or failed batch may have renamed some rows: the listed search results can be stale.
    if (sent) staleResults();
    paintBatch();
    await refreshQueue();
    setBusy(false);
    updateCommands();
  }

  prepareBtn.addEventListener('click', () => { prepareBatch(); });
  pilotInput.addEventListener('change', () => {
    lastBatch = null; batchError = null; paintBatch();
    announce('Choix pilote modifié : préparez un nouveau lot avant toute exécution.');
  });

  // ---------- boot ----------

  if (!cap.enabled) toast(cap.reason, { tone: 'warn' });
  paintSelection();
  refreshQueue();
  return () => { alive = false; csvReader?.abort(); ctx.setScreenCommands([]); stops.forEach((stop) => stop()); };
}
