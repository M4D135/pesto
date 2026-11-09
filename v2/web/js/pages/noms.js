// Noms disponibles : calculateur d’aperçu branché sur names.preview. Le pont ne propose aucun nom si la lecture est
// incomplète (complete !== true) : l’écran affiche alors explicitement « inconnu », sans suggestion.
import { icon } from '../icons.js';
import { esc, applyVars, reveal, errorText, announce, formatDateTime } from '../ui.js';
import { field, createForm, pill, copyButton, bindCopy } from '../kit/index.js';

const TYPES = [
  { value: 'P', label: 'Portable' },
  { value: 'S', label: 'Fixe' },
  { value: 'V', label: 'Virtuel' },
];

function layout() {
  return `<div class="page">
    <header class="page-header reveal">
      <div class="head-row"><span class="page-icon">${icon('star')}</span>
        <div class="titles"><h1 class="gradient-text">Noms disponibles</h1>
          <p class="subtitle">Le nom se calcule dès que le site et le service sont sélectionnés.</p></div></div>
    </header>
    <div class="grid">
      <section class="card span-5 reveal spot">
        <div class="card-head"><span class="card-icon">${icon('settings')}</span><h3>Recherche</h3></div>
        <form class="k-form" novalidate data-form="preview"></form>
      </section>
      <section class="card span-7 reveal spot" data-zone="result">
        <div class="card-head"><span class="card-icon">${icon('sparkles')}</span><h3>Aperçu calculé</h3></div>
        <p class="muted">Choisissez un site et un service pour afficher le nom disponible.</p>
      </section>
    </div>
  </div>`;
}

function resultMarkup(p) {
  if (!p || p.complete !== true) {
    return `<p class="muted" role="status">${icon('alert')} Lecture incomplète : aucun nom disponible n’est confirmé.
      Relancez la recherche pour vérifier quels noms sont libres.</p>`;
  }
  const expiry = formatDateTime(p.expiresAt);
  return `<div class="name-preview" role="status">
    <b class="name mono">${esc(p.name)}</b>
    <div class="kv-grid">
      <span class="k">OU de destination</span><span class="v mono">${esc(p.ou ?? '—')}</span>
      <span class="k">Noms libres trouvés</span><span class="v">${esc(p.availableCount ?? '—')}</span>
      <span class="k">Source</span><span class="v">${esc(p.source ?? 'inconnue')}</span>
      <span class="k">Valide jusqu’à</span><span class="v">${esc(expiry ?? 'inconnue')}</span>
    </div>
    <div class="row-actions">
      ${copyButton(p.name, { label: 'Copier le nom' })}
      <button class="btn" type="button" data-act="other">${icon('refresh')}Un autre nom</button>
    </div>
    <p class="muted small">Cet aperçu expire à l’heure indiquée ; après expiration, un nouveau calcul est nécessaire.
      ${p.source === 'simulation' ? 'Aperçu simulé : aucun contact avec un annuaire réel.' : ''}</p>
  </div>`;
}

export function render(main, ctx) {
  main.innerHTML = layout();
  applyVars(main);
  const stops = [reveal(main)];
  let alive = true;
  let latest = 0;
  let lastArgs = null;
  let servicesToken = 0;
  let sitesToken = 0;

  const formHost = main.querySelector('[data-form="preview"]');
  const result = main.querySelector('[data-zone="result"]');

  formHost.innerHTML = [
    field({ name: 'type', label: 'Type de poste', type: 'radio', options: TYPES, value: 'P', required: true, width: 'full' }),
    field({ name: 'site', label: 'Site', type: 'select', options: [], placeholder: 'Chargement des sites…', required: true, width: 'half' }),
    field({ name: 'service', label: 'Service', type: 'select', options: [], placeholder: 'Chargement des services…', required: true, width: 'half' }),
    field({ name: 'computer', label: 'Poste concerné (facultatif)', hint: 'Pour un renommage : le poste garde son OU si le site ne change pas.', width: 'full', mono: true }),
    '<div class="row-actions"><button class="btn primary" type="submit">' + icon('sparkles') + 'Calculer un nom libre</button></div>',
  ].join('');

  const form = createForm(formHost, { onSubmit: (values) => compute(values, false) });

  // A failed read must not leave « Chargement… » forever: both lists say « Indisponible » and a retry is offered,
  // as on Un poste. The token drops a slower earlier attempt.
  async function loadSites() {
    const token = ++sitesToken;
    servicesToken++;
    formHost.querySelector('[data-zone="sites-retry"]')?.remove();
    formHost.querySelector('[name="site"]').innerHTML = '<option value="">Chargement des sites…</option>';
    formHost.querySelector('[name="service"]').innerHTML = '<option value="">Chargement des services…</option>';
    form.setMessage('site', null);
    form.setMessage('service', null);
    try {
      const { items } = await ctx.call('directory.sites');
      if (!alive || token !== sitesToken) return;
      const select = formHost.querySelector('[name="site"]');
      select.innerHTML = (items ?? []).map((s) => `<option value="${esc(s.selector ?? s.id)}">${esc(s.name === s.code || !s.name ? s.code : s.name + ' (' + s.code + ')')}</option>`).join('') || '<option value="">Aucun site trouvé</option>';
      if (!items?.length) {
        form.setMessage('site', 'Aucun site de la configuration n’a été trouvé. Vérifiez les OU dans Paramètres.', 'warn');
        formHost.querySelector('[name="service"]').innerHTML = '<option value="">Choisissez d’abord un site</option>';
        return;
      }
      loadServices(true);
    } catch (err) {
      if (!alive || token !== sitesToken) return;
      formHost.querySelector('[name="site"]').innerHTML = '<option value="">Indisponible</option>';
      formHost.querySelector('[name="service"]').innerHTML = '<option value="">Indisponible</option>';
      form.setMessage('site', errorText(err), 'error');
      formHost.querySelector('[type="submit"]').parentElement.insertAdjacentHTML('beforebegin',
        '<div class="row-actions" data-zone="sites-retry"><button class="btn" type="button" data-retry-sites>' + icon('refresh') + 'Réessayer le chargement des sites</button></div>');
    }
  }
  formHost.addEventListener('click', (e) => {
    if (!e.target.closest('[data-retry-sites]')) return;
    formHost.querySelector('[name="site"]').focus(); // the button is removed: keep the keyboard focus in the form
    loadSites();
  });

  async function loadServices(calculate = false) {
    const services = ++servicesToken;
    const site = formHost.querySelector('[name="site"]')?.value;
    if (!site) return;
    const select = formHost.querySelector('[name="service"]');
    form.setMessage('service', null);
    select.innerHTML = '<option value="">Chargement…</option>';
    try {
      const { items } = await ctx.call('directory.services', { site });
      if (!alive || services !== servicesToken) return;
      select.innerHTML = (items ?? []).map((s) => `<option value="${esc(s.code)}">${esc(s.name === s.code || !s.name ? s.code : s.name + ' (' + s.code + ')')}</option>`).join('') || '<option value="">Aucun service trouvé</option>';
      if (calculate && select.value) await compute(form.values(), false);
    } catch (err) {
      if (!alive || services !== servicesToken) return;
      select.innerHTML = '<option value="">Indisponible</option>';
      form.setMessage('service', errorText(err), 'error');
    }
  }

  formHost.addEventListener('change', (e) => {
    if (!['type', 'site', 'service', 'computer'].includes(e.target.name)) return;
    latest++; lastArgs = null;
    result.innerHTML = e.target.name === 'computer'
      ? '<p class="muted">Calculez le nom pour le poste indiqué.</p>'
      : '<p class="muted">En attente du site et du service.</p>';
    if (e.target.name === 'site') loadServices(true);
    else if (['type', 'service'].includes(e.target.name) && formHost.querySelector('[name="service"]').value)
      compute(form.values(), false);
  });

  async function compute(values, alternative) {
    if (!form.validate()) return;
    const my = ++latest;
    lastArgs = { type: values.type, site: values.site, service: values.service, computer: values.computer || undefined, alternative };
    result.innerHTML = '<p class="muted" aria-busy="true">Recherche d’un nom libre…</p>';
    try {
      const p = await ctx.call('names.preview', lastArgs);
      if (!alive || my !== latest) return;
      result.innerHTML = `<div class="card-head"><span class="card-icon">${icon('sparkles')}</span><h3>Aperçu calculé</h3>
        <span class="meta">${p.complete === true ? pill('ok', 'Nom libre confirmé', { icon: 'check' }) : pill('warn', 'Lecture incomplète', { icon: 'alert' })}</span></div>
        ${resultMarkup(p)}`;
      bindCopy(result);
      result.querySelector('[data-act="other"]')?.addEventListener('click', () => compute(values, true));
      announce(p?.complete === true ? `Nom proposé : ${p.name}.` : 'Lecture incomplète : aucun nom proposé.');
    } catch (err) {
      if (!alive || my !== latest) return;
      result.innerHTML = `<div class="card-head"><span class="card-icon">${icon('alert')}</span><h3>Calcul refusé</h3></div>
        <p class="muted" role="alert">${esc(errorText(err))}</p>`;
      announce(`Calcul refusé : ${errorText(err)}`, { assertive: true });
    }
  }

  ctx.setScreenCommands([
    { id: 'noms-compute', kind: 'command', label: 'Calculer un nom libre', icon: 'sparkles', group: 'Noms disponibles', effect: 'read', available: true, detailText: 'Relance le calcul avec les valeurs du formulaire.', run: () => formHost.requestSubmit() },
  ]);

  loadSites();
  return () => { alive = false; latest++; stops.forEach((stop) => stop()); };
}
