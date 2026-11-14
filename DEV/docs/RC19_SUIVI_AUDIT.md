# Pesto RC19 : suivi honnête des 44 points de l’audit

Cette matrice est un état d’implémentation, pas un certificat de tests Windows. **Les 44 critères d’acceptation ne sont pas tous clos.** « Implémenté » signifie que le code et son raccordement ont été ajoutés ; les contrôles portables ne prouvent pas une opération réelle WPF/UAC/AD.

La RC19 est une version candidate complète, avec EXE et packs. Les points partiels restent explicitement décrits pour ne pas transformer un changement de source en promesse de sécurité.

| ID | Sujet | État | Code / limite exacte |
|---|---|---|---|
| PE-01 | Retrait Entra conditionnel | **Implémenté** | Safety, Operations, Configuration. AD seul : aucun /leave. Hybride : préparation selon la politique. État ambigu : refus. Essais Windows à réaliser. |
| PE-02 | Effets Entra indépendants | **Partiel** | Safety, Operations, Interventions. Reçus avant/après retrait et relecture ciblée des tâches. Réinscription Entra uniquement à vérifier ; pas de certification cloud. |
| PE-03 | Redémarrage sans forçage implicite | **Implémenté** | Operations, Core. shutdown /r /t 0 sans /f ; délai positif refusé. Un redémarrage demandé est immédiat : enregistrer son travail avant confirmation. Test VM avec document ouvert restant. |
| PE-04 | Identité distante avant mutation | **Implémenté** | Safety, Inspection. Observation Windows/AD exigée avant le renommage, identité conservée dans le reçu central. Essais DNS et machines réelles restants. |
| PE-05 | Registre durable commun | **Partiel** | Safety, Core, Direct, Join. Nouvelles opérations des trois parcours inscrites dans ProgramData/GP/Interventions. Reçus historiques conservés mais non tous migrés. |
| PE-06 | Reprise hors de la file | **Implémenté** | Interventions, Inspection. Les nouvelles interventions restent consultables après retrait d’une ligne. Reprise du déplacement seulement après observation confirmée. Anciennes lignes sans reçu central : examen manuel. |
| PE-07 | Continuité entre copies locales | **Partiel** | Safety, Core. Registre commun aux copies et comptes pour les nouvelles interventions. Anciens checkpoints de file par utilisateur/chemin non découverts exhaustivement. |
| PE-08 | Coordination entre postes opérateurs | **Non implémenté** | Décision d’architecture requise. Le mutex et le registre ne coordonnent que le PC opérateur. Aucun partage ou service de coordination n’a été créé. Ne pas intervenir simultanément depuis deux PC sur la même cible. |
| PE-09 | Protection AD durable | **Partiel** | Operations, Safety, Inspection. Valeur initiale enregistrée avant levée et vérifiée après interruption. Restauration normale dans le moteur ; pas de nouvelle commande autonome de réparation de protection après crash. |
| PE-10 | Résultats typés | **Partiel** | Safety, Operations. Contrat strict sur le retour central et codes Win32 dans les chemins modifiés. Certaines branches héritées emploient encore la classification historique ; revue complète restant. |
| PE-11 | Confiance avant PowerShell | **Partiel** | Lanceur C et empreintes compilées. Empreintes des 27 composants figées dans l’EXE et vérifiées avant PowerShell ; refus de liens et maintien de handles de lecture. Pas d’Authenticode ni de certificat autorisé : authenticité de l’EXE non prouvée. |
| PE-12 | Origine du module AD | **Implémenté** | Safety, Directory et workers. Import absolu du module livré ; refus d’un homonyme déjà chargé ailleurs. Pas de résolution du module par un répertoire utilisateur. |
| PE-13 | Fichiers privilégiés et ACL | **Partiel** | Safety, reçus et vérification native. Contrôles de chemins et écritures atomiques réutilisés. Les ACL de chaque fichier préexistant, liens physiques et courses d’ouverture ne sont pas tous couverts par une primitive native commune. |
| PE-14 | Tâches utilisant un mot de passe | **Partiel** | Operations et contexte worker. Repli avec mot de passe désactivé dans les demandes UI normales ; garde explicite dans le moteur. Pas de remplacement réseau S4U. Une interface de politique d’entreprise complète n’est pas livrée. |
| PE-15 | Cycle de vie des tâches | **Partiel** | Safety, Operations, Interventions. Nom exact, phase et empreinte de XML persistés ; contrôle avant exécution/nettoyage, bouton de relecture sans mutation distante. Tâches non vérifiables conservées ; pas de nettoyage global automatique. |
| PE-16 | Exclusions sensibles | **Implémenté** | Safety et Operations. Contrôle rôle/domaine/identité Windows avant retrait ou renommage ; exclusion des DC pour le déplacement. Les permissions réelles restent évaluées par Windows/AD. |
| PE-17 | Entrées non fiables | **Partiel** | Safety, Preparation, contrôles hérités. Validation des nouveaux reçus, favoris et réponses centrales, bornes et noms. Pas de remplacement exhaustif de tous les anciens schémas CSV/JSON. |
| PE-18 | Durée de vie des secrets | **Partiel** | Authentication conservée, reçus en liste fermée. Aucun credential dans les nouveaux reçus/favoris/rapports. Pas de promesse d’effacement garanti de mémoire managée ; audit exhaustif des chemins historiques restant. |
| PE-19 | Contrôleur adapté | **Implémenté** | Directory. DCLocator via Get-ADDomainController, Writable et ADWS ; FQDN vérifié et contrôleur de session conservé. Essais multi-DC/RODC restant. |
| PE-20 | Diagnostic réseau par action | **Partiel** | Inspection et centre Interventions. Observation Windows/AD avant mutation et relecture du Planificateur. Pas de nouveau tableau exhaustif DNS/SMB/RPC/ADWS avec budget global propre. |
| PE-21 | Conflits de noms | **Implémenté** | Directory, précontrôles existants. Recherche name, sAMAccountName et dNSHostName dans le chemin partagé ; pas de réservation AD ni d’écriture SPN. Concurrence réelle restant à tester. |
| PE-22 | Convention de nommage unique | **Partiel** | Configuration. Préfixe limité à six chiffres comme les analyseurs existants. Détection exhaustive des collisions de codes site et moteur de règles refondu non achevés. |
| PE-23 | Identité de la destination OU | **Partiel** | Operations, Safety. GUID réel de destination lu et persisté avant déplacement. Liaison entre GUID de l’aperçu confirmé et GUID relu à l’engagement non généralisée. |
| PE-24 | Refus Netjoin | **Implémenté** | Operations. Erreur native 2732 distinguée ; renvoi vers la vérification NetSetup, sans suppression d’objet ni ancien contournement registre. Cas réel restant à tester. |
| PE-25 | Configuration neutre | **Partiel** | cfg.json, Configuration. Pack non configuré explicite, import validé par l’écran de configuration ; aucun faux domaine distribué comme opérationnel. Assistant complet de découverte et migration de toutes les clés historiques non réalisé. |
| PE-26 | Postconditions séparées | **Partiel** | Safety, Inspection, Interventions. Étapes Entra/protection/renommage/déplacement et attente reboot visibles. Pas d’intégration à la source du périmètre de synchronisation Entra ; cette information reste inconnue. |
| PE-27 | Journal incrémental | **Partiel** | Journal, Async, SuiteUI. Affichage incrémental borné et tampon monitor limité. Les écritures de journal disque restent synchrones ; pas de mesure de latence sous Windows. |
| PE-28 | Délais et retours tardifs | **Partiel** | Async, Safety. Mesure monotone de durée d’étape ; résultat tardif conservé comme incertain. Tous les budgets hérités transport/UI/Planificateur ne sont pas encore unifiés. |
| PE-29 | Fraîcheur du cache | **Conservé, non étendu** | Directory et UI existantes. Inventaire différé et lecture autoritaire avant action conservés. Pas de refonte exhaustive de l’étiquetage de couverture/fraîcheur. |
| PE-30 | Type matériel inconnu | **Implémenté** | Directory. Une lecture matérielle échouée ne reste plus présentée comme Fixe. Recette des combinaisons de châssis et du formulaire requise. |
| PE-31 | Connexion et thème | **Consolidé, recette requise** | Authentication, Appearance, tests Windows. Parcours domaine intégré, login NoResize, choix du thème indépendant et tests conservés/complétés. UAC deux comptes et rendu non exécutés ici. |
| PE-32 | Rendu et accessibilité réels | **Tests fournis, non exécutés** | maintenance/Test-Pesto19.ps1. Chargement des vrais XAML et captures facultatives. Recette interactive DPI/RDP/lecteur d’écran, notamment 200 %, restant à réaliser. |
| PE-33 | Déblocage dans support | **Implémenté** | wad/support/DEBLOQUER_TOUT.cmd. Deux niveaux au-dessus comme racine vérifiée ; support présent dans les deux packs, facultatif au lancement. Exécution Windows du CMD non réalisée. |
| PE-34 | Mise à jour prévisualisée | **Partiel** | tools/update_installation.py. Prévisualisation, sauvegarde et retour des fichiers sur exceptions testés sur 29 frontières de copie. Interruption brutale/panne électrique : sauvegarde et verrou à examiner ; pas de transaction atomique globale ni annulation AD. |
| PE-35 | Version et inventaire | **Partiel** | Générateur, métadonnées, inventaire joint. Versions courantes cohérentes et empreintes inventoriées. Plusieurs constantes restent dans les sources ; certificats/licences tierces non validés juridiquement. |
| PE-36 | PROD/DEV minimaux | **Implémenté** | package_distribution, refresh_manifest. Racines distinctes ; PROD seulement EXE et wad ; runtime identique. Tests/démos/support exclus des dépendances de lancement. |
| PE-37 | Parseur et PSScriptAnalyzer | **Tests fournis, non exécutés** | TESTER, Verify-Release. Suite cible Windows PowerShell 5.1 et analyseur versionné 1.24.0. Moteur et analyseur absents de cet environnement Linux. |
| PE-38 | Tests comportementaux Pester | **Tests fournis, non exécutés** | tests/Pesto.Safety.Tests.ps1. Scénarios Pester 5.7.1 fournis et autres doubles PowerShell étendus. Aucun résultat Pester ou couverture Windows annoncé. |
| PE-39 | Recette Windows 11/AD | **Non exécuté** | Matrice de recette. Nécessite VM Windows 11, domaine et comptes de test ; aucun accès au parc du client effectué. |
| PE-40 | Preuves CI | **Partiel** | workflow manuel et Verify-Release. Actions figées, rapports exigés, échecs/SKIP bloquants pour les tests prévus. Workflow non lancé ; modules à préprovisionner. Aucun job de publication automatique ou signature. |
| PE-41 | Centre Interventions | **Implémenté** | Interventions, Shell, Core. Nouvelle vue partagée pour les opérations RC19, détail des effets/tâches, lecture de contrôle et reprise guidée. Pas de collecte exhaustive des états historiques non migrés. |
| PE-42 | Aperçu d’impact | **Partiel** | Aperçus existants, Direct, Core. Textes corrigés sur retrait conditionnel et nouvelles étapes détaillées. Empreinte intégrale d’un plan incluant identité destination avant confirmation non généralisée. |
| PE-43 | Favori de préparation | **Implémenté** | Preparation et Shell. Un favori explicite organisme/site/service/type, lié au domaine et à la configuration. Aucun poste, reboot, mot de passe ou confirmation mémorisé. |
| PE-44 | Diagnostic silencieux | **Implémenté** | EXE --check-json et Startup. Rapport local borné de cohérence/prérequis, sans UAC ni AD ; chemin nouveau requis, pas d’écrasement. Diagnostic de réseau séparé non ajouté. |

## Limites déterminantes

Le registre partagé concerne **un seul PC opérateur**, pas plusieurs postes administrateurs. Les anciens checkpoints GP ne sont ni effacés ni tous migrés. Plusieurs verrous globaux historiques restent conservateurs : une cible incertaine peut encore bloquer un autre parcours. Ces protections n’ont pas été supprimées pour donner l’impression de débloquer l’application.

Les signatures approuvées exigent le certificat de l’organisation. Les empreintes incorporées à l’EXE détectent le remplacement d’un script et de son manifeste, tant que l’EXE lui-même est celui attendu ; elles ne permettent pas d’authentifier un EXE remplacé en même temps. Aucune confiance de certificat n’est installée automatiquement.

La recette Windows réelle, la couverture de tous les cas d’interruption et les protections complètes contre les liens physiques/courses de fichiers restent nécessaires avant diffusion élargie. Le journal disque n’a pas été déplacé dans un worker dédié.

## Références consultées

Microsoft Learn : shutdown, Get-ADDomainController, TASK_LOGON_TYPE, about_Signing ; documentation officielle Pester et PSScriptAnalyzer. Ces documents expliquent les mécanismes, pas la validation de Pesto dans le domaine du client.

- https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/shutdown
- https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-addomaincontroller
- https://learn.microsoft.com/en-us/windows/win32/api/taskschd/ne-taskschd-task_logon_type
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-5.1
- https://pester.dev/docs/quick-start
- https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/overview
