// Pure UI naming metadata checks. No browser, Windows or directory access.
import assert from 'node:assert/strict';
import { serviceCodeSpec } from '../../web/js/service-code.js';

let checks = 0;
for (const width of [1, 2, 3, 4, 5, 6]) {
  const spec = serviceCodeSpec(width);
  const valid = new RegExp(`^(?:${spec.pattern})$`);
  assert.equal(spec.maxLength, width);
  assert(valid.test('A'.repeat(width)));
  assert(valid.test('7'.repeat(width)));
  assert(!valid.test('A'.repeat(width - 1)));
  assert(!valid.test('A'.repeat(width + 1)));
  assert(!valid.test('*'.repeat(width)));
  assert.match(spec.placeholder, new RegExp(String(width)));
  assert.match(spec.patternMessage, new RegExp(String(width)));
  checks++;
}
for (const width of [null, 0, 7, -1, 2.5, '4', true, {}, NaN, Infinity]) {
  assert.throws(() => serviceCodeSpec(width), /Convention de nommage invalide/);
  checks++;
}
assert.deepEqual(serviceCodeSpec(), serviceCodeSpec(3));
checks++;
console.log(`${checks}/${checks} service-code metadata checks passed; no Windows/AD execution.`);
