// In-page dialogs (never a new window): free content, confirmation, and reinforced confirmation of writes where the
// operator types the name of the target. One request at a time: a new one withdraws the previous (Domenia 1, TRV-058).
import { glyph } from './glyphs.js';
import {
  esc, uid, fill, focusables, trapFocus, pushModal, popModal, leave, quote, NBSP, announce,
} from './util.js';

/**
 * @typedef {Object} DialogAction
 * @property {string} id                     Returned when chosen.
 * @property {string} label
 * @property {string} [icon]
 * @property {boolean} [primary]             Main action (gradient button).
 * @property {boolean} [danger]              Write or destructive action (red).
 * @property {boolean} [safe]                Safe answer: receives the focus when the dialog opens.
 * @property {boolean} [disabled]
 */

/**
 * @typedef {Object} DialogOptions
 * @property {string} title
 * @property {string} [subtitle]
 * @property {string} [icon]
 * @property {'normal'|'danger'|'info'} [tone='normal']
 * @property {'sm'|'md'|'lg'} [size='md']
 * @property {Node|string} [body]           Node, or trusted markup (escape data with esc()).
 * @property {DialogAction[]} [actions]     Default: a single « Fermer ».
 * @property {boolean} [dismissible=true]   Échap and the close button answer null.
 * @property {string} [badge]                Small label in the header (« Écriture dans l’annuaire »).
 * @property {(el: HTMLElement) => void} [onOpen]
 */

let currentDialog = null;

/**
 * Opens a dialog in the page. The page below is inert while it is open; the focus is trapped, then given back.
 * @param {DialogOptions} opts
 * @returns {{ el: HTMLElement, body: HTMLElement, result: Promise<string|null>, close: (id?: string|null) => void, setDisabled: (id: string, on: boolean) => void }}
 */
export function openDialog(opts) {
  currentDialog?.close(null);
  const id = uid('dlg');
  const tone = opts.tone ?? 'normal';
  const actions = opts.actions?.length ? opts.actions : [{ id: 'close', label: 'Fermer', safe: true, primary: true }];
  const layer = document.createElement('div');
  layer.className = 'k-surface k-dlg-layer';
  layer.innerHTML = `<div class="k-dlg ${esc(tone)} ${esc(opts.size ?? 'md')}" role="${tone === 'danger' ? 'alertdialog' : 'dialog'}" aria-modal="true" aria-labelledby="${id}-t" aria-describedby="${id}-b" tabindex="-1">
    <span class="k-dlg-glow" aria-hidden="true"></span>
    <header class="k-dlg-head">
      ${opts.icon ? `<span class="k-dlg-icon">${glyph(opts.icon)}</span>` : ''}
      <div class="k-dlg-titles">${opts.badge ? `<span class="k-dlg-badge">${glyph('edit')}${esc(opts.badge)}</span>` : ''}
        <h2 id="${id}-t">${esc(opts.title)}</h2>${opts.subtitle ? `<p class="k-dlg-sub">${esc(opts.subtitle)}</p>` : ''}</div>
      ${opts.dismissible === false ? '' : `<button class="btn ghost icon sm k-dlg-x" type="button" aria-label="Fermer" data-tip="Fermer (Échap)">${glyph('x')}</button>`}
    </header>
    <div class="k-dlg-body" id="${id}-b"></div>
    <footer class="k-dlg-foot">${actions.map((a) => `<button class="btn${a.primary ? ' primary' : ''}${a.danger ? ' danger' : ''}${!a.primary && !a.danger ? ' subtle' : ''}" type="button" data-id="${esc(a.id)}"${a.disabled ? ' disabled' : ''}>${a.icon ? glyph(a.icon) : ''}${esc(a.label)}</button>`).join('')}</footer>
  </div>`;
  const dlg = /** @type {HTMLElement} */ (layer.querySelector('.k-dlg'));
  const body = /** @type {HTMLElement} */ (layer.querySelector('.k-dlg-body'));
  fill(body, opts.body);
  const restore = document.activeElement instanceof HTMLElement ? document.activeElement : null;

  let settle;
  const result = new Promise((resolve) => { settle = resolve; });
  let closed = false;
  let release = () => {};

  const close = (answer = null) => {
    if (closed) return;
    closed = true;
    if (currentDialog === ctl) currentDialog = null;
    release();
    window.removeEventListener('hashchange', onHash);
    popModal(layer);
    leave(layer, 360).then(() => layer.remove());
    if (restore?.isConnected) restore.focus({ preventScroll: true });
    settle(answer);
  };
  // Bubbling phase on the dialog: a field of the body that uses Échap itself (search, filter) handles it first.
  const onKey = (e) => {
    if (e.key === 'Escape' && !e.defaultPrevented && opts.dismissible !== false) {
      e.preventDefault();
      e.stopPropagation();
      close(null);
    }
  };
  // Leaving the screen withdraws the request without running anything.
  const onHash = () => close(null);

  layer.addEventListener('click', (e) => {
    const b = e.target instanceof Element ? e.target.closest('button') : null;
    if (!b || b.disabled) return;
    if (b.classList.contains('k-dlg-x')) close(null);
    else if (b.dataset.id && b.closest('.k-dlg-foot')) close(b.dataset.id);
  });

  const ctl = {
    el: dlg,
    body,
    result,
    close,
    setDisabled(actionId, on) {
      const b = dlg.querySelector(`.k-dlg-foot [data-id="${CSS.escape(actionId)}"]`);
      if (b instanceof HTMLButtonElement) b.disabled = !!on;
    },
  };
  currentDialog = ctl;

  document.body.appendChild(layer);
  pushModal(layer);
  release = trapFocus(dlg);
  dlg.addEventListener('keydown', onKey);
  window.addEventListener('hashchange', onHash);
  opts.onOpen?.(dlg);
  const safe = actions.find((a) => a.safe);
  const target = (safe && dlg.querySelector(`.k-dlg-foot [data-id="${CSS.escape(safe.id)}"]`))
    || focusables(body)[0] || dlg.querySelector('.k-dlg-foot button:not([disabled])') || dlg;
  /** @type {HTMLElement} */ (target).focus({ preventScroll: true });
  return ctl;
}

/**
 * Simple confirmation. Resolves true only on the confirm button.
 * @param {{ title: string, message: string, confirmLabel?: string, cancelLabel?: string, danger?: boolean, icon?: string }} opts
 * @returns {Promise<boolean>}
 */
export function confirmDialog(opts) {
  const d = openDialog({
    title: opts.title,
    icon: opts.icon ?? (opts.danger ? 'alert' : 'info'),
    tone: opts.danger ? 'danger' : 'normal',
    size: 'sm',
    body: `<p class="k-dlg-text">${esc(opts.message)}</p>`,
    actions: [
      { id: 'cancel', label: opts.cancelLabel ?? 'Annuler', safe: true },
      { id: 'ok', label: opts.confirmLabel ?? 'Confirmer', primary: !opts.danger, danger: !!opts.danger },
    ],
  });
  return d.result.then((r) => r === 'ok');
}

/**
 * @typedef {Object} WriteConfirmation
 * @property {string} title                  « Désactiver le compte ».
 * @property {string} message                What will happen, in plain words (2 000 characters at most).
 * @property {string} target                 Exact name to type (case-sensitive), e.g. the sAMAccountName.
 * @property {string} [targetKind]           « le compte », « le poste »…
 * @property {string} [targetDetail]         DN or path shown under the name.
 * @property {Array<{label: string, before?: string, after?: string}>} [changes]
 * @property {string[]} [warnings]           Operator warnings, always visible before confirmation.
 * @property {string} [details]              Technical details, folded (plan, controller, fingerprint).
 * @property {string} [confirmLabel]
 * @property {{ label: string }} [alternate] Third answer (resolves 'alternate').
 * @property {string} [badge]                Default « Écriture dans l’annuaire ».
 * @property {boolean} [typed=true]          false: the plan asks for no typed name (docs/WRITES.md), the confirm button
 *                                           is active at once; the dialog still shows target, changes and details.
 * @property {(text: string) => void} [onTyped]  Receives the typed name when the operator confirms, so the page can send
 *                                           it to the engine, which checks it again.
 * @property {Array<{id: string, label: string}>} [checks] Explicit acknowledgements, all required and initially unchecked.
 * @property {(ids: string[]) => void} [onChecks]
 * @property {{label: string, minLength?: number, maxLength?: number}} [reason] Required operator reason.
 * @property {(text: string) => void} [onReason]
 */

/**
 * Reinforced confirmation of a write: changes before and after, folded technical details, and the name of the target
 * to type exactly (paste disabled) unless the plan says otherwise (typed: false). The safe answer has the focus; Entrée
 * confirms only once the name matches. Resolves 'confirm', 'alternate' or null. It never writes anything itself: the page
 * sends the plan afterwards.
 * @param {WriteConfirmation} opts
 * @returns {Promise<'confirm'|'alternate'|null>}
 */
export function confirmWrite(opts) {
  const typed = opts.typed !== false;
  const checks = opts.checks ?? [];
  const minReason = opts.reason?.minLength ?? 3;
  const maxReason = opts.reason?.maxLength ?? 500;
  const id = uid('cw');
  const message = String(opts.message ?? '').slice(0, 2000);
  const changes = (opts.changes ?? []).map((c) => `<li><span class="k-cw-label">${esc(c.label)}</span>`
    + `${c.before !== undefined ? `<span class="k-cw-before">${esc(c.before || '—')}</span>` : ''}`
    + `${c.before !== undefined && c.after !== undefined ? `<span class="k-cw-arrow">${glyph('chevronRight')}<span class="visually-hidden"> devient </span></span>` : ''}`
    + `${c.after !== undefined ? `<span class="k-cw-after">${esc(c.after || '—')}</span>` : ''}</li>`).join('');
  const body = `<p class="k-dlg-text">${esc(message)}</p>
    <div class="k-cw-target"><span class="k-cw-kind">${esc(opts.targetKind ?? 'Cible')}</span><b class="mono">${esc(opts.target)}</b>
      ${opts.targetDetail ? `<span class="k-cw-dn mono">${esc(opts.targetDetail)}</span>` : ''}</div>
    ${changes ? `<ul class="k-cw-changes" aria-label="Changements prévus">${changes}</ul>` : ''}
    ${opts.warnings?.length ? `<ul class="k-cw-warnings" aria-label="Points à vérifier">${opts.warnings.map((warning) => `<li>${esc(warning)}</li>`).join('')}</ul>` : ''}
    ${opts.details ? `<div class="k-cw-details"><button class="k-cw-more" type="button" aria-expanded="false" aria-controls="${id}-d">${glyph('chevronRight')}Détails techniques</button>
      <pre class="k-cw-pre" id="${id}-d" hidden>${esc(opts.details)}</pre></div>` : ''}
    ${checks.length ? `<div class="k-cw-checks">${checks.map((check, i) => `<label class="k-cw-consent" for="${id}-check-${i}"><input id="${id}-check-${i}" type="checkbox" data-consent="${esc(check.id)}"><span>${esc(check.label)}</span></label>`).join('')}</div>` : ''}
    ${opts.reason ? `<div class="k-field k-cw-reason"><label for="${id}-reason">${esc(opts.reason.label)}</label>
      <textarea class="input" id="${id}-reason" rows="3" maxlength="${maxReason}" aria-describedby="${id}-reason-h"></textarea>
      <p class="k-hint" id="${id}-reason-h">${minReason} à ${maxReason} caractères. Ce motif sera conservé avec votre identité dans la preuve durable.</p></div>` : ''}
    ${typed ? `<div class="k-field k-cw-typed">
      <label for="${id}-in">Pour confirmer, saisissez ${esc(quote(opts.target))}</label>
      <div class="k-cw-inrow"><input class="input mono" id="${id}-in" type="text" autocomplete="off" spellcheck="false" aria-describedby="${id}-h">
        <span class="k-cw-ok" aria-hidden="true">${glyph('check')}</span></div>
      <p class="k-hint" id="${id}-h">Respectez les majuscules. Le collage est désactivé pour cette saisie.</p>
    </div>` : ''}`;
  const actions = [
    { id: 'cancel', label: 'Annuler', safe: true },
    ...(opts.alternate ? [{ id: 'alternate', label: opts.alternate.label }] : []),
    { id: 'confirm', label: opts.confirmLabel ?? 'Confirmer l’écriture', icon: 'edit', danger: true, disabled: typed || checks.length > 0 || !!opts.reason },
  ];
  const d = openDialog({
    title: opts.title,
    icon: 'shield',
    tone: 'danger',
    size: 'md',
    badge: opts.badge ?? 'Écriture dans l’annuaire',
    body,
    actions,
  });
  const input = /** @type {HTMLInputElement|null} */ (d.body.querySelector('.k-cw-typed input'));
  const consentInputs = [...d.body.querySelectorAll('[data-consent]')];
  const reason = d.body.querySelector('.k-cw-reason textarea');
  const reasonText = () => String(reason?.value ?? '').replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ').trim();
  const canConfirm = () => (!input || input.value === opts.target) && consentInputs.every((checkbox) => checkbox.checked)
    && (!reason || (reasonText().length >= minReason && reasonText().length <= maxReason));
  const updateConfirmation = () => d.setDisabled('confirm', !canConfirm());
  consentInputs.forEach((checkbox) => checkbox.addEventListener('change', updateConfirmation));
  reason?.addEventListener('input', updateConfirmation);
  if (input) {
    const row = d.body.querySelector('.k-cw-typed');
    const hint = d.body.querySelector('.k-hint');
    let matched = false;
    const check = () => {
      matched = input.value === opts.target;
      row.classList.toggle('ok', matched);
      input.setAttribute('aria-invalid', String(input.value !== '' && !opts.target.startsWith(input.value)));
      updateConfirmation();
    };
    input.addEventListener('input', check);
    const refuse = (e) => {
      e.preventDefault();
      hint.textContent = `Le collage est désactivé${NBSP}: saisissez le nom lettre par lettre.`;
      hint.classList.add('warn');
      announce('Le collage est désactivé : saisissez le nom.');
    };
    input.addEventListener('paste', refuse);
    input.addEventListener('drop', refuse);
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        if (canConfirm()) d.close('confirm');
      }
    });
  }
  const more = d.body.querySelector('.k-cw-more');
  more?.addEventListener('click', () => {
    const pre = d.body.querySelector('.k-cw-pre');
    const open = more.getAttribute('aria-expanded') !== 'true';
    more.setAttribute('aria-expanded', String(open));
    pre.hidden = !open;
  });
  return d.result.then((r) => {
    if (r === 'confirm') {
      if (!canConfirm()) return null;
      if (input) opts.onTyped?.(input.value);
      if (reason) opts.onReason?.(reasonText());
      if (checks.length) opts.onChecks?.(consentInputs.filter((checkbox) => checkbox.checked).map((checkbox) => checkbox.dataset.consent));
    }
    return r === 'confirm' || r === 'alternate' ? r : null;
  });
}
