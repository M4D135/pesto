# Finalisation C9 — 26 octobre 2026

**Le candidat `fd522bd61765834f5b66609a372900ecd1ab4ac3` passe la campagne Windows et les bancs natifs démo/configuration dans la VM autorisée.** [Campagne 40339777991](https://github.com/M4D135/pesto/actions/runs/40339777991), [archives, empreintes et preuves](evidence/20261026/windows-fd522bd/README.md). Le [rapport C8](VALIDATION-C8-20261026.md) conserve ses échecs et ses binaires historiques.

## Corrections du banc et preuve d’erreur UI

Le pilote des dialogues attend maintenant une fenêtre, un champ et un bouton visibles et actifs, puis trois relectures exactes du chemin sur le même contrôle avant de valider. Il conserve les gardes de processus/propriétaire/titre/classe et exclut la barre d’adresse. Les observations enregistrent tentatives, longueur et délai, sans contenu de configuration ni secret.

L’essai intermédiaire `afa9ee7` a produit une preuve de configuration positive avec un code de sortie 2 : il reste un échec global. Le handler UI marquait déjà le processus en échec, mais cette information manquait à la preuve du banc. `fd522bd` conserve désormais la première exception UI et invalide explicitement cette preuve ; seuls type, HResult et noms de méthodes sont conservés, sans message ni arguments. La cause précise de l’exception de l’essai intermédiaire n’est pas connue. Le nouveau passage local puis le binaire exact GitHub terminent avec code 0 et sans exception UI enregistrée.

Ces changements touchent l’hôte et son banc. Le moteur et le harnais AD restent identiques à la source `483a8a3`.

## Windows CI et binaire exact en VM

Trois compilations sans avertissement ni erreur. Réussite de 201 tests moteur, 15 du pont et 30 du compagnon ; parsing PS5.1 de 18 variantes métier et du point d’entrée de qualification ; suites Chromium 33/41/8/149.

PROD et DEV passent démarrage, coexistence locale/démo, six transitions fraîches par canal, fermeture, 44 refus directs et les 14 contrôles natifs de configuration. Huit captures ont été relues. Les quatre transactions entre compilations distinctes réussissent, dont santé négative et interruption/reprise en PROD ; huit reçus santé et sept lancements du helper sont recoupés.

Le PROD GitHub exact a ensuite été contrôlé dans l’invité : 502 entrées SHA-256, manifeste et EXE `8ebec5a431361e380872a4e6803e8e35bc7a3b31f2b2fab7c0a86c6c1bec97c6`. En session interactive 1, non élevée, démo puis configuration réussissent avec codes 0. Aucun adaptateur AD n’est initialisé par ces bancs et les profils temporaires sont supprimés.

- Démo : 44 API refusées, six transitions, contexte du parent conservé, profils/instances/reçus distincts. Preuve SHA-256 `522ba6ab74e89abb7742744a1b2651e08f9fe012d8ee571743cd4e365257c823`.
- Configuration : 14/14, une écriture et trois relectures stables par chemin, import/export exacts, refus d’encodage invalide, annulations, pack personnalisé complet et conservation des profils/source. Preuve `3f0e9eb009c0b805ad94800839e87eb79c144c399b64045fcbb2164201537425`.

Le passage local précédent est conservé séparément : même source, compilation Mac SDK10.0.401 vers win-x64, EXE `ea249bb323ee03673e8d5b1046ec00ec9e55532616e7635c871350882064b43c`. Il ne vaut pas preuve d’identité avec le binaire GitHub compilé sous SDK10.0.302.

## Stabilisation du laboratoire

Deux crashes du processus VirtualBox associé à la seule VM PESTO-W11-TEST sont précédés de la même séquence : limite de l’ancien enregistrement atteinte, arrêt en erreur `VERR_WRONG_ORDER`, puis exception `VBoxC.dll+0x00030c46`. L’essai temporaire du contrôleur vboxvga n’a pas corrigé le problème et a été annulé.

À 14:00 UTC, l’ancien enregistrement est désactivé sur cette seule VM et vboxsvga rétabli ; les configurations et journaux précédents sont sauvegardés sur l’hôte. À 15:04 UTC, la même exécution est toujours active, sans nouvelle ligne de crash dans son journal. Cette observation ne garantit pas la fiabilité générale de VirtualBox. Aucun service hôte ni logiciel VirtualBox global n’est modifié ; VRDE reste désactivé, aucune VM voisine ni snapshot n’est restauré.

Le canal clavier distant initial perdait des touches : un texte fictif a reproduit une fin tronquée. Un canal COM cadencé, avec données sur stdin SSH en mémoire, a été vérifié sur des majuscules, chiffres et répétitions. Aucun secret n’est placé dans un fichier, un argument de processus ou une preuve de test. Le refus d’authentification intermédiaire est conservé ; les lectures et quatre refus AD réussissent après correction du canal.

## Périmètre restant

Les essais AD sont consignés séparément ci-dessous. Les bancs CI et démo/configuration ne qualifient pas les mutations AD, UNC réel, l’acquisition d’une release officielle, UAC sous une autre identité, Program Files, les ACL/DPAPI opérateur, ODJ, CLI ou Entra. La sélection positive du dossier de pack et la coexistence avec un parent connecté à AD nécessitent leurs preuves propres.

La sortie/jonction positive conserve son point d’arrêt : le retour vers le GUID AD d’origine n’est pas démontré. Aucun départ du domaine, reset de compte, remplacement d’objet AD ou restauration de DC n’est utilisé pour forcer cet essai.

Les ZIP PROD/DEV restent candidats et ne remplacent pas la V1. Les mises à jour de documentation sont poussées séparément ; les binaires testés ne sont pas réassemblés après ces éditions.

## AD réel — déplacement aller-retour terminé

Harnais séparé `e237d0062866f67b53dd3b68c197a84fc747f53b7cfff714b1c561f9b0557907`, construit depuis `483a8a3` ; sources métier inchangées jusqu’à `fd522bd`. Configuration synthétique du laboratoire, compte AD explicite dans CredUI, session console 1 élevée. La [synthèse AD](evidence/20261026/windows-fd522bd/ad-summary.json) lie chaque étape aux empreintes de ses preuves.

L’inspection initiale confirme BIOS de PESTO-W11-TEST, nom `P111301VA765158`, GUID `b4797c9c-d790-4797-bf71-424a57acb36e`, OU Paris, UAC4096, protection false et canal sécurisé sain. Les quatre refus attendus passent : join distant, rename sans aperçu, OU étrangère et confirmation incorrecte.

Après préparation relue, un déplacement vers Lyon réussit à 15:15 UTC : reçu `receipt-27b9b8668bc94cb9857175c29ebccfb7`, code30, phase durable Verified. Une nouvelle inspection à Lyon confirme le même GUID. Le retour via un nouveau plan réussit à 15:26 UTC : reçu `receipt-69bb29def30a4a8694f18a94ed46f16f`, code30, phase Verified. Chaque tentative de réutiliser le plan consommé est refusée. Les relectures indépendantes confirment OU, nom, GUID et protection.

L’inspection finale à 15:31 UTC confirme Paris, nom actif et configuré d’origine, GUID d’origine, protection false, UAC4096, domaine et canal sécurisé sains, aucun renommage en attente. Aucun redémarrage ni autre modification AD n’a été requis par cet aller-retour. Les reçus V1 existants restent intacts.

Un essai de lecture à Lyon a échoué avant toute lecture AD avec `credential.unavailable`, autour d’un changement d’affichage de la console. Son échec est conservé ; une nouvelle invocation en lecture seule a réussi, sans rejeu de mutation.

Les messages natifs des reçus de déplacement contiennent des caractères de remplacement : ce défaut d’encodage est identifié pour correction dans le lot suivant. Les codes, identités et relectures indépendantes sont cohérents ; cette preuve ne couvre pas le renommage, la jonction ni une qualification AD générale.
