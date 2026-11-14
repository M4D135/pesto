"""Portable checks for UI Automation exposure, found by driving Pesto on a Windows VM (text only)."""
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class AccessibilityTests(unittest.TestCase):
    def test_log_filter_and_error_copy_expose_help_text(self):
        root = ET.fromstring((ROOT / 'wad' / 'Pesto-Shell.xaml').read_text('utf-8-sig'))
        name_key = '{http://schemas.microsoft.com/winfx/2006/xaml}Name'
        expected = {'SuiteLogLevel', 'SuiteLogErrors'}
        controls = {node.get(name_key): node for node in root.iter() if node.get(name_key) in expected}
        self.assertEqual(set(controls), expected)
        for name, control in controls.items():
            with self.subTest(control=name):
                self.assertTrue(control.get('AutomationProperties.HelpText', '').strip())
                self.assertTrue(control.get('ToolTip', '').strip())

    def test_page_host_generates_tab_containers(self):
        # Sans conteneurs d'onglets (TabPanel IsItemsHost), UI Automation ne voit rien sous MainTabs :
        # formulaire et boutons des pages invisibles pour le Narrateur (vu sous Windows le 03/10).
        xaml = (ROOT / 'wad' / 'Pesto-Shell.xaml').read_text('utf-8-sig')
        style = re.search(r'<Style x:Key="PageHost".*?</Style>', xaml, re.S).group(0)
        self.assertIn('<TabPanel IsItemsHost="True" Visibility="Collapsed"/>', style)
        self.assertIn('PART_SelectedContentHost', style)

    def test_palette_items_announce_their_label(self):
        # Sans nom explicite, chaque commande était annoncée « @{Id=...; Label=...} ».
        text = (ROOT / 'wad' / 'Pesto-Workspace.ps1').read_text('utf-8-sig')
        listbox = re.search(r'<ListBox x:Name="PanelChoices".*?</ListBox>', text, re.S)
        self.assertIsNotNone(listbox)
        self.assertIn('<Setter Property="AutomationProperties.Name" Value="{Binding Label}"/>', listbox.group(0))

    def test_combobox_items_announce_their_label(self):
        # La liste des thèmes annonçait « @{Key=Light; Label=Clair} » (vu sous Windows le 03/10).
        xaml = (ROOT / 'wad' / 'Pesto-Shell.xaml').read_text('utf-8-sig')
        style = re.search(r'<Style TargetType="ComboBoxItem">.*?</Style>', xaml, re.S).group(0)
        self.assertIn('<Setter Property="AutomationProperties.Name" Value="{Binding Label}"/>', style)

    def test_hosted_sheet_focus_button_found_before_detaching(self):
        # P1 : la fiche État gardait le focus sur la fenêtre principale (bouton cherché après détachement du contenu).
        text = (ROOT / 'wad' / 'Pesto-Workspace.ps1').read_text('utf-8-sig')
        body = re.search(r'function Show-PestoHostedWindow \{.*?\n\}', text, re.S).group(0)
        self.assertLess(body.index("$Window.FindName('StateClose')"), body.index('$Window.Content=$null'))

    def test_tabular_reports_use_fixed_width_font(self):
        # P2 : colonnes alignées par des espaces dans les fiches État et Performance.
        inspection = (ROOT / 'wad' / 'Pesto-Inspection.ps1').read_text('utf-8-sig')
        self.assertRegex(inspection, r'<TextBox x:Name="StateReport"[^>]*FontFamily="Consolas"')
        workspace = (ROOT / 'wad' / 'Pesto-Workspace.ps1').read_text('utf-8-sig')
        self.assertIn("-Title 'Performance observée' -Body $report -Monospace", workspace)

    def test_demo_ou_sentinel_never_displayed_raw(self):
        # P3 : « (mode GUI) » reste une valeur interne ; l'affichage passe par Format-PestoOUForDisplay.
        core = (ROOT / 'wad' / 'Pesto-Core.ps1').read_text('utf-8-sig')
        self.assertNotRegex(core, r"Set-OULabel \$LblCurrentOU 'OU actuelle  :' \$script:OU_ACTUELLE")
        inspection = (ROOT / 'wad' / 'Pesto-Inspection.ps1').read_text('utf-8-sig')
        self.assertIn("function Format-PestoOUForDisplay", inspection)
        self.assertIn("@{n='Observe';e={Format-PestoOUForDisplay", inspection)


if __name__ == '__main__':
    unittest.main(verbosity=2)
