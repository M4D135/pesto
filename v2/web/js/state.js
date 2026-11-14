// Small state machines shared by the pages and the regression tests.
export class LatestRequest {
  #version = 0;
  #closed = false;
  invalidate() { return ++this.#version; }
  current(version) { return !this.#closed && version === this.#version; }
  close() { this.#closed = true; this.invalidate(); }
  async run(work, accept, reject = () => {}) {
    const version = this.invalidate();
    try { const value = await work(); if (this.current(version)) accept(value); }
    catch (error) { if (this.current(version)) reject(error); }
  }
}

export function completePreview(preview, now = Date.now()) {
  return !!preview && preview.complete === true && typeof preview.name === 'string' && preview.name.length > 0
    && typeof preview.previewId === 'string' && Number.isFinite(Date.parse(preview.expiresAt)) && Date.parse(preview.expiresAt) > now;
}

export function capability(session, id) {
  const item = session?.capabilities?.find((entry) => entry.id === id);
  return item?.enabled === true ? { enabled: true, reason: '' }
    : { enabled: false, reason: item?.reason || 'Cette action n’est pas disponible avec le moteur connecté.' };
}

export function splitComputers(value) {
  const names = String(value).split(/[\s,;]+/).map((n) => n.trim()).filter(Boolean);
  const seen = new Set();
  return names.filter((name) => { const key = name.toUpperCase(); if (seen.has(key)) return false; seen.add(key); return true; });
}
