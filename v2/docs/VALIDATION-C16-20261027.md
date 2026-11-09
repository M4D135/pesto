# C16 — lots, brouillons, confirmation moteur et parcours de configuration

## Source et état de la qualification

Le candidat final est [`3a8c49d85d5cc16dcab2d7c743be7fa445d05715`](https://github.com/M4D135/pesto/commit/3a8c49d85d5cc16dcab2d7c743be7fa445d05715), sur `codex/pesto-v2-20261023`. Sa [campagne Windows 40491875705](https://github.com/M4D135/pesto/actions/runs/40491875705) est **entièrement réussie**, le 27 octobre 2026 de **10:52:46 à 11:13:51 UTC**. Les candidats PROD et DEV sont publiés. L’archive des preuves a été téléchargée, son SHA-256 vérifié et ses huit JSON natifs recoupés indépendamment : [synthèse finale, empreintes et téléchargements](evidence/20261027/windows-3a8c49d/README.md).

Les corrections fonctionnelles initiales proviennent de `d803d72`, issu de `a7889d8`, puis les sélecteurs natifs sont corrigés dans `1dbdda1` et `3a8c49d`. Aucun fichier privé non poussé du Spark n’est intégré à cette reprise. Les preuves C15 et antérieures conservent leurs propres sources et binaires.

| Campagne C16 | Source | Verdict et portée |
|---|---|---|
| [40486971793](https://github.com/M4D135/pesto/actions/runs/40486971793) | `d803d72` | Échec du banc à l’export après 2 contrôles ; destination effective inconnue, aucun candidat publié |
| [40489970770](https://github.com/M4D135/pesto/actions/runs/40489970770) | `1dbdda1` | Export/enregistrement/import réussis, puis défaut du filtre de dossier après 19 contrôles ; aucun candidat publié |
| [40491875705](https://github.com/M4D135/pesto/actions/runs/40491875705) | `3a8c49d` | Tous les contrôles réussis, dont 36 assertions natives par canal et quatre scénarios transactionnels ; candidats publiés |

Les [premières preuves](evidence/20261027/windows-d803d72-failed/README.md) et [la deuxième tentative](evidence/20261027/windows-1dbdda1-failed/README.md) restent conservées. Leurs succès partiels ne sont pas additionnés au verdict final.

Le lot corrige des défauts de sélection et de bilan des lots, protège les brouillons d’attributs et de paramètres, resserre les dernières vérifications du moteur et répare la documentation livrée dans les packs. Il étend également le harnais Windows pour exercer les boutons de configuration de la vraie fenêtre WebView2. Les parcours et leurs limites restent ceux d’un candidat, sans remplacement de la V1.

## Corrections de l’interface métier

### Identité et corrections CSV avant ajout à la file

Dans **Plusieurs postes**, le type `P`, `S` ou `V` fourni par l’inspection est désormais prioritaire. Un portable ou une VM sans modèle matériel observé ne devient plus implicitement un poste fixe. Le modèle sert seulement de repli lorsqu’il est reconnu ; un type toujours inconnu reste absent.

Une ligne sans type, site ou service est refusée avant `names.preview` et `queue.add`. Le message explique comment fournir les indications manquantes par CSV. Cette correction aurait été inutilisable avec l’ancien comportement, qui ignorait tout nom déjà sélectionné : la réimportation du même poste met maintenant à jour les seules colonnes explicitement renseignées, conserve les autres indications et ne crée pas de doublon. Les comptes d’ajouts et de corrections sont affichés séparément.

Les sources de sélection, les boutons des résultats de recherche et les commandes de file sont verrouillés pendant la lecture du CSV ou l’ajout en cours. Une réponse de recherche tardive conserve ce verrou. La lecture du fichier doit se terminer avant tout ajout, et elle est abandonnée si la page est quittée. Dès qu’un nouvel ajout commence, l’ancien aperçu de lot cesse d’être proposé. Les confirmations, les noms calculés par le moteur et la limite de 50 postes restent appliqués.

### Un bilan de lot lié à chaque plan

Des reçus individuellement réussis ne suffisent plus à afficher un lot entièrement confirmé. Le bilan vérifie le nombre de reçus, leurs identifiants distincts et une correspondance unique pour chaque plan : poste, opération, nom attendu, OU et mode. Chaque reçu doit ensuite porter un état autorisant la confirmation.

Un reçu manquant, dupliqué ou portant un autre nom laisse le lot **à vérifier**, même si la réponse affirme ne pas s’être arrêtée. Les reçus disponibles restent consultables. Cette vérification ne déclenche ni nouvel envoi ni reprise automatique.

### Brouillons conservés et réponses tardives

Les pages **Attributs AD** et **Paramètres** demandent un accord avant de quitter des modifications non appliquées ou non enregistrées. Relire les attributs demande également cet accord ; une annulation conserve les valeurs saisies et les différences déjà préparées. Une confirmation de relecture abandonne le brouillon sans appliquer d’attribut.

Le routeur conserve l’adresse de la page affichée pendant le dialogue de départ. Auparavant, le hash pouvait déjà désigner la destination alors que le formulaire restait visible : une réponse asynchrone vérifiant sa route était alors ignorée, même si l’opérateur annulait finalement son départ. Le résultat d’un enregistrement en cours peut maintenant terminer et remettre les boutons à disposition pendant ce dialogue. La destination est adoptée après l’accord ; un refus conserve le formulaire.

Les régressions couvrent les types portables et virtuels sans modèle, les corrections CSV complètes et partielles, les lectures et ajouts retardés, les trois incohérences de reçus, ainsi que les annulations et confirmations d’abandon des deux formulaires. Les autres parcours métier, dont l’aperçu du nom avant ajout, **Un poste**, la reprise des interventions et le mode pilote, sont relancés dans les suites complètes.

## Vérifications supplémentaires du moteur

### Autorisation encore valide après les dernières lectures

Les dernières lectures d’identité, de groupes et d’horloge peuvent durer au-delà de la validité restante du plan. Le moteur revérifie maintenant l’expiration et l’empreinte de configuration immédiatement avant la consommation du plan et l’envoi de la commande.

Une expiration pendant ces lectures renvoie `plan.stale` ; une configuration modifiée renvoie `config.changed`. Les tests vérifient l’absence d’appel à l’adaptateur de mutation et l’absence de reçu prétendant qu’un envoi a eu lieu. La nouvelle préparation et la nouvelle confirmation restent nécessaires.

### État final réellement relu

Une recherche d’ordinateur peut résoudre un alias CN ou sAM et retrouver un GUID sans prouver le nom final demandé. `ReReadConfirms` exige maintenant le nom final attendu, un GUID valide et non vide, ainsi que le placement attendu. Pour un renommage seul, l’OU relue doit toujours être l’OU source conservée ; pour les autres opérations concernées, elle doit être la destination du plan. Le rapprochement avec le GUID du plan reste exigé hors jonction.

Les cas de nom différent après renommage ou déplacement, de changement d’OU après renommage et de GUID absent après jonction restent **incertains** malgré un succès annoncé par l’adaptateur de test. Un seul envoi est conservé et le plan consommé ne redevient pas rejouable. Ces essais utilisent des adaptateurs explicites ; ils ne constituent pas des mutations AD réelles.

## Documentation et fabrication des packs

Les liens entre documents livrés dans `wad/docs/` sont recalculés selon leur emplacement dans le pack. Les liens vers des preuves JSON, des journaux ou d’autres fichiers de développement non livrés dans cette documentation pointent vers leur source GitHub au commit déclaré. Les journaux et JSON ne sont pas ajoutés aux documents PROD pour faire disparaître les liens cassés.

Le pack DEV inclut maintenant le README et les sources documentaires dans `wad/dev/`. Le test de fabrication réutilise uniquement l’arbre de développement livré, avec les entrées de publication et de runtime fournies au test, pour reconstruire un PROD identique. Il s’agit de la reproductibilité de l’assemblage ; ce contrôle ne recompile pas l’exécutable depuis les sources DEV.

Un processus de vérification interrompu, tué ou impossible à lancer ne peut plus être compté comme un refus réussi du validateur. Les statuts candidat/non officiel, les contrôles d’intégrité, les refus de liens ou de configuration privée et l’interdiction d’écraser une destination existante sont conservés.

Le [guide de prise en main](PRISE-EN-MAIN.md) accompagne le code C16. Le guide et la documentation C16 préparatoire sont inclus dans le commit de fabrication. Ce bilan final et les preuves ont été complétés après la campagne : ils ne sont pas présentés comme déjà présents dans les ZIP de `3a8c49d`. Les ZIP livrés restent exactement ceux validés par la CI.

## Contrôles portables effectivement exécutés

Les validations locales utilisent Linux, le SDK Microsoft **10.0.302**, Playwright **1.62.1** et Chromium **151.0.7922.34**. Les builds moteur et pont terminent avec zéro avertissement et zéro erreur. L’hôte est publié pour `net10.0-windows/win-x64` depuis Linux ; cette publication n’est pas une exécution Windows.

| Contrôle local | Résultat | Portée |
|---|---:|---|
| Suite complète `Pesto.Engine.Tests` | **615/615** | Moteur et services avec fournisseurs, horloges et dossiers de test |
| Suite complète `Pesto.Bridge.Tests` | **15/15** | Arguments fermés, sérialisation et contrats du pont |
| `pack-check.mjs` | **46/46** | Assemblage, intégrité et reproductibilité ; runtime WebView2 factice explicitement déclaré, aucune exécution Windows |
| Scripts DOM compilés du nouveau harnais de configuration | **12/12** | Vrais formulaires et dialogues web dans Chromium, réponses d’hôte fournies par une fixture |

Les 12 contrôles des scripts compilés vérifient l’observation de la page, le champ de version et l’export, la confirmation d’enregistrement, l’import annulé ou confirmé, la création du pack annulée ou confirmée, la sélection et la préparation d’une mise à jour, l’annulation de son installation, la lecture d’état et l’absence d’erreur ou de requête externe. **Ils n’ouvrent aucun dialogue Windows natif.**

### Seize suites JavaScript et navigateur

Toutes les suites ci-dessous terminent avec une sortie 0 après correction de la fixture DOM décrite ensuite. Les tests Chromium chargent les modules et styles de l’application avec des ponts de test explicites ; les contrôles JavaScript purs n’exécutent pas WebView2.

| Suite | Résultat | Portée principale |
|---|---:|---|
| `azerty-check.mjs` | 21/21 | Conversion des saisies AZERTY |
| `bridge-lifecycle-check.mjs` | 21/21 | Cycle du pont, canal et horloge factices |
| `demo-check.mjs` | 11/11 | Monde de démonstration et refus des API réelles |
| `demo-dom-check.mjs` | 9/9 | Boutons de démonstration, reprise fictive et lots CSV |
| `login-dom-check.mjs` | 28/28 | Accueil et saisie avec résultats UAC/AD synthétiques |
| `operator-ui-check.mjs` | 41/41 | Parcours opérateur et réponses différées |
| `parity-ui-check.mjs` | 53/53 | Attributs, parcours ODJ et mode pilote sur fixtures |
| `policy-ui-check.mjs` | 17/17 | Politiques et séparation de la démonstration |
| `watch-check.mjs` | 44/44 | Outil de surveillance sur données de test |
| `watcher-result-check.mjs` | Réussi, sans compteur publié | Verdict d’arrêt : identité, preuve absente ou contradictoire, disparition vérifiée |
| `web-business-check.mjs` | 48/48 | Parcours métier, sélection, lots et reçus |
| `web-check.mjs` | 149/149 | Imports, ressources, contrat fermé et cohérence statique |
| `web-dom-check.mjs` | 32/32 | Navigation, formulaires et relecture de reçus |
| `web-layout-check.mjs` | 8/8 | Boutons et libellés aux largeurs contrôlées |
| `web-maintenance-check.mjs` | 35/35 | Configuration, maintenance et protection des brouillons |
| `web-recovery-check.mjs` | 23/23 | Préparation et confirmation de reprise sur fixture |

Le premier passage de `web-dom-check.mjs` avait réussi 31 contrôles sur 32 : sa liste d’appels autorisés omettait `reservations.list`, lecture locale déjà effectuée par le panneau des réservations d’Interventions. La fixture renvoie désormais une liste vide pour cette lecture et exige exactement un appel avec des arguments vides. Tout autre appel hors de la liste fermée reste refusé. La relance réussit **32/32**, sans changement du code produit. Le journal de cette relance est la source du verdict final, distinct du journal initial.

Le contrôle statique indique également que la référence Domenia n’est pas disponible sur cette machine : ses 28 empreintes locales sont vérifiées, mais aucune comparaison octet à octet avec cette référence absente n’est déclarée.

### Traçabilité portable

Les [preuves portables conservées](evidence/20261027/portable-d803d72/README.md) comprennent les journaux des builds, des suites moteur/pont, du packaging, des seize suites JavaScript/navigateur et des douze étapes DOM compilées. La [synthèse JSON](evidence/20261027/portable-d803d72/summary.json) conserve les verdicts, les limites et les empreintes des dix-neuf fichiers du commit. `SHA256SUMS` couvre chaque pièce.

Le premier échec de fixture DOM et les reproductions des défauts moteur restent distincts des journaux finaux réussis. Les contrôles ciblés de développement se recouvrent avec les suites complètes ; leurs comptes ne s’additionnent pas. Le premier lancement du build du pont sans restauration et le lancement de fabrication bloqué par le sandbox ne servent pas de preuves de réussite.

### Contrôles ciblés du correctif natif

Les [preuves locales complémentaires de `1dbdda1`](evidence/20261027/portable-1dbdda1/README.md) conservent la publication croisée réussie des trois fichiers natifs corrigés et **46/46 contrôles de fabrication**. Leurs sources correspondent au commit publié ; la compilation locale précédait sa création et utilisait encore `HEAD = d803d72`, avec ces modifications dans le working tree. Son EXE n’est donc pas présenté comme identique au binaire Windows de la nouvelle campagne.

Le premier passage de fabrication réalisé pendant une édition documentaire concurrente avait échoué sur le seul contrôle déterministe. Le passage final réussit avec les **299 entrées documentaires inchangées** du début à la fin, dont les empreintes correspondent toutes à `1dbdda1`. Les journaux des deux passages restent séparés. Ces essais emploient un runtime synthétique et ne qualifient aucun dialogue Windows.

Les [contrôles locaux du filtre de dossier `3a8c49d`](evidence/20261027/portable-3a8c49d/README.md) comprennent sa publication croisée réussie et la comparaison sémantique du workflow : **18 étapes strictement identiques**, seul leur ordre change. La compilation locale utilisait encore `HEAD = 1dbdda1`, avec le fichier corrigé dans le working tree ; son contenu correspond au commit publié. Aucun dialogue natif n’est exécuté par cette publication croisée.

## Premier essai Windows et correction du banc

Le premier essai réussit seulement `parentReady` et `isolatedConfigurationPage` avant d’échouer à l’étape `export-ui`. Le sélecteur affiche le chemin demandé dans son contrôle de saisie, le relit trois fois, reçoit le clic puis se ferme. Le vrai service d’export est appelé, mais le wrapper refuse le chemin retourné avec `qualification.scope`. Le chemin concret n’était pas consigné dans cette preuve ; elle ne suffit donc pas à distinguer un défaut de synchronisation du sélecteur d’une autre différence de représentation du chemin.

Le banc C15 fournissait directement le chemin complet comme nom suggéré au sélecteur ; C16 passe par le bouton réel avec son nom suggéré normal. Sa réussite ne prouvait donc pas la saisie complète requise par C16. Le correctif synchronise la saisie native, observe le chemin effectivement retourné et conserve le contrôle strict de portée. Ce contrôle est également effectué avant la lecture du fichier importé ou l’écriture de l’export par l’hôte. Une erreur du backend est remontée immédiatement par le banc, sans attendre un succès devenu impossible. Le contrat de réussite et les 36 assertions restent inchangés.

La garde de portée du premier essai intervenait après l’écriture d’export. Aucun succès ni absence d’accès au profil ordinaire n’est revendiqué pour ce parcours échoué. Les indicateurs déclaratifs du JSON ne remplacent pas ce constat. L’essai a lieu sur le runner GitHub temporaire, pas sur le poste ni l’annuaire de l’utilisateur.

### Deuxième essai : contrôle de dossier absent du filtre

Sur `1dbdda1`, les chemins retournés par les quatre sélecteurs de fichiers sont observés avant lecture/écriture hôte et correspondent exactement aux destinations temporaires demandées. Les contenus, sauvegardes, confirmations, annulations et erreurs d’encodage attendues passent. Le parcours de fichiers qui avait échoué est donc validé dans cette campagne.

L’arrêt suivant ne vient pas d’un refus de service : le dialogue de dossier contient `Edit` **1152**, mais le pilote ne cherchait que **1001/1148**. La preuve donne `writeAttempts: 0` et `clicked: false`. Le correctif `3a8c49d` accepte uniquement 1152 pour les titres de sélection de dossier et conserve 1001/1148 pour les fichiers. La barre d’adresse 41477 reste exclue ; l’unicité, la visibilité, le focus, les trois relectures stables, la fermeture et le chemin réel gardé restent exigés. Aucune assertion n’est retirée.

Pour obtenir ce verdict plus tôt lors de l’itération suivante, le banc est déplacé juste après les packs. Les suites complètes, les autres bancs natifs et les transactions demeurent nécessaires avant publication. Le workflow ne permet pas qu’un succès de configuration seul produise les candidats.

## Configuration native C16 — réussite PROD et DEV

Le gate de configuration de la campagne `40491875705` réussit sur `3a8c49d` en **PROD et DEV**, avec les **36 assertions par canal**, neuf dialogues, deux sélections positives de dossiers et six captures par canal. Les noms des contrôles, les chemins sélectionnés avant IO, les compteurs, les captures et les empreintes sont recoupés dans les [huit preuves natives finales](evidence/20261027/windows-3a8c49d/README.md).

Il pilote les champs, boutons et confirmations de `MainForm` par des scripts DOM compilés, puis les sélecteurs de fichiers et de dossiers Windows. Le pont et les services réels sont observés, sans substitution de réponses de succès. La configuration de départ est synthétique et placée dans un profil temporaire isolé. Les preuves corrèlent les préparations et confirmations par leurs identifiants, contrôlent les fichiers et sauvegardes produits, puis vérifient le nettoyage du profil Pesto temporaire et la conservation du pack source.

Le périmètre du gate comprend :

- l’export depuis le bouton et le champ de version, l’enregistrement après confirmation, l’import avec aperçu puis confirmation et les annulations correspondantes ;
- la création d’un pack personnalisé depuis **Définir comme configuration par défaut**, avec sélection positive du dossier natif, résultat visible et comparaison des paramètres, de l’exécutable et du pack ;
- deux vérifications de service sur le bundle produit, pour son initialisation dans un profil neuf et la conservation d’un profil existant ; elles ne sont pas présentées comme deux parcours supplémentaires de boutons ;
- l’inspection d’un dossier de mise à jour depuis le bouton, sa préparation, la correspondance exacte de la copie préparée et la lecture de l’état ;
- l’ouverture de la confirmation d’installation, puis son **annulation**, avec absence de `updates.install` et de transaction engagée.

**L’installation confirmée depuis les boutons de maintenance n’entre pas dans ce nouveau parcours.** Les transactions natives d’installation et de retour sont des essais distincts, réussis dans cette même campagne avec deux builds réels et quatre scénarios. Les indicateurs du harnais conservent explicitement `nativeUpdateInstallFromUiQualified: false`, `adExecuted: false`, `realUac: false` et `uncQualification: false`.

## Résultats Windows complets et livrables

La campagne relance les **615 tests moteur**, **15 tests du pont**, **46 contrôles de fabrication**, **30 contrôles du compagnon**, **70 gardes AD sur fixtures**, l’analyse des **18 variantes PowerShell 5.1**, celle de l’entrée du banc et les **deux contrôles UTF-8**. Les **seize suites JavaScript/navigateur** passent : 540 contrôles chiffrés, plus le verdict de `watcher-result-check` sans compteur publié. Ces comptes recouvrent ceux du passage local ; ils ne s’y additionnent pas.

L’accueil natif passe **cinq contrôles**, la saisie **seize**. Les deux canaux passent la démonstration et la coexistence avec **44 refus d’API réelles et six transitions** par canal. Les fenêtres ferment normalement, le contexte du parent est conservé et les profils Pesto temporaires sont supprimés.

Les transactions comparent B à une nouvelle compilation A des sources `de527313b98f30d52802ec6abd51804e12f8c298`. Les commits et empreintes d’EXE diffèrent réellement ; aucune version factice n’est substituée. En **PROD**, l’installation depuis le ZIP et le retour explicite réussissent, comme la restauration après santé négative injectée et la reprise après interruption. En **DEV**, l’installation ZIP et le retour réussissent. Les quatre scénarios consignent **huit tentatives de contrôle de santé**, dont les échecs attendus des scénarios négatifs. Les sources, ZIP et configurations sentinelles sont conservés ; les empreintes du ZIP natif et du ZIP publié concordent.

| Livrable C16 | Téléchargement |
|---|---|
| PROD | [Artefact 12730361970](https://github.com/M4D135/pesto/actions/runs/40491875705/artifacts/12730361970) |
| DEV | [Artefact 12729157837](https://github.com/M4D135/pesto/actions/runs/40491875705/artifacts/12729157837) |
| Journaux, captures et preuves | [Artefact 12729422738](https://github.com/M4D135/pesto/actions/runs/40491875705/artifacts/12729422738) |

Disponibilité GitHub jusqu’au **26 novembre 2026**. Les packs sont autonomes avec `Pesto.exe` et `wad/`, WebView2 **156.0.4314.42** et le module Microsoft AD épinglé ; le déblocage reste dans `wad/support/DEBLOQUER_TOUT.cmd`. Windows observé : **10.0.26100.0**.

| Pièce | SHA-256 |
|---|---|
| ZIP candidat PROD intérieur | `6a10bf715390aaa4fa210cd1839ad1dad1e845d4d086bf0db96422f4645ab1cc` |
| ZIP candidat DEV intérieur | `aa33ec85b161216b61a89fd81746611903ddd9ead84abe0cf47ae415141a8710` |
| EXE commun | `0d8e8936060098fffc25f7b807e14546b25df7244775abe7a3dcdee4ebb4bba8` |
| Enveloppe des preuves téléchargée | `e4b250b6ebf8276e8955da7f11d3a23f4896a2459f0f49dcd8ace51c7d50cadb` |

L’enveloppe des preuves fait **3 520 579 octets** et son hash correspond au digest GitHub. Les deux grosses enveloppes binaires n’ont pas été retéléchargées localement ; leurs hashes de ZIP et d’EXE sont ceux de la CI, recoupés dans les transactions natives. Les [métadonnées et preuves conservées](evidence/20261027/windows-3a8c49d/README.md) distinguent les enveloppes GitHub des ZIP intérieurs, documentent la normalisation des fins de ligne et gardent les empreintes de chaque pièce.

## Limites et preuves historiques

Cette reprise locale n’effectue aucune opération sur l’annuaire de l’utilisateur ni sur les VM du laboratoire. Les accès AD réels, UNC/SMB, la concurrence entre machines et l’UAC réel restent des qualifications externes. Les contrôles d’ODJ, d’Entra, de CLI ou de comptes présents dans des suites de fixtures ne prouvent pas ces parcours dans leur environnement réel.

Le [rapport C15](VALIDATION-C15-20261027.md) décrit la campagne et les livrables du code `b875174`, avec son propre périmètre natif de configuration. Les preuves AD des [rapports C14](VALIDATION-C14-20261026.md) et [C9](VALIDATION-C9-20261026.md) restent attachées à leurs sources et binaires respectifs. Elles documentent l’historique ; elles ne sont ni additionnées aux comptes C16 ni réattribuées au candidat corrigé `3a8c49d`.
