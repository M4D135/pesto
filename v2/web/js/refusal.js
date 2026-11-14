// A refusal decided by the page itself: coded, so errorText shows its reason instead of a generic internal error.
export function refusal(message, code = 'ui.refused') {
  return Object.assign(new Error(message), { code });
}
