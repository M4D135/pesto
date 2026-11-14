"""Point 72 : admission et reprises de lectures transitoires bornees.

Controle statique : l'admission livree de wad/Pesto-Async.ps1 plafonne les lectures concurrentes,
derive le drapeau mutation depuis la liste livree, repartit les creneaux selon POLICY.MaxReaders,
borne l'attente a 30 secondes et ne relache que le creneau qu'elle a pris ; la reprise livree de
wad/Pesto-Contracts.ps1 borne tentatives, delai et sommeil, ne publie qu'une lecture complete,
refuse l'acces refuse sans reprise et preserve l'annulation. La suite du moteur relit ces morceaux
par analyse syntaxique et les rejoue dans de vrais runspaces sur de vrais SemaphoreSlim ; le banc
en chronometre la surcharge, le plafond, le backoff et le refus borne. Ce module n'execute pas
PowerShell : l'execution est faite par tests/Run-Engine120Tests.ps1 et tests/Measure-Engine120.ps1
eux-memes, verifiee le 23 octobre 2026 (95 cas sur 95, banc exit 0 et 17 echantillons ReadAdmission,
cinq mutations livrees rejouees en worktree, chacune faisant echouer exactement son cas).
"""
import json
import sys
import unittest
from pathlib import Path

DEV = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DEV / "tests"))
from ps_lexical import functions  # noqa: E402

WAD = DEV / "wad"
ASYNC = WAD / "Pesto-Async.ps1"
CONTRACTS = WAD / "Pesto-Contracts.ps1"
ENGINE_SUITE = DEV / "tests" / "Run-Engine120Tests.ps1"
ENGINE_MEASURE = DEV / "tests" / "Measure-Engine120.ps1"
CATALOGUE = DEV / "docs" / "implementation" / "catalogue-120.json"
SHEET = DEV / "docs" / "implementation" / "ENGINE_120.md"


def read_ps(path):
    raw = path.read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf"), "UTF-8 BOM attendu : " + str(path)
    return raw.decode("utf-8-sig")


def body(text, name):
    spans = functions(text)
    assert name in spans, "Fonction absente : " + name
    start, stop = spans[name]
    return text[start:stop]


class TestPestoReadAdmission(unittest.TestCase):
    def test_shipped_admission_caps_reads_and_derives_mutation(self):
        admission = body(read_ps(ASYNC), "Start-PestoAsyncOperation")
        self.assertIn("$mutation=(Test-PestoAsyncMutationName $Name)", admission,
                      "Le drapeau mutation ne serait plus derive de la liste livree")
        self.assertIn("if(-not $mutation){", admission,
                      "L admission ne serait plus reservee aux lectures")
        self.assertIn("if($reads.Count -ge 12)", admission,
                      "Le plafond de douze lectures actives ne serait plus livre")
        self.assertIn("'Trop de lectures encore actives. Attendez leur retour ; "
                      "aucune nouvelle lecture lancée.'", admission,
                      "Le refus d admission ne serait plus le message livre")
        self.assertIn("$background=[Math]::Max(1,$limit-1)", admission,
                      "Les creneaux de fond ne suivraient plus MaxReaders-1 (au moins un)")
        self.assertIn("[Threading.SemaphoreSlim]::new($background,$background)", admission,
                      "Le creneau de fond ne serait plus un vrai SemaphoreSlim")
        self.assertIn("$script:PestoInteractiveGate=if($limit -eq 1){$script:PestoBackgroundGate}"
                      "else{[Threading.SemaphoreSlim]::new(1,1)}", admission,
                      "Le partage du creneau interactif a MaxReaders=1 ne serait plus livre")

    def test_shipped_wrapper_bounds_wait_and_releases_only_taken_slots(self):
        admission = body(read_ps(ASYNC), "Start-PestoAsyncOperation")
        self.assertIn("$gate=if($Name -in @('PCProbe','DirectPreflight','JoinCheck','JoinStatus'",
                      admission, "Le choix du creneau interactif ne serait plus la liste livree")
        self.assertIn("$taken=$Gate.Wait(200)", admission,
                      "L attente du creneau ne serait plus sondee par pas de 200 ms")
        self.assertIn("if(-not $taken -and $clock.Elapsed.TotalSeconds -gt 30)"
                      "{throw 'Créneau de lecture indisponible après 30 secondes.'}", admission,
                      "L attente ne serait plus coupee a 30 secondes")
        self.assertIn("if($taken){[void]$Gate.Release()}", admission,
                      "Le wrapper relacherait un creneau qu il n a pas obtenu")
        self.assertIn("$Timing.Phase='Ended'", admission,
                      "Le wrapper ne cloturerait plus sa phase, meme refuse")
        start = admission.find("if($mutation){")
        self.assertGreater(start, -1, "La branche mutation aurait disparu")
        branch = admission[start:admission.find("}else{", start)]
        self.assertIn("[void]$ps.AddScript($ScriptBlock.ToString(),$true)", branch,
                      "La mutation ne lancerait plus son worker propre")
        self.assertNotIn("$wrapper", branch,
                         "La mutation passerait par le creneau de lecture")

    def test_shipped_retry_bounds_attempts_delays_and_publication(self):
        failure = body(read_ps(CONTRACTS), "Get-PestoReadFailure")
        self.assertIn("@(5,1326,1385)){'Access'}", failure,
                      "Les codes d acces refuse ne seraient plus classes Access")
        self.assertIn("@(53,64,121,1460,1722,1726)){'TransientNetwork'}", failure,
                      "Les codes transitoires ne seraient plus seuls relancables")
        self.assertIn("Retryable=($category -eq 'TransientNetwork')", failure,
                      "L acces refuse redeviendrait relancable")
        retry = body(read_ps(CONTRACTS), "Invoke-PestoReadRetry")
        self.assertIn("[ValidateRange(1,3)][int]$Attempts=2", retry,
                      "Les tentatives ne seraient plus bornees a trois")
        self.assertIn("[ValidateRange(0,2000)][int]$DelayMs=200", retry,
                      "Le delai de reprise ne serait plus borne a deux secondes")
        self.assertIn("[Math]::Min(4000,$DelayMs*[Math]::Pow(2,$i-1))", retry,
                      "Le sommeil par reprise ne serait plus plafonne a 4000 ms")
        self.assertIn("$result=@(& $Read)", retry,
                      "La reprise publierait de nouveau une sortie partielle")
        self.assertIn("'Lecture remplacée.'", retry, "L annulation avant tentative ne serait plus conservee")
        self.assertIn("'Reprise de lecture annulée.'", retry, "L annulation pendant le sommeil ne serait plus conservee")
        self.assertIn("if($i -ge $Attempts -or -not $failure.Retryable){throw}", retry,
                      "Une erreur non relancable serait de nouveau reprise")

    def test_engine_suite_replays_shipped_pieces_without_copying_them(self):
        suite = read_ps(ENGINE_SUITE)
        for name in ("Start-PestoAsyncOperation", "Invoke-PestoReadRetry",
                     "Get-PestoReadFailure", "Get-PestoNativeFailureCode"):
            self.assertNotIn("function " + name, suite,
                             "La suite redefinirait " + name + " chez elle au lieu d atteindre la source livree")
        self.assertIn("FunctionDefinitionAst", suite,
                      "La suite ne relirait plus les morceaux d admission dans la source livree")
        self.assertIn("Get-PestoShippedFunctionText", suite,
                      "Les fonctions de reprise ne seraient plus relues des sources livrees")
        for case in ("ADMISSION douze lectures puis refus",
                     "ADMISSION mutation jamais refusee",
                     "ADMISSION repartition des creneaux selon MaxReaders",
                     "ADMISSION classification interactive et fond",
                     "SURCHARGE concurrence jamais au-dessus des creneaux",
                     "SURCHARGE la reprise garde son creneau",
                     "REPRISE backoff exponentiel et tentatives bornees",
                     "MUTATION jamais repetee automatiquement"):
            self.assertIn(case, suite, case + " : ce cas neufs a disparu de la suite")
        self.assertIn("Require ($site.Function -cmatch '^(Get|Find|Read|Test)-')", suite,
                      "Le scan des sites de reprise ne refuserait plus les fonctions d ecriture")
        self.assertIn("Require ($site.Statement.Contains('Get-ADComputer'))", suite,
                      "Le scan ne repondrait plus que la reprise entoure une lecture AD")

    def test_engine_measure_prices_admission_backoff_and_bounded_wait(self):
        measure = read_ps(ENGINE_MEASURE)
        for name in ("Start-PestoAsyncOperation", "Invoke-PestoReadRetry", "Get-PestoReadFailure"):
            self.assertNotIn("function " + name, measure,
                             "Le banc redefinirait " + name + " ici au lieu de rejouer la source livree")
        self.assertIn("function Get-PestoMeasureShippedFunctionText", measure,
                      "Le banc ne relirait plus les fonctions de reprise dans les sources livrees")
        for needle in ("ReadAdmission=$readAdmissionSummary",
                       "ReadAdmissionSamples=$readAdmissionMeasures.ToArray()",
                       "'ReadGate.Overload.'", "'ReadAdmission.Cap'",
                       "'ReadRetry.'", "'ReadGate.BoundedWait'"):
            self.assertIn(needle, measure, needle + " : cette mesure ne sort plus du rapport")
        self.assertIn("if($state.Peak -gt $slots)", measure,
                      "La surcharge ne verifierait plus que la concurrence tient dans les creneaux")
        self.assertIn("if($cost -lt $retry.Bound)", measure,
                      "Le banc accepterait un backoff moins cher que ses bornes")
        self.assertIn("if($cost -gt ($retry.Bound+1500))", measure,
                      "Le banc accepterait un backoff au-dela de la borne livree")
        self.assertIn("$cost -lt 30000 -or $cost -gt 31500", measure,
                      "Le refus borne a 30 secondes ne serait plus chronometre")
        self.assertIn("'*Cr*neau de lecture indisponible apr*30 secondes*'", measure,
                      "Le message de refus attendu ne serait plus celui du wrapper livre")

    def test_catalogue_and_sheet_record_the_executed_evaluation(self):
        catalogue = json.loads(CATALOGUE.read_text(encoding="utf-8-sig"))
        item = next(i for i in catalogue["items"] if i["id"] == 72)
        self.assertEqual("implemented", item["state"],
                         "Admission et reprises sont mesurees et gardees : le point ne peut rester en cours")
        self.assertIn("Évalué le 23 octobre 2026", item["implementation"])
        self.assertIn("MaxReaders", item["implementation"])
        for needle in ("95 cas sur 95", "runspaces", "ReadAdmission", "worktree"):
            self.assertIn(needle, item["validation"],
                          needle + " : la validation du catalogue ne rendrait plus l execution")
        self.assertIn("CI Windows", item["remaining"])
        for evidence in item["evidence"]:
            self.assertTrue((DEV.parent / evidence).is_file(), evidence)
        states = [i["state"] for i in catalogue["items"]]
        declared = dict(catalogue["counts"]["states"])
        for state, total in declared.items():
            self.assertEqual(total, states.count(state), "Total " + state + " du catalogue perime")
        self.assertEqual(len(states), sum(declared.values()))
        sheet = SHEET.read_text(encoding="utf-8-sig")
        row = next(line for line in sheet.splitlines()
                   if line.startswith("| 72 |") and "Relecture des limites" in line)
        for needle in ("95 cas", "worktree", "30 077", "ReadAdmission"):
            self.assertIn(needle, row,
                          needle + " : la fiche ENGINE_120 ne rendrait plus l evaluation executee")


if __name__ == "__main__":
    unittest.main()
