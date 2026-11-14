"""Portable checks of Windows PowerShell 5.1 pitfalls seen on a real VM (text only)."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
# PowerShell 5.1.26100.6584 : @() sur une collection générique créée par New-Object (objet enveloppé)
# lève « Argument types do not match » ; le mode démo s'arrêtait. Utiliser [...]::new().
NEW_OBJECT_GENERIC = re.compile(
    r'New-Object\s+(-TypeName\s+)?(System\.)?(Collections\.Generic\.)?'
    r'(List|HashSet|Dictionary|Queue|Stack|SortedDictionary)\[', re.IGNORECASE)


class PowerShell51CompatTests(unittest.TestCase):
    def test_no_generic_collection_created_by_new_object(self):
        hits = []
        for path in sorted((ROOT / 'wad').rglob('*.ps1')):
            for number, line in enumerate(path.read_text('utf-8-sig').splitlines(), 1):
                if NEW_OBJECT_GENERIC.search(line):
                    hits.append(f'{path.relative_to(ROOT)}:{number}')
        self.assertEqual([], hits)

    def test_no_psscriptroot_in_parameter_defaults(self):
        # PowerShell 5.1 (APERCU_LOGIN.cmd, recette 2.3) : $PSScriptRoot vide dans une valeur par défaut de paramètre,
        # Join-Path échoue avant toute fenêtre. Calculer le chemin dans le corps du script.
        hits = []
        for folder in ('wad', 'tests'):
            for path in sorted((ROOT / folder).rglob('*.ps1')):
                in_param = False
                for number, line in enumerate(path.read_text('utf-8-sig').splitlines(), 1):
                    # Bloc param( sur plusieurs lignes, ou param(...) avec des paramètres sur la même ligne.
                    opening = re.match(r'\s*param\((.*)$', line, re.IGNORECASE)
                    if opening:
                        in_param = not re.search(r'\)\s*$', opening.group(1)) or opening.group(1).strip() == ''
                        if '$PSScriptRoot' in opening.group(1):
                            hits.append(f'{path.relative_to(ROOT)}:{number}')
                    elif in_param and re.match(r'\s*\)', line):
                        in_param = False
                    elif in_param and '$PSScriptRoot' in line:
                        hits.append(f'{path.relative_to(ROOT)}:{number}')
        self.assertEqual([], hits)


    def test_parser_passes_keep_only_ps1_extension(self):
        # Windows (VM, recette 1.1, 02/10 et 04/10) : -Filter *.ps1 passe par le filtre Win32, où une extension de trois
        # caractères reconnaît aussi les extensions plus longues ; les deux .ps1xml de wad/ étaient analysés comme des
        # scripts (68 fichiers sous Windows, 66 sous Linux). Chaque passe du vrai parseur doit filtrer l'extension exacte.
        self.assert_exact_extension(ROOT / 'tools/checks/validate_pesto.py')

    def test_repository_parser_keeps_only_ps1_extension(self):
        path = ROOT.parent / 'outils/parse_all.ps1'
        if not path.exists() and not (ROOT.parent / 'CLAUDE.md').exists():
            self.skipTest('Outil du dépôt absent du pack DEV autonome ; parseur livré contrôlé séparément.')
        self.assert_exact_extension(path)

    def assert_exact_extension(self, path):
        hits = []
        for number, line in enumerate(path.read_text('utf-8-sig').splitlines(), 1):
            if re.search(r"-Filter\s+['\"]?\*\.ps1\b", line, re.IGNORECASE) and not re.search(
                    r"\.Extension\s+-eq\s+'\.ps1'", line, re.IGNORECASE):
                hits.append(f'{path.name}:{number}')
        self.assertEqual([], hits)

if __name__ == '__main__':
    unittest.main(verbosity=2)
