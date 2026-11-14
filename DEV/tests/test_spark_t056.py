"""Point 56 : pool borne de runspaces de lecture, isole par identite, et reellement emprunte.

Controle statique : le chemin livre de wad/Pesto-Async.ps1 emprunte bien le pool pour les lectures MTA
et jamais pour les mutations, transmet le credential, le domaine et le DC courants, rend le lease dans
le finally de fin d operation comme dans le chemin d echec de demarrage, et retire le pool au changement
d identite ; wad/Pesto-Core.ps1 le ferme a la fermeture de la fenetre. La suite du moteur relit ces
morceaux par analyse syntaxique et les rejoue dans de vrais runspaces sur un vrai pool, et le banc en
chronometre l emprunt, le nettoyage et le changement de compte. Ce module n'execute pas PowerShell :
l'execution est faite par tests/Run-ReadPool56Tests.ps1, tests/Run-Engine120Tests.ps1 et
tests/Measure-Engine120.ps1 eux-memes, verifiee le 23 octobre 2026 (45 cas sur 45 et 100 cas sur 100,
banc exit 0 avec les cles ReadPool et ReadPoolConcurrency, quatorze mutations livrees rejouees en
worktree — les neuf du chemin livre et cinq visees sur la concurrence : vague rendue sequentielle par un
tourniquet, comptabilite par runspace forcee sur une cle fixe, runspace rendu dans un pool retire
conserve, plafond de saturation neutralise, comparaison du credential neutralisee —, chacune faisant
echouer exactement sa garde, l'arbre de reference tenant 45 cas sur 45). Le plafond de concurrence,
seule valeur que le pool tienne vraiment, est mesure sous de vrais workers paralleles reveilles par une
barriere, dans la suite comme au
banc : un runspace prete ne sert jamais deux lecteurs a la fois et le pic reste sous le maximum.
"""
import json
import re
import sys
import unittest
from pathlib import Path

DEV = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DEV / "tests"))
from ps_lexical import functions  # noqa: E402

WAD = DEV / "wad"
ASYNC = WAD / "Pesto-Async.ps1"
CORE = WAD / "Pesto-Core.ps1"
ENGINE_SUITE = DEV / "tests" / "Run-Engine120Tests.ps1"
POOL_SUITE = DEV / "tests" / "Run-ReadPool56Tests.ps1"
ENGINE_MEASURE = DEV / "tests" / "Measure-Engine120.ps1"
CATALOGUE = DEV / "docs" / "implementation" / "catalogue-120.json"
SHEET = DEV / "docs" / "implementation" / "ENGINE_120.md"
COMPLETE = DEV / "docs" / "implementation" / "IMPLEMENTATION_COMPLETE_120.md"

POOL_FUNCTIONS = ("New-PestoReadRunspacePool", "Close-PestoReadRunspacePool",
                  "Get-PestoSessionReadPool", "Enter-PestoReadRunspace", "Exit-PestoReadRunspace")
# Doubles d'observation autorises dans la suite du moteur : elle peut simuler « quel pool me
# rend-on » et « rends-moi un runspace » pour ecouter ce que fait le chemin livre. La
# comptabilite (creation, pret, rendu, fermeture) reste toujours celle du module charge.
POOL_DOUBLES = ("Get-PestoSessionReadPool", "Enter-PestoReadRunspace")
POOL_ACCOUNTING = tuple(n for n in POOL_FUNCTIONS if n not in POOL_DOUBLES)
POOL_CASES = ("POOL la lecture livree emprunte le pool",
              "POOL la mutation garde son runspace propre",
              "POOL le lease est rendu a chaque issue",
              "POOL un demarrage en echec ne retient aucun runspace",
              "POOL sature la lecture est refusee sans runspace de repli")


def read_ps(path):
    raw = path.read_bytes()
    # Windows PowerShell 5.1 ne lit correctement un fichier que s'il porte un BOM
    # des qu'il contient un caractere non ASCII ; un fichier ASCII pur n'en a pas besoin.
    assert raw.startswith(b"\xef\xbb\xbf") or not any(b > 127 for b in raw), \
        "BOM UTF-8 requis des qu'il y a un caractere non ASCII : " + str(path)
    return raw.decode("utf-8-sig")


def top_level(text):
    """Definitions de fonctions au niveau racine, hors chaines et hors blocs imbriques."""
    return functions(text)


def definitions(text):
    """Noms de fonctions definis n'importe ou dans le fichier, blocs imbriques compris."""
    return set(re.findall(r"(?i)function\s+([A-Za-z][\w:-]*)", text))


def body(text, name):
    spans = top_level(text)
    assert name in spans, "Fonction absente : " + name
    start, stop = spans[name]
    return text[start:stop]


class TestPestoReadPoolWiring(unittest.TestCase):
    def test_shipped_read_path_borrows_the_pool_and_mutations_never_do(self):
        start = body(read_ps(ASYNC), "Start-PestoAsyncOperation")
        self.assertIn("if(-not $mutation -and $ApartmentState -eq 'MTA'){", start,
                      "Le chemin livre n'emprunterait plus le pool de lectures")
        self.assertIn("$pool=Get-PestoSessionReadPool -Credential $credential "
                      "-Domain ([string]$script:DOMAINE) -DC ([string]$script:DC)", start,
                      "Le credential, le domaine et le DC courants ne seraient plus transmis au pool")
        self.assertIn("$credential=if($ArgumentList.Count -and $null -ne $ArgumentList[0].Credential)"
                      "{$ArgumentList[0].Credential}else{$script:cred}", start,
                      "Le credential de la demande ne serait plus préféré au credential de session")
        self.assertIn("$readLease=Enter-PestoReadRunspace $pool;$rs=$readLease.Slot.Runspace", start,
                      "Le runspace de la lecture ne serait plus celui rendu par le pool")
        self.assertIn("ReadLease=$readLease", start,
                      "L'operation ne conserverait plus son lease : il ne pourrait plus etre rendu")
        mutation_start = start.find("if($mutation){")
        self.assertGreater(mutation_start, -1, "La branche mutation aurait disparu")
        branch = start[mutation_start:start.find("}else{", mutation_start)]
        self.assertIn("[void]$ps.AddScript($ScriptBlock.ToString(),$true)", branch,
                      "La mutation ne lancerait plus son worker propre")
        self.assertNotIn("ReadRunspace", branch,
                         "La mutation passerait par le pool de lectures")

    def test_shipped_releases_return_the_lease_on_every_outcome(self):
        start = body(read_ps(ASYNC), "Start-PestoAsyncOperation")
        self.assertIn("if($readLease){Exit-PestoReadRunspace $readLease -Discard}", start,
                      "Un demarrage en echec retiendrait un runspace du pool")
        tick = body(read_ps(ASYNC), "Invoke-PestoAsyncTimerTick")
        self.assertIn("finally{", tick, "La fin d'operation n'aurait plus de finally : le lease "
                                        "pourrait n'etre rendu que sur le chemin de succes")
        self.assertIn("if($op.ReadLease){Exit-PestoReadRunspace $op.ReadLease "
                      "-Discard:([bool]($caught -or $op.Cancelled -or $op.TimeoutReported))}", tick,
                      "Le runspace d'une lecture en erreur, annulee ou hors delai ne serait plus ecarte du pool")

    def test_shipped_pool_is_scoped_to_one_identity_and_refuses_dirty_runspaces(self):
        text = read_ps(ASYNC)
        session = body(text, "Get-PestoSessionReadPool")
        self.assertIn("Close-PestoReadRunspacePool $pool;$pool=$null", session,
                      "Le changement de credential, de domaine ou de DC ne retirerait plus le pool")
        self.assertIn("$pool.Domain -cne $Domain -or $pool.DC -cne $DC", session,
                      "Le domaine ou le DC ne serait plus compare : deux sessions partageraient leurs runspaces")
        self.assertIn("$pool=New-PestoReadRunspacePool -Credential $Credential -Domain $Domain -DC $DC;"
                      "$script:PestoReadPool=$pool", session,
                      "Le pool ne serait plus rattache a l'identite qui l'a cree")
        enter = body(text, "Enter-PestoReadRunspace")
        self.assertIn("if($Pool.Retired){throw", enter, "Un pool retire serait encore empruntable")
        self.assertIn("if($Pool.Count -ge $Pool.Maximum){throw", enter,
                      "Le maximum de lectures concurrentes ne serait plus borne")
        self.assertIn("[Threading.ApartmentState]::MTA", enter, "Les runspaces de lecture ne seraient plus en MTA")
        leave = body(text, "Exit-PestoReadRunspace")
        self.assertIn("$keep=(-not $Discard -and -not $pool.Retired)", leave,
                      "Le rendu ne distinguerait plus un runspace propre d'un runspace souille ou retire")
        self.assertIn("throw 'Fonction initiale modifiee.'", leave,
                      "Une fonction initiale alteree laisserait le runspace dans le pool")
        self.assertIn("throw 'Alias initial modifie.'", leave,
                      "Un alias initial altere laisserait le runspace dans le pool")
        self.assertIn("throw 'Etat initial incomplet.'", leave,
                      "Une fonction ou un alias supprime laisserait le runspace dans le pool")
        self.assertIn("$slot.Runspace.ResetRunspaceState()", leave,
                      "Les variables du travail precedent ne seraient plus effacees avant reutilisation")
        close = body(text, "Close-PestoReadRunspacePool")
        self.assertIn("$Pool.Retired=$true;$Pool.Credential=$null", close,
                      "La fermeture laisserait la credential et le pool empruntables")

    def test_shipped_window_close_retires_the_pool(self):
        core = read_ps(CORE)
        self.assertIn("$Win.Add_Closed({\n    Close-PestoReadRunspacePool $script:PestoReadPool",
                      core.replace("\r\n", "\n"),
                      "La fermeture de la fenetre ne retirerait plus le pool de lectures")


class TestPestoReadPoolGuards(unittest.TestCase):
    def test_engine_suite_replays_the_wiring_without_copying_the_pool(self):
        suite = read_ps(ENGINE_SUITE)
        racine = top_level(suite)
        for name in POOL_FUNCTIONS + ("Start-PestoAsyncOperation", "Invoke-PestoAsyncTimerTick"):
            self.assertNotIn(name, racine,
                             "La suite redefinirait " + name + " au niveau racine au lieu d'atteindre la source livree")
        self.assertEqual(set(POOL_DOUBLES), definitions(suite) & set(POOL_FUNCTIONS),
                         "La suite ne peut simuler que « quel pool me rend-on » et « rends-moi un runspace » : "
                         "la comptabilite du pool — creation, pret, rendu, fermeture — doit rester celle du module charge")
        for needle in ("$asyncPoolPrefix='if(-not $mutation -and $ApartmentState -eq ''MTA'')'",
                       "Exit-PestoReadRunspace $op.ReadLease",
                       "$asyncTry.Finally.Extent.Text",
                       "if($readLease){Exit-PestoReadRunspace",
                       ". ([scriptblock]::Create($Branch))",
                       ". ([scriptblock]::Create($Release))"):
            self.assertIn(needle, suite, needle + " : ce morceau du chemin livre n'est plus relu puis rejoue")
        for case in POOL_CASES:
            self.assertIn(case, suite, case + " : ce cas a disparu de la suite")
        self.assertIn("New-PestoReadRunspacePool -Maximum 2", suite,
                      "Le rendu du lease n'est plus rejoue sur un vrai pool")
        self.assertIn("ReferenceEquals($r.Calls[0].Credential,$credential)", suite,
                      "La transmission du credential au pool n'est plus verifiee")

    def test_readpool_suite_still_prices_the_primitives_it_does_not_redefine(self):
        suite = read_ps(POOL_SUITE)
        self.assertFalse(definitions(suite) & set(POOL_FUNCTIONS),
                         "La suite du pool redefinirait une primitive au lieu d'atteindre le module")
        for needle in ("Pool admitted a third reader", "State leaked across read jobs",
                       "Double release changed accounting", "Retirement closed a busy reader",
                       "Credential switch retained the old pool", "DC switch reused old state"):
            self.assertIn(needle, suite, needle + " : ce controle des primitives a disparu")

    def test_parallel_readers_really_contend_for_the_pool(self):
        """Le plafond de concurrence n'existe que sous lecteurs simultanes : la suite doit en lancer.

        Des workers reellement paralleles (BeginInvoke/EndInvoke), reveilles par une barriere, et les
        invariants qui en decoulent — un runspace prete ne sert jamais deux lecteurs a la fois, le
        nombre de runspaces en cours ne depasse jamais le maximum, un pool plein refuse tout le monde.
        """
        suite = read_ps(POOL_SUITE)
        for needle in ("$ps.BeginInvoke()", "$worker.PS.EndInvoke($worker.Handle)",
                       "Start-PestoReaderWave", "Wait-PestoReaderWave",
                       "[hashtable]::Synchronized(@{Ready=0;Go=$false"):
            self.assertIn(needle, suite, needle + " : la suite du pool ne lance plus de lecteurs paralleles")
        for needle in ("Check ($shared.PeakInFlight -eq 1)",
                       "Two concurrent readers shared one borrowed runspace",
                       "Check ($shared.PeakRunspaces -le $ceiling)",
                       "The pool admitted more concurrent runspaces than its maximum",
                       "Check ($shared.Refused -ge 1)",
                       "A borrower was admitted into a saturated pool",
                       "'Pool de lectures sature*'"):
            self.assertIn(needle, suite, needle + " : le plafond de concurrence n'est plus tenu par la suite")
        for needle in ("The new account reused the runspace borrowed by the account still reading",
                       "The account still reading leaked its state to the new account",
                       "The read in flight lost its own state when the account changed",
                       "A retired pool kept a returned runspace"):
            self.assertIn(needle, suite,
                          needle + " : l'isolation d'identite sous une lecture en cours n'est plus gardee")

    def test_measure_prices_reuse_cleanup_and_identity_switch(self):
        measure = read_ps(ENGINE_MEASURE)
        self.assertFalse(definitions(measure) & set(POOL_FUNCTIONS) |
                         definitions(measure) & {"Start-PestoAsyncOperation"},
                         "Le banc redefinirait une primitive du pool ou le chemin livre ici, "
                         "au lieu d'atteindre le module charge")
        for needle in ("ReadPool=$readPoolSummary", "ReadPoolSamples=$readPoolMeasures.ToArray()",
                       "ReadPoolComparison=$readPoolComparison",
                       "'ReadPool.FreshRunspace'", "'ReadPool.FirstLease'", "'ReadPool.ReusedRunspace.'",
                       "'ReadPool.IdentitySwitch'",
                       "PoolCheaperThanFresh=($readPoolMedianPooled -lt $readPoolMedianFresh)"):
            self.assertIn(needle, measure, needle + " : cette mesure ne sort plus du rapport")
        self.assertIn("if($reused.Runspaces -ne 1)", measure,
                      "Le banc accepterait huit runspaces ouverts pour huit lectures empruntees")
        self.assertIn("if($reused.Idle -ne 1 -or $reused.Count -ne 1)", measure,
                      "Le banc accepterait qu'un runspace emprunte ne revienne jamais au pool")
        self.assertIn("if($cost -gt ($first*1.5+100))", measure,
                      "Le banc accepterait que le cout par lecture s accumule a force de reutiliser le meme runspace")
        self.assertIn("if(-not $switch.Retired -or $switch.KeptCredential)", measure,
                      "Le banc accepterait que le changement de compte laisse l'ancien pool en service")
        self.assertIn("if($switch.SameRunspace)", measure,
                      "Le banc accepterait qu'un runspace survit au changement de compte")
        self.assertNotIn("coute plus cher que l ouverture", measure,
                         "Le banc \u00e9rigerait en contrat un gain de cout que la mesure locale ne montre pas")
        self.assertNotIn("isolation identités à qualifier avant activation", measure,
                         "Le banc declare encore le pool inactif alors qu'il est branche")

    def test_measure_prices_the_concurrency_ceiling_on_parallel_readers(self):
        """Le plafond de creneaux est la valeur tenue du pool : le banc doit le mesurer, pas le supposer.

        La vague est chronometree a l ouverture de la barriere, hors creation des workers et hors import
        du module, pour que l emprunt et le runspace neuf soient comparables ; les invariants de la vague
        (un seul lecteur par runspace prete, pic sous le maximum, refus rencontre, tous les leases rendus)
        sont des echecs du banc, pas des colonnes de plus.
        """
        measure = read_ps(ENGINE_MEASURE)
        for needle in ("'ReadPool.ConcurrencyWave'", "'ReadPool.ConcurrencyWaveFresh'",
                       "ReadPoolConcurrency=$readPoolConcurrencySummary",
                       "ReadPoolConcurrencySamples=$readPoolConcurrencyMeasures.ToArray()",
                       "$ps.BeginInvoke()", "$barrier=[Diagnostics.Stopwatch]::StartNew()",
                       "Milliseconds=[Math]::Round($wave.WaveMs,3)"):
            self.assertIn(needle, measure, needle + " : la vague de lecteurs paralleles ne sort plus du rapport")
        for needle in ("if($wave.PeakInFlight -ne 1)",
                       "if($wave.PeakRunspaces -gt $readPoolCeiling)",
                       "if($wave.PeakRunspaces -lt 2)",
                       "if($wave.Refused -lt 1)",
                       "if($wave.Idle -ne $wave.PoolCount)",
                       "if($fresh.Read -ne $readPoolWave)"):
            self.assertIn(needle, measure, needle + " : la vague concurrente pourrait passer sans tenir le plafond")
        self.assertIn("param($P)Enter-PestoReadRunspace $P", measure,
                      "Les lecteurs paralleles n'emprunteraient plus le pool du module charge")
        self.assertNotIn("PoolCheaperThanConcurrent", measure,
                         "Le banc \u00e9rigerait en contrat un gain sous concurrence que la mesure locale ne montre pas")


class TestPestoReadPoolRecords(unittest.TestCase):
    def test_catalogue_records_the_executed_evaluation(self):
        catalogue = json.loads(CATALOGUE.read_text(encoding="utf-8-sig"))
        item = next(i for i in catalogue["items"] if i["id"] == 56)
        self.assertEqual("implemented", item["state"],
                         "Le pool est branche, mesure et garde : le point ne peut rester en cours")
        for needle in ("45 cas sur 45", "100 cas sur 100", "ReadPool", "ReadPoolConcurrency",
                       "worktree", "neuf mutations", "cinq mutations supplementaires",
                       "vague de huit lecteurs"):
            self.assertIn(needle, item["validation"],
                          needle + " : la validation du catalogue ne rendrait plus l'execution")
        self.assertIn("CI Windows", item["remaining"])
        for evidence in item["evidence"]:
            self.assertTrue((DEV.parent / evidence).is_file(), evidence)
        states = [i["state"] for i in catalogue["items"]]
        declared = dict(catalogue["counts"]["states"])
        for state, total in declared.items():
            self.assertEqual(total, states.count(state), "Total " + state + " du catalogue perime")
        self.assertEqual(len(states), sum(declared.values()))

    def test_sheets_record_the_branched_pool_rather_than_the_old_study(self):
        sheet = SHEET.read_text(encoding="utf-8-sig")
        row = next(line for line in sheet.splitlines()
                   if line.startswith("| 56 |") and "emprunte" in line)
        for needle in ("45 cas", "100 cas", "ReadPool", "ReadPoolConcurrency", "worktree"):
            self.assertIn(needle, row,
                          needle + " : la fiche ENGINE_120 ne rendrait plus l'evaluation executee")
        complete = COMPLETE.read_text(encoding="utf-8-sig")
        line = next(line for line in complete.splitlines() if line.startswith("| 56 |"))
        self.assertNotIn("| En cours |", line,
                         "La fiche de clôture tient encore le pool de lectures pour non intégré")


if __name__ == "__main__":
    unittest.main()
