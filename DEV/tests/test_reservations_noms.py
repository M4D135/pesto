"""Plusieurs techniciens : registre partagé, réservation AD, numéro au hasard, reprise après redémarrage, Paramètres
(08/10/2026, demandes de David)."""
from pathlib import Path
import re
import unittest

WAD = Path(__file__).resolve().parents[1] / 'wad'


def text(name):
    return (WAD / name).read_text('utf-8-sig').replace('\r\n', '\n')


def body(file, name):
    t = text(file)
    m = re.search(r'(?m)^function ' + re.escape(name) + r'\b', t)
    if not m:
        return ''
    nxt = re.search(r'(?m)^(function |\$script:\w+ = \{|#####)', t[m.end():])
    return t[m.start():m.end() + nxt.start()] if nxt else t[m.start():]


class PolicyTests(unittest.TestCase):
    def test_new_policy_keys_typed_and_bounded(self):
        pol = body('Pesto-Policy.ps1', 'ConvertTo-PestoPolicy')
        for default in ('NameReservationMinutes=15', 'ReserveNamesInAD=$false',
                        'RandomNameEnabled=$true', 'LogRetentionDays=30',
                        'UnattendedJoinEnabled=$false', 'UnattendedOperationsEnabled=$false',
                        'IncidentMode=$false'):
            self.assertRegex(pol, re.escape(default) + r"(?=[;}])")
        # Reprise après redémarrage retirée le 08/10 (décision de David : « supprime totalement cette option »).
        self.assertNotIn('ResumeAfterRestart', pol)
        self.assertIn("@('NameReservationMinutes',5,240)", pol)
        self.assertIn("'AllowOfflineJoin','ReserveNamesInAD'", pol)


class SharedRegistryTests(unittest.TestCase):
    def test_worker_is_atomic_and_never_blocks_ui(self):
        t = text('Pesto-Names.ps1')
        w = t[t.index('$script:PestoSharedNameWorker = {'):t.index('function Get-PestoSharedNameSettings')]
        self.assertIn('[IO.FileMode]::CreateNew', w)
        self.assertIn('[IO.FileShare]::None', w)               # reprise d'une réservation expirée sous verrou exclusif
        self.assertIn("if($name -notmatch '^[A-Z0-9-]{1,15}$'){throw", w)
        release = w.split("'Release'{", 1)[1].split("\n        default{", 1)[0]
        opened = '$s=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Delete)'
        read = '$s.Read($buffer,$read,$buffer.Length-$read)'
        owned_delete = 'if($e -and [string]$e.Owner -eq $owner){[IO.File]::Delete($path);$released.Add($name)}'
        disposed = 'finally{if($s){$s.Dispose()}}'
        for fragment in (opened, read, owned_delete, disposed):
            self.assertIn(fragment, release)
        # Le même handle reste ouvert entre la lecture du propriétaire et la suppression.
        self.assertNotIn('[IO.File]::ReadAllText', release)
        self.assertEqual(release.count('[IO.File]::Delete($path)'), 1)
        self.assertLess(release.index(opened), release.index(read))
        self.assertLess(release.index(read), release.index(owned_delete))
        self.assertLess(release.index(owned_delete), release.index(disposed))
        self.assertIn('ne crée aucun partage', w)
        start = body('Pesto-Names.ps1', 'Start-PestoSharedNameOperation')
        self.assertIn('Start-PestoAsyncOperation', start)           # toujours en arrière-plan
        self.assertNotRegex(body('Pesto-Names.ps1', 'Invoke-PestoSharedNameTick'), r'\[IO\.File\]')

    def test_proposals_skip_names_reserved_elsewhere(self):
        self.assertIn('if(Test-PestoNameReservedByOther $name){continue}', body('Pesto-Join.ps1', 'Get-PestoJoinNameCandidates'))
        self.assertIn('Test-PestoNameReservedByOther ([string]$n)', body('Pesto-Core.ps1', 'Update-NameList'))

    def test_simulation_reserves_nothing(self):
        self.assertIn('if($script:SIM){return}', body('Pesto-Names.ps1', 'Invoke-PestoSharedNameTick'))

    def test_timer_started_and_stopped(self):
        core = text('Pesto-Core.ps1')
        self.assertIn('try{Start-PestoSharedNameTimer}', core)
        self.assertIn('Stop-PestoSharedNameTimer', core)


class RandomChoiceTests(unittest.TestCase):
    def test_random_choice_among_all_free(self):
        idx = body('Pesto-Names.ps1', 'Get-PestoInitialNameIndex')
        self.assertIn('if($Count -eq 1 -or -not (Get-PestoSharedNameSettings).Random){return 0}', idx)
        self.assertIn('[M4D.Admin.Common.Core.RandomSelection]::NextIndex($Count)', idx)
        self.assertNotIn('SharedNameRandom', idx)
        self.assertIn('Get-PestoInitialNameIndex $ui.Name.Items.Count', body('Pesto-Join.ps1', 'Update-PestoJoinNames'))
        self.assertIn('Get-PestoInitialNameIndex $CbName.Items.Count', body('Pesto-Core.ps1', 'Update-NameList'))


class ADReservationTests(unittest.TestCase):
    def test_reservation_before_confirmation_and_reuse_by_guid(self):
        check = body('Pesto-Join.ps1', 'Complete-PestoJoinCheck')
        self.assertRegex(check, r"(?s)\(Get-PestoSharedNameSettings\)\.ReserveInAD\)\{\s*Start-PestoJoinADReservation -Plan \$p;return")
        self.assertLess(check.index('Start-PestoJoinADReservation'), check.index('Confirm-YesNo'))
        pre = body('Pesto-Join.ps1', 'Get-PestoJoinPreflight')
        self.assertIn("([Guid]$existing[0].ObjectGUID).ToString('D') -ieq [string]$plan.ReservedGuid", pre)
        self.assertIn('($joinPolicy.AllowPrecreatedJoin -or ([bool]$plan.ReservedByPesto -and $joinPolicy.ReserveNamesInAD))', body('Pesto-Join.ps1', 'Invoke-PestoJoinExecuteLocked'))

    def test_release_only_unused_own_reservation(self):
        t = text('Pesto-Join.ps1')
        w = t[t.index('$script:PestoJoinADReserveWorker = {'):t.index('function Start-PestoJoinADReservation')]
        self.assertIn('[string]$o.Description -cne $marker', w)
        self.assertIn("$marker='Réservé par Pesto ['+[string]$Request.OperationId+']'", w)
        self.assertIn("$_.Exception.GetType().Name -eq 'ADIdentityNotFoundException'", w)
        self.assertIn('[string]$o.DNSHostName -or @($o.ServicePrincipalName).Count', w)  # jamais un compte qui a servi
        self.assertIn('Remove-ADComputer -Identity $id', w)
        done = body('Pesto-Join.ps1', 'Complete-PestoJoinExecution')
        self.assertIn("elseif($code -notin @(97,98)){Stop-PestoJoinADReservation", done)   # incertain : gardé


class CollisionAuditFixesTests(unittest.TestCase):
    """Défauts trouvés par l'audit du banc de collisions (08/10 soir)."""

    def test_registry_reserves_during_processing(self):
        # Clic avant la seconde de stabilité, ou nom changé par Pesto pendant le traitement : réservé au tick suivant.
        tick = body('Pesto-Names.ps1', 'Invoke-PestoSharedNameTick')
        self.assertNotIn("if($busy){continue}", tick)
        busy = tick[tick.index('if($busy){'):tick.index('if(-not $want){')]
        self.assertIn('-not (Test-PestoNameReservedByOther $want)', busy)   # pas une demande par seconde si détenu
        self.assertIn('Start-PestoSharedNameOperation -Mode Reserve -Name $want -Context $ctx', busy)
        self.assertNotIn("Mode Release", busy)                              # rien libéré pendant le traitement
        self.assertIn('if(Test-PestoNameReservedByOther $want){Invoke-PestoSharedNameRefreshLists;continue}', tick)
        done = body('Pesto-Names.ps1', 'Complete-PestoSharedNameOperation')
        self.assertIn('pendant votre opération', done)
        self.assertIn('autre nom proposé', done)

    def test_held_by_other_switches_before_confirmation(self):
        # Départs simultanés : « détenu ailleurs » reçu pendant le contrôle -> nom suivant AVANT réservation AD et confirmation.
        check = body('Pesto-Join.ps1', 'Complete-PestoJoinCheck')
        i = check.index("est réservé par un autre poste dans le registre partagé.")
        self.assertLess(i, check.index('Start-PestoJoinADReservation -Plan $p'))
        self.assertLess(i, check.index('Confirm-YesNo'))
        self.assertIn("-not [bool]$p.ReservedByPesto -and (Test-PestoNameReservedByOther ([string]$p.NewName))", check)
        pre = body('Pesto-Direct.ps1', 'Complete-PestoDirectPreflight')
        j = pre.index("est réservé par un autre poste dans le registre partagé.")
        self.assertLess(j, pre.index('Confirm-YesNo'))

    def test_registry_held_is_not_a_session_ban(self):
        # Revue du 08/10 : un nom seulement réservé au registre n'est pas écarté pour toute la session ni dit « pris dans l'AD ».
        for f, fn, prefix in (('Pesto-Join.ps1', 'Select-PestoJoinNextName', 'JONCTION'), ('Pesto-Direct.ps1', 'Select-PestoDirectNextName', 'RENOMMAGE')):
            b = body(f, fn)
            self.assertIn('[switch]$RegistryHeld', b)
            self.assertIn('if(-not $RegistryHeld){[void]$script:PestoTakenNames.Add($TakenName)}', b)
            self.assertIn("réservé par un autre poste (registre partagé)", b)
        self.assertIn("-RegistryHeld)", body('Pesto-Join.ps1', 'Complete-PestoJoinCheck'))
        self.assertIn("-RegistryHeld)", body('Pesto-Direct.ps1', 'Complete-PestoDirectPreflight'))

    def test_close_refused_while_ad_reservation_in_flight(self):
        core = text('Pesto-Core.ps1')
        i = core.index('$Win.Add_Closing({')
        closing = core[i:i + 1500]
        self.assertIn("$_ -eq 'JoinADReserve' -or $_ -like 'JoinADRelease*'", closing)
        self.assertIn('$e.Cancel = $true', closing)

    def test_share_connection_closed_at_exit(self):
        t = text('Pesto-Names.ps1')
        w = t[t.index('$script:PestoSharedNameWorker = {'):t.index('function Get-PestoSharedNameSettings')]
        self.assertIn('-not [IO.File]::Exists($marker) -and -not [IO.Directory]::Exists($root)', w)   # registre lisible : aucune connexion
        self.assertIn('Connected=$connected', w)
        self.assertIn('Close-PestoShareConnections', body('Pesto-Names.ps1', 'Stop-PestoSharedNameTimer'))
        close = body('Pesto-Names.ps1', 'Close-PestoShareConnections')
        self.assertIn("use ([string]$share) /delete /y", close)
        self.assertIn('-not $script:INDOMAIN -and $script:cred', close)
        self.assertIn('Add-PestoShareConnection', body('Pesto-Names.ps1', 'Complete-PestoSharedNameOperation'))

    def test_close_finishes_shared_release_and_preserves_ad_receipt(self):
        stop = body('Pesto-Names.ps1', 'Stop-PestoSharedNameTimer')
        self.assertIn('$script:SharedNamePending.Values', stop)
        self.assertIn('WaitOne(3000)', stop)
        self.assertNotIn('Start-PestoSharedNameOperation', stop)   # plus d'opération asynchrone annulée aussitôt
        closed = text('Pesto-Core.ps1')
        i = closed.index('$Win.Add_Closed({')
        self.assertIn('try{Stop-PestoJoinADReservationAtClose}catch{}', closed[i:i + 200])
        ad = body('Pesto-Join.ps1', 'Stop-PestoJoinADReservationAtClose')
        self.assertIn('Réservation AD conservée', ad)
        self.assertIn('Get-PestoJoinADReservationPath', ad)
        for mutation in ('BeginInvoke', 'BeginStop', 'Remove-ADComputer', "Mode='Release'", '$script:JoinADReservation=$null'):
            self.assertNotIn(mutation, ad)
        self.assertIn('Restore-PestoJoinADReservation', body('Pesto-Join.ps1', 'Initialize-PestoJoinUI'))

    def test_random_seed_not_clock(self):
        idx = body('Pesto-Names.ps1', 'Get-PestoInitialNameIndex')
        self.assertIn('[M4D.Admin.Common.Core.RandomSelection]::NextIndex($Count)', idx)
        self.assertNotIn('[Random]::new()', idx)

    def test_next_name_message_matches_setting(self):
        for f, fn in (('Pesto-Join.ps1', 'Select-PestoJoinNextName'), ('Pesto-Direct.ps1', 'Select-PestoDirectNextName')):
            b = body(f, fn)
            self.assertIn('(Get-PestoSharedNameSettings).Random', b)
            self.assertIn('tiré au hasard', b)

    def test_share_connected_with_ad_account_out_of_domain(self):
        conn = body('Pesto-Policy.ps1', 'Connect-PestoCoordinationShare')
        self.assertIn('New-PSDrive', conn)
        self.assertIn('-Credential $Credential', conn)
        self.assertNotIn('-Persist', conn)                          # aucune lettre de lecteur, rien d'enregistré
        root = body('Pesto-Policy.ps1', 'Get-PestoCoordinationRoot')
        self.assertIn('Connect-PestoCoordinationShare -Root $root -Credential $script:cred', root)
        self.assertIn("'Connect-PestoCoordinationShare'", text('Pesto-Core.ps1'))   # disponible dans les workers
        t = text('Pesto-Names.ps1')
        w = t[t.index('$script:PestoSharedNameWorker = {'):t.index('function Get-PestoSharedNameSettings')]
        self.assertIn('-Credential $Request.Credential', w)
        self.assertIn('Credential=$script:cred}', body('Pesto-Names.ps1', 'Start-PestoSharedNameOperation'))
        entry = w[w.index('function New-Entry'):w.index('$result=')]
        self.assertNotIn('Credential', entry)                      # jamais écrit dans le registre


class ResumeRemovedTests(unittest.TestCase):
    def test_resume_after_restart_fully_removed(self):
        # 08/10 : « supprime totalement cette option c pas faisable » (relance au prochain logon jugée inutilisable).
        for f in ('Pesto-Interventions.ps1', 'Pesto-Join.ps1', 'Pesto-Direct.ps1', 'Pesto-Core.ps1', 'Pesto-Configuration.ps1', 'Pesto-Shell.xaml', 'Pesto-Policy.ps1'):
            src = text(f)
            for token in ('ResumeAfterRestart', 'Register-PestoResumeAfterRestart', 'Invoke-PestoResumeAtStartup', 'SetCmbResume', 'PestoVerification'):
                self.assertNotIn(token, src, f + ' : ' + token)


class SettingsTests(unittest.TestCase):
    def test_settings_controls_exist_and_are_wired(self):
        shell = text('Pesto-Shell.xaml')
        names = ['SetTxtCoordRoot', 'SetBtnCoordPrepare', 'SetBtnCoordTest', 'SetTxtReserveMinutes', 'SetChkCoordRequired', 'SetChkRandomName',
                 'SetChkReserveAD', 'SetChkPrecreated', 'SetTxtMaxBatch', 'SetTxtMaxReaders', 'SetTxtReadAttempts', 'SetChkClearProtection',
                 'SetChkPasswordFallback', 'SetTxtExcludedNames', 'SetTxtExcludedOUs', 'SetTxtExcludedGroups']
        core = text('Pesto-Core.ps1')
        for n in names:
            self.assertIn(f'x:Name="{n}"', shell)
            self.assertIn(f"'{n}'", core)
        build = body('Pesto-Configuration.ps1', 'Build-CfgFromUI')
        self.assertIn("Set-PestoMapValue $cfg 'POLICY' (Build-PestoPolicyFromUI)", build)

    def test_policy_defaults_do_not_force_restart(self):
        sig = body('Pesto-Configuration.ps1', 'Get-PestoConfigurationSignature')
        self.assertIn("$value['POLICY']=$policy", sig)
        self.assertIn("ClearProtectionOnMove", sig)


if __name__ == '__main__':
    unittest.main(verbosity=2)
