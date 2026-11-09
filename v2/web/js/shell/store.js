// Shell store: appearance preferences (kept apart for the real mode and the simulation, per the mission), session
// facts read from the engine, and a tiny pub/sub shared by the shell and the screens. Nothing here calls the bridge:
// app.js feeds the store after its calls. No secret is ever stored.
const BASE = 'pesto.prefs.v1';
const THEMES = ['light', 'dark', 'contrast', 'system'];
const MOTIONS = ['full', 'reduced', 'system'];
const NAV_MIN = 200, NAV_MAX = 320, NAV_DEFAULT = 248, NAV_COLLAPSED = 72;

const DEFAULTS = {
  theme: 'system', motion: 'full', navCollapsed: false, navWidth: null, bannerCompact: false,
};

const listeners = new Map(); // event → Set<fn>

function readKey(key) {
  try {
    const raw = localStorage.getItem(key);
    const parsed = raw ? JSON.parse(raw) : null;
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch { return null; }
}

function writeKey(key, value) {
  try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* private mode: memory only */ }
}

function sanitize(saved) {
  const p = { ...DEFAULTS, ...(saved ?? {}) };
  if (!THEMES.includes(p.theme)) p.theme = DEFAULTS.theme;
  if (!MOTIONS.includes(p.motion)) p.motion = DEFAULTS.motion;
  p.navCollapsed = !!p.navCollapsed;
  p.bannerCompact = !!p.bannerCompact;
  if (p.navWidth !== null && (!Number.isFinite(p.navWidth) || p.navWidth < NAV_MIN || p.navWidth > NAV_MAX)) p.navWidth = null;
  return p;
}

let mode = null; // null until session.info answers; then 'live' or 'simulation'
let prefs = sanitize(readKey(BASE));

const modeKey = () => (mode ? `${BASE}#${mode}` : BASE);

export const state = {
  get prefs() { return prefs; },
  session: null,   // last session.info payload
  reach: { offline: false, since: null },
};

export function on(event, fn) {
  if (!listeners.has(event)) listeners.set(event, new Set());
  listeners.get(event).add(fn);
  return () => listeners.get(event)?.delete(fn);
}

export function emit(event, value) {
  for (const fn of listeners.get(event) ?? []) {
    try { fn(value); } catch (err) { console.error(err); }
  }
}

/** Applies the copy of the preferences kept for this mode (mission: appearance separated live/simulation). */
export function adoptMode(nextMode) {
  const resolved = nextMode === 'live' || nextMode === 'simulation' ? nextMode : null;
  if (resolved === mode) return prefs;
  mode = resolved;
  const copy = mode ? readKey(modeKey()) : null;
  prefs = sanitize(copy ?? readKey(BASE));
  emit('prefs', prefs);
  return prefs;
}

export function setPrefs(patch) {
  const next = sanitize({ ...prefs, ...patch });
  prefs = next;
  writeKey(BASE, next);
  if (mode) writeKey(modeKey(), next);
  emit('prefs', prefs);
  return prefs;
}

export { NAV_MIN, NAV_MAX, NAV_DEFAULT, NAV_COLLAPSED };
