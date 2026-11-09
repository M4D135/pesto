import unittest
import os
import re

class TestSparkT058(unittest.TestCase):
    def test_startup_log_fallback_and_path(self):
        # Lire le fichier source
        file_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'wad', 'Pesto-Startup.ps1')
        self.assertTrue(os.path.exists(file_path), f"Fichier source introuvable : {file_path}")
        
        with open(file_path, 'r', encoding='utf-8-sig') as f:
            content = f.read()

        # Vérifier la présence de la variable de script pour mémoriser le chemin
        self.assertIn('$script:PestoStartupLogPath', content, "La variable $script:PestoStartupLogPath doit être utilisée.")
        
        # Vérifier la logique de repli (candidates)
        self.assertIn('$candidates', content, "La liste de candidats $candidates doit être présente.")
        self.assertIn('LOCALAPPDATA', content, "Le repli sur LOCALAPPDATA doit être présent.")
        self.assertIn('TEMP', content, "Le repli sur TEMP doit être présent.")
        
        # Vérifier que le message d'échec ou l'info utilise le chemin réel
        # On cherche une ligne qui construit le message avec le chemin du journal
        self.assertIn('Journal :', content, "Le message doit mentionner 'Journal :'.")
        self.assertIn('$script:PestoStartupLogPath', content, "Le message doit utiliser la variable de chemin.")

if __name__ == '__main__':
    unittest.main()