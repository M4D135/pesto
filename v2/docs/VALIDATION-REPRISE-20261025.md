# Reprise directe GitHub — 25 octobre 2026

## Périmètre et provenance

Branche : `codex/pesto-v2-20261023`. Le head distant vérifié au début puis juste avant intégration est `7f6332f8816c7fee2917fb6b06d8a326b4074532`. Aucun commit plus récent n’était présent à ces deux lectures. Les fichiers non poussés du Spark ne sont pas intégrés à ce lot. Les modifications V2 ont été réalisées directement dans ce dépôt ; les releases et packs V1 n’ont pas été remplacés.

Ce rapport décrit les lots successifs de la reprise. Chaque campagne reste liée à son commit et à son binaire ; la matrice [PARITY.md](PARITY.md) décrit l’état courant. Les anciennes preuves GUI/AD de `VALIDATION-20261025.md` restent attachées à leurs anciens binaires. Elles ne qualifient pas les fonctionnalités ajoutées ici.

## Fonctions raccordées dans le premier lot e815af3

- Nom calculé et affiché avant l’action de jonction ; contrôle de disponibilité, nouvel aperçu après collision, identité et OU relues. Le lot CSV demande maintenant `renameMove` lorsque le site change. Le moteur normalise vers un renommage seul sur le même site et préserve une éventuelle sous-OU.
- Démonstration ouverte dans une fenêtre/profil distincts, bannière permanente, huit scénarios, remise à zéro, redémarrage fictif et IDs non réutilisés. Les API réelles sont refusées avant accès AD, SMB, HTTP ou dialogue natif, y compris par appel direct au moteur et aux services.
- Paramètres autonomes, export/import comparé, pack complet personnalisé généré par le bouton dédié. Nettoyage des secrets/sessions/historique/caches, conservation des politiques métier reconnues et du scénario structuré. Une clé de politique inconnue, mal nommée ou répétée est refusée.
- Configuration distribuée : import automatique sur profil neuf ; choix Remplacer/Conserver avec différences, sauvegarde et remplacement atomique sur profil existant ; décision liée au profil/version/empreinte. Les plans utilisent l’empreinte des octets réellement lus et refusent une modification concurrente.
- Référentiels : aperçu des ajouts/conflits/inchangés, résolution exhaustive, écriture atomique unique et absence de doublons ; aucun objet AD ou OU créé par l’import.
- Mise à jour officielle GitHub V2, dossier/UNC ou ZIP local ; inspection, préparation et installation confirmée distinctes ; journal durable, helper du même EXE, santé liée au nonce/hash/transaction, rollback et reprise. Les modifications externes sont préservées par refus.
- Séparation du profil opérateur et de l’identité AD. Le SID original est conservé sous UAC ; le compte AD se choisit dans un dialogue Windows, jamais dans le pont. Un LocalAppData redirigé ou non vérifiable est refusé avant import, plutôt que remplacé par celui de l’administrateur.
- Contrôle Entra local/distant avant renommage : diagnostic distant temporaire sous SYSTEM, authentification COM avec le compte AD de session, script de statut fermé, vérification d’identité/domaine/rôle/SID, traces durables et nettoyage relu. Un état hybride ou non prouvé refuse le renommage. Aucun `/leave`, reboot ni mutation métier n’est exécuté par le diagnostic.
- Politiques V1 IncidentMode, exclusions de noms/OU, scénario et borne des lots ; restrictions HKLM relues. Dernière vérification aussi dans l’adaptateur direct. Mutex GP, reçus avant envoi, protection restaurée et incertitude sans rejeu conservés.
- Délai du pont corrigé : les mutations engagées, copies longues et dialogues natifs attendent leur résultat réel ; le délai de lecture JS ne les abandonne plus après deux minutes. Une fermeture ou un refus tardif ne provoque aucun réenvoi.

## Contrôles portables exécutés

SDK officiel .NET **10.0.302**, conformément à `global.json`. Les bancs C# ci-dessous utilisent des fixtures et doubles déclarés. Aucun processus PowerShell/AD natif n’a été exécuté par ces tests sous Linux.

| Contrôle | Résultat | Preuve locale |
|---|---:|---|
| Build moteur/tests intégré | 0 erreur, 0 avertissement | `logs/build-engine-final-20261025.log` |
| Suite moteur intégrée | **332/332**, sortie 0 et synthèse complète exigée | `logs/engine-final-20261025.log` |
| Build pont/tests | 0 erreur, 0 avertissement | `logs/build-bridge-final-20261025.log` |
| Lecture/identité AD après correction finale | **21/21**, dont un nouveau cas (20 déjà couverts) | `logs/account-final-20261025.log` |
| Suite pont | **6/6** | `logs/bridge-final-20261025.log` |
| Contrôles web/contrat/provenance | **124/124** | `logs/web-final-20261025.log` |
| Interface DOM Chromium | **32/32** | `logs/web-dom-final-20261025.log` |
| Parcours métier Chromium | **25/25** | `logs/web-business-integrated.log` |
| Configuration/maintenance Chromium | **16/16** | `logs/web-maintenance-integrated.log` |
| Cycle de vie du pont JS | **11/11** | `logs/bridge-lifecycle-final-20261025.log` |
| Démonstration navigateur | **11/11** | Banc `tools/tests/demo-check.mjs` |
| Démonstration DOM | **8/8** | Banc `tools/tests/demo-dom-check.mjs` |
| Contrôle des espaces et conflits du diff | Propre | `git diff --check` |

La suite moteur intégrée contient notamment 18 cas de profil, 6 de conservation des politiques, 7 d’import référentiel, 12 de démo, 6 de frontière de services, 10 de politiques d’opération, 7 de diagnostic Entra distant, 17 de repli et 16 de mises à jour. Ces sous-totaux ne doivent pas être ajoutés aux 332.

Les tests de transaction injectent sept interruptions entre sauvegarde/remplacement/journal et deux interruptions du rollback. Ils refusent une santé booléenne sans preuve correspondante, une preuve périmée, un journal détourné ou lié, un pack modifié, une redirection HTTP hors origine et les ZIP dangereux. Ils vérifient aussi la conservation d’un cfg sentinelle pendant installation et retour.

Deux vrais défauts UI ont été reproduits puis corrigés : message de préparation conservé après annulation de destination du pack ; formulaire Paramètres non rafraîchi après remplacement d’une configuration distribuée. La suite maintenance finale est entièrement verte. Une dernière correction d’affichage distingue le domaine ciblé d’une connexion authentifiée et affiche le compte AD explicitement choisi ; son build est à zéro erreur/avertissement et les 21 lectures concernées ont été rejouées après cette correction, sans répéter les autres suites. Le banc des reçus autorise désormais la seule lecture initiale `configuration.status`, sans autoriser une écriture supplémentaire.

## Publication et runtime

L’EXE est publié self-contained single-file Windows x64. L’assemblage impose seulement `Pesto.exe` et `wad` à la racine ; DEV contient également sources/tests/outils et dépendances vendored sous `wad/dev`. Le runtime Microsoft réel est distinct du runtime factice explicitement utilisé par `pack-check`.

Runtime fixe Microsoft : **156.0.4314.42 x64**, 257 fichiers extraits depuis le CAB officiel.

- SHA-256 CAB : `cb4612ce79a62a0be094301a72f73cf91bb250f5e83dc51886f66a083fc0694f`.
- SHA-256 `msedgewebview2.exe` : `337a496fffec9940ef7142e67162f80e40c878cb8fc2af66e5bd9aa75ffcdbae`.
- Source : `https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/074c0930-36ad-4756-9d04-dfe0e503bd94/Microsoft.WebView2.FixedVersionRuntime.156.0.4314.42.x64.cab`.

Les résultats d’assemblage et les identités des packs sont consignés dans la section de preuves de publication ci-dessous. Aucune vérification Authenticode native n’est revendiquée depuis Linux. Les packs restent `distribution=candidate`, `official=false`, `qualification=unqualified`. Le bouton de personnalisation produit ensuite `distribution=custom`, jamais une release officielle.

## Qualification Windows et AD

Le workflow V2 construit les candidats et exécute un smoke natif isolé pour PROD et DEV. Il exige un vrai chargement WebView2, une fermeture normale, 21 refus directs d’API réelles en démo, absence de création du profil réel sentinelle, et des preuves JSON portant les hashes exacts. Il conserve les preuves et les ZIP candidats comme artefacts, sans créer de release.

Le premier run [40216990717](https://github.com/M4D135/pesto/actions/runs/40216990717) est **réussi**, attaché au commit poussé `e815af35bada17947b2eb2b20a4b95e43fe0e7e9`. Sur Windows NT `10.0.26100.0`, les preuves natives PROD et DEV confirment `ready=true`, `closeReturned=true`, `blockedDirectApis=21`, `hostInvocations=0`, `realProfileCreated=false`, `success=true`. Elles restent `adQualification=false` et `binaryUpdateQualification=false` : ce smoke ne qualifie pas UAC avec un autre compte, le démarrage d’une session AD normale, COM distant, un partage UNC ni un remplacement binaire natif.

Le rebond du laboratoire a été testé **après le push**, uniquement avec la commande `hostname` prévue après connexion SSH. L’accès à `192.168.1.173:22` a répondu **Connection refused**, exit 255. Aucune session n’a été ouverte, aucune VM modifiée et aucune opération AD tentée. Le canari réversible, son retour et le contrôle Entra distant restent donc non qualifiés.

Le banc natif de mise à jour isolée est ensuite exécuté dans le run [40220687266](https://github.com/M4D135/pesto/actions/runs/40220687266), sur le commit **`6d9329c0f42f5e4338feb37df0c49b102d3d1cd3`**. Cette campagne est **réussie** : démarrage/fermeture et 21 refus directs en démo PROD/DEV, installation réelle sur copie PROD puis rollback explicite, santé candidate négative puis rollback automatique, et interruption observée pendant la santé WebView2 puis reprise. Chaque scénario conserve deux tentatives de santé distinctes. Le pack source et la configuration sentinelle restent identiques. Les [preuves JSON originales et leurs empreintes](evidence/20261025/windows-6d9329c/README.md) sont conservées dans le dépôt ; les trois campagnes précédentes échouées du moniteur restent également documentées.

Le binaire testé de cette campagne porte le SHA-256 **`bf91f1d132415efeb1794164306dc9626ff775a4568cacf8e9a56b0e90f12710`**. Les versions de manifeste des trois scénarios sont synthétiques (`2.0.0.100`, `.101`, `.102`) et emploient le même EXE. La transaction Windows est prouvée sur ces copies, mais pas le passage entre deux EXE indépendamment compilés, un partage UNC réel, UAC avec un autre utilisateur ni les droits de Program Files. `adQualification` reste faux. Les changements postérieurs à `6d9329c` exigent une reconstruction et une nouvelle campagne native.

## Preuves de publication locale et première CI

Publication croisée finale : sortie 0, self-contained/single-file, aucun DLL applicatif adjacent ; **62 empreintes de sources identiques** avant/après l’assemblage. Le `pack-check` est **35/35**. Les packs locaux ont passé le validateur Node et le validateur du moteur C#.

| Pack local | Fichiers | Octets | SHA-256 de `wad/SHA256SUMS` |
|---|---:|---:|---|
| PROD | 341 | 825 282 911 | `5dd7bed8468a80c625973ab12a7ee13a4a8a0afb1de6f29efcac391c525b5a9b` |
| DEV | 552 | 840 679 523 | `dee532002a34b1ea9cf49b645b489fc76605e51052c7109d055966594178652a` |

Leur EXE local est `3dcbe0dfbc5a7374efaefc72248b4d0630acf86dc651c88450e70ac8828f602f` (118 131 015 octets). L’intégralité des **257 fichiers** de chaque runtime a été comparée au CAB Microsoft épinglé. Des copies partielles externes apparues dans les premiers dossiers de travail ont été préservées et excluent ces premiers dossiers des livrables ; les packs retenus ont été reconstruits dans des destinations isolées depuis une extraction neuve du CAB vérifié. Aucun fichier concurrent n’a été supprimé ni ignoré pour faire passer un inventaire.

La CI Windows a reconstruit depuis le commit `e815af3` ; son EXE testé est **`6c3ef1cd514fd148e86f2197172c7f91dcb3416d308762203035533d54f53841`**. Il ne doit pas être confondu avec le binaire de compilation croisée.

- [PROD candidat du run e815](https://github.com/M4D135/pesto/actions/runs/40216990717/artifacts/12608167423) ; ZIP intérieur SHA-256 `cc1e619b06f5abb421b87eb578e4b3b6ad06da9b58ab23ee121506a686b9b9e5`.
- [DEV candidat du run e815](https://github.com/M4D135/pesto/actions/runs/40216990717/artifacts/12608326838) ; ZIP intérieur SHA-256 `f69959a358070f5a74189fc7cf76db576db0ea696f42663e961a8b254cab4bee`.
- [Preuves natives e815](https://github.com/M4D135/pesto/actions/runs/40216990717/artifacts/12607827970), également recopiées en [texte dans le dépôt](evidence/20261025/README.md).

Ces artefacts sont des candidats historiques conservés trente jours par GitHub, pas des releases. Ils précèdent la correction du bundle AD : leur démarrage/démo est prouvé, mais ils n’embarquent pas encore le module AD autonome. Les validateurs courants les refusent comme incomplets. Aucune release V1 n’a été modifiée.

## Correctifs après la première campagne Windows

L’examen du pack a révélé une dépendance AD restée à l’emplacement V1 : le profil AppData normal ne possédait pas le module. L’assembleur livre maintenant exactement les six fichiers Microsoft déjà versionnés dans `DEV/wad`, sous `wad/runtime/activedirectory`. Le resolver préfère ce dossier près de l’exécutable, sans lire la configuration pour trouver du code. Les six empreintes sont épinglées ; un bundle présent mais incomplet/altéré est refusé, sans repli silencieux. Les validateurs Node et C# refusent aussi les ajouts, suppressions ou altérations après recalcul des sommes. Aucun import de module ni appel AD n’est ajouté à la démo ou à la santé.

Le contrôle de santé conserve désormais un reçu atomique par nonce sous `health-attempts`. Un échec du candidat, le contrôle du rollback et une tentative interrompue restent distincts et liés à la transaction, à la version et au hash EXE. La reprise conserve la tentative inachevée avant de lancer le contrôle suivant. Les critères d’acceptation du contrôle de santé restent stricts.

Les builds moteur/tests, hôte Windows et banc de qualification réussissent sans avertissement ni erreur. Les suites ciblées passent : **module AD 2/2 ; transactions 20/20 ; profils 18/18 ; référentiels 7/7 ; auto-test du banc 10/10 ; packaging 42/42**. Les journaux originaux sont dans [l’index des preuves](evidence/20261025/README.md). Ce contrôle du packaging utilise l’EXE de compilation croisée précédent comme entrée, sans lui attribuer les modifications C# nouvelles. Le workflow reconstruit le nouvel EXE avant toute qualification native.

Le banc Windows utilise des copies complètes du vrai pack PROD dans un dossier Temp neuf : installation et retour explicite, page candidate volontairement invalide et retour automatique, puis interruption observée pendant le contrôle réel WebView2 et reprise. Il vérifie les identités PID/démarrage/chemin avant toute action sur un processus, et n’acquitte le dialogue du helper qu’après un état terminal durable. Une frontière non observée ou un reçu manquant produit un échec de qualification, jamais un succès synthétique. La configuration sentinelle et le pack source doivent rester identiques. Il ne qualifie pas AD, UAC inter-utilisateur ni un partage UNC réel.

## Lot de politiques métier après 6d9329c

Le code normal raccorde désormais la coordination partagée compatible V1, les baux de nom, les réservations AD avec reprise/retrait confirmés, les groupes exclus imbriqués, la mesure horaire et l’audit EventLog. Les paramètres et panneaux sont reliés à des API fermées. Les huit nouvelles API de coordination/réservation sont refusées dès l’entrée en démo ; le smoke natif courant attend donc **29 refus**. La preuve native historique de `6d9329c` reste à 21 et n’est pas attribuée rétroactivement à ce lot.

La configuration est lue une seule fois en octets bornés : modèle et SHA-256 décrivent le même instantané. Le worker natif revérifie cette empreinte sous le mutex GP et conserve le fichier protégé pendant l’action. Son processus PowerShell appartient à un Job Object non hérité avant le premier octet de demande sur stdin ; une sortie du parent ne laisse pas un nouveau worker poursuivre après libération du mutex. Cela n’annule jamais une commande déjà acceptée côté AD : son résultat reste incertain et non rejoué.

Le démarrage Windows servant aux réconciliations vient de Kernel-General, événement 12, champ `StartTime`. Une correction de l’horloge ne doit pas être prise pour un reboot. Le lecteur d’historique valide le format réellement écrit par l’adaptateur, y compris les nouvelles métadonnées et leur liaison au reçu ; les champs inconnus restent refusés. Cette vérification a détecté puis corrigé une incompatibilité de relecture après redémarrage avant le push.

| Contrôle de ce lot | Résultat | Preuve |
|---|---:|---|
| Suite moteur intégrée après correction du lecteur | **431/431** | `logs/engine-policies-final-20261025.log` |
| Build moteur/tests | 0 erreur, 0 avertissement | `logs/build-engine-policies-final-20261025.log` |
| Build hôte Windows et banc de qualification | 0 erreur, 0 avertissement | `logs/build-app-policies-final-20261025.log`, `logs/build-harness-policies-final-20261025.log` |
| Auto-test portable du banc | **10/10** | `logs/harness-policies-final-20261025.log` |
| Pont fermé C# | **8/8**, build 0 erreur/avertissement | `logs/bridge-policies-20261025.log` |
| Panneaux coordination et réservations, Chromium | **17/17** | `logs/policy-ui-final-20261025.log` |
| Paramètres et maintenance, Chromium | **18/18** | `logs/web-maintenance-check-policies-20261025.log` |
| Parcours métier, Chromium | **25/25**, puis **2/2 ciblés** après ajout de l’annonce de réservation AD | `logs/web-business-check-policies-20261025.log`, `logs/business-reservation-final-20261025.log` |
| Contrats web et provenance | **132/132** | `logs/web-check-policies-final-20261025.log` |
| Cycle de vie du pont JS | **13/13** | `logs/bridge-lifecycle-check-policies-final-20261025.log` |
| Démonstration navigateur | **11/11** | `logs/demo-check-policies-final-20261025.log` |

Les 2 contrôles métier ciblés ne représentent pas une nouvelle exécution des 26 cas en une seule invocation. Les suites se recouvrent et ne s’additionnent pas. Les **178 empreintes de sources/tests C#** sont identiques avant/après la vérification intégrée. Les [journaux originaux et leurs empreintes](evidence/20261025/policies/README.md) sont versionnés. Les tests C# et Chromium de ce lot n’ont émis aucune opération AD/SMB réelle. Les preuves natives restent attachées au commit et au binaire exacts de leur campagne.

## Campagne Windows du lot de politiques b7e781f

Le run [40222575362](https://github.com/M4D135/pesto/actions/runs/40222575362), attaché au commit **`b7e781f474eb2ce2a9103445ce0169f87f1fbbf0`**, est réussi sur Windows NT `10.0.26100.0`. Le binaire testé porte le SHA-256 **`b1c27d677a6a302abeabf5ebec31a513a0bffb39cbb0a8b648f6dba2d3a877af`** ; l’empreinte du pack PROD source est `7f5d642e704c474858a15571b2b112aba861355e109fdd9534ae41458cd718cb`.

Les deux packs confirment démarrage WebView2, fermeture normale, **29 refus directs** d’API réelles, zéro invocation de l’hôte réel et absence de création du profil sentinelle. Le banc natif PROD confirme de nouveau les trois scénarios : installation puis rollback explicite ; santé candidate négative puis rollback automatique ; interruption observée pendant le contrôle WebView2 puis reprise. Chaque scénario conserve deux tentatives de santé distinctes, avec pack source et configuration sentinelle inchangés.

Les [40 fichiers de preuves originaux](evidence/20261025/windows-b7e781f/README.md), soit 62 733 octets, sont conservés sans réécriture de leur contenu. Les archives restent des candidats GitHub, pas des releases. Comme dans la campagne précédente, les versions de manifeste de transaction sont synthétiques et utilisent le même EXE ; cette preuve ne couvre pas deux EXE indépendamment compilés, UNC, UAC avec un autre compte, Program Files ni une opération AD. `adQualification` reste faux.

## Limites fonctionnelles constatées à la fin de b7e781f

Ce lot n’est pas présenté comme une parité V1 absolue ou une V2 qualifiée pour la production. Le lot de politiques suivant porte les chemins de coordination partagée, exclusions de groupes imbriqués, réservations partagées et AD, audit EventLog et contrôle horaire. Ces fonctions ne sont plus des intentions documentées ; leurs fournisseurs natifs, journaux, gardes et parcours UI sont présents. Leur exécution AD/SMB/Windows reste à qualifier séparément.

L’audit complémentaire retrouve des parcours V1 encore non portés à ce stade : réconciliation et continuation distantes du résultat 89, acquittement motivé, retrait Entra explicitement autorisé avant renommage hybride, redémarrage réel confirmé, jonction d’un compte précréé hors réservation Pesto, CLI/double opt-in non accompagné, attributs AD et jonction hors connexion. [PARITY.md](PARITY.md) distingue ces écarts fonctionnels des exclusions définitives et des limites de recette. La présence d’une clé de configuration conservée ne vaut pas implémentation de son effet.

À ce stade, le renommage distant exige le choix explicite « Autre compte AD » ; le jeton Windows seul ne fournit pas le mot de passe à déléguer, et les gardes V1 correspondants sont maintenus. Les postes hybrides Entra sont alors refusés au renommage. Les évolutions du lot suivant sont décrites ci-dessous, sans attribuer ses chemins natifs à la campagne b7e781f. La redirection LocalAppData n’est pas prise en charge ; Pesto bloque avant initialisation lorsque le chemin observé diffère du profil enregistré dans HKLM. Le transport COM et son nettoyage effectif doivent encore être qualifiés sur une cible Windows.

Exclusions définitives inchangées : LAPS, GLPI, tickets, multidomaine, PowerShell 7 obligatoire et signature applicative.

## Lot opérateur après b7e781f

Ce lot ajoute cinq parcours effectifs, avec API fermées et interface raccordée : jonction sur un compte AD précréé, acquittement motivé, redémarrage réel explicitement confirmé, retrait Entra explicitement autorisé avant renommage hybride, et preuve Windows distante servant à la réconciliation et à la continuation limitée du résultat 89.

Le compte précréé conserve son GUID et son OU ; son nom est visible avant Ajouter et aucun `AccountCreate` n’est permis dans ce mode. L’acquittement écrit un événement séparé lié aux octets exacts des reçus, sans modifier les effets ni les liens parent/enfant. Une copie V1 et son registre peuvent recevoir la même décision V2, sans réécriture des fichiers V1. La sélection du registre de coordination privilégie le reçu qui possède effectivement les clés.

Le redémarrage a un plan de deux minutes distinct du plan métier, une confirmation du nom Windows courant, une demande durable avant envoi et un blocage de répétition sur le même boot. L’acceptation laisse le reçu métier en attente. Une première jonction peut encore être observée en workgroup avant son reboot : ce fait n’est pas changé en appartenance fictive ; il n’est admis que s’il correspond à la baseline initiale, au MachineGuid, aux noms et au boot enregistrés. Un ancien reçu sans ces preuves reste refusé.

Le retrait Entra exige une observation fraîche, la politique `HybridOnly` et une case de consentement distincte. L’intention locale et le journal cible précèdent l’unique `/leave`. Le résultat doit être relu ; un retrait confirmé reste visible si le renommage échoue ensuite. Une interruption conserve une barrière. « Vérifier l’état » peut demander un nouveau diagnostic en lecture pour prouver la terminaison du worker, mais ne relance pas le retrait et ne transforme pas un résultat incertain en succès. La preuve Windows distante utilise une tâche SYSTEM sans déclencheur et un fichier de résultat fermé, borné et lié au nonce ; les octets sont conservés localement avant nettoyage du seul fichier possédé.

La file reprend la sémantique V1 pour les machines indépendantes : un résultat accepté en attente de redémarrage ne bloque plus à lui seul toutes les lignes suivantes. Les refus et incertitudes arrêtent la file ; chaque reçu en attente demeure non vérifié. Les chaînes/cycles entre noms et les autorisations déjà expirées en fin de préparation sont refusés. Aucune continuation n’invente de nom de substitution.

### Défauts détectés avant publication du lot

La revue des chemins natifs a trouvé une limite de transport qui n’était pas couverte par le smoke démo : le script de mutation complet représentait environ 100 560 caractères en `EncodedCommand`, au-delà de la limite de commande Windows. Le moteur et les workers de réservation/Entra locaux utilisent désormais un bootstrap court contenant le SHA attendu du script compilé ; le script exact puis les données sont transmis dans stdin après attache au Job Object. Une substitution de script est refusée. Les commandes des tâches Entra distantes sont bornées avant leur enregistrement. Les premiers lots n’avaient pas été qualifiés sur une opération AD réelle ; leur preuve de démarrage/démo/mise à jour n’est pas étendue à ce transport métier.

Une revue croisée a aussi corrigé la projection d’un acquittement disque sur une ancienne phase du reçu en mémoire, la détection d’une OU/identité modifiée après une jonction précréée et le choix du registre V1 lors du nettoyage des verrous après acquittement. Les nouvelles confirmations recontrôlent le contexte après le dialogue ; changer le poste ou la destination ne permet pas d’envoyer l’ancien plan.

Le workflow Windows analyse désormais les sources PowerShell effectivement générées avec le parseur **Windows PowerShell 5.1**, sans exécution de script métier. Cette vérification est distincte de la compilation C# et de la qualification AD. Le smoke natif reconstruit du lot exige **34 refus directs** en démo. Les preuves natives de b7e781f, avec 29 refus, restent historiques.

Les parcours CLI/non accompagnés, attributs AD et jonction hors connexion restent identifiés séparément comme travail de port dans la matrice de parité. Le laboratoire AD est toujours non qualifié à ce stade ; la tentative de connexion et ses limites sont conservées ci-dessus.


### Vérification intégrée du lot opérateur

Après correction des fixtures Entra, des capacités et des assertions de plateforme, la suite moteur termine à **519/519**. Les builds moteur/tests, hôte Windows et banc terminent chacun avec **0 erreur et 0 avertissement** ; l’auto-test portable du banc réussit **10/10**. Les **194 empreintes de sources C# et projets** restent identiques pendant la campagne, puis sont revérifiées avant publication.

| Contrôle complémentaire | Résultat |
|---|---:|
| Pont fermé C# | **11/11** |
| Parcours opérateur Chromium, confirmations et barrières | **32/32** |
| Parcours métier Chromium | **29/29** |
| Paramètres et maintenance Chromium | **18/18** |
| Reprise Chromium | **23/23** |
| Contrats web et provenance | **137/137** |
| Cycle de vie du pont JS | **21/21** |
| Démo navigateur | **11/11** |

Les [journaux originaux et leurs empreintes](evidence/20261025/operator/README.md) sont versionnés. Les suites se recouvrent : ces nombres ne représentent pas un total de scénarios indépendants. La compilation croisée et les fixtures portables ne qualifient aucun accès AD/SMB, retrait Entra ou redémarrage réel.

Le redémarrage limité du résultat 89 est une action séparée après preuve du renommage et maintien de l’OU source ; il conserve le résultat partiel et ne lance pas le déplacement. Les codes 32/97 restent refusés. Son admission relit configuration, mode consultation, politiques et exclusions avant l’envoi, et fixe l’empreinte de configuration d’autorisation distinctement de celle du reçu d’origine. L’acquittement administratif reste possible en mode incident comme en V1, mais il est refusé en consultation et ne change jamais un effet incertain en succès.


### Échec natif 9f2147e et correctif de syntaxe PS5.1

Le run [40227090418](https://github.com/M4D135/pesto/actions/runs/40227090418), commit `9f2147e8e350544cea73eea58a9dc961c16765ae`, a compilé les assemblages Windows mais a échoué dans le contrôle syntaxique. Les étapes de packaging, démarrage et transaction ont été sautées : aucune qualification native ne leur est attribuée.

Le parseur a révélé deux défauts de sources : des apostrophes typographiques dans des chaînes PowerShell à quotes simples, que PowerShell traite comme délimiteurs, et des opérateurs `-or` placés en début de ligne sans continuation valide. Un défaut du banc enveloppait également le tableau renvoyé par `ConvertFrom-Json` dans un second tableau en PowerShell 5.1, concaténant les treize sources dans une seule analyse. Le correctif échappe les apostrophes, conserve les opérateurs sur la ligne précédente et analyse chaque élément séparément. Il ne modifie aucune règle métier.

Une copie isolée du commit 9f2147e avec uniquement les fichiers de ce correctif compile sans erreur ni avertissement et passe **519/519** tests moteur. Les sources C5 simultanément en développement ne font pas partie de cette vérification ni de ce correctif. La nouvelle exécution du parseur PowerShell 5.1 reste requise sur le commit corrigé.

Le bootstrap court conserve aussi un marqueur fixe `Pesto compiled worker` reconnu par le contrôle natif des processus actifs. Le passage du script complet vers stdin ne peut ainsi rendre un worker invisible à la barrière d’acquittement. Le test de transport compare les vrais bootstraps au vrai motif du scanner natif.
