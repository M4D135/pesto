// Contrôle portable du mapping AZERTY du pilote GUI (aucune VM touchée : comparaison de tableaux de scancodes).
// Source des vérité : GUI_HANDOFF_20261025.md §1 — scancodes éprouvés sur la console VBox réelle, dont la
// séquence complète « c:\temp\g.bat » après Ctrl+A. L'ancien tableau tapait « CM\Te,p\w:bat » (capture
// supervisor-gui-current.png) : ce test verrouille chaque pièce fautive et la séquence entière octet à octet.
// Exécution : node tools/tests/azerty-check.mjs — sortie 0 seulement si tout passe.
import { charCodes, tapCodes, codesForText } from '../qualification/gui-session1.mjs';

let checks = 0, failures = 0;
const eq = (name, got, want) => {
  checks += 1;
  const okArr = Array.isArray(got) && Array.isArray(want) && got.length === want.length && got.every((v, i) => v === want[i]);
  if (okArr) console.log(`  ok   ${name}`);
  else { failures += 1; console.error(`  FAIL ${name}\n       attendu : ${want?.map((c) => c.toString(16)).join(' ')}\n       reçu    : ${got?.map((c) => c.toString(16)).join(' ')}`); }
};
eq('m = 27 a7 (éprouvé handoff)', charCodes('m'), [0x27, 0xa7]);
eq('w = 2c ac (éprouvé handoff)', charCodes('w'), [0x2c, 0xac]);
eq(': = 34 b4 sans shift (éprouvé)', charCodes(':'), [0x34, 0xb4]);
eq('. = 2a 33 b3 aa shift+0x33 (éprouvé)', charCodes('.'), [0x2a, 0x33, 0xb3, 0xaa]);
eq('antislash = e0 38 09 89 e0 b8 (éprouvé)', charCodes('\\'), [0xe0, 0x38, 0x09, 0x89, 0xe0, 0xb8]);
eq('slash = 2a 34 b4 aa (éprouvé)', charCodes('/'), [0x2a, 0x34, 0xb4, 0xaa]);
eq('Ctrl+A = 1d 10 90 9d (éprouvé)', tapCodes(0x10, { ctrl: true }), [0x1d, 0x10, 0x90, 0x9d]);

// Fautes de la capture supervisor-gui-current.png : « CM\Te,p\w:bat » pour « C:\Temp\w.bat ».
eq('C = shift+c (2a 2e ae aa)', charCodes('C'), [0x2a, 0x2e, 0xae, 0xaa]);
eq('T = shift+t (2a 14 94 aa)', charCodes('T'), [0x2a, 0x14, 0x94, 0xaa]);
eq('virgule = 32 b2 (et non 33)', charCodes(','), [0x32, 0xb2]);
eq('point-virgule = 33 b3 (et non 27)', charCodes(';'), [0x33, 0xb3]);
eq('tiret = 07 87 (touche 6, pas 0c)', charCodes('-'), [0x07, 0x87]);
eq('parenthèse fermante = 0c 8c (touche °, pas 0a)', charCodes(')'), [0x0c, 0x8c]);
eq('apostrophe = 05 85 (touche 4)', charCodes("'"), [0x05, 0x85]);
eq('guillemet = 04 84 (touche 3)', charCodes('"'), [0x04, 0x84]);
eq('inférieur = e0 56 e0 d6 (touche 102)', charCodes('<'), [0xe0, 0x56, 0xe0, 0xd6]);
eq('chiffre 8 = shift+09 (2a 09 89 aa)', charCodes('8'), [0x2a, 0x09, 0x89, 0xaa]);
eq('accent aigu = 03 83 (touche 2)', charCodes('é'), [0x03, 0x83]);
eq('AltGr+0 = @ en RMENU seul (e0 38 0b 8b e0 b8)', charCodes('@'), [0xe0, 0x38, 0x0b, 0x8b, 0xe0, 0xb8]);

// Séquence complète éprouvée du handoff : c:\temp\g.bat après Ctrl+A.
const PROUVÉ = '2e ae 34 b4 e0 38 09 89 e0 b8 14 94 12 92 27 a7 19 99 e0 38 09 89 e0 b8 22 a2 2a 33 b3 aa 30 b0 10 90 14 94'
  .split(' ').map((h) => parseInt(h, 16));
eq('séquence complète « c:\\temp\\g.bat » identique octet à octet', codesForText('c:\\temp\\g.bat'), PROUVÉ);

// Caractère non établi → erreur explicite (aucun code deviné tapé en silence).
checks += 1;
try { charCodes('^'); failures += 1; console.error('  FAIL caractère non mappé (^) doit lever'); }
catch (e) { console.log('  ok   caractère non mappé (^) lève : ' + e.message); }

console.log(`\n${checks - failures}/${checks} contrôles AZERTY réussis.`);
process.exit(failures === 0 ? 0 : 1);
