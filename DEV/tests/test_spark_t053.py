import unittest
from pathlib import Path

JOIN = Path(__file__).resolve().parents[1] / 'wad' / 'Pesto-Join.ps1'


def read_join():
    if not JOIN.is_file():
        raise AssertionError('Fichier source introuvable : ' + str(JOIN))
    return JOIN.read_text(encoding='utf-8-sig')


class TestSparkT053ReceiptAcl(unittest.TestCase):
    def test_file_exists(self):
        self.assertTrue(JOIN.is_file(), "Pesto-Join.ps1 not found: " + str(JOIN))

    def test_conditional_acl_logic_present(self):
        # Lit le fichier et vérifie la présence de la logique conditionnelle
        content = read_join()
            
        # Aucun cache global : les droits sont relus à chaque écriture et réappliqués s'ils diffèrent.
        self.assertNotIn('PestoReceiptAclCache', content, "Cache inutilisé réintroduit")
        self.assertIn('$needsAcl=$true', content, "Les droits doivent être réappliqués par défaut")
        self.assertIn('@($foundSids|Select-Object -Unique).Count -eq 2', content, "SID distincts requis")
        self.assertIn('Get-Acl', content, "Get-Acl call missing")
        self.assertIn('AreAccessRulesProtected', content, "Protection check missing")
        
        # Vérifie que Set-Acl est bien dans un bloc if
        # Recherche approximative : Set-Acl doit apparaître après une condition if($needsAcl)
        # On vérifie la structure logique
        self.assertIn('if($needsAcl)', content, "Conditional block for Set-Acl missing")

    def test_no_weakening_of_protections(self):
        # Vérifie que les SID attendus sont toujours présents dans la logique de création
        content = read_join()
            
        # Vérifie que les SID critiques sont toujours utilisés pour la création de l'ACL
        self.assertIn("'S-1-5-18'", content, "SYSTEM SID missing")
        self.assertIn("'S-1-5-32-544'", content, "Admins SID missing")
        self.assertIn("FullControl", content, "FullControl missing")
        self.assertIn("ContainerInherit,ObjectInherit", content, "Inheritance flags missing")

if __name__ == '__main__':
    unittest.main()