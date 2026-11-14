// Paramètres : coque de l’écran reprise de Domenia 2 (bandeau, tuiles d’état, recherche « / », rail de sections avec
// pastille glissante, une section visible à la fois, éclat du réglage trouvé). Aucun appel moteur ici : la page
// (../parametres.js) lit et enregistre, la coque montre. Toutes les sections sont montées une fois et basculent par
// hidden, sans remontage : le brouillon unique du formulaire couvre Annuaire et Politiques. show() est synchrone ;
// l’adresse #/parametres?section=… est réécrite par ctx.replaceParams (routeur), sans hashchange ni garde de sortie.
// CSP : aucun attribut style, les variables (--y, --h, --j, --tone) passent par le CSSOM.
import { icon } from '../../icons.js';
import { glyph } from '../../kit/glyphs.js';
import { esc, applyVars, announce, motionReduced } from '../../ui.js';
import { focusables, isTextEntry, modalOpen } from '../../kit/util.js';
import { DEFAULT_SECTION, INDEX, sectionsFor, addressOf, addressParams, searchSettings } from './sections.js';

const DECO = '<div class="pr-hero-deco" aria-hidden="true"><span class="glow-ring hero-ring"></span>'
  + '<div class="orbs"><span class="orb a"></span><span class="orb b"></span><span class="orb c"></span></div></div>';
const FLASH_MS = 1700;
const BLUR_CLOSE_MS = 120;
const SEARCH_MAX = 8;

function navItem(section, n) {
  return `<li><button type="button" class="pr-nav-item" data-section="${section.id}" data-j="${n}" aria-current="false" aria-controls="pr-panel-${section.id}">
          <span class="pr-nav-ico" data-tone="${section.tone}">${icon(section.icon)}</span>
          <span class="pr-nav-text"><span class="pr-nav-label">${esc(section.label)}</span> <span class="pr-nav-desc">${esc(section.desc)}</span></span>
          <span class="pr-nav-badge" data-badge="${section.id}" hidden></span></button></li>`;
}

function panelMarkup(section, html) {
  return `<section class="pr-section" data-section-panel="${section.id}" id="pr-panel-${section.id}" aria-labelledby="pr-title-${section.id}" tabindex="-1" hidden>
          <header class="pr-sec-head"><span class="pr-sec-icon" data-tone="${section.tone}">${icon(section.icon)}</span>
            <div class="pr-sec-titles"><h2 id="pr-title-${section.id}">${esc(section.label)}</h2><p>${esc(section.intro)}</p></div></header>
          ${html ?? ''}
        </section>`;
}

function tileMarkup(tile) {
  return `<button type="button" class="pr-pulse-tile" data-pulse="${tile.id}" data-go-section="${tile.section}" data-tone="info">
          <span class="pr-pulse-ico">${glyph(tile.icon)}</span> <span class="pr-pulse-k">${esc(tile.label)}</span>
          <span class="pr-pulse-v">Lecture…</span> <span class="pr-pulse-s"></span></button>`;
}

/**
 * Markup of the whole screen. panels = { id: html } (content after the section header); tiles = [{ id, label, icon, section }].
 * The panels of the sections marked form (Annuaire, Politiques) are wrapped in the single settings form.
 */
export function shellMarkup({ live, lead, panels = {}, tiles = [] }) {
  const sections = sectionsFor({ live });
  const formPanels = sections.filter((s) => s.form).map((s) => panelMarkup(s, panels[s.id])).join('');
  const otherPanels = sections.filter((s) => !s.form).map((s) => panelMarkup(s, panels[s.id])).join('');
  return `<div class="page pr-page">
  <section class="hero pr-hero reveal">
    ${DECO}
    <div class="pr-hero-grid">
      <div class="pr-hero-main">
        <div class="eyebrow">${icon('settings')}<span>Réglages de Pesto</span></div>
        <h1 class="gradient-text">Paramètres</h1>
        <p class="lead">${esc(lead)}</p>
        <div class="pr-chips" data-zone="mode"></div>
        <div class="pr-search" role="search">
          <span class="pr-search-box">${icon('search')}<input type="search" class="input" id="pr-search" placeholder="Rechercher un réglage…"
            autocomplete="off" spellcheck="false" role="combobox" aria-expanded="false" aria-controls="pr-search-list"
            aria-autocomplete="list" aria-label="Rechercher un réglage" aria-keyshortcuts="/"><kbd>/</kbd></span>
          <ul class="pr-search-list" id="pr-search-list" role="listbox" aria-label="Réglages trouvés" hidden></ul>
        </div>
      </div>
      <div class="pr-pulse" role="group" aria-label="État des paramètres">
        ${tiles.map(tileMarkup).join('')}
      </div>
    </div>
    <div class="pr-alert" data-configuration-invalid role="alert" hidden>
      <span class="pr-alert-ico">${icon('alert')}</span>
      <div><b>Configuration invalide</b> <span data-configuration-diagnostic></span></div>
      <button class="btn" type="button" data-alert-go="configuration" data-alert-target="${esc('[data-maint="import"]')}">Aller à l’import</button>
    </div>
  </section>
  <div class="pr-layout">
    <div class="pr-aside">
      <nav class="pr-nav reveal" aria-label="Sections des paramètres"><span class="pr-nav-pill" aria-hidden="true"></span><ul>
        ${sections.map(navItem).join('')}
      </ul></nav>
      <div class="pr-draft" role="group" aria-label="Brouillon des paramètres">
        <p class="muted small" data-settings-status role="status"></p>
        <div class="pr-draft-actions">
          <button class="btn" type="button" data-act="reload">${icon('refresh')}Relire</button>
          <button class="btn primary" type="button" data-act="save">${icon('check')}Enregistrer</button>
        </div>
        <p class="muted small">${icon('alert')} Enregistrer invalide tous les aperçus, plans et file en cours : chaque
          écriture devra être re-préparée et re-confirmée.</p>
      </div>
    </div>
    <div class="pr-content" tabindex="-1">
      <form data-form="settings" novalidate>
        ${formPanels}
      </form>
      ${otherPanels}
    </div>
  </div>
</div>`;
}

// An element hidden by its own markup ([data-coordination] outside the real directory) is not a search result;
// the panels of the sections are hidden only while another section is shown.
function hiddenOutsidePanel(el, main) {
  for (let node = el; node && node !== main; node = node.parentElement) {
    if (node.hidden && !node.hasAttribute('data-section-panel')) return true;
  }
  return false;
}

/**
 * Wires the shell rendered by shellMarkup. Reads ctx.params once (start). Never calls the engine.
 * @returns {{ show: Function, current: () => string|null, highlight: Function, setTile: Function, setBadge: Function,
 *   start: () => string, destroy: () => void }}
 */
export function mountShell(main, ctx, { live }) {
  const sections = sectionsFor({ live }).filter((s) => main.querySelector(`[data-section-panel="${s.id}"]`));
  const nav = main.querySelector('.pr-nav');
  const pill = nav.querySelector('.pr-nav-pill');
  const items = [...nav.querySelectorAll('.pr-nav-item')];
  const panels = [...main.querySelectorAll('[data-section-panel]')];
  const search = main.querySelector('#pr-search');
  const list = main.querySelector('#pr-search-list');
  const sectionById = (id) => sections.find((s) => s.id === id) ?? null;
  const panelOf = (id) => panels.find((p) => p.dataset.sectionPanel === id) ?? null;
  let alive = true;
  let current = null;
  let flashTimer = 0;
  let blurTimer = 0;
  let index = [];
  let hits = [];
  let active = -1;

  function placePill() {
    const item = items.find((i) => i.dataset.section === current);
    if (!item || !pill) return;
    pill.style.setProperty('--y', `${item.offsetTop}px`);
    pill.style.setProperty('--h', `${item.offsetHeight}px`);
    pill.classList.add('on');
  }

  function highlight(selector) {
    if (!alive || !selector) return;
    const el = main.querySelector(selector);
    if (!el) return;
    // Never a .card: its ::after is the spotlight of the card.
    const box = el.closest('.k-field, .row-actions, [data-setting]') ?? el;
    // « auto » would follow the scroll-behavior: smooth of .main (layout.css): reduced motion asks for an immediate jump.
    box.scrollIntoView({ block: 'center', behavior: motionReduced() ? 'instant' : 'smooth' });
    clearTimeout(flashTimer);
    main.querySelectorAll('.pr-flash').forEach((node) => node.classList.remove('pr-flash'));
    void box.offsetWidth;
    box.classList.add('pr-flash');
    flashTimer = setTimeout(() => box.classList.remove('pr-flash'), FLASH_MS);
    let target = el.matches('input, select, textarea, button') ? (el.disabled ? null : el) : focusables(box)[0];
    if (!target) {
      // Nothing enabled to focus (disabled actions, a note, the state card): the focus follows the view to the lit box,
      // never stays in the search field scrolled away. Its tabindex lasts until it loses the focus.
      if (!box.hasAttribute('tabindex')) {
        box.setAttribute('tabindex', '-1');
        box.addEventListener('blur', () => box.removeAttribute('tabindex'), { once: true });
      }
      target = box;
    }
    target.focus({ preventScroll: true });
  }

  // The header of a panel shown with the focus must be in view: in a narrow window the rail and the draft come first,
  // and the panel may start below the fold (tile, menu entry).
  function bringIntoView(panel) {
    const head = panel.querySelector('.pr-sec-head') ?? panel;
    const view = main.getBoundingClientRect();
    const box = head.getBoundingClientRect();
    if (box.top < view.top || box.bottom > view.bottom) panel.scrollIntoView({ block: 'start', behavior: motionReduced() ? 'instant' : 'smooth' });
  }

  function closeSearch() {
    if (!search.value && list.hidden) return;
    search.value = '';
    renderHits();
  }

  /** Shows one section (synchronous). Returns the id shown; an unknown or absent section shows Annuaire. */
  function show(id, { target = null, focus = false, quiet = false, first = false } = {}) {
    if (!alive) return current;
    const section = sectionById(id) ?? sectionById(DEFAULT_SECTION) ?? sections[0];
    const panel = panelOf(section.id);
    if (section.id !== current || first) {
      current = section.id;
      for (const p of panels) p.hidden = p.dataset.sectionPanel !== section.id;
      for (const item of items) item.setAttribute('aria-current', item.dataset.section === section.id ? 'true' : 'false');
      placePill();
      panel.classList.remove('pr-enter');
      if (!first && !motionReduced()) {
        void panel.offsetWidth;
        panel.classList.add('pr-enter');
      }
      ctx.replaceParams?.(addressParams(section.id));
      if (!quiet && !first) announce(`Section ${section.label}`);
      closeSearch();
    }
    if (target) highlight(target);
    else if (focus) { bringIntoView(panel); panel.focus({ preventScroll: true }); }
    return current;
  }

  // ----- Tiles and badges (text only, never aria-busy nor a skeleton: data-ready waits for neither) -----

  function setTile(id, { value = '', sub = '', tone, section } = {}) {
    const tile = main.querySelector(`[data-pulse="${id}"]`);
    if (!tile) return;
    const v = tile.querySelector('.pr-pulse-v');
    const changed = v.textContent !== String(value);
    v.textContent = String(value);
    tile.querySelector('.pr-pulse-s').textContent = String(sub ?? '');
    if (tone && tile.dataset.tone !== tone) { tile.dataset.tone = tone; applyVars(tile); }
    if (section) tile.dataset.goSection = section;
    if (changed && !motionReduced()) {
      tile.classList.remove('pr-bump');
      void tile.offsetWidth;
      tile.classList.add('pr-bump');
    }
  }

  // badge = null (hidden) or { mark, label, tone }: the mark is shown, the label is read with the rail item.
  function setBadge(id, badge) {
    const b = main.querySelector(`[data-badge="${id}"]`);
    if (!b) return;
    if (!badge) { b.hidden = true; b.replaceChildren(); delete b.dataset.mark; return; }
    const tone = badge.tone ?? 'off';
    if (!b.hidden && b.dataset.mark === badge.mark && b.dataset.tone === tone) return;
    const mark = document.createElement('span');
    mark.setAttribute('aria-hidden', 'true');
    mark.textContent = badge.mark;
    const label = document.createElement('span');
    label.className = 'visually-hidden';
    label.textContent = badge.label;
    b.replaceChildren(mark, label);
    b.dataset.mark = badge.mark;
    b.dataset.tone = tone;
    applyVars(b);
    b.hidden = false;
  }

  // ----- Search of a setting -----

  function renderHits() {
    const q = search.value.trim();
    hits = q ? searchSettings(q, { live, max: SEARCH_MAX, entries: index }) : [];
    active = hits.length ? 0 : -1;
    list.innerHTML = hits.length
      ? hits.map((hit, n) => {
        const s = sectionById(hit.section);
        return `<li role="option" id="pr-hit-${n}" aria-selected="${n === active}" data-hit="${n}">${icon(s.icon)}<span class="pr-hit-label">${esc(hit.label)}</span><span class="pr-hit-sec">${esc(s.label)}</span></li>`;
      }).join('')
      : (q ? '<li class="pr-hit-none" role="option" aria-disabled="true">Aucun réglage ne correspond.</li>' : '');
    list.hidden = !q;
    search.setAttribute('aria-expanded', String(!!q));
    if (active >= 0) search.setAttribute('aria-activedescendant', `pr-hit-${active}`);
    else search.removeAttribute('aria-activedescendant');
  }

  function choose(n) {
    const hit = hits[n];
    if (!hit) return;
    search.value = '';
    renderHits();
    show(hit.section, { target: hit.target });
  }

  const onSearchKey = (e) => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      if (!hits.length) return;
      e.preventDefault();
      active = (active + (e.key === 'ArrowDown' ? 1 : -1) + hits.length) % hits.length;
      list.querySelectorAll('[data-hit]').forEach((li) => li.setAttribute('aria-selected', String(Number(li.dataset.hit) === active)));
      search.setAttribute('aria-activedescendant', `pr-hit-${active}`);
    } else if (e.key === 'Enter') {
      e.preventDefault();
      choose(active);
    } else if (e.key === 'Escape' && search.value) {
      e.stopPropagation();
      search.value = '';
      renderHits();
    }
  };
  search.addEventListener('input', renderHits);
  search.addEventListener('keydown', onSearchKey);
  search.addEventListener('focus', () => { if (search.value.trim()) renderHits(); });
  search.addEventListener('blur', () => {
    clearTimeout(blurTimer);
    blurTimer = setTimeout(() => {
      if (!alive || document.activeElement === search) return;
      list.hidden = true;
      search.setAttribute('aria-expanded', 'false');
    }, BLUR_CLOSE_MS);
  });
  list.addEventListener('pointerdown', (e) => {
    const li = e.target instanceof Element ? e.target.closest('[data-hit]') : null;
    if (li) { e.preventDefault(); choose(Number(li.dataset.hit)); }
  });

  // « / » focuses the search (outside text fields, dialogs and shortcuts with Ctrl, Cmd or Alt; Shift is AZERTY’s « / »).
  const onKey = (e) => {
    if (e.key !== '/' || e.defaultPrevented || e.isComposing || e.ctrlKey || e.metaKey || e.altKey) return;
    if (modalOpen() || isTextEntry(e.target)) return;
    e.preventDefault();
    search.focus();
  };

  // ----- Rail, tiles and alert -----

  const onClick = (e) => {
    const t = e.target instanceof Element ? e.target : null;
    if (!t) return;
    const item = t.closest('.pr-nav-item');
    if (item && nav.contains(item)) { show(item.dataset.section); return; }
    const go = t.closest('[data-alert-go]');
    if (go && main.contains(go)) { show(go.dataset.alertGo, { target: go.dataset.alertTarget || null, focus: true }); return; }
    const tile = t.closest('[data-go-section]');
    if (tile && main.contains(tile)) show(tile.dataset.goSection, { focus: true });
  };
  // ↑ ↓ (circular), Home and End move the focus only; Enter and Space activate the native button.
  const onNavKey = (e) => {
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp' && e.key !== 'Home' && e.key !== 'End') return;
    const at = items.indexOf(document.activeElement);
    if (at < 0) return;
    e.preventDefault();
    const next = e.key === 'Home' ? 0 : e.key === 'End' ? items.length - 1 : (at + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
    items[next].focus();
  };
  // A link to the bare address of this screen (the menu entry « Paramètres ») shows Annuaire in place. In 2.0.14 it
  // pointed at the address shown and did nothing; followed from another section it would remount the screen (leave
  // guard, two reads). A modified click (new window, Ctrl…) and every other link keep the router’s navigation.
  const onLink = (e) => {
    if (e.defaultPrevented || e.button !== 0 || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return;
    const link = e.target instanceof Element ? e.target.closest('a[href="#/parametres"]') : null;
    if (!link || !alive || (ctx.isCurrent && !ctx.isCurrent())) return;
    e.preventDefault();
    if (current !== DEFAULT_SECTION) show(DEFAULT_SECTION, { focus: true });
  };
  main.addEventListener('click', onClick);
  nav.addEventListener('keydown', onNavKey);
  document.addEventListener('keydown', onKey);
  document.addEventListener('click', onLink, true);
  const ro = 'ResizeObserver' in window ? new ResizeObserver(() => placePill()) : null;
  ro?.observe(nav);

  /** First display from the address: section (alias accepted), then ouvrir=<nom>, used once (never an action). */
  function start() {
    index = INDEX.filter((entry) => sectionById(entry.section) && (live || !entry.live)
      && (() => { const el = main.querySelector(entry.target); return Boolean(el && !hiddenOutsidePanel(el, main)); })());
    const { section, ouvrir } = addressOf(ctx.params ?? {}, { live });
    let id = section;
    let target = null;
    if (ouvrir) {
      const name = CSS.escape(ouvrir);
      const selector = [`[name="${name}"]`, `[data-maint="${name}"]`].find((s) => main.querySelector(s));
      const home = selector ? main.querySelector(selector).closest('[data-section-panel]')?.dataset.sectionPanel : null;
      if (home && sectionById(home)) { id = home; target = selector; }
    }
    show(id, { first: true });
    // After the router has focused main on a navigation (it does so once render returns).
    if (target) queueMicrotask(() => highlight(target));
    return current;
  }

  function destroy() {
    alive = false;
    clearTimeout(flashTimer);
    clearTimeout(blurTimer);
    main.removeEventListener('click', onClick);
    nav.removeEventListener('keydown', onNavKey);
    document.removeEventListener('keydown', onKey);
    document.removeEventListener('click', onLink, true);
    ro?.disconnect();
  }

  return { show, current: () => current, highlight, setTile, setBadge, start, destroy };
}
