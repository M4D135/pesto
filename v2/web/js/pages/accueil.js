// Accueil : tableau de bord Pesto. Lit dashboard.read et session.info via le pont fermé ; null reste « inconnu »,
// jamais remplacé par une réussite fictive. Les activités sont les reçus de la session (jamais des événements inventés).
import { icon } from '../icons.js';
import { esc, applyVars, reveal, countUp, formatNumber, errorText, announce, toast } from '../ui.js';
import { pill, timeline, bindTimeline } from '../kit/index.js';
import { KIND_LABEL, STATUS_LABEL } from '../writeflow.js';

const UNREAD_TIP = 'Valeur inconnue : lecture impossible, jamais remplacée par 0.';

function kpiCard(label, value, { tone = 'accent', foot = '', icon: name = 'info' } = {}) {
  // span-3 obligatoire : .grid est en 12 colonnes (layout.css) — sans classe span, chaque carte KPI s'écrase à
  // 1/12 de largeur (défaut constaté en fenêtre réelle le 25/10 : texte coupé, grand espace vide à droite).
  return `<section class="card kpi reveal spot span-3" data-tone="${tone}">
    <span class="label">${icon(name)}${esc(label)}</span>
    <b class="value" data-kpi="${esc(label)}">—</b>
    <span class="foot">${esc(foot)}</span></section>`;
}

function layout() {
  return `<div class="page">
    <header class="page-header reveal">
      <div class="head-row"><span class="page-icon">${icon('home')}</span>
        <div class="titles"><h1 class="gradient-text">Accueil</h1>
          <p class="subtitle">Vue d’ensemble du parc simulé ou réel, selon le moteur connecté.</p></div></div>
      <div class="actions">
        <button class="btn" type="button" data-act="refresh">${icon('refresh')}Rafraîchir</button>
        <button class="btn primary" type="button" data-act="noms">${icon('star')}Noms disponibles</button>
      </div>
    </header>
    <div class="grid" data-zone="kpis" aria-busy="true">
      ${kpiCard('Postes suivis', null, { tone: 'accent', icon: 'monitor', foot: 'Ordinateurs du périmètre lu' })}
      ${kpiCard('Noms libres', null, { tone: 'ok', icon: 'star', foot: 'Disponibilités confirmées par lecture' })}
      ${kpiCard('Redémarrages en attente', null, { tone: 'warn', icon: 'power', foot: 'D’après les reçus durables relus' })}
      ${kpiCard('Résultats à vérifier', null, { tone: 'alert', icon: 'eye', foot: 'Reçus incertains relus : jamais rejoués' })}
    </div>
    <div class="grid">
      <section class="card span-7 reveal spot" data-zone="activity" aria-busy="true">
        <div class="card-head"><span class="card-icon">${icon('activity')}</span><h3>Dernières interventions</h3>
          <span class="meta"><button class="btn ghost sm" type="button" data-act="interventions">Tout voir</button></span></div>
        <p class="muted">Chargement…</p>
      </section>
      <section class="card span-5 reveal spot" data-zone="sites" aria-busy="true">
        <div class="card-head"><span class="card-icon">${icon('server')}</span><h3>Sites</h3></div>
        <p class="muted">Chargement…</p>
      </section>
    </div>
    <section class="card reveal spot" data-zone="session">
      <div class="card-head"><span class="card-icon">${icon('wifi')}</span><h3>Session</h3>
        <span class="meta" data-slot="mode"></span></div>
      <p class="muted" data-slot="session-line">Lecture de la session…</p>
    </section>
  </div>`;
}

function renderActivity(zone, receipts, history) {
  if (!receipts?.length) {
    zone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('activity')}</span><h3>Dernières interventions</h3></div>
      <p class="muted">Aucune intervention lue : ni reçu de la session, ni reçu durable dans le registre relu. Les reçus apparaîtront ici, marqués selon leur mode.</p>
      ${historyNote(history)}`;
    return;
  }
  const events = receipts.map((r) => ({
    when: r.time,
    title: `${esc(KIND_LABEL[r.kind] ?? r.kind)} · ${esc(r.computer)}${r.newName && r.newName !== r.computer ? ` → ${esc(r.newName)}` : ''}`,
    text: r.message ?? '',
    tone: r.status === 'refused' ? 'alert' : r.status === 'uncertain' ? 'warn' : r.mode === 'simulation' ? 'info' : 'ok',
    icon: r.mode === 'simulation' ? 'sparkles' : 'check',
    meta: `${r.mode === 'simulation' ? 'Simulé' : 'Réel'} · ${esc(STATUS_LABEL[r.status] ?? r.status ?? 'inconnu')}`,
  }));
  zone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('activity')}</span><h3>Dernières interventions</h3>
    <span class="meta"><button class="btn ghost sm" type="button" data-act="interventions">Tout voir</button></span></div>
    ${timeline(events, { label: 'Dernières interventions' })}
    ${historyNote(history)}`;
  bindTimeline(zone);
  zone.querySelector('[data-act="interventions"]')?.addEventListener('click', () => ctxGo('interventions'));
}

let ctxGo = () => {};

function renderSites(zone, sites) {
  if (!sites?.length) {
    zone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('server')}</span><h3>Sites</h3></div>
      <p class="muted">Aucun site configuré lu. Configurez les sites dans Paramètres.</p>`;
    return;
  }
  const rows = sites.map((s) => `<li><span>${esc(s.name)}</span><b class="num"${s.count === null ? ' data-tip="Compte inconnu : lecture d’inventaire incomplète, jamais remplacée par 0."' : ''}>${s.count === null ? '—' : formatNumber(s.count)}</b></li>`).join('');
  zone.innerHTML = `<div class="card-head"><span class="card-icon">${icon('server')}</span><h3>Sites</h3></div>
    <ul class="kv-list">${rows}</ul>`;
}

function historyNote(history) {
  if (!history) return '';
  if (!history.readable) return `<p class="muted small">${esc(history.reason ?? 'Historique durable non lu : les compteurs d’après reçus restent inconnus.')}</p>`;
  const bits = [`${history.validCount ?? 0} reçu(s) durable(s) relu(s)`];
  if (history.invalidCount) bits.push(`${history.invalidCount} fichier(s) illisible(s) — à faire contrôler, aucun verrou levé`);
  if (history.truncated) bits.push('liste tronquée à la borne v1 de 5 000 fichiers');
  return `<p class="muted small">Historique durable : ${esc(bits.join(' · '))}.</p>`;
}

export function render(main, ctx) {
  ctxGo = (id) => ctx.navigate(id);
  main.innerHTML = layout();
  applyVars(main);
  const stops = [reveal(main)];
  let alive = true;
  const latest = { n: 0 };

  const kpis = main.querySelector('[data-zone="kpis"]');
  const activity = main.querySelector('[data-zone="activity"]');
  const sites = main.querySelector('[data-zone="sites"]');
  const sessionLine = main.querySelector('[data-slot="session-line"]');
  const modeSlot = main.querySelector('[data-slot="mode"]');

  function paintSession() {
    const s = ctx.session();
    if (!s) { sessionLine.textContent = 'Session inconnue : le moteur n’a pas encore répondu.'; return; }
    const modePill = s.mode === 'simulation'
      ? pill('info', 'Simulation', { icon: 'sparkles', tip: 'Monde fictif en mémoire, aucun effet réel.' })
      : s.readOnly ? pill('accent', 'Lecture seule', { icon: 'lock', tip: 'Aucune écriture admise.' })
      : pill('ok', 'Annuaire réel', { icon: 'shield', tip: 'Faits observés sur ce poste.' });
    modeSlot.innerHTML = modePill;
    sessionLine.textContent = `Poste ${s.computer ?? 'inconnu'} · compte ${s.account ?? 'inconnu'} · domaine ${s.domain ?? 'non connecté'} · moteur ${s.version ?? '?'}`;
  }

  async function load(inventory = true) {
    const my = ++latest.n;
    kpis.setAttribute('aria-busy', 'true');
    try {
      const d = await ctx.call('dashboard.read', inventory ? {} : { inventory: false });
      if (!alive || my !== latest.n) return;
      const set = (label, value, { unknownText = 'inconnu' } = {}) => {
        const el = kpis.querySelector(`[data-kpi="${CSS.escape(label)}"]`);
        if (!el) return;
        if (value === null || value === undefined) { el.textContent = '—'; el.dataset.tip = `Valeur ${unknownText} : lecture incomplète, jamais remplacée par 0.`; return; }
        delete el.dataset.tip;
        countUp(el, value);
      };
      set('Postes suivis', d.computers);
      set('Noms libres', d.availableNames);
      set('Redémarrages en attente', d.pendingRestart);
      set('Résultats à vérifier', d.uncertain);
      renderActivity(activity, d.lastActivity, d.history);
      if (d.inventoryRead === false) {
        sites.innerHTML = '<div class="card-head"><span class="card-icon">' + icon('server') + '</span><h3>Sites</h3></div><p class="muted">Cliquez sur « Rafraîchir » pour compter les postes du parc.</p>';
      } else renderSites(sites, d.sites);
      kpis.removeAttribute('aria-busy');
      activity.removeAttribute('aria-busy');
      sites.removeAttribute('aria-busy');
      applyVars(main);
      stops.push(reveal(main));
      return true;
    } catch (err) {
      if (!alive || my !== latest.n) return false;
      // Old figures next to « Lecture impossible » would read as current: every KPI goes back to unknown,
      // through countUp so a count still animating from the previous read cannot write its figures back.
      kpis.querySelectorAll('[data-kpi]').forEach((el) => { countUp(el, NaN); el.dataset.tip = UNREAD_TIP; });
      kpis.removeAttribute('aria-busy');
      activity.innerHTML = `<div class="card-head"><span class="card-icon">${icon('alert')}</span><h3>Lecture impossible</h3></div>
        <p class="muted">${esc(errorText(err))}</p>`;
      sites.innerHTML = '<p class="muted">Non lu.</p>';
      activity.removeAttribute('aria-busy');
      sites.removeAttribute('aria-busy');
      announce(`Tableau de bord indisponible : ${errorText(err)}`, { assertive: true });
      return false;
    }
  }

  main.querySelector('[data-act="refresh"]').addEventListener('click', () => {
    ctx.refreshSession().then(paintSession).catch(() => {});
    load().then((ok) => { if (ok) toast('Tableau de bord relu.', { tone: 'info', life: 2200 }); });
  });
  main.querySelector('[data-act="noms"]').addEventListener('click', () => ctx.navigate('noms'));

  ctx.setScreenCommands([
    { id: 'accueil-refresh', kind: 'command', label: 'Rafraîchir le tableau de bord', icon: 'refresh', group: 'Accueil', effect: 'read', available: true, detailText: 'Relit le tableau de bord auprès du moteur.', run: () => load() },
    { id: 'accueil-noms', kind: 'command', label: 'Ouvrir Noms disponibles', icon: 'star', group: 'Accueil', available: true, detailText: 'Ouvre la calculatrice de noms.', run: () => ctx.navigate('noms') },
  ]);

  paintSession();
  load(ctx.session()?.mode !== 'live');
  return () => { alive = false; latest.n++; stops.forEach((stop) => stop()); };
}
