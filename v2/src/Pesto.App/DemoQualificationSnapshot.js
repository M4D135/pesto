(capture => {
  const root = document.documentElement;
  const main = document.querySelector('main');
  // Startup polls must not trigger layout or animation queries while the route is loading.
  const readiness = {
    ready: Boolean(root.dataset.ready && main?.querySelector('h1') && !main.querySelector('.error-card, .skeleton, [aria-busy="true"]')),
    readyRoute: root.dataset.ready ?? '',
    mainPage: main?.dataset.page ?? '',
    documentState: document.readyState,
    documentVisible: document.visibilityState === 'visible',
    headingPresent: Boolean(main?.querySelector('h1')),
    errorCards: main?.querySelectorAll('.error-card').length ?? 0,
    skeletons: main?.querySelectorAll('.skeleton').length ?? 0,
    busyRegions: main?.querySelectorAll('[aria-busy="true"]').length ?? 0,
    // A screen that never becomes ready must name the engine call still holding it.
    pendingOps: globalThis.__pestoNativeQualificationPending?.() ?? [],
    route: location.hash,
    mode: document.querySelector('.mode-chip')?.dataset.mode ?? '',
    backend: globalThis.__pestoNativeQualification ?? null
  };
  if (!readiness.ready) return readiness;
  if (capture) {
    const finiteAnimationsRunning = document.getAnimations().some(a =>
      a.playState === 'running' && Number.isFinite(a.effect?.getComputedTiming().endTime));
    return { ...readiness, finiteAnimationsRunning };
  }
  const page = main?.querySelector(':scope > .page');
  const mounts = globalThis.__pestoNativeQualificationMounts ??= { next: 0, seen: new WeakMap() };
  if (page && !mounts.seen.has(page)) mounts.seen.set(page, ++mounts.next);
  const banner = document.querySelector('.sim-banner');
  const dialog = [...document.querySelectorAll('.k-dlg-layer:not(.leaving) .k-dlg')].at(-1);
  return {
    ...readiness,
    mountId: page ? mounts.seen.get(page) : 0,
    configurationEntry: new URLSearchParams(location.search).get('configuration') === 'local',
    reloaded: performance.getEntriesByType('navigation')[0]?.type === 'reload',
    title: document.querySelector('main h1')?.textContent ?? '',
    bannerVisible: Boolean(banner && !banner.hidden && getComputedStyle(banner).display !== 'none' && banner.getBoundingClientRect().height > 0),
    bannerText: banner?.querySelector('.text')?.textContent ?? '',
    demoEnabled: Boolean(document.querySelector('.demo-trigger:not([disabled])')),
    navigation: [...document.querySelectorAll('.nav-item[href]')].map(a => a.dataset.id).filter(Boolean).sort(),
    theme: root.dataset.themePref ?? '',
    collapsed: Boolean(document.querySelector('.shell.nav-collapsed')),
    draft: Object.fromEntries([...document.querySelectorAll('[data-form="settings"] [name], textarea[name="sites"]')].map(e => [e.name, e.type === 'checkbox' ? e.checked : e.value])),
    // The join page computes a free name once its lists are read: settled is either that preview or a disabled Ajouter.
    joinFormReady: Boolean(main?.querySelector('[data-form="join"] [name="site"]') && main.querySelector('[data-act="add"]')
      && !main.querySelector('[data-zone="preview"] [aria-busy="true"]')
      && (main.querySelector('[data-zone="preview"] .name-preview') || main.querySelector('[data-act="add"][disabled]'))),
    singleComputerFormReady: Boolean(main?.querySelector('[data-form="search"] [name="query"]') && main.querySelector('[data-zone="identity"]')),
    receiptListReady: Boolean(main?.querySelector('[data-zone="list"]:not([aria-busy="true"])') && !main.querySelector('[data-zone="list"] [role="alert"]')),
    receiptCards: [...document.querySelectorAll('main [data-zone="list"] [data-receipt]')].map(card => ({ id: card.dataset.receipt, status: card.dataset.status, mode: card.dataset.mode })),
    preferences: Object.fromEntries(Object.keys(localStorage).sort().map(k => [k, localStorage.getItem(k)])),
    dialog: dialog ? {
      title: dialog.querySelector('h2')?.textContent ?? '',
      scenario: dialog.querySelector('[name="demoScenario"]')?.value ?? null,
      actions: [...dialog.querySelectorAll('.k-dlg-foot button:not([disabled])')].map(b => b.dataset.id)
    } : null
  };
})
