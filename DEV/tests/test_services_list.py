"""Liste des services et libellé « Service » (signalés par David le 05/10/2026, texte seulement).

1. Mode jonction (poste hors domaine) : le service n'était qu'une zone de texte, sans liste ; et le login léger ne
   charge pas l'inventaire, donc aucune liste de services ni de noms déjà pris tant que Noms n'était pas ouvert.
2. Noms disponibles : le code service était affiché « Équipe ».
"""
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
WAD = ROOT / 'wad'
X = '{http://schemas.microsoft.com/winfx/2006/xaml}'


def read(name):
    return (WAD / name).read_text('utf-8-sig')


def function_body(text, name):
    match = re.search(r'(?m)^function ' + re.escape(name) + r'\b', text)
    if not match:
        return ''
    following = re.search(r'(?m)^function ', text[match.end():])
    return text[match.start():match.end() + following.start()] if following else text[match.start():]


class JoinServiceListTests(unittest.TestCase):
    def test_join_service_is_editable_list(self):
        root = ET.fromstring(read('Pesto-Join.xaml'))
        found = [e for e in root.iter() if e.get(X + 'Name') == 'JnService']
        self.assertEqual(1, len(found))
        control = found[0]
        self.assertTrue(control.tag.endswith('ComboBox'), control.tag)
        self.assertEqual('True', control.get('IsEditable'))

    def test_join_service_list_filled_from_site_codes(self):
        join = read('Pesto-Join.ps1')
        update = function_body(join, 'Update-PestoJoinServices')
        self.assertIn('Get-PestoSiteServiceCodes', update)
        changed = function_body(join, 'Invoke-PestoJoinInputChanged')
        self.assertIn('Update-PestoJoinServices', changed)
        self.assertRegex(changed, r"'JnOrg'\s*,\s*'JnSite'")
        init = function_body(join, 'Initialize-PestoJoinUI')
        # TextBox.TextChanged n'existe pas sur un ComboBox : l'événement routé de sa zone éditable.
        self.assertRegex(init, r'\$ui\.Service\.AddHandler\(\[Windows\.Controls\.Primitives\.TextBoxBase\]::TextChangedEvent')
        self.assertNotIn('$ui.Service.Add_TextChanged', init)
        self.assertIn('Update-PestoJoinServices', init)

    def test_join_page_requests_inventory_out_of_domain(self):
        join = read('Pesto-Join.ps1')
        request = function_body(join, 'Request-PestoJoinInventory')
        for token in ('$script:INDOMAIN', '$script:GUI', '$script:InventoryLoaded', '$script:Running',
                      '$script:DirectBusy', '$script:JoinBusy', 'Refresh-Names'):
            self.assertIn(token, request)
        page = function_body(read('Pesto-Core.ps1'), 'Set-PestoUxPage')
        # 08/10 soir : la page de jonction lit seulement le site choisi (recherche ciblée), plus l'inventaire complet.
        self.assertRegex(page, r"if\(\$Page -eq 'Join'\)\{[^}]*Request-PestoJoinSiteLookup")
        self.assertNotRegex(page, r"if\(\$Page -eq 'Join'\)\{[^}]*Request-PestoJoinInventory")

    def test_lists_refreshed_after_inventory(self):
        directory = read('Pesto-Directory.ps1')
        complete = function_body(directory, 'Complete-PestoDirectoryRefresh')
        self.assertIn('Update-PestoServiceChoices', complete)
        choices = function_body(directory, 'Update-PestoServiceChoices')
        items = function_body(directory, 'Update-PestoServiceItems')
        self.assertIn('Update-PestoServiceItems', choices)
        self.assertIn('Get-PestoSiteServiceCodes', items)
        self.assertIn('Update-PestoJoinServices', choices)
        # La saisie en cours est conservée.
        self.assertRegex(items, r'\$text=\[string\]\$CbService\.Text')

    def test_single_page_uses_shared_site_codes_and_requests_inventory(self):
        apply = function_body(read('Pesto-Core.ps1'), 'Apply-SiteSelection')
        self.assertIn('Get-PestoSiteServiceCodes', apply)
        self.assertNotIn('Extract-Equipe', apply)
        # 08/10 soir : plus d'inventaire complet au choix du site (il bloquait « Vérifier puis renommer ») ; recherche ciblée.
        self.assertNotIn('Refresh-Names', apply)
        self.assertIn('Request-PestoSiteLookup -OrganismeOU $script:OU_ORGANISME -Site $site', apply)

    def test_site_codes_function_reads_cache_only(self):
        body = function_body(read('Pesto-Directory.ps1'), 'Get-PestoSiteServiceCodes')
        self.assertTrue(body)
        self.assertIn('Get-PestoNameInventoryIndex', body)
        index = function_body(read('Pesto-Directory.ps1'), 'Get-PestoNameInventoryIndex')
        self.assertIn('Get-PestoNameInventoryIndexTable', index)
        self.assertIn('ConvertTo-PestoNameParts',
                      function_body(read('Pesto-Directory.ps1'), 'Get-PestoNameInventoryIndexTable'))
        self.assertIn('Get-SiteTag', body)
        self.assertIn('EndsWith', body)
        self.assertNotRegex(body, r'Get-AD|Invoke-Command|Refresh-Names')


class ServiceLabelTests(unittest.TestCase):
    def test_names_page_shows_service_not_team(self):
        shell = read('Pesto-Shell.xaml')
        visible = re.findall(r'(?:Text|Header|Content|ToolTip|AutomationProperties\.(?:Name|HelpText))="([^"]*)"', shell)
        self.assertEqual([], [v for v in visible if re.search(r'(?i)[ée]quipe', v)])
        core = read('Pesto-Core.ps1')
        for name in ('Populate-NmFilters', 'Update-NameGrid', 'Set-NmNextButtons', 'Export-NameView'):
            body = function_body(core, name)
            self.assertTrue(body, name)
            strings = re.findall(r"'[^']*'|\"[^\"]*\"", body)
            self.assertEqual([], [s for s in strings if re.search(r'(?i)équipe|\(toutes\)', s)], name)
        self.assertRegex(function_body(core, 'Export-NameView'), r"@\{Name='Service';Expression=\{\$_\.Equipe\}\}")


if __name__ == '__main__':
    unittest.main(verbosity=2)
