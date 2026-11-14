# Finalisation de l’accueil et recette AD — 26 octobre 2026

Source du candidat : `e5a67227449e60ca8b91dc7a397a7671d51a6378`. Les archives finales, leurs empreintes et les preuves de la campagne Windows sont référencées dans la synthèse associée. Les rapports C9 et antérieurs restent historiques ; aucun pack V1 ni release officielle n’est remplacé.

## Connexion et interface

Le démarrage non élevé affiche l’accueil Pesto, avec le compte Windows courant et le bouton **Ouvrir Pesto**. Ce bouton demande l’élévation native UAC ; l’utilisateur confirme dans le dialogue Windows. L’application ne reproduit pas ce dialogue et ne recueille aucun mot de passe administrateur dans WebView. Le processus relancé vérifie son jeton réel. Un poste joint conserve l’authentification Windows automatique ; un poste hors domaine demande ensuite le compte AD dans la fenêtre native. Le changement explicite de compte et le mode paramètres restent disponibles.

L’accueil reprend les couleurs et composants visuels du produit, sans slogan ni ascenseur. Il adapte la disposition aux petites fenêtres, au thème clair/sombre et au contraste. Après erreur ou annulation, le canal fermé signale un changement de disposition ; l’hôte mesure lui-même son contenu et ajuste la hauteur à la zone utile de l’écran. Le navigateur ne fournit ni commandes, ni chemins, ni dimensions arbitraires. Les boutons restent visibles et une nouvelle tentative demeure possible.

La fenêtre native de saisie AD est compacte et recalcule également sa taille après un message. Son champ mot de passe reste natif ; le secret passe en mémoire protégée, avec effacement des buffers et du champ. Les tests synthétiques ne constituent pas une preuve de tous les cas d’authentification AD.

Les commandes de démonstration et le réglage des animations se trouvent uniquement dans **Paramètres**. Les préférences de la démo et celles de la session réelle restent distinctes ; le brouillon du parent est conservé.

## Preuves intermédiaires conservées

Sur le candidat local `3316a6b` (SDK Mac 10.0.401 vers Windows x64), le pack complet est vérifié dans PESTO-W11-TEST : 507 entrées SHA-256, EXE `f0498776fb1b5b2eeb4529024c2241a63b9693b0ed1c34529529ece656f509cf`. En session console 1 non élevée, accueil, saisie native, démo et configuration terminent tous avec code 0. L’accueil passe cinq assertions, la saisie native seize, et la configuration quatorze. La démo confirme ses six transitions et ses refus d’API réelles.

L’UAC réel est également observé : le bouton d’accueil ouvre le consentement Windows, puis le relais prouve le jeton administrateur, le PID, le nonce et le même hash d’exécutable. Les trois contrôles terminent avec code 0, sans accès au profil ordinaire ni appel AD. Cette preuve concerne une élévation sous le même compte ; elle ne qualifie pas un autre compte administrateur.

Deux incidents de banc sont conservés : le premier accueil produisait une preuve positive mais un code 2 dû à une double libération de fenêtre, corrigée par une fermeture idempotente ; le premier essai UAC utilisait un TEMP redéfini que le processus élevé ne retrouvait pas. L’essai réussi garde le TEMP Windows d’origine. Aucun de ces échecs n’est présenté comme une réussite.

La campagne GitHub `40364052689` de `3316a6b` est entièrement réussie : 203 tests moteur, 15 du pont, 30 du compagnon, PS5.1 syntaxe et aller-retour UTF-8, Chromium 33/41/9/28/149, accueil et saisie natifs, démo/configuration PROD et DEV. Quatre transactions de mise à jour relient deux compilations distinctes, avec huit reçus santé et sept lancements du helper. Ce binaire Windows porte l’empreinte `0229164f448a42b7c3268052a2ee7ade376ac57b8bcdccdedf26258aa37f8d85`, différente de la compilation locale. La correction suivante touche le harnais AD, ses tests et le workflow ; les sources de l’interface et du moteur métier sont inchangées.

## Renommage AD réel et retour

L’inspection initiale du 26 octobre à 17:00 UTC confirme `P111301VA765158`, le GUID `b4797c9c-d790-4797-bf71-424a57acb36e`, l’OU Paris, UAC4096, protection false et canal sécurisé sain. Le harnais `3316a6b` utilise une configuration synthétique du laboratoire et un compte AD explicite saisi dans CredUI.

Une seule demande produit renomme le poste en `P111301VA765586`. Le reçu `receipt-8c546d8c7460472e995bc369096ce8c4` est persisté en PendingRestart ; la réutilisation du plan consommé est refusée. La relecture indépendante confirme le même GUID, Paris et la protection d’origine. Les messages du nouveau reçu conservent correctement les caractères UTF-8 ; les anciens reçus mal encodés ne sont pas réécrits.

Après redémarrage séparé de la seule VM, la vérification explicite du reçu réussit à 17:12 UTC : nom Windows actif/configuré et nom AD cohérents, nouveau boot, canal sain, status succeeded et restartRequired false. Cette vérification n’exécute aucune mutation.

Le premier retour a été refusé avant réservation ou commande native parce que cinq interventions historiques V1 des 13–18 octobre portent encore PendingRestart. Le harnais assimilait tout historique en attente à une barrière active. La correction `e5a6722` conserve ces entrées et leur statut ; elle n’admet cette distinction qu’après validation complète du canari et du reçu courant, pour une origine V1 stricte, une date antérieure au boot et au reçu vérifié, et des anciens/nouveaux noms différents du nom actif. Toute ambiguïté, opération V2 en attente, état envoyé/incertain/partiel ou barrière brute non terminale reste bloquant. Les deux barrières GP sont relues sous mutex, puis immédiatement avant l’unique appel natif. Les 28 gardes d’identité, 20 contrôles de barrières brutes et 22 contrôles d’historique passent localement et dans Windows.

Une nouvelle invocation du harnais corrigé accepte le retour à 17:30 UTC, en une tentative native. Le reçu durable de qualification indique le nom AD et configuré original, le même GUID, Paris, UAC4096 et protection false. Il reste non rejouable ; son observation PendingRestart n’est pas falsifiée après le redémarrage.

Le redémarrage Windows de retour est resté bloqué plus de cinq minutes après l’arrêt du service invité. Les journaux ne montrent pas de nouveau crash du processus VirtualBox. Un diagnostic est conservé sur l’hôte, puis la seule VM PESTO-W11-TEST est réinitialisée à 17:37:54 UTC conformément à l’autorisation existante. Aucune opération Pesto n’était encore active ; la relecture du retour était durable avant cette action.

L’inspection indépendante finale termine avec code 0 à 17:41:58 UTC. Elle confirme le nom initial `P111301VA765158`, le GUID et l’OU d’origine, UAC4096 et protection false. Windows est joint au domaine, rôle 1, canal sécurisé sain, noms actif/configuré identiques et pendingRename false. La comparaison des cinq entrées historiques avant/après montre des valeurs intégralement inchangées.

## Paquets finaux et validation du même binaire

La [campagne 40368778290](https://github.com/M4D135/pesto/actions/runs/40368778290) de `e5a67227449e60ca8b91dc7a397a7671d51a6378` est entièrement réussie. Elle reprend les 203 tests moteur, 15 du pont, 30 du compagnon, les contrôles PS5.1/UTF-8, Chromium 33/41/9/28/149, les bancs natifs accueil/saisie/démo/configuration et les quatre transactions de mise à jour. Elle ajoute les 70 gardes du retour AD, sans appeler AD. Les trois enveloppes et les deux ZIP ont été téléchargés, puis leurs empreintes recoupées ; le pack PROD passe aussi la vérification fermée locale.

Le pack PROD GitHub exact de `e5a6722` passe accueil, saisie native AD synthétique, démonstration et configuration, puis une élévation UAC réelle depuis un parent non élevé, en session console 1. Les cinq parcours terminent avec code 0. Les bancs restent isolés du profil ordinaire et ne font aucun appel AD. L’installation conserve les 508 fichiers du pack, dont 507 entrées SHA-256 ; l’EXE `9e2f6eb2400d7d06d219d3a435d24f72b8dbf336120139153437313e703a5336` est identique à celui des archives. L’accueil passe cinq contrôles, la saisie native seize, la configuration quatorze, la démo six transitions et 44 refus. L’UAC réel passe trois contrôles : fenêtre prête, fermeture normale et jeton élevé avec PID/nonce/hash concordants. Le TEMP Windows d’origine est conservé.

La [synthèse finale](evidence/20261026/windows-e5a6722/README.md) contient les résultats et les empreintes. Archives GitHub : [PROD](https://github.com/M4D135/pesto/actions/runs/40368778290/artifacts/12671514909), [DEV](https://github.com/M4D135/pesto/actions/runs/40368778290/artifacts/12673057185), [preuves Windows](https://github.com/M4D135/pesto/actions/runs/40368778290/artifacts/12671679566). Les preuves complètes de la VM et de la séquence AD sont également livrées séparément, sans profils navigateur ni secrets. Les fichiers de qualification et le reçu de retour non rejouable restent conservés ; aucune donnée historique n’est supprimée pour rendre le tableau artificiellement vert.

## Limites de qualification

Les packs restent des candidats. La sortie/jonction positive n’est pas exécutée : le retour à l’objet AD d’origine après ce parcours n’est pas démontré. Aucun compte utilisateur ou machine partagé n’est réinitialisé, aucun contrôleur de domaine ni VM voisine n’est modifié ou restauré. Les preuves de déplacement Paris → Lyon → Paris restent celles du rapport C9.

Les cas externes non couverts restent distincts : élévation sous une autre identité, acquisition sur UNC réel ou release officielle, déploiement Program Files, sélection positive du dossier de pack, coexistence avec un parent connecté à AD, ODJ, CLI et Entra en environnement réel. Une réussite des bancs isolés ne vaut pas qualification générale de ces parcours.
