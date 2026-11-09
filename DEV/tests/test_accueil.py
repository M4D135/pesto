"""Accueil sobre (demande de David du 07/10/2026 : « l'accueil aussi nul, pas de slogan »)."""
from pathlib import Path
import re
import unittest

SHELL = Path(__file__).resolve().parents[1] / 'wad' / 'Pesto-Shell.xaml'


def home_tab():
    text = SHELL.read_text('utf-8-sig')
    match = re.search(r'<TabItem Header="Accueil".*?</TabItem>', text, re.S)
    return match.group(0) if match else ''


class HomePageTests(unittest.TestCase):
    def test_title_is_plain(self):
        self.assertIn('<TextBlock Text="Accueil" Style="{StaticResource PageTitle}"/>', home_tab())

    def test_no_slogan(self):
        home = home_tab()
        for slogan in ('Votre parc', 'au même endroit', 'puis agir', 'Une règle simple', 'Que souhaitez-vous faire'):
            self.assertNotIn(slogan, home)

    def test_actions_kept(self):
        home = home_tab()
        for name in ('HomeInterventions', 'HomePrepare', 'HomeQueue', 'HomeNames', 'HomeHistory', 'UxCacheCount',
                     'UxQueueTotal', 'UxReviewTotal', 'UxHomeContext'):
            self.assertIn('x:Name="' + name + '"', home)


class HistorySimulationNoticeTests(unittest.TestCase):
    def test_simulation_notice_only_for_simulated_lots(self):
        core = (Path(__file__).resolve().parents[1] / 'wad' / 'Pesto-Core.ps1').read_text('utf-8-sig')
        self.assertNotIn('lot(s). Les réussites en simulation ne sont pas des opérations réelles.', core)
        self.assertIn("$simulated=@($items|Where-Object{[string]$_.Mode -match '^SIMUL'}).Count", core)


if __name__ == '__main__':
    unittest.main(verbosity=2)
