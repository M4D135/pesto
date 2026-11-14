// Command palette (Ctrl+K or the search field of the top bar): screens and commands of the screen shown, keyboard
// first. Every typed word must appear (accents, case and apostrophes ignored); available commands come first, then the
// rank of the match (40 at most). An unavailable command stays listed with its reason and the palette stays open.
// The palette never writes: a prepared write only brings its button forward.
import { icon } from './icons.js';
import { esc, fold, announce } from './ui.js';

const LIMIT_PER_GROUP = 12;
const LIMIT_TOTAL = 40;
const NBSP = ' ';

// All words of the query must appear (folded); rank = position of the first word, then catalogue order.
export function selectEntries(list, query, limit) {
  const words = fold(query.trim()).split(/\s+/).filter(Boolean);
  if (!words.length) return list.slice(0, limit);
  const scored = [];
  for (const entry of list) {
    const text = fold(`${entry.label ?? ''} ${entry.keywords ?? ''} ${entry.hint ?? ''}`);
    let rank = -1; let all = true;
    for (const w of words) {
      const at = text.indexOf(w);
      if (at < 0) { all = false; break; }
      if (rank < 0 || at < rank) rank = at;
    }
    if (all) scored.push({ entry, rank });
  }
  return scored.sort((a, b) => a.rank - b.rank).slice(0, limit).map((x) => x.entry);
}

function highlight(text, query) {
  if (!query) return esc(text);
  const chars = [...String(text)];
  const folded = chars.map((c) => fold(c));
  const flat = folded.join('');
  const words = query.split(/\s+/).filter(Boolean);
  const marks = new Array(chars.length).fill(false);
  for (const w of words) {
    const at = flat.indexOf(w);
    if (at < 0) continue;
    let pos = 0;
    folded.forEach((f, n) => {
      if (pos + f.length > at && pos < at + w.length) marks[n] = true;
      pos += f.length;
    });
  }
  let out = '';
  let open = false;
  chars.forEach((c, n) => {
    if (marks[n] && !open) { out += '<mark>'; open = true; }
    if (!marks[n] && open) { out += '</mark>'; open = false; }
    out += esc(c);
  });
  return open ? `${out}</mark>` : out;
}

function template() {
  return `<div class="palette" role="dialog" aria-modal="true" aria-label="Palette de commandes">
    <div class="palette-input">${icon('command')}
      <input type="text" role="combobox" aria-expanded="true" aria-controls="palette-results" aria-autocomplete="list"
        aria-label="Rechercher un écran ou une commande" autocomplete="off" spellcheck="false"
        placeholder="Aller à un écran, lancer une commande…">
      <kbd>Échap</kbd>
    </div>
    <div class="pal-body">
      <div class="results" id="palette-results" role="listbox" aria-label="Résultats"></div>
      <aside class="pal-detail" aria-live="polite"></aside>
    </div>
    <div class="foot" aria-hidden="true">
      <span><kbd>↑</kbd> <kbd>↓</kbd> naviguer</span><span><kbd>Entrée</kbd> ouvrir</span><span><kbd>Échap</kbd> fermer</span>
    </div>
  </div>`;
}

/**
 * @param {{ sources: () => { pages: object[], screen: object[], recents: string[] },
 *   onRun: (entry: object) => void, inertTarget?: HTMLElement }} o
 */
export function createPalette(o) {
  const backdrop = document.createElement('div');
  backdrop.className = 'palette-backdrop';
  backdrop.hidden = true;
  backdrop.innerHTML = template();
  document.body.appendChild(backdrop);

  const input = backdrop.querySelector('input');
  const results = backdrop.querySelector('.results');
  const detail = backdrop.querySelector('.pal-detail');
  let items = [];
  let selected = 0;
  let restoreFocus = null;
  let closing = false;

  function groupsFor(raw) {
    const src = o.sources();
    const groups = [];
    if (!raw.trim()) {
      const recents = src.recents
        .map((id) => [...src.screen, ...src.pages].find((c) => c.id === id))
        .filter(Boolean).slice(0, 5);
      const all = [...recents, ...src.pages.filter((p) => !recents.includes(p))].slice(0, 6);
      if (all.length) groups.push({ title: 'Récents', list: all });
      groups.push({ title: 'Aller à', list: src.pages.filter((p) => !all.includes(p)) });
      if (src.screen.length) groups.push({ title: 'Sur cet écran', list: src.screen });
      return groups;
    }
    const pages = selectEntries(src.pages, raw, LIMIT_PER_GROUP);
    const screen = selectEntries(src.screen, raw, LIMIT_PER_GROUP);
    if (pages.length) groups.push({ title: 'Aller à', list: pages });
    if (screen.length) groups.push({ title: 'Sur cet écran', list: screen });
    return groups;
  }

  function render(fresh = false) {
    const raw = input.value;
    const query = fold(raw.trim());
    const groups = groupsFor(raw);
    items = groups.flatMap((g) => g.list);
    selected = Math.min(selected, Math.max(0, items.length - 1));
    let n = 0;
    results.classList.toggle('fresh', fresh);
    results.innerHTML = groups.map((g, gi) => `<div class="pal-group" role="group" aria-labelledby="pal-g-${gi}">`
      + `<div class="group" role="presentation" id="pal-g-${gi}">${esc(g.title)}<span class="pal-count">${g.list.length}</span></div>`
      + g.list.map((c) => {
        const k = n++;
        const off = c.available === false;
        const mark = c.active ? `${icon('check', 'on-mark')}<span class="visually-hidden">, ${c.kind === 'page' ? 'écran affiché' : 'actif'}</span>` : '';
        const hint = off ? `<span class="hint pal-reason">${esc(c.reason ?? 'Indisponible')}</span>` : c.hint ? `<span class="hint">${esc(c.hint)}</span>` : '';
        const kbd = c.kbd ? `<kbd>${esc(c.kbd)}</kbd>` : '';
        return `<div class="item${off ? ' unavailable' : ''}" role="option" id="pal-opt-${k}" data-n="${k}" data-j="${k}" aria-selected="${k === selected}"${off ? ' aria-disabled="true"' : ''}>`
          + `${icon(c.icon ?? 'chevronRight')}<span class="label">${highlight(c.label, query)}</span><span class="pal-right">${hint}${mark}${kbd ? kbd : '<span class="pal-kbd-gap" aria-hidden="true"></span>'}</span></div>`;
      }).join('') + '</div>').join('')
      || '<div class="none" role="presentation">Aucun résultat. Essayez un autre mot.</div>';
    results.querySelectorAll('[data-j]').forEach((el) => el.style.setProperty('--j', String(Math.min(Number(el.dataset.j), 20))));
    syncSelection();
  }

  function detailFor(c) {
    if (!c) { detail.innerHTML = '<p class="faint">Choisissez une entrée pour voir ce qu’elle fait.</p>'; return; }
    detail.innerHTML = `<div class="pal-detail-head">${icon(c.icon ?? 'chevronRight')}<div><h3>${esc(c.label)}</h3>${c.group ? `<p>${esc(c.group)}</p>` : ''}</div></div>
      ${c.detailText ? `<p class="pal-detail-text">${esc(c.detailText)}</p>` : ''}
      ${c.available === false ? `<p class="pal-detail-reason">${icon('lock')}<span>Indisponible${NBSP}: ${esc(c.reason ?? '')}</span></p>` : ''}
      ${c.kbd ? `<p class="pal-detail-kbd">Raccourci${NBSP}: ${c.kbd.split(' ').map((k) => `<kbd>${esc(k)}</kbd>`).join(' ')}</p>` : ''}`;
  }

  const syncSelection = (scroll = true) => {
    results.querySelectorAll('.item').forEach((el) => el.setAttribute('aria-selected', String(Number(el.dataset.n) === selected)));
    const current = results.querySelector(`#pal-opt-${selected}`);
    if (current) {
      input.setAttribute('aria-activedescendant', current.id);
      if (scroll) current.scrollIntoView({ block: 'nearest' });
    } else {
      input.removeAttribute('aria-activedescendant');
    }
    detailFor(items[selected]);
  };

  const move = (delta) => {
    if (!items.length) return;
    selected = (selected + delta + items.length) % items.length;
    syncSelection();
  };

  const runSelected = (n = selected) => {
    const cmd = items[n];
    if (!cmd) return;
    if (cmd.available === false) {
      selected = n;
      syncSelection();
      announce(`Indisponible${NBSP}: ${cmd.reason ?? ''}`, { assertive: true });
      detail.classList.remove('shake');
      void detail.offsetWidth;
      detail.classList.add('shake');
      return;
    }
    close();
    // Let the closing animation start before heavy work (page render, theme swap).
    requestAnimationFrame(() => o.onRun(cmd));
  };

  function open(prefill = '') {
    if (!backdrop.hidden && !closing) { input.select(); return; }
    closing = false;
    backdrop.classList.remove('closing');
    restoreFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    input.value = prefill;
    selected = 0;
    backdrop.hidden = false;
    if (o.inertTarget) o.inertTarget.inert = true;
    render(true);
    input.focus();
  }

  function close() {
    if (backdrop.hidden || closing) return;
    closing = true;
    backdrop.classList.add('closing');
    const done = () => {
      if (!closing) return;
      closing = false;
      backdrop.hidden = true;
      backdrop.classList.remove('closing');
    };
    backdrop.addEventListener('animationend', (e) => { if (e.target === backdrop) done(); }, { once: true });
    setTimeout(done, 400);
    if (o.inertTarget) o.inertTarget.inert = false;
    if (restoreFocus?.isConnected) restoreFocus.focus({ preventScroll: true });
  }

  input.addEventListener('input', () => { selected = 0; render(false); });
  backdrop.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); move(1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1); }
    else if (e.key === 'PageDown') { e.preventDefault(); move(8); }
    else if (e.key === 'PageUp') { e.preventDefault(); move(-8); }
    else if (e.key === 'Home' && e.ctrlKey) { e.preventDefault(); selected = 0; syncSelection(); }
    else if (e.key === 'End' && e.ctrlKey) { e.preventDefault(); selected = Math.max(0, items.length - 1); syncSelection(); }
    else if (e.key === 'Enter') { e.preventDefault(); runSelected(); }
    else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(); }
    else if (e.key === 'Tab') { e.preventDefault(); input.focus(); } // focus stays in the dialog
  });
  // Only a real pointer movement selects: a list scrolled by the keyboard under a still pointer does not.
  let lastPointer = '';
  results.addEventListener('pointermove', (e) => {
    const at = `${e.clientX},${e.clientY}`;
    if (at === lastPointer) return;
    lastPointer = at;
    const el = e.target instanceof Element ? e.target.closest('.item') : null;
    if (el && Number(el.dataset.n) !== selected) { selected = Number(el.dataset.n); syncSelection(false); }
  });
  results.addEventListener('click', (e) => {
    const el = e.target instanceof Element ? e.target.closest('.item') : null;
    if (el) runSelected(Number(el.dataset.n));
  });
  backdrop.addEventListener('pointerdown', (e) => { if (e.target === backdrop) close(); });
  document.addEventListener('focusin', (e) => {
    if (!backdrop.hidden && !closing && !backdrop.contains(e.target)) input.focus();
  });

  return {
    open,
    close,
    toggle: () => (backdrop.hidden || closing ? open() : close()),
    isOpen: () => !backdrop.hidden && !closing,
    refresh: () => { if (!backdrop.hidden) render(); },
  };
}
