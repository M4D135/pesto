// Un poste — renommage et déplacement (mission Pesto v2). Recherche bornée puis identité lue (computer.inspect) ;
// le nom est calculé par names.preview avant toute activation. Renommage : plan lié à l'aperçu, confirmation exacte,
// exécution unique, reçu. Déplacement seul comme V1 GoMoveOnly : identité relue, capacité serveur, plan et confirmation.
// Même site = OU inchangée, donc la destination exclut le site courant. Collision après
// préparation = nouvel aperçu + nouveau clic, jamais de nouvel ajout automatique.
import { icon } from '../icons.js';
import { esc, applyVars, reveal, errorText, announce, toast, formatDateTime } from '../ui.js';
import { field, createForm, pill, bindCopy } from '../kit/index.js';
import { confirmAndExecute, refusalMarkup, receiptMarkup, receiptFeedback } from '../writeflow.js';

const TYPES = [
  { value: 'P', label: 'Portable' },
  { value: 'S', label: 'Fixe' },
  { value: 'V', label: 'Virtuel' },
];

function readOnlyReason(computer) {
  if (computer.inManagedScope === false) return 'Lecture seule : ce poste est hors de la racine gérée.';
  if (computer.inManagedScope !== true) return 'Lecture seule : le périmètre de ce poste n’est pas confirmé.';
  if (computer.status !== 'known' || !computer.guid || !computer.name) return 'Lecture seule : l’identité ou l’état de ce poste n’est pas confirmé.';
  return '';
}

function layout() {
  return `<div class="page">
    <header class="page-header reveal">
      <div class="head-row"><span class="page-icon">${icon('monitor')}</span>
        <div class="titles"><h1 class="gradient-text">Un poste</h1>
          <p class="subtitle">Renommer ou déplacer un poste après lecture de son identité et confirmation du plan.</p></div></div>
    </header>
    <div class="grid">
      <section class="card span-5 reveal spot">
        <div class="card-head"><span class="card-icon">${icon('monitor')}</span><h3>Poste à modifier</h3></div>
        <form class="k-form" novalidate data-form="target"></form>
        <form class="k-form" novalidate data-form="search" hidden></form>
        <div data-zone="results" aria-live="polite"></div>
      </section>
      <section class="card span-7 reveal spot" data-zone="identity">
        <div class="card-head"><span class="card-icon">${icon('shield')}</span><h3>Identité lue</h3></div>
        <p class="muted">Aucun poste sélectionné.</p>
      </section>
    </div>
    <div class="grid">
      <section class="card span-6 reveal spot" data-zone="rename">
        <div class="card-head"><span class="card-icon">${icon('sync')}</span><h3>Renommer</h3></div>
        <p class="muted">Sélectionnez d’abord un poste.</p>
      </section>
      <section class="card span-6 reveal spot" data-zone="move">
        <div class="card-head"><span class="card-icon">${icon('folder')}</span><h3>Déplacer</h3></div>
        <p class="muted">Sélectionnez un poste pour relire son identité avant de préparer le déplacement.</p>
      </section>
    </div>
    <section class="card reveal spot" data-zone="receipt">
      <div class="card-head"><span class="card-icon">${icon('file')}</span><h3>Reçus de la session</h3></div>
      <p class="muted">Aucune écriture demandée ici.</p>
    </section>
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
  let sites = [];
  let sitesState = 'loading';
  let sitesError = '';
  let sitesLoading = false;
  let current = null;        // computer.inspect payload
  let renamePreview = null;  // names.preview payload for the rename flow
  let busy = false;
  let selectionToken = 0;
  let renameToken = 0;       // stale names.preview responses are ignored, never painted

  const results = main.querySelector('[data-zone="results"]');
  const identity = main.querySelector('[data-zone="identity"]');
  const renameZone = main.querySelector('[data-zone="rename"]');
  const moveZone = main.querySelector('[data-zone="move"]');
  const receiptZone = main.querySelector('[data-zone="receipt"]');
  const capRename = ctx.capability('rename');
  const capMove = ctx.capability('move');

  function addReceipt(r) {
    const line = receiptZone.querySelector('p');
    if (line) line.remove();
    receiptZone.insertAdjacentHTML('afterbegin', receiptMarkup(r));
    applyVars(receiptZone);
  }

  // ---------- target: this PC by default, as in V1, or another domain computer ----------

  // The engine treats the local name as the local target: Rename-Computer here, never a remote call.
  const localName = ctx.session()?.computer || '';
  // Membership read by Windows itself, without the directory; null or absent means it could not be read.
  const localJoined = ctx.session()?.localJoined;
  let target = localName ? 'local' : 'remote';
  const targetHost = main.querySelector('[data-form="target"]');
  targetHost.innerHTML = field({ name: 'target', label: 'Poste concerné', type: 'radio', width: 'full', value: target,
    options: [{ value: 'local', label: localName ? `Ce poste (${localName})` : 'Ce poste (nom non lu)', disabled: !localName },
      { value: 'remote', label: 'Un autre poste du domaine' }] });
  createForm(targetHost, { onChange: (values) => { if (values.target && values.target !== target) chooseTarget(values.target); } });

  function chooseTarget(next) {
    if (busy) {
      targetHost.querySelector(`input[value="${target}"]`).checked = true;
      toast('Une opération est en cours sur le poste sélectionné : terminez-la avant de changer de poste.', { tone: 'warn' });
      return;
    }
    target = next;
    applyTarget();
  }

  // Switching target drops the previous selection, so no action can reach the other computer.
  function applyTarget() {
    searchSequence++;
    searchHost.hidden = target !== 'remote';
    if (target === 'remote') {
      clearSelection('Aucun poste sélectionné.');
      results.innerHTML = '<p class="muted">Saisissez un nom ou un fragment.</p>';
      return;
    }
    results.innerHTML = '';
    // The join capability only says that joining is allowed; membership comes from Windows, never from that capability.
    if (localJoined === false) { selectionToken++; renameToken++; current = null; renamePreview = null; paintLocalAbsent(); return; }
    select(localName);
  }

  // A workgroup PC goes to the join page without any directory read (an AD object of the same name is not this PC);
  // a member PC whose name the directory does not know (account deleted or renamed) is checked in AD, never joined again.
  function paintLocalAbsent() {
    const member = localJoined === true;
    identity.innerHTML = `<div class="card-head"><span class="card-icon">${icon('shield')}</span><h3>Identité lue</h3></div>
      ${member ? `<p class="muted" role="alert">${icon('alert')} Ce poste est membre d’un domaine, mais l’annuaire ne connaît pas le nom ${esc(localName)} : son compte a pu être supprimé ou renommé. Vérifiez-le dans l’AD ; ne rejoignez pas ce poste de nouveau.</p>`
        : `<p class="muted" role="status">${localJoined === false ? 'Ce poste n’est pas membre du domaine' : 'Ce poste n’est pas encore dans l’annuaire du domaine'} : utilisez « Ajouter ce PC au domaine ».</p>`}`;
    renameZone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('sync')}</span><h3>Renommer</h3></div><p class="muted">${member ? 'Lecture impossible.' : 'Disponible une fois ce poste dans l’annuaire.'}</p>`;
    paintMove();
  }

  function clearSelection(message) {
    selectionToken++;
    renameToken++;
    current = null;
    renamePreview = null;
    identity.innerHTML = `<div class="card-head"><span class="card-icon">${icon('shield')}</span><h3>Identité lue</h3></div><p class="muted">${esc(message)}</p>`;
    renameZone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('sync')}</span><h3>Renommer</h3></div><p class="muted">Sélectionnez d’abord un poste.</p>`;
    paintMove();
  }

  // ---------- search ----------

  const searchHost = main.querySelector('[data-form="search"]');
  searchHost.innerHTML = field({ name: 'query', label: 'Nom ou fragment', type: 'search', required: true, mono: true });
  const searchForm = createForm(searchHost, {
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
        results.querySelectorAll('[data-pick]').forEach((b) => b.addEventListener('click', () => select(b.dataset.pick)));
      } catch (err) {
        if (!isActive() || request !== searchSequence) return;
        results.innerHTML = `<p class="muted" role="alert">${esc(errorText(err))}</p>`;
      }
    },
  });

  // After a write the listed names may no longer exist: drop them (and any search still running) rather than
  // offer a stale row whose click would fail. No automatic re-query: the field may have been edited since.
  function staleResults() {
    searchSequence++;
    if (target === 'remote') results.innerHTML = '<p class="muted" role="status">Un poste a changé : relancez la recherche.</p>';
  }

  // ---------- identity ----------

  async function select(name) {
    if (busy) return;
    const selected = ++selectionToken;
    renameToken++;
    current = null;
    renameZone.innerHTML = '<p class="muted">Lecture du poste sélectionné…</p>';
    paintMove();
    identity.innerHTML = '<p class="muted" aria-busy="true">Lecture du poste…</p>';
    renamePreview = null;
    try {
      const c = await ctx.call('computer.inspect', { computer: name });
      if (!alive || selected !== selectionToken) return;
      current = c;
      const rows = [
        ['Nom', c.name], ['DNS', c.dnsName ?? 'inconnu'], ['Site', c.site ?? 'inconnu'], ['Service', c.service ?? 'inconnu'],
        ['OU', c.ou ?? 'inconnue'], ['OS', c.os ?? 'inconnu'], ['GUID', c.guid ?? 'inconnu'], ['État', c.status ?? 'inconnu'],
      ];
      identity.innerHTML = `<div class="card-head"><span class="card-icon">${icon('shield')}</span><h3>Identité lue</h3>
        <span class="meta">${c.pendingRestart ? pill('warn', 'Redémarrage en attente', { icon: 'power' }) : pill('ok', 'À jour', { icon: 'check' })}</span></div>
        <div class="kv-grid">${rows.map(([k, v]) => `<span class="k">${esc(k)}</span><span class="v mono">${esc(v)}</span>`).join('')}</div>
        ${(c.checks ?? []).map((k) => `<p class="muted small">${esc(k.label)} — ${esc(k.detail ?? k.state)}</p>`).join('')}
        ${ctx.session()?.mode === 'live' ? `<div class="row-actions"><a class="btn" href="#/attributs?computer=${encodeURIComponent(c.name)}">${icon('file')}Lire les attributs AD</a></div>` : ''}`;
      buildRenameForm();
      paintMove();
      announce(`Poste sélectionné : ${c.name}.`);
    } catch (err) {
      if (!alive || selected !== selectionToken) return;
      current = null;
      if (target === 'local' && name === localName && err?.code === 'computer.missing') { paintLocalAbsent(); return; }
      identity.innerHTML = `<div class="card-head"><span class="card-icon">${icon('shield')}</span><h3>Identité lue</h3></div>
        <p class="muted" role="alert">${icon('alert')} ${esc(errorText(err))}</p>`;
      renameZone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('sync')}</span><h3>Renommer</h3></div><p class="muted">Lecture impossible.</p>`;
      paintMove();
    }
  }

  // ---------- rename ----------

  const same = (a, b) => typeof a === 'string' && typeof b === 'string' && a.trim().toUpperCase() === b.trim().toUpperCase();

  // The live reader returns the naming code (PA); demonstration readers return the site id (paris).
  // Do not fall back from an unknown live code to an unrelated id with the same spelling.
  function sourceSites(computer) {
    const field = ctx.session()?.mode === 'simulation' ? 'id' : 'code';
    return sites.filter((site) => same(site[field], computer.site));
  }

  function sourceSite(computer) {
    const candidates = sourceSites(computer);
    if (candidates.length === 1) return candidates[0];
    const inSourceOu = candidates.filter((site) => typeof computer.ou === 'string' && typeof site.ou === 'string'
      && (same(computer.ou, site.ou) || computer.ou.toUpperCase().endsWith(',' + site.ou.toUpperCase())));
    return inSourceOu.length === 1 ? inSourceOu[0] : null;
  }

  function sameSite(site, computer) {
    return !!site && sourceSites(computer).some((source) => same(source.code, site.code));
  }

  function waitForSites(zone, heading) {
    if (sitesState === 'ready' && sites.length) return false;
    const message = sitesState === 'loading'
      ? '<p class="muted" role="status" aria-busy="true">Chargement des sites avant de proposer les choix…</p>'
      : sitesState === 'failed'
      ? `<p class="muted" role="alert">Les sites n’ont pas pu être chargés : ${esc(sitesError)}</p><button class="btn" type="button" data-retry-sites>Réessayer le chargement des sites</button>`
      : '<p class="muted" role="status">Aucun site configuré : ajoutez-en dans Paramètres avant de préparer une opération.</p>';
    zone.innerHTML = `<div class="card-head"><h3>${esc(heading)}</h3></div>${message}`;
    zone.querySelector('[data-retry-sites]')?.addEventListener('click', loadSites);
    return true;
  }

  function buildRenameForm() {
    if (!current) return;
    if (waitForSites(renameZone, `Renommer ${current.name}`)) return;
    const target = current;
    const selected = selectionToken;
    const blocked = readOnlyReason(target) || (!capRename.enabled && capRename.reason);
    let servicesToken = 0;
    let previewValues = null;
    const site = sourceSite(current);
    renameZone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('sync')}</span><h3>Renommer ${esc(current.name)}</h3></div>
      <form class="k-form" novalidate data-form="rename"></form>
      <div data-zone="rpreview" aria-live="polite"><p class="muted">Aucun aperçu : renommage désactivé.</p></div>
      <div class="row-actions">
        <button class="btn primary" type="button" data-act="apply" disabled>${icon('sync')}Appliquer le renommage</button>
        <span data-slot="rhint" class="muted small">Calculez d’abord un nom libre.</span>
      </div>`;
    const host = renameZone.querySelector('[data-form="rename"]');
    host.innerHTML = [
      field({ name: 'type', label: 'Type', type: 'radio', options: TYPES, value: guessType(current), required: true, width: 'full' }),
      field({ name: 'site', label: 'Site', type: 'select', options: sites.map((s) => ({ value: s.id, label: `${s.name} (${s.code})` })), value: site?.id ?? '', placeholder: site ? undefined : 'Choisissez le site', required: true, width: 'half' }),
      field({ name: 'service', label: 'Service', type: 'text', value: target.service ?? '', placeholder: 'Code service (3 caractères)', required: true,
        maxLength: 3, pattern: '[A-Za-z0-9]{3}', patternMessage: 'Saisissez un code service de trois caractères.',
        hint: 'Suggestions AD disponibles ; vous pouvez aussi saisir un nouveau code.', width: 'half' }),
      '<div class="row-actions"><button class="btn" type="submit">' + icon('sparkles') + 'Calculer le nom libre</button></div>',
    ].join('');
    const form = createForm(host, { onSubmit: (values) => computeRename(values) });
    const serviceInput = host.querySelector('[name="service"]');
    const serviceList = document.createElement('datalist');
    serviceList.id = 'pesto-service-suggestions-' + selected;
    serviceInput.setAttribute('list', serviceList.id);
    serviceInput.insertAdjacentElement('afterend', serviceList);
    serviceInput.addEventListener('input', () => {
      const start = serviceInput.selectionStart, end = serviceInput.selectionEnd;
      const normalized = serviceInput.value.toUpperCase();
      if (normalized !== serviceInput.value) {
        serviceInput.value = normalized;
        serviceInput.setSelectionRange(start, end);
      }
    });
    const rpreview = renameZone.querySelector('[data-zone="rpreview"]');
    const apply = renameZone.querySelector('[data-act="apply"]');
    const rhint = renameZone.querySelector('[data-slot="rhint"]');

    async function loadServices(calculate = false) {
      const services = ++servicesToken;
      const siteId = host.querySelector('[name="site"]').value;
      form.setMessage('service', null);
      if (!siteId) { serviceList.replaceChildren(); return; }
      serviceList.innerHTML = '';
      try {
        const { items } = await ctx.call('directory.services', { site: siteId });
        if (!alive || selected !== selectionToken || services !== servicesToken) return;
        serviceList.innerHTML = (items ?? []).map((s) => `<option value="${esc(s.code)}" label="${esc(s.name === s.code || !s.name ? s.code : s.name + ' (' + s.code + ')')}"></option>`).join('');
        if (!(items ?? []).length) form.setMessage('service', 'Aucun service connu pour ce site : saisissez le code manuellement.', 'warn');
        if (calculate && serviceInput.value.trim() && host.isConnected) await computeRename(form.values());
      } catch (err) {
        if (!alive || selected !== selectionToken || services !== servicesToken) return;
        // La panne de suggestions ne doit pas interdire un code service saisi manuellement.
        form.setMessage('service', 'Suggestions AD indisponibles : vous pouvez saisir le code manuellement.', 'warn');
      }
    }
    host.addEventListener('change', (e) => {
      if (!['type', 'site', 'service'].includes(e.target.name)) return;
      renameToken++; renamePreview = null; previewValues = null; paintPreview();
      if (e.target.name === 'site') loadServices(true);
      else if (host.querySelector('[name="service"]').value) computeRename(form.values());
    });

    function paintPreview() {
      if (!renamePreview) {
        rpreview.innerHTML = '<p class="muted">Aucun aperçu : renommage désactivé.</p>';
        apply.disabled = true;
        rhint.textContent = blocked || 'Calculez d’abord un nom libre.';
        return;
      }
      rpreview.innerHTML = `<div class="name-preview"><b class="name mono">${esc(renamePreview.name)}</b>
        <div class="kv-grid"><span class="k">OU prévue</span><span class="v mono">${esc(renamePreview.ou ?? '—')}</span>
        <span class="k">Valide jusqu’à</span><span class="v">${esc(formatDateTime(renamePreview.expiresAt) ?? 'inconnue')}</span></div></div>`;
      bindCopy(rpreview);
      apply.disabled = !capRename.enabled || !!blocked;
      rhint.textContent = blocked || 'Nom confirmé libre par le moteur.';
    }

    async function computeRename(values) {
      if (!form.validate()) return;
      const token = ++renameToken;
      renamePreview = null; previewValues = null; apply.disabled = true;
      rpreview.innerHTML = '<p class="muted" aria-busy="true">Calcul en cours…</p>';
      try {
        const p = await ctx.call('names.preview', {
          type: values.type, site: values.site, service: values.service, computer: target.name,
        });
        if (!alive || token !== renameToken || selected !== selectionToken) return;
        if (p?.complete !== true) {
          rpreview.innerHTML = `<p class="muted" role="status">${icon('alert')} Lecture incomplète : le nom reste inconnu.</p>`;
          apply.disabled = true;
          return;
        }
        renamePreview = p;
        previewValues = { ...values };
        paintPreview();
      } catch (err) {
        if (!alive || token !== renameToken || selected !== selectionToken) return;
        paintPreview();
        rpreview.innerHTML = refusalMarkup(err);
        rhint.textContent = blocked || 'Le calcul a été refusé : consultez le motif avant de réessayer.';
        announce(`Calcul refusé : ${errorText(err)}`, { assertive: true });
      }
    }

    async function replaceTakenPreview(values, oldName) {
      await computeRename(values);
      if (renamePreview) rhint.textContent = oldName + ' a été pris. Vérifiez le nouveau nom puis cliquez sur Appliquer le renommage.';
    }

    apply.addEventListener('click', async () => {
      if (!renamePreview || busy || !current || blocked || !capRename.enabled) return;
      const values = form.values();
      if (selected !== selectionToken || current !== target || !previewValues || ['type', 'site', 'service'].some((key) => values[key] !== previewValues[key])) {
        renameToken++; renamePreview = null; paintPreview(); announce('Les choix ont changé : calculez un nouvel aperçu.'); return;
      }
      const token = renameToken;
      const previewId = renamePreview.previewId;
      const oldName = renamePreview.name;
      const changedSite = !sameSite(sites.find((site) => site.id === previewValues.site), target);
      const kind = changedSite ? 'renameMove' : 'rename';
      busy = true;
      apply.disabled = true;
      const preparing = document.createElement('p');
      preparing.className = 'muted small';
      preparing.setAttribute('role', 'status');
      preparing.setAttribute('aria-busy', 'true');
      preparing.textContent = 'Vérification Windows, AD et Entra en cours. Un diagnostic temporaire peut être nécessaire sur le poste ; le renommage attend votre confirmation.';
      rpreview.append(preparing);
      try {
        const plan = await ctx.call('operation.prepare', { kind, computer: target.name, previewId });
        if (!alive || selected !== selectionToken || token !== renameToken || renamePreview?.previewId !== previewId) return;
        preparing.remove();
        const guardedCall = (op, args) => {
          if (!alive || selected !== selectionToken || current !== target || token !== renameToken || renamePreview?.previewId !== previewId)
            throw Object.assign(new Error('Le poste ou les choix ont changé : préparez un nouveau plan.'), { code: 'plan.contextChanged' });
          return ctx.call(op, args);
        };
        const outcome = await confirmAndExecute(guardedCall, plan, {
          title: `Confirmer le ${plan.kind === 'renameMove' ? 'renommage et déplacement' : 'renommage'}`,
          message: 'Une seule exécution, liée à cet aperçu. Aucun redémarrage automatique.',
          targetKind: 'le nouveau nom',
        });
        if (!isActive()) return;
        if (outcome.ok) {
          addReceipt(outcome.receipt);
          staleResults();
          const result = receiptFeedback(outcome.receipt);
          toast(result.text, { tone: result.tone });
          renamePreview = null;
          paintPreview();
          if (result.confirmed) { busy = false; select(outcome.receipt?.newName ?? target.name); }
          else requireFreshInspection(result.text);
          paintMove();
        } else if (outcome.reason === 'collision' && outcome.error?.code === 'name.taken') {
          if (selected === selectionToken && token === renameToken && current === target)
            await replaceTakenPreview(values, oldName);
        } else if (outcome.reason === 'collision') {
          rpreview.innerHTML = refusalMarkup(outcome.error, { collision: true });
          renamePreview = null;
          apply.disabled = true;
        } else if (outcome.reason === 'error') {
          // A transport failure or foreign receipt after execute does not prove the rename did not happen.
          if (outcome.sent) staleResults();
          rpreview.innerHTML = refusalMarkup(outcome.error);
          renamePreview = null;
          apply.disabled = true;
        }
      } catch (err) {
        if (!isActive() || selected !== selectionToken || token !== renameToken || current !== target) return;
        if (err?.code === 'name.taken') await replaceTakenPreview(values, oldName);
        else { rpreview.innerHTML = refusalMarkup(err); renamePreview = null; apply.disabled = true; }
      } finally {
        preparing.remove();
        busy = false;
        if (alive && current === target && renamePreview) apply.disabled = !capRename.enabled || !!blocked;
      }
    });

    paintPreview();
    loadServices();
  }

  function guessType(c) {
    if (TYPES.some((type) => type.value === c.type)) return c.type;
    const m = String(c.model ?? '').toLowerCase();
    if (m.includes('portable') || m.includes('laptop')) return 'P';
    if (m.includes('virtuel') || m.includes('virtual') || m.includes('vm')) return 'V';
    if (m.includes('fixe') || m.includes('desktop')) return 'S';
    return '';
  }

  function requireFreshInspection(message) {
    current = null; renamePreview = null; renameToken++;
    staleResults();
    identity.innerHTML = `<div class="card-head"><h3>État à vérifier</h3></div><p class="muted" role="status">${esc(message)}</p>`;
    renameZone.innerHTML = '<p class="muted">Relisez le poste avant toute nouvelle demande.</p>';
  }

  // ---------- move (V1 GoMoveOnly: no prior rename required) ----------

  function paintMove() {
    if (!current) {
      moveZone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('folder')}</span><h3>Déplacer</h3></div>
        <p class="muted">Sélectionnez un poste pour relire son identité avant de préparer le déplacement.</p>`;
      return;
    }
    if (!current.name || !current.guid) {
      moveZone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('folder')}</span><h3>Déplacer</h3></div>
        <p class="muted" role="status">L’identité du poste est incomplète : relisez-la avant de préparer un déplacement.</p>`;
      return;
    }
    if (!capMove.enabled) {
      moveZone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('folder')}</span><h3>Déplacer ${esc(current.name)}</h3></div>
        <p class="muted" role="status">${esc(readOnlyReason(current) || capMove.reason)}</p>`;
      return;
    }
    if (waitForSites(moveZone, `Déplacer ${current.name}`)) return;
    const inspected = current;
    const blocked = readOnlyReason(inspected);
    const others = sites.filter((site) => !sameSite(site, current) && !same(site.ou, current.ou));
    moveZone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('folder')}</span><h3>Déplacer ${esc(current.name)}</h3>
      <span class="meta">${pill('ok', 'Identité relue', { icon: 'check' })}</span></div>
      <form class="k-form" novalidate data-form="move"></form>
      <div class="row-actions">
        <button class="btn primary" type="button" data-act="domove" ${others.length && !blocked ? '' : 'disabled'}>${icon('folder')}Déplacer le poste</button>
        <span class="muted small">${esc(blocked || 'Même site = OU inchangée : le site courant n’est pas proposé.')}</span>
      </div>`;
    const host = moveZone.querySelector('[data-form="move"]');
    host.innerHTML = field({
      name: 'site', label: 'Site de destination', type: 'select', required: true,
      options: others.map((s) => ({ value: s.ou, label: `${s.name} (${s.code})` })),
      placeholder: sourceSite(current) ? undefined : 'Choisissez le site de destination',
      hint: `L’OU cible est l’OU du site : ${others.map((s) => s.name).join(', ') || 'aucun autre site configuré'}.`,
    });
    const form = createForm(host);
    moveZone.querySelector('[data-act="domove"]').addEventListener('click', async () => {
      if (busy || current !== inspected || blocked || !form.validate()) return;
      const target = current;
      const destination = form.values().site;
      busy = true;
      moveZone.querySelectorAll('[data-refusal]').forEach((el) => el.remove());
      const preparing = document.createElement('p');
      preparing.className = 'muted small';
      preparing.setAttribute('role', 'status');
      preparing.setAttribute('aria-busy', 'true');
      preparing.textContent = 'Relecture de l’identité AD et de l’OU de destination avant confirmation…';
      moveZone.append(preparing);
      try {
        const plan = await ctx.call('operation.prepare', { kind: 'move', computer: target.name, targetOU: destination });
        if (!alive || current !== target || form.values().site !== destination) return;
        preparing.remove();
        const guardedCall = (op, args) => {
          if (!alive || current !== target || form.values().site !== destination)
            throw Object.assign(new Error('Le poste ou la destination a changé : préparez un nouveau déplacement.'), { code: 'plan.contextChanged' });
          return ctx.call(op, args);
        };
        const outcome = await confirmAndExecute(guardedCall, plan, {
          title: 'Confirmer le déplacement',
          message: 'Le compte du poste rejoindra l’OU du site choisi. Une seule exécution.',
          targetKind: 'le nom du poste',
          confirmLabel: 'Confirmer le déplacement',
        });
        if (!isActive()) return;
        if (outcome.ok) {
          addReceipt(outcome.receipt);
          const result = receiptFeedback(outcome.receipt);
          toast(result.text, { tone: result.tone });
          if (result.confirmed) { busy = false; select(target.name); }
          else { requireFreshInspection(result.text); paintMove(); }
        } else if (outcome.reason !== 'cancelled') {
          moveZone.insertAdjacentHTML('beforeend',
            `<div data-refusal>${refusalMarkup(outcome.error, { collision: outcome.reason === 'collision' })}</div>`);
        }
      } catch (err) {
        if (!isActive()) return;
        moveZone.insertAdjacentHTML('beforeend', `<div data-refusal>${refusalMarkup(err)}</div>`);
      } finally {
        preparing.remove();
        busy = false;
      }
    });
  }

  // ---------- boot ----------

  async function loadSites() {
    if (!isActive() || sitesLoading) return;
    sitesLoading = true;
    sitesState = 'loading';
    sitesError = '';
    if (current) { buildRenameForm(); paintMove(); }
    try {
      const { items } = await ctx.call('directory.sites');
      if (!isActive()) return;
      sites = (items ?? []).map(site => ({ ...site, id: site.selector ?? site.id }));
      sitesState = 'ready';
      if (!sites.length) toast('Aucun site configuré : ajoutez-en dans Paramètres.', { tone: 'warn' });
    } catch (err) {
      if (!isActive()) return;
      sitesState = 'failed';
      sitesError = errorText(err);
      toast(errorText(err), { tone: 'alert' });
    } finally {
      sitesLoading = false;
      // No editable form exists before this catalogue succeeds, so late arrival cannot replace a draft.
      if (isActive() && current) { buildRenameForm(); paintMove(); }
    }
  }

  ctx.setScreenCommands([
    { id: 'unposte-search', kind: 'command', label: 'Rechercher un poste', icon: 'search', group: 'Un poste', effect: 'read', available: true, detailText: 'Ouvre la recherche bornée d’un autre poste du domaine.', run: () => {
      if (target !== 'remote' && !busy) { targetHost.querySelector('input[value="remote"]').checked = true; chooseTarget('remote'); }
      searchHost.querySelector('input')?.focus();
    } },
  ]);

  loadSites();
  applyTarget();
  return () => { alive = false; ctx.setScreenCommands([]); stops.forEach((stop) => stop()); };
}
