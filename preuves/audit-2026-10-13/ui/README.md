# Pesto 1.0 — audit de l’interface Windows

18 suites sans échec ; 2 contrôles de géométrie Ux ignorés en session 0.

## Périmètre

Windows PowerShell 5.1 x64, STA, session 0. Contrôles WPF et données synthétiques ; aucune connexion AD, préférence réelle, console interactive ou opération sur le poste. Les sources testées sont identifiées dans `summary.json`.

| Suite | Réussis | Ignorés | Échecs | Rapport |
| --- | ---: | ---: | ---: | --- |
| Login | 19 | 0 | 0 | [initial/Login.json](initial/Login.json) |
| LoginPreferences | 15 | 0 | 0 | [initial/LoginPreferences.json](initial/LoginPreferences.json) |
| Progress | 21 | 0 | 0 | [pass2/Progress.json](pass2/Progress.json) |
| Ux | 48 | 2 | 0 | [initial/Ux.json](initial/Ux.json) |
| UiPresentation | 41 | 0 | 0 | [initial/UiPresentation.json](initial/UiPresentation.json) |
| Zoom | 42 | 0 | 0 | [initial/Zoom.json](initial/Zoom.json) |
| ToolsTabs | 33 | 0 | 0 | [initial/ToolsTabs.json](initial/ToolsTabs.json) |
| HomeDashboard | 44 | 0 | 0 | [pass2/HomeDashboard.json](pass2/HomeDashboard.json) |
| DomainNavigation | 10 | 0 | 0 | [initial/DomainNavigation.json](initial/DomainNavigation.json) |
| Settings | 26 | 0 | 0 | [initial/Settings.json](initial/Settings.json) |
| InterventionView | 18 | 0 | 0 | [pass2/InterventionView.json](pass2/InterventionView.json) |
| Async | 32 | 0 | 0 | [Async.json](Async.json) |
| Pilotage | 55 | 0 | 0 | [pass2/Pilotage.json](pass2/Pilotage.json) |
| QueueRemoval | 25 | 0 | 0 | [pass2/QueueRemoval.json](pass2/QueueRemoval.json) |
| Pesto21 | 61 | 0 | 0 | [Pesto21.json](Pesto21.json) |
| Pesto22 | 33 | 0 | 0 | [pass2/Pesto22.json](pass2/Pesto22.json) |
| Pesto23 | 66 | 0 | 0 | [pass2/Pesto23.json](pass2/Pesto23.json) |
| NamesLoading | 37 | 0 | 0 | [NamesLoading.json](NamesLoading.json) |

## Correctif produit

La construction de la source du worker passe à l’intérieur des blocs de gestion d’erreur existants. En cas d’échec, Accueil publie l’erreur et Interventions réactive Actualiser au lieu de rester bloqué en chargement. Deux régressions échouent avant la correction puis réussissent localement et sur Windows.

## Bancs remis en cohérence

Les échecs initiaux sont conservés dans `initial/` et `pass2/`. Ils proviennent des dépendances de modules/Common non chargées, d’un ConfigStamp absent dans une fixture et d’une suppression de lien qui demandait une confirmation sous PS5.1. Le chemin de reçus de QueueRemoval est maintenant entièrement synthétique. Async ajoute les contrôles de remplacement des mutations, admission de la treizième lecture et verrou après erreur de restitution directe.

## Limites

Deux mesures de grande fenêtre sont ignorées car la session 0 offre un écran de 1024 px. Les mesures WPF sans Show des suites Zoom/ToolsTabs passent ; la vérification de la console réelle reste séparée. Aucune nouvelle qualification AD ni d’un EXE reconstruit n’est déduite de ces résultats. Les comptes de suites ne sont pas additionnés en exigences distinctes.

Les fichiers sources des preuves restent dans `C:\PestoAudit20261013\ui`. Le manifeste distingue copies identiques et conversion UTF-16 vers UTF-8 ; aucun contenu de rapport n’a été corrigé pour transformer un échec en succès.

## Sources finales

Après gel du build `22f8f5c4`, cinq suites sont rejouées sur une copie dont les empreintes des sources sont relues sur l’invité et identiques au runtime final : Accueil 44/44, Interventions 18/18, Async 32/32, Noms-WPF 37/37 et Pesto21-WPF 61/61. Voir [la preuve ciblée finale](final/summary.json). Ces bancs ne lancent pas l’EXE ; le lancement réel appartient à la recette interactive séparée.

## Finition du premier lancement

Après la campagne liée au build `22f8f5c4`, le contrôle interactif du parent a identifié le libellé doublé de l’assistant et le centrage vertical du JSON. `Pesto-Configuration.ps1` corrige uniquement ces présentations : apostrophe unique et `VerticalContentAlignment="Top"` pour `Json` et `Errors`. Deux assertions XML reproduisent les défauts avant correction ; `UiPresentation` passe ensuite **43/43** sur Mac et Windows PowerShell 5.1 en session 0. Cette suite ne lance pas l’application. Preuves et empreintes : `first-start/summary.json`, `first-start/before.json`, `first-start/after.json` et `first-start/windows/UiPresentation.json`. La vérification visuelle du nouvel EXE appartient à la recette interactive du parent.
