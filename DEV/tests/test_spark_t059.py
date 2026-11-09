"""Point 59 : index compact C# integre au parcours d'inventaire.

Controle statique : le parcours d'inventaire livre (Get-PestoNameInventoryIndex) route desormais
vers l'index compact C# (Pesto.Inventory.CompactIndex, precompile dans la DLL verifiee du produit) et
garde la table PowerShell comme repli ; la suite du moteur compare compact et table sur le meme
jeu de noms et exerce les deux consommateurs branches (Get-AvailableMachines, Get-PestoSiteServiceCodes) ;
le banc mesure les trois chemins livres sur 1 000 et 10 000 noms en refusant toute mesure ou ils
divergent. Ce module n'execute pas PowerShell : l'execution est faite par tests/Run-Engine120Tests.ps1
et tests/Measure-Engine120.ps1 eux-memes.
"""
import json
import sys
import unittest
from pathlib import Path

DEV = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DEV / "tests"))
from ps_lexical import functions  # noqa: E402

WAD = DEV / "wad"
DIRECTORY = WAD / "Pesto-Directory.ps1"
RUNTIME = WAD / "Pesto.Engine.Runtime.ps1"
ENGINE_SUITE = DEV / "tests" / "Run-Engine120Tests.ps1"
ENGINE_MEASURE = DEV / "tests" / "Measure-Engine120.ps1"
CATALOGUE = DEV / "docs" / "implementation" / "catalogue-120.json"
TYPE_NEEDLE = "namespace Pesto." + "Inventory"


def read_ps(path):
    raw = path.read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf"), "UTF-8 BOM attendu : " + str(path)
    return raw.decode("utf-8-sig")


def body(text, name):
    spans = functions(text)
    assert name in spans, "Fonction absente : " + name
    start, stop = spans[name]
    return text[start:stop]


class TestPestoCompactInventoryIndex(unittest.TestCase):
    def test_shipped_inventory_index_routes_through_the_compact_type(self):
        text = read_ps(DIRECTORY)
        main = body(text, "Get-PestoNameInventoryIndex")
        self.assertIn("Get-PestoNameInventoryIndexCompact $Computers", main,
                      "Le parcours d inventaire ne routerait plus vers l index compact")
        self.assertIn("Get-PestoNameInventoryIndexTable $Computers", main,
                      "Le repli PowerShell ne serait plus branche derriere le compact")
        guard = body(text, "Test-PestoCompactNameIndex")
        self.assertIn("Initialize-PestoRuntimeTypes", guard,
                      "Le type compact ne serait plus charge depuis le produit verifie")
        self.assertIn("-as [type]", guard,
                      "La compilation ne serait plus gardee par la presence du type")
        compact = body(text, "Get-PestoNameInventoryIndexCompact")
        self.assertIn("[Pesto.Inventory.CompactIndex]::Build(", compact,
                      "Le chemin compact n atteindrait plus le type livre")
        table = body(text, "Get-PestoNameInventoryIndexTable")
        self.assertIn("ConvertTo-PestoNameParts", table,
                      "Le repli ne passerait plus par l analyse de nom livree")

    def test_generated_runtime_carries_the_compact_definition(self):
        runtime = read_ps(RUNTIME)
        self.assertIn("Initialize-PestoRuntimeTypes", runtime,
                      "Le module Engine genere ne porterait plus la definition de l index compact")
        self.assertIn("Get-PestoNameInventoryIndexCompact $Computers", runtime,
                      "Le module Engine genere ne routerait plus l inventaire vers l index compact")

    def test_engine_suite_compares_compact_to_table_and_wires_consumers(self):
        suite = read_ps(ENGINE_SUITE)
        self.assertNotIn(TYPE_NEEDLE, suite,
                         "La suite redefinirait le type compact chez elle au lieu d atteindre le produit")
        for needle in ("Get-PestoNameInventoryIndexCompact", "Get-PestoNameInventoryIndexTable",
                       "Pesto.Inventory.CompactIndex",
                       "Index compact C# charge par le parcours d inventaire",
                       "Index compact et table PowerShell rendent le meme index",
                       "Get-AvailableMachines rendu par l index compact du parcours inventaire",
                       "Get-PestoSiteServiceCodes rendu par l index compact du parcours inventaire",
                       "Surface livree : le parcours inventaire atteint l index compact"):
            self.assertIn(needle, suite, needle + " : la comparaison compact-table a disparu de la suite")

    def test_engine_measure_compares_shipped_inventory_paths_on_volumes(self):
        measure = read_ps(ENGINE_MEASURE)
        self.assertNotIn("function Get-PestoNameInventoryIndex", measure,
                         "Le banc redefinirait le parcours d inventaire ici et repondrait d une copie")
        for needle in ("Inventory.Shipped.Path", "Inventory.Shipped.Compact", "Inventory.Shipped.Table",
                       "Index compact et table livres non equivalents",
                       "la table PowerShell aurait repris la main",
                       "InventoryIndex=$inventorySummary", "InventoryIndexSamples=$inventoryMeasures.ToArray()",
                       "PathMedianMs", "CompactMedianMs", "TableMedianMs"):
            self.assertIn(needle, measure, needle + " : la mesure comparee ne sort plus du rapport")
        self.assertIn("foreach($count in @(1000,10000))", measure,
                      "La mesure comparee ne couvre plus les deux volumes d inventaire")

    def test_catalogue_records_the_integrated_index(self):
        catalogue = json.loads(CATALOGUE.read_text(encoding="utf-8-sig"))
        item = next(i for i in catalogue["items"] if i["id"] == 59)
        self.assertEqual("implemented", item["state"],
                         "L index compact est branche et compare : le point ne peut rester en cours")
        self.assertIn("compact", item["implementation"])
        for evidence in item["evidence"]:
            self.assertTrue((DEV.parent / evidence).is_file(), evidence)
        states = [i["state"] for i in catalogue["items"]]
        declared = dict(catalogue["counts"]["states"])
        for state, total in declared.items():
            self.assertEqual(total, states.count(state), "Total " + state + " du catalogue perime")
        self.assertEqual(len(states), sum(declared.values()))


if __name__ == "__main__":
    unittest.main()
