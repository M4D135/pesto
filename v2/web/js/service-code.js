// The directory catalogue already carries the active naming width: no extra settings/AD read.
// Older fixtures and the browser demo use the default three-character convention.
import { refusal } from './refusal.js';

export function serviceCodeSpec(width = 3) {
  if (!Number.isInteger(width) || width < 1 || width > 6)
    throw refusal('Convention de nommage invalide : le code service doit compter de 1 à 6 caractères.', 'naming.serviceWidth');
  const length = `${width} caractère${width === 1 ? '' : 's'}`;
  return {
    maxLength: width,
    pattern: `[A-Za-z0-9]{${width}}`,
    placeholder: `Code service (${length})`,
    patternMessage: `Saisissez un code service de ${length}.`,
  };
}
