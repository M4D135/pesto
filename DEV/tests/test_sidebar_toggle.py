"""Sidebar toggle layout shared with DOMENIA; XML/source checks, no WPF/VM."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1] / 'wad'
NAME = '{http://schemas.microsoft.com/winfx/2006/xaml}Name'
NS = '{http://schemas.microsoft.com/winfx/2006/xaml/presentation}'

class SidebarToggleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = ET.parse(ROOT / 'Pesto-Shell.xaml').getroot()
        cls.named = {n.get(NAME): n for n in cls.root.iter() if n.get(NAME)}
        cls.parents = {child: parent for parent in cls.root.iter() for child in parent}
        cls.ui = (ROOT / 'Pesto-SuiteUI.ps1').read_text('utf-8-sig')

    def test_toggle_is_last_item_in_sidebar_bottom_row(self):
        button = self.named['SuiteNavToggle']
        bottom = self.parents[button]
        self.assertEqual(bottom.get('Grid.Row'), '2')
        self.assertIs(list(bottom)[-1], button)
        self.assertIs(self.parents[bottom], self.named['SuiteSidebarGrid'])
        self.assertNotIn(button, self.named['SuiteBrand'].iter())
        self.assertNotIn(button, self.named['SuiteNavFooter'].iter())

    def test_small_icon_only_button_matches_domenia_dimensions(self):
        button = self.named['SuiteNavToggle']
        self.assertEqual(button.get('Width'), '32')
        self.assertEqual(button.get('Height'), '32')
        self.assertNotIn('Content', button.attrib)
        glyph = self.named['SuiteNavToggleGlyph']
        self.assertIs(self.parents[glyph], button)
        self.assertEqual(glyph.get('Width'), '18')
        self.assertEqual(glyph.get('Height'), '18')
        self.assertEqual(glyph.get('StrokeThickness'), '1.6')
        self.assertEqual(glyph.get('Data'), 'M2,2 L20,2 20,18 2,18 Z M8,2 L8,18 M16,6 L12,10 16,14')

    def test_direction_accessibility_and_action_are_kept(self):
        self.assertIn("$u.SuiteNavToggle.HorizontalAlignment=if($collapsed){'Center'}else{'Left'}", self.ui)
        self.assertIn('M12,6 L16,10 12,14', self.ui)
        self.assertIn('[Windows.Automation.AutomationProperties]::SetName($u.SuiteNavToggle,$u.SuiteNavToggle.ToolTip)', self.ui)
        self.assertIn("'SuiteNavToggle' {$script:NavigationCollapsed=-not $script:NavigationCollapsed;Update-PestoSuiteLayout;Update-PestoUxLayout;Save-Prefs}", self.ui)
        self.assertNotIn("'SuiteNavToggle')){$u[$n].Visibility", self.ui)

if __name__ == '__main__':
    unittest.main()

class NamesResponsiveLayoutTests(unittest.TestCase):
    def test_names_filters_and_actions_wrap_instead_of_overflowing(self):
        root = ET.parse(ROOT / 'Pesto-Shell.xaml').getroot()
        named = {n.get(NAME): n for n in root.iter() if n.get(NAME)}
        self.assertEqual(named['NmQuickActions'].tag, NS + 'WrapPanel')
        self.assertEqual(named['NmFilters'].tag, NS + 'WrapPanel')
        for control in ('NmCmbSite', 'NmCmbEquipe', 'NmCmbType', 'NmCmbStatut', 'NmTxtSearch'):
            self.assertIn(named[control], named['NmFilters'].iter())
            self.assertNotIn('Grid.Column', named[control].attrib)
