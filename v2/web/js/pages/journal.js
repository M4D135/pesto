// Journal : journaux du moteur (logs.list). Lecture seule : le filtre interroge le moteur, l'interface n'invente
// aucune ligne et n'en supprime aucune. Les niveaux sont ceux renvoyés par le moteur (info, warn, error…).
import { icon } from '../icons.js';
import { esc, applyVars, reveal, errorText, announce, formatDateTime } from '../ui.js';
import { pill } from '../kit/index.js';

const LEVEL = { info: ['accent', 'info'], warn: ['warn', 'alert'], error: ['alert', 'alert'], debug: ['off', 'info'] };

function row(l, n) {
  const [tone, ic] = LEVEL[l.level] ?? ['off', 'info'];
  return `<li data-j="${Math.min(n, 18)}"><span class="mk" aria-hidden="true"></span>
    <span class="log-line"><span class="log-time mono">${esc(formatDateTime(l.time) ?? '—')}</span>
    ${pill(tone, String(l.level ?? 'info'), { icon: ic, size: 'sm' })}
    <span class="log-msg">${esc(l.message ?? '')}</span></span></li>`;
}

function layout(query, level) {
  return `<div class="page">
    <header class="page-header reveal">
      <div class="head-row"><span class="page-icon">${icon('file')}</span>
        <div class="titles"><h1 class="gradient-text">Journal</h1>
          <p class="subtitle">Lignes lues du moteur, dans l’ordre du plus récent au plus ancien.</p></div></div>
      <div class="actions"><button class="btn" type="button" data-act="refresh">${icon('refresh')}Rafraîchir</button></div>
    </header>
    <section class="card reveal spot">
      <div class="card-head"><span class="card-icon">${icon('search')}</span><h3>Filtrer</h3></div>
      <form class="k-form" novalidate data-form="q">
        <div class="k-field w-half"><input class="input" type="search" name="query" placeholder="message…" value="${esc(query)}" aria-label="Filtrer les messages"></div>
        <div class="k-field w-half"><span class="k-select"><select name="level" aria-label="Niveau">
          <option value="">Tous les niveaux</option>
          ${['info', 'warn', 'error', 'debug'].map((v) => `<option value="${v}"${v === level ? ' selected' : ''}>${v}</option>`).join('')}
        </select></span></div>
      </form>
    </section>
    <section class="card reveal spot" data-zone="list" aria-busy="true" aria-live="polite">
      <div class="card-head"><span class="card-icon">${icon('file')}</span><h3>Lignes</h3></div>
      <p class="muted">Lecture du journal…</p>
    </section>
  </div>`;
}

export function render(main, ctx) {
  main.innerHTML = layout(ctx.params?.query ?? '', ctx.params?.level ?? '');
  applyVars(main);
  const stops = [reveal(main)];
  let alive = true;
  let latest = 0;
  const zone = main.querySelector('[data-zone="list"]');
  const qInput = main.querySelector('[name="query"]');
  const levelSelect = main.querySelector('[name="level"]');

  async function load() {
    const my = ++latest;
    zone.setAttribute('aria-busy', 'true');
    const args = {};
    if (qInput.value.trim()) args.query = qInput.value.trim();
    if (levelSelect.value) args.level = levelSelect.value;
    try {
      const { items } = await ctx.call('logs.list', args);
      if (!alive || my !== latest) return;
      if (!items?.length) {
        zone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('file')}</span><h3>Lignes</h3></div>
          <p class="muted">Aucune ligne pour ce filtre.</p>`;
      } else {
        zone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('file')}</span><h3>Lignes</h3>
          <span class="meta">${items.length} lue${items.length > 1 ? 's' : ''}</span></div>
          <ul class="feature-list cascade">${items.map(row).join('')}</ul>`;
      }
      zone.removeAttribute('aria-busy');
      applyVars(zone);
      stops.push(reveal(zone));
    } catch (err) {
      if (!alive || my !== latest) return;
      zone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('alert')}</span><h3>Lecture impossible</h3></div>
        <p class="muted" role="alert">${esc(errorText(err))}</p>`;
      zone.removeAttribute('aria-busy');
      announce(`Journal indisponible : ${errorText(err)}`, { assertive: true });
    }
  }

  let deb = 0;
  qInput.addEventListener('input', () => { clearTimeout(deb); deb = setTimeout(load, 350); });
  levelSelect.addEventListener('change', load);
  main.querySelector('[data-form="q"]').addEventListener('submit', (e) => { e.preventDefault(); load(); });
  main.querySelector('[data-act="refresh"]').addEventListener('click', load);

  ctx.setScreenCommands([
    { id: 'journal-refresh', kind: 'command', label: 'Relire le journal', icon: 'refresh', group: 'Journal', effect: 'read', available: true, detailText: 'Relit les lignes du moteur.', run: load },
  ]);

  load();
  return () => { alive = false; latest++; clearTimeout(deb); ctx.setScreenCommands([]); stops.forEach((stop) => stop()); };
}
