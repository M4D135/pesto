# C15 — choix de poste, lectures AD et inspections de mise à jour

## Source et périmètre

Le candidat de code est [`b87517453a4d00d0082b8f3a346459fe0c4890c6`](https://github.com/M4D135/pesto/commit/b87517453a4d00d0082b8f3a346459fe0c4890c6), issu de `daa256477452b4866bb24fdd690f1761dbb42c3c` sur `codex/pesto-v2-20261023`. Cette reprise conserve les travaux C14 présents sur GitHub. Elle n’intègre aucun fichier privé non poussé du Spark.

Le lot corrige les choix proposés dans **Un poste**, réduit les lectures répétées des OU et nettoie les extractions temporaires des ZIP refusés. Il ne change pas les confirmations, les reçus, les verrous GP ni les commandes de mutation AD. La présence des correctifs dans un candidat ne transforme pas les preuves AD historiques en qualification de son nouveau binaire.

## Corrections

### Sites chargés après l’identité du poste

La recherche et la lecture de la fiche peuvent finir avant le chargement des sites. Auparavant, les formulaires étaient construits avec une liste vide qui ne se mettait pas à jour à l’arrivée du catalogue. L’identité est maintenant visible immédiatement ; les choix de renommage et de déplacement attendent les sites puis s’initialisent sur le **dernier poste sélectionné**, sans deuxième inspection.

Une erreur de catalogue reste affichée avec **Réessayer le chargement des sites**. Un catalogue vide est distingué d’un chargement en cours. Aucun appel de services avec un site vide n’est envoyé. Les réponses reçues après navigation restent ignorées et les contrôles modifiables ne sont pas reconstruits au détriment d’une saisie existante.

### Code de site et identifiant de catalogue

Le moteur réel renvoie le code du nom, par exemple `LY`, tandis que le catalogue peut utiliser l’identifiant `lyon`. Comparer ces valeurs directement pouvait présélectionner le premier site, proposer le site courant comme destination ou préparer la mauvaise intention de renommage.

En session réelle, le rapprochement utilise le **code**. En démonstration, il utilise l’identifiant de son monde fictif. Si un code correspond à plusieurs entrées, l’OU observée sert à les départager uniquement quand elle désigne une entrée unique. Un site inconnu ou encore ambigu impose un choix explicite.

Le cas où l’identifiant `PA` appartient à une entrée de code `LY`, alors que le poste réel porte le code `PA`, fait l’objet d’une régression dédiée : Lyon ne se sélectionne pas implicitement. Son choix explicite prépare un renommage avec déplacement. La règle métier existante reste **même code de site : OU réelle conservée**.

### Type de poste conservé

`directory.search` et `computer.inspect` exposent maintenant `type`, issu de la convention de nommage déjà analysée par le moteur. Un portable `P` ou une VM `V` conserve ce choix même si le modèle matériel n’a pas été observé. La page ne présélectionne plus « Fixe » par défaut quand le type est inconnu. Un nom hors convention donne `null`, sans nouvelle sonde matérielle ni découpage approximatif du nom dans le navigateur.

### Refus de calcul visible

Le message d’erreur de `names.preview` était écrit puis aussitôt effacé par le rafraîchissement de l’aperçu. Le motif reste maintenant visible, le bouton d’application demeure désactivé et une nouvelle saisie invalide l’ancien aperçu. Les protections existantes contre une réponse tardive et contre une confirmation après changement de poste sont conservées.

### Une lecture des enfants par conteneur

`ResolveSites` relisait les mêmes OU enfants pour chaque motif de site. Il conserve maintenant un instantané **limité à une seule résolution** pour chaque conteneur, puis applique les motifs dans leur ordre initial. Les identifiants et leur dédoublonnage sont inchangés.

Sur le test de 30 motifs et 2 conteneurs, les appels au lecteur passent de **60 à 2**. Ce nombre mesure les appels de la fixture, pas un gain de temps observé sur un domaine réel. La demande suivante relit l’annuaire. Un échec au second conteneur après lecture du premier ne publie ni ne conserve un résultat partiel.

### Extraction d’un ZIP refusé

Une extraction achevée restait dans le profil lorsque les vérifications suivantes refusaient le pack. `InspectLocal` nettoie désormais seulement le dossier temporaire créé par cet appel. L’archive sélectionnée, les dossiers sources, l’installation, la configuration du profil et les candidats acceptés antérieurement restent intacts.

Les cas couverts sont le mauvais canal, l’intégrité invalide, le pack déjà installé et la structure ambiguë. Le candidat accepté avant le refus peut toujours être préparé. Un échec de nettoyage sûr ne masque pas la raison initiale du refus ; aucun nettoyage général du dossier de mises à jour n’est ajouté.

## Contrôles portables réellement exécutés

Environnement Linux, SDK Microsoft **10.0.302**, Playwright **1.62.1** et Chromium **151.0.7922.34**. Le build de l’hôte cible `net10.0-windows/win-x64` et termine avec **zéro avertissement et zéro erreur** ; il s’agit d’une compilation croisée, sans exécution de Windows dans ce contrôle local.

| Suite | Résultat | Portée |
|---|---:|---|
| `LiveReadTests` | 24/24 | Sites, fraîcheur, erreurs, types lus |
| `LiveWriteTests` | 16/16 | Plans et exécution avec adaptateur de test |
| `LiveQueueTests` | 28/28 | Lots, invalidation, confirmations et résultats |
| `LiveSettingsTests` | 16/16 | Convention et configuration moteur |
| `UpdateTests` | 24/24 | Inspections, préparation, transactions sur dossiers de test |
| `web-business-check.mjs` | 39/39 | Vrais modules et formulaires dans Chromium, pont de test explicite |
| `web-check.mjs` | 149/149 | Imports, actifs, contrat fermé, simulation et cohérence de l’interface |

Les cinq suites moteur totalisent **108 tests ciblés**, dont cinq nouveaux ; ce n’est pas l’exécution de toute la suite moteur. Les dix nouveaux scénarios de navigateur ont aussi été lancés contre une copie isolée de l’ancienne interface `daa2564` : ils échouent tous (**0/10**). Le lot corrigé réussit les 39 contrôles, dont l’absence d’erreur JavaScript/console.

Les [preuves portables](evidence/20261027/portable-b875174/summary.json) conservent les journaux moteur et web, les empreintes des huit fichiers du commit et une synthèse des résultats UI. `ui-validation-summary.json` est explicitement une synthèse des sorties observées, pas un journal brut intégral reconstruit. Les sous-totaux des campagnes locale et Windows se recouvrent et ne s’additionnent pas.

## Campagne Windows et livrables

La [campagne Windows 40479609012](https://github.com/M4D135/pesto/actions/runs/40479609012) est **entièrement réussie** sur le commit `b875174`, le 27 octobre 2026. Toutes les étapes terminent avec succès, sans étape ignorée. Le workflow inclut désormais `LiveReadTests` et `web-business-check.mjs` pour vérifier les correctifs lors de la fabrication des candidats.

| Contrôle Windows | Résultat et portée |
|---|---|
| Moteur ciblé | **229 tests**, zéro échec ; inclut 24 `LiveReadTests` et 24 `UpdateTests` |
| Pont / compagnon de mise à jour | **15 tests / 30 contrôles**, réussis |
| Gardes du retour AD | **70 contrôles**, sans mutation AD |
| PowerShell 5.1 | 18 variantes métier et entrée du banc sans erreur de syntaxe ; 2 contrôles UTF-8 |
| Web : Chromium et statique | Maintenance 33, opérateur 41, métier 39, démo 9, accueil/login 28, statiques 149 : **299 contrôles** réussis |
| Accueil et saisie natifs | **5 + 16 contrôles** ; UAC et identifiants synthétiques |
| Démonstration PROD et DEV | Démarrage, fermeture et coexistence réussis ; 6 transitions et 44 refus d’API réelles par canal ; aucun profil ordinaire créé |
| Configuration PROD et DEV | **14 contrôles par canal**, dialogues de fichiers et service natifs, profils temporaires supprimés |
| Mise à jour PROD | Installation depuis ZIP et rollback explicite ; santé négative et restauration ; interruption et reprise |
| Mise à jour DEV | Installation depuis ZIP et rollback explicite |

Les quatre transactions utilisent deux **compilations réellement distinctes**, la base `de527313b98f30d52802ec6abd51804e12f8c298` et le candidat `b875174`. Les huit tentatives de santé sont consignées ; chaque scénario se termine sur la base restaurée. Les dossiers sources, les ZIP et la configuration sentinelle sont préservés. Les scénarios négatifs injectent des pannes dans ces transactions réelles ; ils ne changent pas les versions des exécutables pour simuler deux builds.

Le runtime WebView2 embarqué est **156.0.4314.42** ; l’hôte observe Windows `10.0.26100.0`. Les contrôles Chromium utilisent Playwright **1.62.1** et Chrome for Testing **151.0.7922.34**, comme les contrôles locaux. La configuration native couvre les dialogues de fichiers, leurs annulations et le service de création du pack ; la sélection positive du dossier et le parcours complet du bouton web restent à qualifier.

### Téléchargements et empreintes

| Livrable | Lien |
|---|---|
| Candidat PROD | [Pesto V2 PROD — b875174](https://github.com/M4D135/pesto/actions/runs/40479609012/artifacts/12723481580) |
| Candidat DEV | [Pesto V2 DEV — b875174](https://github.com/M4D135/pesto/actions/runs/40479609012/artifacts/12723720181) |
| Preuves Windows complètes | [Journaux, JSON et captures](https://github.com/M4D135/pesto/actions/runs/40479609012/artifacts/12723740186) |

Les artefacts GitHub expirent le **26 novembre 2026**. L’enveloppe téléchargée contient l’archive du candidat, à extraire pour obtenir `Pesto.exe` et `wad/`. Les sommes suivantes concernent les **ZIP candidats intérieurs**, pas les enveloppes GitHub :

| Élément | SHA-256 |
|---|---|
| ZIP PROD | `c0f4cf41c2c9d1f45cc2f46988e8067b4ebdada0b85cbfbdeda4046222cd1db0` |
| ZIP DEV | `2bd88cbc9f7237309e5a10efb0200664b160fdb9409dd52a1e6956b7ebadc305` |
| `Pesto.exe`, commun aux deux canaux | `981e67c8b3a3fc8a95ef3dd19a51d204a80e71348d075b2616ec842db0af7094` |

Les [preuves Windows conservées dans le dépôt](evidence/20261027/windows-b875174/README.md) comprennent les huit JSON natifs relus, les métadonnées des artefacts, les extraits de journaux et leur synthèse. L’archive complète des preuves a été téléchargée et son SHA-256 vérifié contre GitHub. Les gros packs binaires n’ont pas été retéléchargés localement : leurs empreintes viennent des preuves CI et des transactions natives, recoupées entre elles. Ce rapport est ajouté après la fabrication ; il n’est pas présenté comme déjà inclus dans les ZIP.

## Limites conservées

Cette reprise n’exécute aucune mutation sur le domaine de l’utilisateur ni sur les VM du laboratoire. Les preuves de renommage/retour et d’UAC réel sous le même compte restent celles du [rapport C14](VALIDATION-C14-20261026.md), et celles du déplacement restent liées à C9. Un test avec un pont de navigateur ou un fournisseur d’annuaire synthétique ne prouve pas une opération AD réelle.

Les qualifications externes du rapport précédent restent ouvertes, notamment la jonction/sortie positive, UAC sous une autre identité, UNC/SMB et concurrence intermachines, installation dans Program Files, acquisition depuis une release officielle, ODJ, CLI et Entra réels. Les packs conservent leur statut de candidats ; la V1 n’est pas remplacée.
