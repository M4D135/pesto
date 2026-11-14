"""Services et noms du site en quelques secondes (08/10/2026, David : « ça met 30 s mini pour afficher un service alors
qu'avant non. et le bouton vérification est grisé »)."""
from pathlib import Path
import re
import unittest

WAD = Path(__file__).resolve().parents[1] / 'wad'


def body(file, name):
    text = (WAD / file).read_text('utf-8-sig').replace('\r\n', '\n')
    m = re.search(r'(?m)^function ' + re.escape(name) + r'\b', text)
    if not m:
        return ''
    nxt = re.search(r'(?m)^(function |\$script:)', text[m.end():])
    return text[m.start():m.end() + nxt.start()] if nxt else text[m.start():]


class FastSiteLookupTests(unittest.TestCase):
    def test_targeted_queries_only(self):
        text = (WAD / 'Pesto-Directory.ps1').read_text('utf-8-sig').replace('\r\n', '\n')
        worker = text[text.index('$script:PestoSiteLookupWorker = {'):]
        # Facettes explicites selon la convention et OU du site : jamais de -Filter * sur l'OU racine.
        self.assertIn('New-PestoNameLdapPattern -Prefix $prefix -Site $tag', worker)
        self.assertIn("SearchBase=$siteOU;SearchScope='Subtree'", worker)
        self.assertNotIn('-Filter *', worker)
        self.assertIn("if($prefix -notmatch (Get-PestoFacetPattern Prefix) -or ($tag -and $tag -cnotmatch (Get-PestoFacetPattern Site)))", worker)
        self.assertIn('Import-PestoADModule', worker)

    def test_lookup_is_background_and_read_only(self):
        req = body('Pesto-Directory.ps1', 'Request-PestoSiteLookup')
        self.assertIn("Start-PestoAsyncOperation -Name 'SiteLookup'", req)
        self.assertIn('-Replace -TimeoutSec 60', req)
        self.assertNotRegex(req, r'Set-AD|New-AD|Remove-AD|Rename-|Add-Computer')
        done = body('Pesto-Directory.ps1', 'Complete-PestoSiteLookup')
        self.assertIn('$script:SiteLookupCache[$Key]=if($Result.Complete){@($Result.Items)}', done)
        self.assertIn('Select-PestoUniqueComputers (@($script:SiteLookupCache[$Key])+@($Result.Items))', done)
        self.assertIn('Update-PestoServiceChoices', done)
        self.assertIn('if($script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy){$script:ServiceChoicesPending=$true;return}', done)

    def test_lookup_requested_when_site_chosen(self):
        self.assertIn('Update-PestoJoinServices;Request-PestoJoinSiteLookup}', body('Pesto-Join.ps1', 'Invoke-PestoJoinInputChanged'))
        self.assertIn('Update-PestoJoinUI;Request-PestoJoinSiteLookup}', body('Pesto-Core.ps1', 'Set-PestoUxPage'))
        self.assertIn('Request-PestoSiteLookup -OrganismeOU $script:OU_ORGANISME -Site $site', body('Pesto-Core.ps1', 'Apply-SiteSelection'))

    def test_lists_use_lookup_results(self):
        self.assertIn('Update-PestoServiceItems', body('Pesto-Directory.ps1', 'Update-PestoServiceChoices'))
        for file, fn in (('Pesto-Join.ps1', 'Update-PestoJoinServices'), ('Pesto-Directory.ps1', 'Update-PestoServiceItems'),
                         ('Pesto-Core.ps1', 'Apply-SiteSelection')):
            self.assertIn('-Computers (Get-PestoKnownComputers)', body(file, fn), fn)
        self.assertIn('Get-PestoKnownComputers', body('Pesto-Core.ps1', 'Get-ComputersForNameGeneration'))
        self.assertIn('$script:SiteLookupCache=@{}', body('Pesto-Names.ps1', 'Invalidate-PestoNameInventory'))

    def test_service_list_completed_when_opened(self):
        # 19/10/2026, David : en « Un poste », seule l'entrée du poste chargé apparaissait jusqu'à un aller-retour de site.
        core = (WAD / 'Pesto-Core.ps1').read_text('utf-8-sig')
        self.assertIn('$CbService.Add_DropDownOpened({ Invoke-PestoServiceDropDownOpened })', core)
        opened = body('Pesto-Directory.ps1', 'Invoke-PestoServiceDropDownOpened')
        self.assertIn('if($script:Suspend -or $script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy){return}', opened)
        self.assertIn('if(-not (Update-PestoServiceItems)){return}', opened)
        self.assertIn('if($pending){Update-NameList}', opened)
        self.assertIn('Request-PestoFormSiteLookup', opened)
        form = body('Pesto-Directory.ps1', 'Request-PestoFormSiteLookup')
        self.assertIn('Request-PestoSiteLookup -OrganismeOU $script:OU_ORGANISME -Site $site', form)
        self.assertNotIn('-Force', form)
        # Lecture relancée une fois la fenêtre prête, puis une fois après un échec.
        self.assertIn('[void]$Win.Dispatcher.BeginInvoke([Action]{Request-PestoFormSiteLookup},[Windows.Threading.DispatcherPriority]::ApplicationIdle)', core)
        self.assertIn('Start-PestoSiteLookupRetry', body('Pesto-Directory.ps1', 'Complete-PestoSiteLookup'))

    def test_grey_check_button_says_what_is_missing(self):
        ctx = body('Pesto-UXFlow.ps1', 'Get-PestoPrimaryContext')
        for text in ('Choisissez le site.', 'Choisissez ou saisissez le service (3 caractères).', 'Aucun nom proposé pour ce service.'):
            self.assertIn(text, ctx)
        self.assertIn('-Missing $missing', ctx)
        self.assertIn("$Missing+' « Compléter le formulaire » place le curseur sur ce choix.'", body('Pesto-UXFlow.ps1', 'Get-PestoPrimaryStep'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
