# Lot automatisation — catalogue 120

Travail sur Pesto 1.0. Ce rapport distingue implémentation et qualification.

| ID | Réalisation | Preuve locale | Validation restante |
|---:|---|---|---|
| 79 | `Invoke-Pesto.ps1`, `Invoke-PestoUnattendedOperation` : préparation, Rename, Move, RenameMove ; workers, policy et reçus du moteur existant ; opt-in distinct | Contrats `Run-IntegrationTests.ps1` | Parcours Windows et AD réel du CLI |
| 80 | Actions Inspect et Diagnose, JSON, observation sans clôture de reçu | Point d'entrée et API moteur raccordés | Lecture Windows/AD réelle |
| 81 | Plan fermé exportable, durée 24 h, empreinte de cohérence, contexte et identités relus, aucune réservation implicite | Export sans écrasement, altération, expiration, machine/configuration différentes | Réutilisation réelle après évolution AD |
| 82 | Clé idempotente locale, marqueur durable avant action, restitution de résultat, conservation des incertains, payload différent refusé | Coupures simulées avant/après action, disque refusé, résultat ambigu, rejeu | ACL Windows et concurrence de processus |
| 83 | Adaptateur commun ConfigMgr/PSADT/PDQ/DeployR, code retour conservé, clé requise, paramètres explicites | Contrat du moteur et exemple appelable | Orchestrateurs réels non installés sur ce banc |
| 84 | Adaptateur FirstBoot réservé à SYSTEM, documentation du réseau/compte, aucun service/tâche/autologon créé | Garde de contexte dans l'adaptateur | Véritable séquence SYSTEM |
| 85 | Métadonnées fermées Campaign/Sequence/Stage/DeploymentBuild/Orchestrator, propagées aux résultats et reçus | Types, longueurs, caractères, noms inconnus et motifs de secrets refusés | Chaîne complète moteur/receipt Windows |
| 86 | Contrat JSON et codes documentés dans `integrations/README.md` ; ancien AutoJoin conservé | Tests des codes et du dispatcher | Compatibilité du consommateur à qualifier par produit |
| 112 | ADMX/ADML et stratégie ordinateur restrictive ; pas d'activation forcée d'une fonction désactivée localement | XML et merge pur testés, cfg brut conservé via LocalOnly | Console GPO réelle et moteur worker Windows |
| 118 | IncidentMode booléen strict ; blocage avant mutation dans moteur et CLI ; commandes de lecture disponibles | Banc moteur et policy | Clic UI et changement administré en cours de session |

## Contrats contrôlés

`Run-IntegrationTests.ps1` : fonctions réelles ; identité machine, écriture des reçus
et dispatcher Windows remplacés explicitement par des doubles. Ce banc ne prouve
ni les ACL, ni le réseau, ni les droits AD. Il utilise un répertoire temporaire sous
les tests pour respecter la protection contre liens/jonctions sur macOS.

`Run-OptionalIntegrationsTests.ps1` : schémas de profils/scénarios,
proposition d'attributs non exécutable, projection audit fermée et restrictions GPO.
Aucune application GPO ni mutation réseau.

Les rapports datés sont dans `preuves/ameliorations-120-2026-10-13/local/`.

## Limites conservées

- Le registre idempotent est celui de la machine opérateur. Il n'est pas une base
  de coordination distribuée. Les contrôles existants entre machines restent distincts.
- L'empreinte d'un plan n'est pas une signature ou un accord d'approbateur.
- 3010 signifie accepté avec redémarrage nécessaire ; aucune mutation n'est rejouée.
- Les identifiants sont des PSCredential en mémoire. Aucun coffre n'est créé dans Pesto.
- Un adaptateur exécutable et des tests de doubles ne constituent pas une qualification
  de ConfigMgr, PSADT, PDQ ou DeployR.
