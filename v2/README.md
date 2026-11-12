# Pesto V2 — développement autonome

Pesto V2 reprend l’interface et la séparation hôte/pont/moteur de Domenia V2, avec les parcours métier de Pesto. Le code courant se trouve sous `v2/`, sur `master`. Les releases et les packs V1 restent indépendants.

## Utilisation

À partir de 2.0.10, un seul pack est publié : **LIGHT** (asset `Pesto_V2_PRODLIGHT_<version>.zip`). Il contient `Pesto.exe` et `wad/`, sans runtime WebView2 intégré. Le moteur est choisi au démarrage : Evergreen installé sur le poste, sinon le Socle WebView2 extrait dans `wad\runtime\webview2\`, sinon un message clair avec le lien de la release du Socle. Les [releases GitHub](https://github.com/M4D135/pesto/releases) fournissent le ZIP et `SHA256SUMS`. Les sources, tests et outils sont disponibles au tag de chaque release.

Le [guide de prise en main](docs/PRISE-EN-MAIN.md) décrit l’installation, la première configuration, la démonstration, les opérations sur un poste, les lots et la lecture des reçus.

Le pack LIGHT contient **`Pesto.exe` et `wad` à la racine**, .NET embarqué et le module Microsoft ActiveDirectory épinglé. Aucun Spark, OpenCode, SDK .NET ni PowerShell 7 n’est nécessaire pour l’exécuter. L’adaptateur Windows utilise Windows PowerShell 5.1 et le module livré ; RSAT n’est pas requis pour obtenir ce module. L’accès au domaine et les droits AD restent nécessaires aux opérations réelles.

Au premier lancement, Pesto importe automatiquement une configuration distribuée valide dans le profil de l’opérateur. Sans configuration distribuée, il ouvre les Paramètres. L’interface permet de créer/importer la configuration, la comparer, l’exporter et, avec le bouton **Définir comme configuration par défaut**, l’écrire dans `wad\defaults\configuration.json` de l’installation en cours. Depuis 2.0.14, aucun pack n’est recréé : ce fichier reste hors de l’identité du pack, comme le Socle, et un pack officiel reste officiel. Il contient le domaine et les OU : diffusez ce dossier comme un fichier privé et ne le publiez jamais. Le détail figure dans [la configuration](docs/CONFIGURATION.md#configuration-par-défaut-de-linstallation). Après une première configuration, **Reconnecter Pesto** ouvre explicitement la session AD. Au démarrage normal non élevé, Windows demande l’UAC immédiatement ; une annulation propose **Réessayer** ou **Fermer**. Sur un poste joint, le démarrage utilise ensuite l’identité Windows effective après UAC ; le choix du compte se fait sur demande avec Reconnecter Pesto. Hors domaine, Pesto affiche la fenêtre de connexion Pesto avec saisie native des identifiants AD. Une annulation laisse accessibles les Paramètres, sans adaptateur AD. Démonstration et Animations se trouvent uniquement dans **Paramètres**, section **Interface**. `Pesto.exe --settings` ouvre aussi ce mode local, sans élévation ni connexion AD. Une configuration illisible peut être réparée par un import confirmé avec sauvegarde exacte. Aucun mot de passe ne transite par l’interface web. Pour le renommage distant, choisir **Autre compte AD** ; les gardes de délégation V1 sont conservés.

Après la sélection du site et du service, Pesto lit les noms de la série dans le domaine et affiche un aperçu. Noms disponibles, Renommer et Ajouter ce PC au domaine utilisent la même convention. Si un autre opérateur prend le nom avant la confirmation, Pesto propose un nouvel aperçu à confirmer. Un résultat partiel ou incertain reste visible dans les reçus.

Le bouton **Démonstration** ouvre une autre fenêtre avec son propre profil WebView2 et un monde fictif. La fenêtre réelle reste ouverte. Bannière permanente, scénarios, remise à zéro et redémarrage fictif appartiennent uniquement à cette fenêtre.

Le parcours **Un poste → Attributs AD** prépare un diff explicite pour description, emplacement et responsable. La **jonction hors ligne** possède sa fenêtre locale dédiée (`Pesto.exe --offline-join`), sans connexion AD avant son contrôle explicite après redémarrage. Les lots disposent d’un mode pilote limité à la première ligne. La CLI du même EXE prépare des plans exportés puis les exécute avec double opt-in et clé idempotente.

Les mises à jour se préparent depuis Paramètres, à partir d’un ZIP, d’un dossier local ou d’un partage UNC ; Pesto ne contacte aucun serveur pour les chercher ou les télécharger. Le choix, la préparation et l’installation confirmée sont distinctes. Un helper copié depuis le même Pesto.exe gère transaction, santé isolée, rollback et reprise. Depuis 2.0.14, la configuration par défaut de l’installation est conservée par la mise à jour et par le retour arrière ; un pack source qui apporte une configuration par défaut différente est refusé sans remplacement.

Les paramètres préservent les brouillons pendant les réponses lentes. Enregistrer prépare une seule confirmation à la fois ; Relire demande avant d’abandonner une saisie. Une réponse de maintenance arrivée après navigation ne rouvre pas de dialogue sur un autre écran.

Les recherches de postes et les listes de file ignorent les réponses anciennes. Un retrait invalide immédiatement le plan préparé ; quitter la page interrompt la suite des ajouts. Les imports natifs refusent les encodages invalides et lisent au maximum 1 Mio hors du fil de la fenêtre.

## État et références

**État au 12 novembre 2026 : release publiée [v2.0.15](https://github.com/M4D135/pesto/releases/tag/v2.0.15), source `b7fd4c67a1da990dce588ab9dd161e06bd5bd683`, [campagne 43228752890](https://github.com/M4D135/pesto/actions/runs/43228752890).** Le pack publié est LIGHT. La 2.0.15 reprend la page Paramètres de Domenia 2 : bandeau d’état, rail de sections, une section à la fois et recherche de réglage ([écran Paramètres](docs/PARAMETRES.md)). Depuis la 2.0.14, la configuration par défaut s’écrit sur place, dans `wad\defaults\configuration.json` de l’installation, sans fabriquer de pack personnalisé ; ce fichier reste hors de l’identité du pack et suit les mises à jour et les retours arrière. Les releases antérieures à la 2.0.14 ont été retirées de GitHub le 12 novembre. Les corrections ultérieures présentes dans `master` sont des changements de source ; elles ne constituent pas une nouvelle release. La liste des sites/services du domaine réel et le démarrage sans Evergreen sur le Socle restent à qualifier sur le binaire exact.

### Archives de livraison antérieures à la recréation du dépôt

Les références ci-dessous conservent leur date, leur SHA et leur portée historique. Le dépôt GitHub a été recréé le 9 novembre : les anciens tags, commits et campagnes distantes peuvent ne plus être accessibles. Les rapports conservés ici ne qualifient pas automatiquement la source courante ni le pack LIGHT.

**Release officielle 2.0.9 : [v2.0.9](https://github.com/M4D135/pesto/releases/tag/v2.0.9), source `ee40af18458ae0bb604f02665a6f4e2df57d7378`, [campagne 41284549253](https://github.com/M4D135/pesto/actions/runs/41284549253)** — détection du poste hors domaine, motifs de refus affichés et journal de mise à jour plus robuste. Les tests Windows V2 et le contrôle après téléchargement sont réussis ; VM/AD restent non qualifiés ([rapport](docs/RELEASE-v2.0.9.md)).

**Release précédente 2.0.8 : [v2.0.8](https://github.com/M4D135/pesto/releases/tag/v2.0.8), source `aeb00259b3ef094e14c584559b788433aea38901`, [campagne 41104439245](https://github.com/M4D135/pesto/actions/runs/41104439245)** — en contraste élevé Windows, les choix cochés et les boutons pleins sont de nouveau visibles ([rapport](docs/RELEASE-v2.0.8.md)).

**Release précédente 2.0.7 : [v2.0.7](https://github.com/M4D135/pesto/releases/tag/v2.0.7), source `f954ca19d42678ca7c1c75c5d67bab90aa439b6b`, [campagne 41037119110](https://github.com/M4D135/pesto/actions/runs/41037119110)** — « Un poste » lit toujours ce poste et ne renvoie vers la jonction que s’il est absent de l’annuaire ; ne pas utiliser la 2.0.6 sur un poste joint ([rapport](docs/RELEASE-v2.0.7.md)).

**Release précédente 2.0.6 : [v2.0.6](https://github.com/M4D135/pesto/releases/tag/v2.0.6), source `0cbdf3a66ef243e6fda6d74b8d92b57861f058f4`, [campagne 41024785514](https://github.com/M4D135/pesto/actions/runs/41024785514)** — « Un poste » vise de nouveau ce poste par défaut, ou un autre poste du domaine au choix, comme en V1 ([rapport](docs/RELEASE-v2.0.6.md)).



**Release précédente 2.0.1 : [v2.0.1](https://github.com/M4D135/pesto/releases/tag/v2.0.1), source `062c59535e2e721ce2ee4c594b2935f56f3e7ba0`, [campagne 40823673562](https://github.com/M4D135/pesto/actions/runs/40823673562)** — correctifs d’interface et installation depuis les boutons qualifiée depuis la v2.0.0 publiée ([rapport](docs/RELEASE-v2.0.1.md)).

**Release précédente 2.0.0 : [v2.0.0](https://github.com/M4D135/pesto/releases/tag/v2.0.0), source `84d76fc022eb11172021447672cfde5381a2d4ea`, [campagne 40720801680](https://github.com/M4D135/pesto/actions/runs/40720801680).** Les ZIP PROD/DEV publiés sont les octets testés sous Windows (617 tests moteur, configuration 36/36 par canal, installation depuis les boutons, refabrication DEV, mises à jour PROD en place depuis `de527313`) et ont été revérifiés après téléchargement. Une installation DEV de `de527313` passe à 2.0.0 par **nouvelle installation** (refus explicite qualifié). Statuts : `official=true`, `distribution=official`, `qualification=unqualified` — **AD, UAC réel, UNC et retour depuis les boutons UI non qualifiés**. Détails et empreintes : [rapport de release](docs/RELEASE-v2.0.0.md).

**La release 2.0.0 n’est pas qualifiée AD.** Un test sur fixtures ou une compilation Windows croisée ne prouve pas une opération AD réelle ; la campagne VM finale reste à faire.

**Historique C18 réussi sur `2adf60e15f8f7d5fd808c0471a63e1fd4457cd90` :** la [campagne 40675773761](https://github.com/M4D135/pesto/actions/runs/40675773761) passe ses **25 étapes**, dont **616 tests moteur**, **250 gardes de restauration** et **16 suites navigateur**. Les confirmations individuelles affichent le plan sans recopie ; les lots conservent leur saisie de confirmation. Les reçus sont rapprochés du plan avant tout succès, et les reçus de simulation refusée/incertaine conservent la destination demandée. Les parcours natifs PROD/DEV, les transactions et l’installation depuis les boutons réussissent ; les sources DEV livrées sont recompilées avec le SDK 10.0.302 et le résultat démarre. Le [rapport C18](docs/VALIDATION-C18-20261028.md) conserve les preuves, leurs empreintes et l’échec initial du banc de reprise, corrigé avant la campagne finale.

**Historique C17 réussi sur `e087bb1` :** la [campagne 40513849690](https://github.com/M4D135/pesto/actions/runs/40513849690) valide l’installation confirmée depuis les boutons de maintenance en PROD et DEV, son retour distinct par le service et la recompilation depuis les seules sources du DEV livré avec démarrage natif du résultat. Elle conserve les suites complètes et les quatre transactions séparées entre builds. La préparation reste liée à la source choisie. Le [rapport C17](docs/VALIDATION-C17-20261027.md), actualisé après relecture des preuves le 28 octobre, distingue ces acquis du retour par bouton UI, de l’AD, de l’UAC et de l’UNC réels encore non qualifiés par cette campagne.

**Historique C16 du 27 octobre — candidat `3a8c49d` :** les lots conservent les types P/S/V observés et permettent de corriger par CSV un poste déjà sélectionné. Une identité incomplète bloque avant calcul du nom ; un reçu manquant, dupliqué ou contradictoire empêche un bilan entièrement confirmé. Les brouillons d’attributs et de paramètres sont protégés lors des relectures et de la navigation. Le moteur recontrôle la validité du plan après ses dernières lectures, puis exige le nom, le GUID et l’OU attendus pour confirmer le résultat. Les sources documentaires sont livrées dans DEV et les liens des guides sont adaptés au pack. Le [rapport C16](docs/VALIDATION-C16-20261027.md) détaille les corrections et leurs preuves.

Les [contrôles portables C16](docs/evidence/20261027/portable-d803d72/README.md) réussissent : suite complète moteur **615/615**, pont **15/15**, fabrication **46/46**, seize suites JavaScript/navigateur et douze contrôles DOM compilés. Le réassemblage du même PROD depuis l’arbre DEV est vérifié avec les mêmes entrées de publication et de runtime ; ce test ne recompile pas l’EXE depuis DEV.

La [campagne Windows C16](https://github.com/M4D135/pesto/actions/runs/40491875705) est **entièrement réussie sur `3a8c49d`** : suites complètes moteur/pont, fabrication, seize suites JavaScript, accueil et saisie natifs, démonstration, **36 contrôles de configuration par canal**, puis **quatre scénarios de mise à jour entre deux builds distincts**. Les boutons d’export/import, de création du pack personnalisé (parcours du bouton en vigueur jusqu’à 2.0.13) et d’inspection/préparation de maintenance passent avec deux sélections positives de dossiers. L’installation effective depuis le bouton de maintenance reste hors de ce parcours : sa confirmation est annulée, et les transactions d’installation sont testées séparément.

| Candidats historiques C18 | Téléchargement |
|---|---|
| Preuves Windows | [Journaux, captures et JSON](https://github.com/M4D135/pesto/actions/runs/40675773761/artifacts/12812880598) |

Les ZIP candidats C18 ont été retirés lors du nettoyage autorisé du 1er novembre ; les preuves Windows sont conservées. Utiliser la release actuelle pour télécharger l’application. Les [preuves C18 et empreintes](docs/evidence/20261028/windows-2adf60e/README.md) sont recoupées : trois enveloppes téléchargées et hashées, ZIP intérieurs et EXE contrôlés, sources web/DEV comparées au commit exact et vérification locale des deux packs réussie. Les packs restent `official=false`, `distribution=candidate`, `qualification=unqualified`. AD, UNC et UAC réels, profil ordinaire et retour depuis les boutons UI ne sont pas qualifiés par cette CI ; les essais du harnais de domaine ne qualifient pas ces ZIP.

Les deux incidents du banc C16 restent dans le rapport : [saisie de l’export](docs/evidence/20261027/windows-d803d72-failed/README.md), puis [contrôle de dossier](docs/evidence/20261027/windows-1dbdda1-failed/README.md), tous deux corrigés avant la campagne finale. Les [preuves C15](docs/evidence/20261027/windows-b875174/README.md) conservent leur binaire historique. Le guide C16 préparatoire est dans les packs ; le rapport final en ligne a été complété après leur fabrication.

**Historique C14 réussi sur `e5a6722` :** accueil sans slogan ni ascenseur, cinq contrôles natifs d’accueil et seize de saisie AD, démo/animations uniquement dans Paramètres. L’accueil déclenche l’UAC Windows ; après élévation, un poste joint conserve l’authentification Windows automatique, sinon Pesto demande le compte AD natif.

Les deux canaux passent la démonstration isolée, les 14 contrôles natifs de configuration et les transactions entre deux compilations : ZIP/rollback en PROD et DEV, santé négative/restauration et interruption/reprise en PROD. Les [preuves finales](docs/evidence/20261026/windows-e5a6722/README.md) et le [rapport C14](docs/VALIDATION-C14-20261026.md) précisent le périmètre, les empreintes et les incidents corrigés.

**Laboratoire historique C14 :** Le pack PROD GitHub exact de `e5a6722` passe accueil, saisie native AD synthétique, démonstration et configuration, puis une élévation UAC réelle depuis un parent non élevé, en session console 1. Les cinq parcours terminent avec code 0. Les bancs restent isolés du profil ordinaire et ne font aucun appel AD. Le renommage réel `P111301VA765158` → `P111301VA765586`, sa vérification après redémarrage et le retour au nom initial sont confirmés. L’inspection finale du 26 octobre à 17:41 UTC retrouve le même GUID, Paris, UAC4096, protection false, domaine et canal sécurisé sains, noms actif/configuré cohérents et aucun renommage en attente. Les cinq anciennes entrées V1 sont inchangées. Le déplacement Paris → Lyon → Paris reste lié au moteur C9 et à son rapport historique.

Archives historiques C14 : ZIP candidats retirés lors du nettoyage autorisé du 1er novembre ; [preuves Windows](https://github.com/M4D135/pesto/actions/runs/40368778290/artifacts/12671679566). Les packs restent `official=false`, `distribution=candidate`, `qualification=unqualified`. La jonction/sortie positive, l’élévation sous une autre identité, UNC réel, Program Files, acquisition depuis une release officielle et les autres parcours externes du rapport restent à qualifier. Aucune release V1 n’est remplacée.

Les [preuves historiques C5 de `de52731`](docs/evidence/20261025/windows-de52731/README.md) et les premières campagnes C6 restent attachées à leurs propres binaires ; leur chronologie est conservée dans le [rapport C6](docs/VALIDATION-C6-20261026.md).

- [Parité actuelle et limites fonctionnelles](docs/PARITY.md)
- [Release 2.0.9 : changements, empreintes et résultats](docs/RELEASE-v2.0.9.md)
- [Release 2.0.8 : contraste élevé, empreintes et résultats](docs/RELEASE-v2.0.8.md)
- [Release 2.0.7 : correctif, empreintes et résultats](docs/RELEASE-v2.0.7.md)
- [Release 2.0.6 : changement, empreintes et résultats](docs/RELEASE-v2.0.6.md)
- [Release 2.0.5 : changement, empreintes et résultats](docs/RELEASE-v2.0.5.md)
- [Release 2.0.4 : changement, empreintes et résultats](docs/RELEASE-v2.0.4.md)
- [Release 2.0.3 : changement, empreintes et résultats](docs/RELEASE-v2.0.3.md)
- [Release 2.0.2 : changements, empreintes et résultats](docs/RELEASE-v2.0.2.md)
- [Release 2.0.1 : changements, empreintes et résultats](docs/RELEASE-v2.0.1.md)
- [Recette VM AD réelle du 29 octobre 2026](docs/VALIDATION-VM-20261029.md)
- [Release 2.0.0 : empreintes, résultats et limites](docs/RELEASE-v2.0.0.md)
- [Validation C18](docs/VALIDATION-C18-20261028.md)
- [Index des preuves](docs/EVIDENCE.md)
- [Configuration et référentiels](docs/CONFIGURATION.md)
- [CLI et jonction non accompagnée](docs/CLI.md)
- [Jonction hors ligne locale](docs/OFFLINE-JOIN.md)
- [Packaging et mises à jour](docs/PACKAGING.md)
- [Contrat du pont](docs/BRIDGE.md)
- [Qualification Windows critique](docs/QUALIFICATION-WINDOWS.md)

Les anciens rapports sont conservés comme preuves datées. Ils ne qualifient pas les binaires reconstruits après leurs campagnes. LAPS, GLPI, tickets, multidomaine, PowerShell 7 obligatoire et signature applicative sont hors périmètre.
