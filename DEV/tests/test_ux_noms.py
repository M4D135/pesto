"""La table des libellés ne doit pas dériver de ce que le XAML affiche réellement.

Le 10/10/2026, trois messages renvoyaient l'utilisateur vers des contrôles que
l'interface ne nommait pas ainsi : « Cochez Traiter un poste distant » (ChkRemote
porte « Un autre poste du domaine »), « Utilisez Reprendre déplacement »
(BtnRetryMove porte « Vérifier puis reprendre »), « Traitement par lot »
(SuiteModeBatch porte « Plusieurs postes »). Rien dans la suite ne le détectait :
le XAML et les messages étaient simplement tous les deux écrits à la main.

Ces contrôles rendent la table $script:PESTO_UX_NOMS solidaire du XAML.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
WAD = ROOT / 'wad'
TABLE_FICHIER = WAD / 'Pesto-UXFlow.ps1'


def table_ux():
    """Les paires clef -> libellé de $script:PESTO_UX_NOMS."""
    texte = TABLE_FICHIER.read_text('utf-8-sig')
    bloc = re.search(r'\$script:PESTO_UX_NOMS\s*=\s*\[ordered\]@\{(.*?)\n\}', texte, re.S)
    assert bloc, 'la table $script:PESTO_UX_NOMS est introuvable dans Pesto-UXFlow.ps1'
    return dict(re.findall(r"^\s*(\w+)\s*=\s*'([^']*)'\s*$", bloc.group(1), re.M))


def libelles_affiches():
    """Tout ce que le XAML affiche : Content=, Header= et Text= des fichiers .xaml
    et des blocs XAML embarqués dans les .ps1 (les fenêtres de jonction, d'authentification
    et d'interventions sont construites là, pas dans un fichier .xaml)."""
    trouves = set()
    for f in sorted(WAD.glob('*.xaml')) + sorted(WAD.glob('*.ps1')):
        texte = f.read_text('utf-8-sig')
        for attribut in ('Content', 'Header', 'Text'):
            trouves.update(re.findall(attribut + r'="([^"]*)"', texte))
    return trouves


def clefs_citees():
    """Les clefs réellement demandées par les messages, avec leur fichier."""
    cites = []
    for f in sorted(WAD.glob('*.ps1')):
        texte = f.read_text('utf-8-sig')
        for m in re.finditer(r"Get-PestoUxNom\s+'(\w+)'", texte):
            cites.append((f.name, m.group(1)))
    return cites


class TableUxNomsTests(unittest.TestCase):
    def test_chaque_libelle_de_la_table_est_affiche(self):
        # Un libellé renommé dans le XAML sans reprendre la table laisserait un message
        # citer un bouton qui n'existe plus : c'est exactement le défaut mesuré le 10/10.
        affiches = libelles_affiches()
        for clef, libelle in table_ux().items():
            self.assertIn(libelle, affiches,
                          'la table annonce %s = %r, aucun élément du XAML ne porte ce libellé' % (clef, libelle))

    def test_les_messages_n_inventent_aucune_clef(self):
        # Get-PestoUxNom lève sur une clef inconnue : cette erreur éclaterait à l'écran,
        # au moment où l'utilisateur lit un message. Elle se rattrape ici.
        connues = set(table_ux())
        for fichier, clef in clefs_citees():
            self.assertIn(clef, connues, '%s demande la clef UX %s, absente de la table' % (fichier, clef))

    def test_la_table_est_citee_par_au_moins_un_message(self):
        # Une table que personne n'utilise ne protège de rien : elle redevient une
        # seconde écriture du libellé, à maintenir à la main.
        self.assertGreaterEqual(len(set(c for _, c in clefs_citees())), 5,
                                'la table est définie mais presque jamais utilisée par les messages')

    def test_les_fantomes_ne_reviennent_pas(self):
        # Les libellés mesurés en défaut le 10/10/2026 : les trois du premier correctif,
        # celui trouvé dans la même phrase, puis les deux citations de la page de
        # jonction reprises le même jour. Les réintroduire ferait échouer ce test
        # plutôt que le technicien.
        interdits = ('Traiter un poste distant', 'Reprendre déplacement', 'Traitement par lot',
                     'Utilisez Renommer / déplacer', 'Utilisez « Renommer / déplacer »')
        fautifs = []
        for f in sorted(WAD.glob('*.ps1')):
            for n, ligne in enumerate(f.read_text('utf-8-sig').splitlines(), 1):
                for interdit in interdits:
                    if interdit in ligne:
                        fautifs.append('%s:%d' % (f.name, n))
        self.assertFalse(fautifs,
                         'libellé retiré le 10/10/2026 revenu à %s' % ', '.join(fautifs[:10]))


if __name__ == '__main__':
    unittest.main()
