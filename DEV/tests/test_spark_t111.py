import unittest
import re
from pathlib import Path

class TestSparkT111(unittest.TestCase):
    def setUp(self):
        self.file_path = Path(__file__).resolve().parents[1] / 'wad' / 'Pesto-Async.ps1'
        self.assertTrue(self.file_path.is_file(), f"Fichier introuvable: {self.file_path}")
        self.content = self.file_path.read_text(encoding='utf-8-sig')

    def test_gate_split_unchanged(self):
        # Répartition d'origine : un créneau interactif, MaxReaders-1 (au moins un) pour le fond.
        self.assertIn("$background=[Math]::Max(1,$limit-1)", self.content)
        self.assertIn("[Threading.SemaphoreSlim]::new(1,1)", self.content)
        self.assertIn("MaxReaders-1 (au moins un) aux travaux de fond", self.content)
        self.assertNotIn("trois aux travaux de fond", self.content)

    def test_interactive_names_correct(self):
        # Vérifier la présence des nouveaux noms interactifs dans la condition $gate
        # On cherche la ligne spécifique qui assigne $gate
        pattern = r"\$gate=if\(\$Name -in @\(([^)]+)\)\)\{\$script:PestoInteractiveGate\}"
        match = re.search(pattern, self.content)
        self.assertIsNotNone(match, "Ligne de sélection de la gate non trouvée.")
        
        names_str = match.group(1)
        names = [n.strip().strip("'") for n in names_str.split(',')]
        
        # Noms requis par la spec
        required_interactive = [
            'PCProbe', 'DirectPreflight', 'JoinCheck', 'JoinStatus', 'PostState',
            'WindowsAuth', 'LoginAuth', 'NameCandidateCheck', 'SiteLookup',
            'QueuePreflight', 'ConfigReadCheck'
        ]
        
        for name in required_interactive:
            self.assertIn(name, names, f"Le nom interactif '{name}' est manquant dans la liste.")
        
        # Vérifier que 'Login' n'est PAS dans la liste (remplacé par LoginAuth)
        self.assertNotIn('Login', names, "Le nom 'Login' ne doit plus être dans la liste interactive.")
        
        # Vérifier que les noms de fond ne sont PAS dans la liste interactive
        background_names = ['DirectoryRefresh', 'AffectedRefresh', 'NamesProjection', 'InventoryReview', 'LedgerRead', 'HomeReceipts', 'HardwareSuggestion', 'ConfigOuPicker']
        for name in background_names:
            self.assertNotIn(name, names, f"Le nom de fond '{name}' ne doit pas être dans la liste interactive.")


if __name__ == '__main__':
    unittest.main()