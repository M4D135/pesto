// Pesto 2 shell: navigation rail (248 px, folded 72 px, Ctrl+B at the very bottom), glass top bar, mode chip,
// simulation banner, theme and motion switches, command palette (Ctrl+K), shortcuts and router.
// The only native capability is the closed bridge (docs/BRIDGE.md): this file never reaches the host directly.
import { call } from './bridge.js';
import { icon } from './icons.js';
import {
  esc, errorText, initLive, initPointerEffects, inkFollow, setBusy, motionReduced, cssMs, announce,
} from './ui.js';
import { createRouter } from './router.js';
import { createPalette } from './palette.js';
import { openMenu, confirmDialog } from './kit/index.js';
import { modalOpen, isTextEntry } from './kit/util.js';
import { state, on, emit, setPrefs, adoptMode, NAV_MIN, NAV_MAX, NAV_DEFAULT, NAV_COLLAPSED } from './shell/store.js';

const root = document.documentElement;
const NBSP = ' ';

const OFFLINE_ENTRY = location.hash.split('?')[0] === '#/offline-join';
const CONFIGURATION_ENTRY = new URLSearchParams(location.search).get('configuration') === 'local';
const PAGES = OFFLINE_ENTRY ? [{ id: 'offline-join', label: 'Jonction hors ligne', icon: 'power', section: 'Postes', keywords: 'blob local import appliquer observer' }] : [
  { id: 'accueil', label: 'Accueil', icon: 'home', section: 'Pilotage', keywords: 'tableau de bord kpi postes redemarrage' },
  { id: 'ajouter', label: 'Ajouter ce PC au domaine', icon: 'power', section: 'Postes', keywords: 'jonction domaine join nouveau poste' },
  { id: 'unposte', label: 'Un poste', icon: 'monitor', section: 'Postes', keywords: 'renommer deplacer rename move ordinateur' },
  { id: 'plusieurspostes', label: 'Plusieurs postes', icon: 'chip', section: 'Postes', keywords: 'collecte file import csv lot' },
  { id: 'noms', label: 'Noms disponibles', icon: 'star', section: 'Postes', keywords: 'nommage aperçu disponibilité convention' },
  { id: 'interventions', label: 'Interventions', icon: 'activity', section: 'Suivi', keywords: 'recus operations historiques verifier' },
  { id: 'journal', label: 'Journal', icon: 'file', section: 'Suivi', keywords: 'journaux messages niveaux' },
  { id: 'parametres', label: 'Paramètres', icon: 'settings', section: null, keywords: 'domaine controleur prefixe convention sites preferences politiques coordination configuration import export defaut mises a jour animations demonstration' },
  { id: 'aide', label: 'Aide', icon: 'info', section: null, keywords: 'aide raccourcis diagnostics contact' },
];
const NAV_PAGES = CONFIGURATION_ENTRY ? PAGES.filter((page) => ['parametres', 'aide'].includes(page.id)) : PAGES;

const THEMES = [
  { id: 'light', label: 'Thème clair', icon: 'sun' },
  { id: 'dark', label: 'Thème sombre', icon: 'moon' },
  { id: 'contrast', label: 'Contraste élevé', icon: 'contrast' },
  { id: 'system', label: 'Thème : suivre Windows', icon: 'monitor' },
];

// ---------- Theme and motion ----------

const mqDark = matchMedia('(prefers-color-scheme: dark)');
const mqContrast = matchMedia('(forced-colors: active), (prefers-contrast: more)');
// Same breakpoint as layout.css: the rail is always icon-only there, whatever the saved preference says.
const mqNarrow = matchMedia('(max-width: 900px)');
let themeInk = null;

function resolvedTheme() {
  if (state.prefs.theme !== 'system') return state.prefs.theme;
  if (mqContrast.matches) return 'contrast';
  return mqDark.matches ? 'dark' : 'light';
}

function applyTheme() {
  root.dataset.theme = resolvedTheme();
  root.dataset.themePref = state.prefs.theme;
  document.querySelectorAll('.theme-switch button').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.set === state.prefs.theme)));
  themeInk?.update();
}

function setTheme(id) {
  if (state.prefs.theme === id) return;
  setPrefs({ theme: id });
  if (document.startViewTransition && !motionReduced()) {
    root.classList.add('theme-swap');
    const vt = document.startViewTransition(applyTheme);
    vt.finished.finally(() => root.classList.remove('theme-swap'));
  } else {
    applyTheme();
  }
  announce(THEMES.find((t) => t.id === id)?.label ?? 'Thème');
}

// ---------- Shell markup ----------

function navItem(page, n) {
  const kbd = n < 9 ? `<kbd class="nav-kbd" aria-hidden="true">Alt ${n + 1}</kbd>` : '';
  const keys = n < 9 ? ` aria-keyshortcuts="Alt+${n + 1}"` : '';
  return `<a class="nav-item" href="#/${page.id}" data-id="${page.id}" aria-label="${esc(page.label)}"${keys} data-tip="${esc(page.label)}">`
    + `${icon(page.icon)}<span class="nav-label">${esc(page.label)}</span>${kbd}</a>`;
}

function navMarkup() {
  const sections = ['Pilotage', 'Postes', 'Suivi'].map((name) => {
    const items = NAV_PAGES.map((p, n) => (p.section === name ? navItem(p, n) : '')).join('');
    return items ? `<div class="nav-section">${esc(name)}</div>${items}` : '';
  }).join('');
  const bottom = NAV_PAGES.map((p, n) => (p.section === null ? navItem(p, n) : '')).join('');
  return `<nav class="nav" aria-label="Navigation principale">
    <div class="brand" data-tip="Pesto 2"><span class="brand-mark">${icon('logo')}</span><span class="brand-name"><span class="brand-title">Pesto</span><span class="brand-sub">Postes du domaine</span></span></div>
    <span class="nav-pill" aria-hidden="true"></span>
    ${sections}
    <div class="nav-spacer"></div>
    ${bottom}
    <div class="nav-foot">
      <button class="nav-account" type="button" aria-haspopup="menu" aria-label="Compte de la session" data-tip="Compte de la session">
        <span class="nav-avatar" aria-hidden="true">${icon('user')}</span>
        <span class="nav-account-text"><span class="nav-account-login">Session…</span><span class="nav-account-domain">Domaine non connecté</span></span>
        ${icon('more', 'nav-account-more')}
      </button>
      <button class="nav-item nav-toggle" type="button" aria-expanded="true" aria-label="Replier le menu" aria-keyshortcuts="Control+B" data-tip="Replier le menu (Ctrl B)">
        ${icon('panel')}<span class="nav-label">Replier le menu</span><kbd class="nav-kbd" aria-hidden="true">Ctrl B</kbd>
      </button>
    </div>
    <div class="nav-grip" role="separator" aria-orientation="vertical" tabindex="0" aria-label="Largeur du menu" aria-valuemin="${NAV_MIN}" aria-valuemax="${NAV_MAX}" aria-valuenow="${NAV_DEFAULT}"></div>
  </nav>`;
}

function topbarMarkup() {
  const themes = THEMES.map((t) => `<button type="button" data-set="${t.id}" aria-pressed="false" aria-label="${esc(t.label)}" data-tip="${esc(t.label)}">${icon(t.icon)}</button>`).join('');
  return `<header class="topbar">
    <button class="search-trigger" type="button" aria-haspopup="dialog" aria-keyshortcuts="Control+K">
      ${icon('search')}<span>Aller à un écran, une commande…</span><kbd>Ctrl K</kbd>
    </button>
    <div class="topbar-spacer"></div>
    <button class="mode-chip pending" type="button" aria-haspopup="menu"><span class="glow-ring" aria-hidden="true"></span><span class="dot pulse" aria-hidden="true"></span><span class="txt">Session…</span><span class="visually-hidden detail"></span></button>
    <div class="segmented theme-switch" role="group" aria-label="Thème"><span class="thumb" aria-hidden="true"></span>${themes}</div>
    <div class="busy-line" aria-hidden="true"></div>
  </header>`;
}

function shellMarkup() {
  return `<a class="skip-link" href="#main">Aller au contenu</a>
  <div class="aurora" aria-hidden="true"></div>
  <div class="cursor-halo" aria-hidden="true"></div>
  <div class="shell">
    ${navMarkup()}
    ${topbarMarkup()}
    <div class="sim-banner" role="note" hidden>
      <span class="sh-banner-icon">${icon('info')}</span>
      <span class="text"></span>
    </div>
    <main class="main" id="main" tabindex="-1"><div class="page" role="status">Chargement de la session…</div></main>
  </div>
  <div class="toasts" role="region" aria-label="Notifications"></div>`;
}

// ---------- Mode, session, banner ----------

function writeAvailability(info = state.session) {
  if (!info) return { text: 'En attente de la session', detail: 'La session est en cours de lecture.' };
  if (info.mode === 'simulation') return { text: 'Simulées uniquement', detail: 'Aucune écriture réelle.' };
  if (info.configurationOnly) return { text: 'Indisponibles', detail: 'Configuration locale : reconnectez Pesto pour ouvrir une session Active Directory.' };
  if (info.mode === 'offline') return { text: info.readOnly ? 'Application indisponible' : 'Application locale après confirmation',
    detail: info.capabilities?.find(c => c.id === 'offlineJoin')?.reason || 'Import et application locaux. Seule l’observation explicitement demandée après redémarrage contacte AD.' };
  const capabilities = Array.isArray(info.capabilities) ? info.capabilities : [];
  if (!info.readOnly && capabilities.some((item) => item.enabled === true)) {
    return { text: 'Disponibles après confirmation', detail: 'Chaque écriture demande un aperçu puis votre confirmation.' };
  }
  const reason = capabilities.find((item) => item.reason)?.reason || 'Les écritures ne sont pas disponibles dans cette session.';
  return { text: 'Indisponibles', detail: reason + (capabilities.some(item => item.id === 'acknowledge' && item.enabled === true)
    ? ' L’acquittement motivé des reçus reste disponible ; il ne valide aucun résultat métier.' : '') };
}

function modeState(info = state.session) {
  if (!info) return null;
  if (info.mode === 'simulation') return { id: 'simulation', text: 'Simulation', detail: `Annuaire fictif en mémoire${NBSP}: aucune écriture réelle, aucun contact réseau.` };
  if (info.configurationOnly) return { id: 'configuration', text: 'Configuration locale', detail: 'Paramètres du profil local ; aucun annuaire connecté dans cette fenêtre.' };
  if (info.mode === 'offline') return { id: 'offline', text: 'Jonction locale réelle', detail: writeAvailability(info).detail };
  if (info.readOnly || info.mode === 'live') {
    const label = info.readOnly
      ? (info.capabilities?.some(item => item.id === 'acknowledge' && item.enabled === true) ? 'Actions AD suspendues' : 'Lecture seule')
      : 'Annuaire';
    return { id: info.readOnly ? 'readonly' : 'live', text: `${label} · ${info.domain || 'domaine non configuré'}`,
      detail: `Annuaire réel. ${writeAvailability(info).detail}` };
  }
  return null;
}

function paintBanner() {
  const banner = document.querySelector('.sim-banner');
  const shell = document.querySelector('.shell');
  if (!banner || !shell) return;
  const info = state.session;
  const simulation = info?.mode === 'simulation';
  const offline = info?.mode === 'offline';
  const configuration = info?.configurationOnly === true;
  // The safety label is not an appearance preference: old bannerCompact values cannot hide it.
  if (!simulation && !offline && !configuration) {
    banner.hidden = true;
    shell.classList.remove('has-banner');
    return;
  }
  const text = configuration ? 'CONFIGURATION LOCALE — annuaire non connecté. Paramètres et démonstration disponibles ; reconnectez Pesto pour les opérations AD.'
    : offline ? 'JONCTION HORS LIGNE — opération réelle sur ce PC après confirmation. Import et application locaux ; observation AD explicite après redémarrage.'
    : `DÉMONSTRATION${NBSP}— données fictives en mémoire. Aucun accès AD, SMB ou HTTP ; aucun changement réel.`;
  const line = banner.querySelector('.text');
  line.textContent = text;
  line.dataset.tip = text;
  banner.hidden = false;
  shell.classList.add('has-banner');
}

function paintAccount() {
  const s = state.session;
  const button = document.querySelector('.nav-account');
  if (!button) return;
  button.querySelector('.nav-account-login').textContent = s?.account || 'Aucun compte connecté';
  button.querySelector('.nav-account-domain').textContent = s?.configurationOnly ? 'Annuaire non connecté'
    : s?.domain || (s?.mode === 'simulation' ? 'Domaine simulé' : 'Domaine non configuré');
  const brand = document.querySelector('.brand');
  if (brand && typeof s?.version === 'string' && s.version) brand.dataset.tip = `Pesto 2 · version ${s.version}`;
}

function paintSession() {
  const chip = document.querySelector('.mode-chip');
  const mode = modeState() ?? (state.reach.offline ? { id: 'unavailable', text: 'Moteur injoignable', detail: '' } : null);
  if (!chip || !mode) return;
  const s = state.session;
  let stateName = 'local';
  let label = mode.text;
  let tip = mode.detail;
  if (state.reach.offline) {
    stateName = 'offline';
    label = 'Moteur injoignable';
    tip = 'Le moteur n’a pas répondu à la dernière demande. Aucune relance automatique.';
  } else if (s?.mode === 'simulation') {
    stateName = 'simulated';
    tip += ` Domaine fictif${NBSP}: ${s.domain || 'inconnu'}.`;
  } else if (s?.mode === 'live' && !s.configurationOnly) {
    stateName = s.dc ? 'discovered' : 'targeted';
    tip += s.dc ? ` Contrôleur découvert${NBSP}: ${s.dc}.` : ' Contrôleur non confirmé : seul le domaine cible est configuré.';
    tip += ' Les droits et l’état de la cible sont vérifiés lors de chaque demande.';
  }
  chip.classList.remove('pending');
  chip.dataset.mode = mode.id;
  chip.dataset.state = stateName;
  chip.dataset.tip = `${tip} Cliquez pour le détail de la session.`;
  chip.querySelector('.txt').textContent = label;
  chip.querySelector('.detail').textContent = `${NBSP}: ${tip}`;
}

// ---------- Boot ----------

let inflight = 0;
const pendingOps = new Map(); // op -> { started, count } : which call is holding the screen, and for how long

function notePending(op) {
  const held = pendingOps.get(op);
  if (held) held.count += 1; else pendingOps.set(op, { started: performance.now(), count: 1 });
}

function releasePending(op) {
  const held = pendingOps.get(op);
  if (!held) return;
  held.count -= 1;
  if (held.count <= 0) pendingOps.delete(op);
}

globalThis.__pestoNativeQualificationPending = () => [...pendingOps.entries()]
  .map(([op, held]) => ({ op, count: held.count, ageMilliseconds: Math.max(0, Math.round(performance.now() - held.started)) }))
  .sort((a, b) => b.ageMilliseconds - a.ageMilliseconds);

function trackedCall(op, args) {
  inflight += 1;
  notePending(op);
  setBusy(true);
  return call(op, args).then((data) => {
    if (state.reach.offline) { state.reach = { offline: false, since: null }; paintSession(); }
    return data;
  }, (err) => {
    if (err?.code === 'bridge.timeout' || err?.code === 'bridge.unavailable' || err?.code === 'bridge.closed') {
      state.reach = { offline: true, since: Date.now() };
      paintSession();
    }
    throw err;
  }).finally(() => {
    inflight -= 1;
    releasePending(op);
    setBusy(false);
  });
}

function boot() {
  applyTheme();
  root.dataset.motion = state.prefs.motion;
  const syncWindow = () => root.toggleAttribute('data-window-inactive', document.hidden || !document.hasFocus());
  window.addEventListener('blur', () => root.setAttribute('data-window-inactive', ''));
  window.addEventListener('focus', syncWindow);
  document.addEventListener('visibilitychange', syncWindow);
  syncWindow();
  initLive();
  const host = document.getElementById('app');
  host.innerHTML = shellMarkup();
  const shell = host.querySelector('.shell');
  const nav = shell.querySelector('.nav');
  const main = shell.querySelector('.main');
  const toggle = nav.querySelector('.nav-toggle');
  const topbar = shell.querySelector('.topbar');

  themeInk = inkFollow(host.querySelector('.theme-switch'), 'button', 'button[aria-pressed="true"]');
  applyTheme();
  initPointerEffects();

  let router = null;
  let palette = null;

  // ---------- Navigation rail: collapse (Ctrl+B), width, account ----------

  const slideColumn = (change) => {
    const movers = [...shell.children].filter((el) => el !== nav && !el.hidden);
    const before = movers.map((el) => el.getBoundingClientRect().left);
    change();
    if (motionReduced() || typeof Element.prototype.animate !== 'function') return;
    const duration = cssMs('--t-slow', 520);
    movers.forEach((el, n) => {
      const dx = before[n] - el.getBoundingClientRect().left;
      if (Math.abs(dx) < 1) return;
      el.animate([{ transform: `translateX(${dx}px)` }, { transform: 'translateX(0)' }], { duration, easing: 'cubic-bezier(.16, 1, .3, 1)' });
    });
  };
  const isCollapsed = () => shell.classList.contains('nav-collapsed');
  const paintToggle = (on) => {
    const text = on ? 'Déplier le menu' : 'Replier le menu';
    toggle.setAttribute('aria-expanded', String(!on));
    toggle.setAttribute('aria-label', text);
    toggle.querySelector('.nav-label').textContent = text;
    toggle.dataset.tip = `${text} (Ctrl B)`;
    router?.updatePill();
  };
  // Rail tooltips: one fixed element outside the rail, whose overflow clips ::after tips (shell.css .flytip). Shown for
  // every item while the rail is icon-only, and always for the fold button, which never has a visible label.
  nav.classList.add('js-tips');
  const flytip = document.createElement('div');
  flytip.className = 'flytip';
  flytip.setAttribute('aria-hidden', 'true');
  document.body.appendChild(flytip);
  let tipFor = null, tipTimer = 0;
  const hideTip = () => { clearTimeout(tipTimer); tipFor = null; flytip.classList.remove('on'); };
  const showTip = (el) => {
    if (el === tipFor) return;
    hideTip();
    if (!el.dataset.tip || !(isCollapsed() || mqNarrow.matches)) return;
    tipFor = el;
    tipTimer = setTimeout(() => {
      if (tipFor !== el || !el.isConnected) return;
      flytip.textContent = el.dataset.tip;
      const r = el.getBoundingClientRect();
      // Placed without transition, then shown: it must not slide in from its previous place.
      flytip.classList.add('jump');
      flytip.style.setProperty('--tx', `${Math.round(r.right + 10)}px`);
      flytip.style.setProperty('--ty', `${Math.round(r.top + r.height / 2 - flytip.offsetHeight / 2)}px`);
      void flytip.offsetWidth;
      flytip.classList.remove('jump');
      flytip.classList.add('on');
    }, 250);
  };
  const tipTarget = (e) => e.target.closest?.('[data-tip]');
  nav.addEventListener('pointerover', (e) => { const el = tipTarget(e); if (el && nav.contains(el)) showTip(el); });
  nav.addEventListener('pointerout', (e) => { if (tipFor && !tipFor.contains(e.relatedTarget)) hideTip(); });
  nav.addEventListener('focusin', (e) => { const el = tipTarget(e); if (el && nav.contains(el) && el.matches(':focus-visible')) showTip(el); });
  nav.addEventListener('focusout', hideTip);
  // A scroll moves another item under a resting pointer, and pointerover only fires on the next crossing: show its tip
  // once the scroll ends, or at the next pointer move.
  let tipRearm = false;
  nav.addEventListener('scroll', () => { hideTip(); tipRearm = true; }, { passive: true });
  const rearmTip = (el) => { if (!tipRearm || !el || !nav.contains(el)) return; tipRearm = false; showTip(el); };
  nav.addEventListener('scrollend', () => rearmTip([...nav.querySelectorAll('[data-tip]:hover')].pop()));
  nav.addEventListener('pointermove', (e) => rearmTip(tipTarget(e)));
  nav.addEventListener('pointerdown', hideTip);
  mqNarrow.addEventListener?.('change', hideTip);

  const foot = nav.querySelector('.nav-foot');
  const shadeFoot = () => {
    nav.classList.toggle('nav-scrolls', nav.scrollHeight > nav.clientHeight + 1);
    // scroll-padding (shell.css) keeps a focused item clear of the sticky footer, whose height changes when folded.
    nav.style.setProperty('--nav-foot-h', `${foot.offsetHeight}px`);
  };
  const setCollapsed = (collapsed, save = true) => {
    if (save) setPrefs({ navCollapsed: collapsed });
    const apply = () => { shell.classList.toggle('nav-collapsed', collapsed); shadeFoot(); };
    if (save) slideColumn(apply); else apply();
    paintToggle(collapsed);
    hideTip();
  };
  setCollapsed(state.prefs.navCollapsed, false);
  if (typeof ResizeObserver === 'function') { const ro = new ResizeObserver(shadeFoot); ro.observe(nav); ro.observe(foot); }

  const applyNavWidth = () => {
    const w = state.prefs.navWidth ?? NAV_DEFAULT;
    shell.style.setProperty('--nav-w', `${w}px`);
    const grip = nav.querySelector('.nav-grip');
    grip.setAttribute('aria-valuenow', String(w));
    grip.setAttribute('aria-valuetext', `${w} pixels`);
  };
  applyNavWidth();
  on('prefs', applyNavWidth);

  const grip = nav.querySelector('.nav-grip');
  grip.addEventListener('pointerdown', (e) => {
    if (isCollapsed() || mqNarrow.matches || e.button !== 0) return;
    e.preventDefault();
    grip.setPointerCapture(e.pointerId);
    const startX = e.clientX;
    const startW = state.prefs.navWidth ?? NAV_DEFAULT;
    shell.classList.add('nav-resizing');
    const moveW = (ev) => shell.style.setProperty('--nav-w', `${Math.round(Math.max(NAV_MIN, Math.min(NAV_MAX, startW + ev.clientX - startX)))}px`);
    const up = (ev) => {
      grip.removeEventListener('pointermove', moveW);
      grip.removeEventListener('pointerup', up);
      shell.classList.remove('nav-resizing');
      setPrefs({ navWidth: Math.round(Math.max(NAV_MIN, Math.min(NAV_MAX, startW + ev.clientX - startX))) });
      router?.updatePill();
    };
    grip.addEventListener('pointermove', moveW);
    grip.addEventListener('pointerup', up);
  });
  grip.addEventListener('dblclick', () => { setPrefs({ navWidth: null }); announce('Largeur du menu par défaut.'); });
  grip.addEventListener('keydown', (e) => {
    if (mqNarrow.matches) return;
    const w = state.prefs.navWidth ?? NAV_DEFAULT;
    const step = e.shiftKey ? 64 : 16;
    let next = null;
    if (e.key === 'ArrowRight') next = w + step;
    else if (e.key === 'ArrowLeft') next = w - step;
    else if (e.key === 'Home') next = NAV_MIN;
    else if (e.key === 'End') next = NAV_MAX;
    else if (e.key === 'Enter') next = NAV_DEFAULT;
    if (next === null) return;
    e.preventDefault();
    setPrefs({ navWidth: Math.max(NAV_MIN, Math.min(NAV_MAX, next)) });
    router?.updatePill();
  });

  toggle.addEventListener('click', () => { if (!mqNarrow.matches) setCollapsed(!isCollapsed()); });

  nav.querySelector('.nav-account').addEventListener('click', (e) => {
    const s = state.session;
    openMenu(e.currentTarget, [
      { heading: s?.account || 'Compte de la session' },
      { label: 'Poste', hint: s?.computer ?? 'inconnu', run: () => {} },
      { label: 'Copier le compte', icon: 'copy', run: async () => {
        try { await navigator.clipboard.writeText(s?.account ?? ''); announce('Compte copié.'); } catch { announce('Copie impossible.'); }
      } },
      ...(s?.mode === 'live' ? [{ label: 'Changer de compte AD…', icon: 'refresh', run: async () => {
        if (!await confirmDialog({ title: 'Changer de compte AD',
          message: 'Pesto fermera cette session puis proposera le compte Windows ou un autre compte AD dans une fenêtre Windows. Hors domaine, un compte AD sera demandé directement. Les plans et la file non exécutés seront abandonnés. Les reçus durables restent conservés.',
          confirmLabel: 'Fermer et reconnecter' })) return;
        try { await trackedCall('host.reconnect', { confirmed: true }); }
        catch (error) { announce(errorText(error)); }
      } }] : []),
      '-',
      ...(s?.mode === 'offline' ? [] : [{ label: 'Diagnostics de la session', icon: 'shield', run: () => router.go('aide', { tab: 'diagnostics' }) }]),
    ], { label: 'Compte de la session', placement: 'top-start' });
  });

  // ---------- Top bar ----------

  topbar.querySelector('.search-trigger').addEventListener('click', () => palette?.open());
  topbar.querySelectorAll('.theme-switch button').forEach((b) => b.addEventListener('click', () => setTheme(b.dataset.set)));
  topbar.querySelector('.mode-chip').addEventListener('click', (e) => {
    const s = state.session;
    openMenu(e.currentTarget, [
      { heading: 'Session' },
      { label: 'Mode', hint: s?.mode === 'simulation' ? 'Simulation' : s?.mode === 'offline' ? 'Jonction hors ligne locale' : s?.configurationOnly ? 'Configuration locale' : s ? 'Annuaire réel' : 'inconnu', run: () => {} },
      { label: 'Domaine', hint: s?.domain ?? 'inconnu', run: () => {} },
      { label: 'Contrôleur', hint: s?.dc || 'non confirmé', run: () => {} },
      { label: 'Écritures', hint: writeAvailability(s).text, run: () => {} },
      { label: 'Compte', hint: s?.account ?? 'inconnu', run: () => {} },
      { label: 'Poste', hint: s?.computer ?? 'inconnu', run: () => {} },
      { label: 'Version du moteur', hint: s?.version ?? 'inconnue', run: () => {} },
    ], { label: 'Session' });
  });
  on('prefs', () => { root.dataset.motion = state.prefs.motion; paintBanner(); });

  // Keep the current route: the skip link changes focus, never the hash router's address.
  host.querySelector('.skip-link').addEventListener('click', (e) => {
    e.preventDefault();
    main.focus({ preventScroll: true });
  });
  const followSystemTheme = () => { if (state.prefs.theme === 'system') applyTheme(); };
  mqDark.addEventListener('change', followSystemTheme);
  mqContrast.addEventListener('change', followSystemTheme);

  // ---------- Router and palette ----------

  const screenCommands = { current: [] };

  router = createRouter({
    main,
    nav,
    pages: NAV_PAGES,
    defaultId: OFFLINE_ENTRY ? 'offline-join' : CONFIGURATION_ENTRY ? 'parametres' : 'accueil',
    isBusy: () => inflight > 0,
    context: () => ({
      call: trackedCall,
      session: () => state.session,
      capability: (id) => {
        const item = state.session?.capabilities?.find((c) => c.id === id);
        return item?.enabled === true ? { enabled: true, reason: '' }
          : { enabled: false, reason: item?.reason || 'Cette action n’est pas disponible avec le moteur connecté.' };
      },
      openPalette: (prefill) => palette?.open(prefill ?? ''),
      setScreenCommands: (list) => { screenCommands.current = Array.isArray(list) ? list : []; },
      refreshSession: () => trackedCall('session.info').then(applySession),
    }),
  });

  palette = createPalette({
    inertTarget: shell,
    sources: () => ({
      pages: NAV_PAGES.filter((p) => !p.hidden).map((p) => ({
        id: p.id, kind: 'page', label: p.label, icon: p.icon, group: 'Aller à', keywords: p.keywords,
        active: router?.current() === p.id, detailText: `Ouvre l’écran ${p.label}.`,
      })),
      screen: screenCommands.current,
      recents: [],
    }),
    onRun: (cmd) => {
      if (cmd.kind === 'page') router.go(cmd.id);
      else if (typeof cmd.run === 'function') cmd.run();
    },
  });

  // ---------- Session ----------

  function applySession(info) {
    if (!info || typeof info !== 'object') return;
    state.session = info;
    adoptMode(info.mode === 'simulation' ? 'simulation' : 'live');
    setCollapsed(state.prefs.navCollapsed, false);
    root.dataset.motion = state.prefs.motion;
    applyTheme();
    paintBanner();
    paintAccount();
    paintSession();
    emit('session', info);
  }

  trackedCall('session.info').then(applySession).catch((err) => {
    console.error(err);
    announce(`Le moteur n’a pas répondu : ${errorText(err)}`, { assertive: true });
  }).finally(async () => {
    await router.start();
    if (state.session?.mode === 'live') {
      const notice = await import('./configuration-notice.js');
      await notice.showConfigurationNotice({ call: trackedCall, refreshSession: () => trackedCall('session.info').then(applySession) });
    }
  });

  // ---------- Shortcuts ----------

  document.addEventListener('keydown', (e) => {
    if (e.defaultPrevented || e.isComposing) return;
    if (e.ctrlKey && !e.shiftKey && !e.altKey && (e.key === 'k' || e.key === 'K')) {
      if (modalOpen()) return;
      e.preventDefault();
      palette.toggle();
      return;
    }
    // A modal or the palette owns its keys; do not navigate behind an active dialog.
    if (palette.isOpen() || modalOpen()) return;
    if (e.ctrlKey && !e.shiftKey && !e.altKey && (e.key === 'b' || e.key === 'B')) {
      e.preventDefault();
      // The width keeps the rail folded: flipping the saved preference here would only surface later, unseen.
      if (mqNarrow.matches) { announce('Menu replié automatiquement : fenêtre trop étroite.'); return; }
      setCollapsed(!isCollapsed());
      return;
    }
    if (e.key === 'F1') {
      e.preventDefault();
      router.go(OFFLINE_ENTRY ? 'offline-join' : 'aide');
      return;
    }
    // AZERTY : les chiffres de la rangée haute exigent Shift (e.key = '&', 'é'…), donc l'ancienne condition
    // « !shiftKey && /^[1-9]$/.test(e.key) » rendait Alt+1..9 inatteignable sur clavier français — prouvé en
    // session réelle 25/10/2026 (les 9 Alt+N restaient sur « Accueil · Pesto »). e.code reste Digit1..9 : on
    // accepte la touche physique, Shift étant autorisé.
    if (e.altKey && !e.ctrlKey && (/^[1-9]$/.test(e.key) || /^Digit[1-9]$/.test(e.code))) {
      const n = /^[1-9]$/.test(e.key) ? Number(e.key) : Number(e.code.slice(5));
      const page = NAV_PAGES[n - 1];
      if (page) { e.preventDefault(); router.go(page.id); }
    }
  });
  // Never steal keys from a text entry (palette input, forms).
  const guarded = (fn) => (e) => { if (isTextEntry(e.target) || modalOpen()) return; fn(e); };
  document.addEventListener('keypress', guarded((e) => {
    if (e.key === '?' && e.shiftKey) { e.preventDefault(); router.go(OFFLINE_ENTRY ? 'offline-join' : 'aide', { tab: 'raccourcis' }); }
  }));

}

boot();
