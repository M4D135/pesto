// Hash router (#/accueil, #/journal?query=…): loads pages/<id>.js, swaps the screen with a view transition, moves the
// nav pill. No list of pages here: the navigation of app.js is the only one. A route without its own module shows
// pages/_todo.js; a route outside the navigation exists only if its module exports `meta` (hidden screens).
import { icon } from './icons.js';
import { esc, errorText, motionReduced, announce } from './ui.js';

const fallback = () => import('./pages/_todo.js');

// Readiness signal a capture tool could read: <html data-ready="<route>"> once the route is mounted, no bridge call
// is in flight and the screen shows no skeleton nor busy region. Nothing reads it otherwise.
const READY_POLL_MS = 80;
const READY_GIVE_UP_MS = 120_000;
const MAX_PARAM_LENGTH = 2048;
const docRoot = document.documentElement;

// Route ids are lower-case words with dashes: they become file names, so nothing else is accepted (no path, no « .. »).
function parseHash(hash = location.hash) {
  const m = /^#\/([a-z0-9]+(?:-[a-z0-9]+)*)(?:\?(.*))?$/i.exec(hash);
  if (!m) return { id: '', params: {} };
  const params = {};
  if (m[2]) {
    for (const [k, v] of new URLSearchParams(m[2])) {
      if (k && !(k in params) && v.length <= MAX_PARAM_LENGTH) params[k] = v;
    }
  }
  return { id: m[1].toLowerCase(), params: Object.freeze(params) };
}

/**
 * Hash of a route: link('journal', { query }) → '#/journal?query=…'.
 * @param {string} id @param {Object<string, string|number|boolean|null|undefined>} [params]
 */
export function link(id, params = {}) {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v !== null && v !== undefined && v !== '') q.set(k, String(v));
  const s = q.toString();
  return `#/${id}${s ? `?${s}` : ''}`;
}

function errorPage(err) {
  return {
    render(main) {
      main.innerHTML = `<div class="page"><section class="card error-card" role="alert"><div class="empty">
        <div class="art">${icon('alert')}</div><h2>Cet écran n’a pas pu s’ouvrir</h2>
        <p>${esc(errorText(err, 'Le module de cet écran n’a pas pu être chargé.'))}</p>
        <button class="btn primary" type="button" data-retry>${icon('refresh')}Réessayer</button>
      </div></section></div>`;
      main.querySelector('[data-retry]').addEventListener('click', () => location.reload());
    },
  };
}

// A missing module (404) is « not ported yet »; a module that exists but fails (syntax, evaluation) is an error.
function isMissingModule(err) {
  if (!(err instanceof TypeError)) return false;
  return /dynamically imported module|Importing a module script failed|error loading dynamically imported module/i.test(String(err.message));
}

const modules = new Map(); // id → Promise<{ mod, own: boolean }>

function loadModule(id) {
  if (!modules.has(id)) {
    const p = import(`./pages/${id}.js`)
      .then((mod) => ({ mod, own: true }))
      .catch((err) => {
        if (!isMissingModule(err)) throw err;
        return fallback().then((mod) => ({ mod, own: false }));
      });
    // A failure is not kept: « Réessayer » or a later visit tries again.
    p.catch(() => modules.delete(id));
    modules.set(id, p);
  }
  return modules.get(id);
}

/**
 * @param {{ main: HTMLElement, nav: HTMLElement, pages: Array<{id: string, label: string, icon?: string, section?: string|null}>,
 *   context: (page: any) => Object, defaultId?: string, onChange?: (page: any) => void, isBusy?: () => boolean }} opts
 * context(page) → object handed to render(main, ctx); the router adds ctx.params (frozen), ctx.route, ctx.link,
 * ctx.navigate(id, params), ctx.guardLeave(fn), ctx.isCurrent() and ctx.replaceParams(params). One guard per screen,
 * removed when the screen changes. ctx.params and ctx.route stay those of the mount; ctx.isCurrent() is what a late
 * response checks: false once the address leaves the screen or a newer render started, true again when a leave guard
 * restores it, unchanged by ctx.replaceParams (which rewrites the query of the screen shown: no hashchange, no remount).
 */
export function createRouter({ main, nav, pages, context, defaultId = 'accueil', onChange, isBusy = () => false }) {
  // Navigation can be requested while session.info is pending; mount only once start() releases it.
  let started = false;
  let cleanup = null;
  let token = 0;
  let currentId = null;
  let currentParams = {};
  let leaveGuard = null;
  let guarding = false;

  const runCleanup = () => {
    const fn = cleanup;
    cleanup = null;
    if (typeof fn === 'function') {
      try { fn(); } catch (err) { console.error(err); }
    }
  };

  function updatePill() {
    const pill = nav.querySelector('.nav-pill');
    const item = nav.querySelector('.nav-item[aria-current="page"]');
    if (!pill) return;
    if (!item) { pill.style.setProperty('--y', '-100px'); return; }
    pill.style.setProperty('--y', `${item.offsetTop}px`);
    pill.style.setProperty('--h', `${item.offsetHeight}px`);
  }

  function markNav(id) {
    nav.querySelectorAll('.nav-item[data-id]').forEach((el) => {
      if (el.dataset.id === id) el.setAttribute('aria-current', 'page');
      else el.removeAttribute('aria-current');
    });
    updatePill();
  }

  // Sets data-ready once the screen of render `my` is quiet on two checks in a row; a newer render stops the watch.
  function watchReady(id, my) {
    const started = performance.now();
    let calm = 0;
    const check = () => {
      if (my !== token) return;
      const quiet = !isBusy() && !main.querySelector('.skeleton, [aria-busy="true"]');
      calm = quiet ? calm + 1 : 0;
      if (calm >= 2) { docRoot.dataset.ready = id; return; }
      if (performance.now() - started < READY_GIVE_UP_MS) setTimeout(check, READY_POLL_MS);
    };
    setTimeout(check, READY_POLL_MS);
  }

  function navigate(id, params = {}) {
    const target = link(id, params);
    if (location.hash === target) render(); else location.hash = target;
  }

  // first: initial render at start-up (focus stays where the browser put it).
  function mount(mod, page, params, my, first) {
    runCleanup();
    main.replaceChildren();
    main.scrollTop = 0;
    main.dataset.page = page.id;
    let out;
    const route = Object.freeze({ id: page.id, params, hash: link(page.id, params) });
    leaveGuard = null;
    const guardLeave = (fn) => {
      const mine = token;
      leaveGuard = typeof fn === 'function' ? fn : null;
      return () => { if (mine === token && leaveGuard === fn) leaveGuard = null; };
    };
    // Address of the screen as mounted, then as rewritten by replaceParams. Pages used to compare location.hash with
    // the one read at mount: isCurrent keeps that check (a hash leaving the screen, before its hashchange is handled,
    // is no longer current) and follows the in-page rewrites, so changing a section never makes a screen stale.
    let address = location.hash;
    const isCurrent = () => my === token && location.hash === address;
    // Rewrites the parameters of the current screen without hashchange, remount or leave guard. Refused (false) once
    // the screen is no longer current, so a late call never overwrites an address the user is leaving for.
    const replaceParams = (next = {}) => {
      if (!isCurrent()) return false;
      const clean = {};
      for (const [k, v] of Object.entries(next ?? {})) {
        if (k && v !== null && v !== undefined && v !== '' && String(v).length <= MAX_PARAM_LENGTH) clean[k] = String(v);
      }
      currentParams = Object.freeze(clean);
      const hash = link(page.id, clean);
      if (location.hash !== hash) history.replaceState(null, '', hash);
      address = location.hash;
      return true;
    };
    try {
      out = mod.render(main, { ...context(page), params, route, link, navigate, guardLeave, isCurrent, replaceParams });
    } catch (err) {
      console.error(err);
      errorPage(err).render(main);
      return;
    } finally {
      if (!first) {
        // Keyboard and screen reader users land on the new screen, which is announced by name.
        main.focus({ preventScroll: true });
        announce(`Écran ${page.label}`);
      }
    }
    if (typeof out === 'function') cleanup = out;
    else if (out && typeof out.then === 'function') {
      out.then((fn) => {
        if (typeof fn !== 'function') return;
        if (my === token) cleanup = fn; else fn();
      }).catch((err) => console.error(err));
    }
  }

  async function render(event) {
    if (!started) return;
    // Unsaved input of the screen shown: its guard is asked first; a refusal keeps the screen and its address.
    const previous = currentId !== null ? link(currentId, currentParams)
      : event instanceof HashChangeEvent ? new URL(event.oldURL).hash : location.hash;
    if (guarding) {
      if (location.hash !== previous) history.replaceState(null, '', previous);
      return;
    }
    if (leaveGuard && currentId !== null) {
      const fn = leaveGuard;
      const requested = location.hash;
      guarding = true;
      // Keep the displayed screen active while its asynchronous guard asks about a draft.
      // Otherwise a response received during the dialog could be discarded even when leaving is cancelled.
      if (location.hash !== previous) history.replaceState(null, '', previous);
      let ok = false;
      try {
        ok = await fn({ hash: requested, same: requested === previous });
      } catch (err) {
        console.error(err);
      } finally {
        guarding = false;
      }
      if (!ok) {
        // The screen may have rewritten its parameters during the dialog (replaceParams): restore its address as it is now.
        const restore = currentId !== null ? link(currentId, currentParams) : previous;
        if (location.hash !== restore) history.replaceState(null, '', restore);
        return;
      }
      if (leaveGuard === fn) leaveGuard = null;
      if (location.hash !== requested) history.replaceState(null, '', requested);
    }
    delete docRoot.dataset.ready; // the previous screen is no longer the one being shown
    const { id, params } = parseHash();
    const listed = pages.find((p) => p.id === id);
    const my = ++token;
    if (!id) {
      history.replaceState(null, '', `#/${defaultId}`); // no hashchange: render directly
      if (pages.some((p) => p.id === defaultId)) render();
      return;
    }
    let loaded;
    try {
      loaded = await loadModule(id);
    } catch (err) {
      console.error(err);
      loaded = { mod: errorPage(err), own: true };
    }
    if (my !== token) return;
    // A route outside the navigation needs its own module declaring itself (export const meta = { label, icon }).
    const meta = loaded.own && loaded.mod?.meta && typeof loaded.mod.meta.label === 'string' ? loaded.mod.meta : null;
    const page = listed ?? (meta ? { id, label: meta.label, icon: meta.icon ?? 'sparkles', section: null, hidden: true } : null);
    if (!page) {
      if (!loaded.own) console.warn(`Route inconnue : #/${id}`);
      history.replaceState(null, '', `#/${defaultId}`);
      if (id !== defaultId) render();
      return;
    }
    markNav(id);
    document.title = `${page.label} · Pesto`;
    const first = currentId === null;
    currentId = id;
    currentParams = params;
    // A view transition skipped by a newer navigation still runs its callback: only the latest one mounts.
    const swap = () => {
      if (my !== token) return;
      mount(loaded.mod, page, params, my, first);
      watchReady(page.id, my);
    };
    if (!first && document.startViewTransition && !motionReduced()) {
      const vt = document.startViewTransition(swap);
      vt.finished.catch(() => {});
      vt.updateCallbackDone.catch((err) => console.error(err));
    } else {
      swap();
    }
    if (onChange) onChange(page);
  }

  window.addEventListener('hashchange', render);

  return {
    start() {
      if (started) return;
      started = true;
      return render();
    },
    /** Goes to a screen; params become the query string of the hash. Same hash: renders again. */
    go(id, params) {
      navigate(id, params ?? {});
    },
    navigate,
    link,
    current: () => currentId,
    params: () => currentParams,
    updatePill,
  };
}
