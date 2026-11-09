"""Accents des messages visibles de Pesto-Startup.ps1 et Pesto-Join.ps1.

Toutes les chaînes littérales (y compris les here-strings) sont extraites hors commentaires, puis comparées à des
radicaux interdits sans accent, en préfixe et sans filtre par mot-clé. Seuls quelques identifiants stables sont admis
(nom de fichier de journal, nom de lanceur, valeur d'état). Le lanceur natif (tools/launcher) est régénéré par
l'intégrateur : ses chaînes sans accent sont listées dans docs/implementation/LOT_SPARK_FILTRE2.md, pas testées ici.
"""
import re
import unittest
from pathlib import Path

DEV = Path(__file__).resolve().parents[1]
FILES = ('wad/Pesto-Startup.ps1', 'wad/Pesto-Join.ps1')
FORBIDDEN = (r'\bdemarr', r'\bredemarr', r'\bdeja\b', r'\bechou', r'\breussi', r'\bparametre', r'\brecu\b', r'\bverifie')
# Identifiants à ne jamais renommer : fichier de journal, script de recette, valeur d'état des reçus.
ALLOWED = (r'Pesto-demarrage\.log', r'VERIFIER_UAC\.cmd', r'\bVerified\b')


def string_literals(source):
    """Chaînes PowerShell hors commentaires : '...', "...", @'...'@ et @"..."@."""
    out = []
    i, n = 0, len(source)
    while i < n:
        c = source[i]
        if source.startswith('<#', i):
            end = source.find('#>', i + 2)
            i = n if end < 0 else end + 2
        elif c == '#':
            end = source.find('\n', i)
            i = n if end < 0 else end + 1
        elif source.startswith("@'", i) or source.startswith('@"', i):
            quote = source[i + 1]
            match = re.compile(r'\r?\n' + quote + '@').search(source, i + 2)
            end = n if not match else match.start()
            out.append(source[i + 2:end])
            i = n if not match else match.end()
        elif c == "'":
            j = i + 1
            while j < n:
                if source[j] in "'‘’":
                    if j + 1 < n and source[j + 1] in "'‘’":
                        j += 2
                        continue
                    break
                j += 1
            out.append(source[i + 1:j])
            i = j + 1
        elif c == '"':
            j = i + 1
            while j < n:
                if source[j] == '`':
                    j += 2
                    continue
                if source[j] == '"':
                    if j + 1 < n and source[j + 1] == '"':
                        j += 2
                        continue
                    break
                j += 1
            out.append(source[i + 1:j])
            i = j + 1
        elif c == '`':
            i += 2
        else:
            i += 1
    return out


def unaccented(literal):
    text = literal
    for allowed in ALLOWED:
        text = re.sub(allowed, ' ', text)
    lower = text.lower()
    return [stem for stem in FORBIDDEN if re.search(stem, lower)]


class TestAccents(unittest.TestCase):
    def test_extraction_sees_strings_not_comments(self):
        sample = "# demarrage dans un commentaire\n<# deja #>\n$a='Argument de demarrage invalide.'\n$b=\"deja `\"ouvert`\"\"\n$c=@'\nparametre\n'@\n"
        self.assertEqual([unaccented(s) for s in string_literals(sample)],
                         [[r'\bdemarr'], [r'\bdeja\b'], [r'\bparametre']])
        self.assertEqual(unaccented('Argument de démarrage invalide.'), [])
        self.assertEqual(unaccented('Pesto-demarrage.log'), [])
        self.assertEqual(unaccented('redemarrer le poste'), [r'\bredemarr'])

    def test_launcher_wide_messages_keep_french_accents(self):
        path = DEV / 'tools' / 'launcher' / 'Pesto-launcher.c'
        literals = re.findall(r'W\("((?:\\.|[^"\\])*)"\)', path.read_text(encoding='utf-8'))
        self.assertGreater(len(literals), 30)
        hits = [(literal, unaccented(literal)) for literal in literals if unaccented(literal)]
        self.assertEqual(hits, [])

    def test_accents_in_sources(self):
        hits = []
        for name in FILES:
            path = DEV / name
            self.assertTrue(path.is_file(), 'Fichier introuvable : ' + str(path))
            for literal in string_literals(path.read_text(encoding='utf-8-sig')):
                found = unaccented(literal)
                if found:
                    hits.append('%s : %r (%s)' % (name, literal[:120], ', '.join(found)))
        self.assertEqual(hits, [], 'Chaînes sans accent dans les messages')


if __name__ == '__main__':
    unittest.main()
