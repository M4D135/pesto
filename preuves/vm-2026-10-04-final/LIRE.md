# Campagne finale du 4 octobre 2026

Branche `cloud/points-suite`, base `75bbfb6` puis correctif UAC de ce lot. VM exclusivement `PESTO-W11-TEST`, Windows 11 build 26200, Windows PowerShell 5.1.26100.6584 Desktop. Compte temporaire `PestoFinal` (administrateur local), lancement interactif non élevé. Aucun mot de passe de labadmin modifié ni secret archivé. Contrôleur de domaine et autres VM non modifiés.

## Correctif et preuve UAC (recette 2.9, O7)

- Ancien EXE `8fd5bd8cf914058f1f0b84a95f43536ff91c4dc2718c6c67f411bb24b7fd7ca0` : vrai clic Non, puis « démarrage impossible » et diagnostic natif, code 1. `uac-refuser-*`, `uac-refus-erreur.png` et arbre. Le cmdlet PS5.1 `Start-Process` perd le code Win32 1223.
- Nouveau EXE `aed2be1900b45d380ac95f360daaf770b613c047e4d1a80f5bea07e24722d782` : `Process.Start`, `UseShellExecute=true`, `Verb=RunAs`, même PowerShell absolu et arguments, interrogation des exceptions internes inchangée.
- `uac-refuser-corrige-fin.json` : vrai clic Non, code 1223 à 18:51:48. Aucun reçu associé (`nettoyage.json`).
- `uac-accepter-corrige-fin.json` : vrai clic Oui, code 0 à 18:54:04 ; `pesto-uac-sonde.png` : UAC_OK, Admin=True, RelaisEleve=True ; reçu `Pesto-sonde-uac-2749d5c4890b4fe392340089cf669501.txt`.
- Captures `pesto-uac-*.png` obtenues par `VBoxManage controlvm ... screenshotpng`, réponses par `keyboardputscancode` après observation : Entrée sur Non ; flèche gauche puis Entrée sur Oui. Autorisation actuelle de David (« fais-le toi », puis « termine »). Aucune politique UAC désactivée. `VERIFIER_UAC.cmd` est lancé par un processus console filtré, piloté par la tâche interactive.

**Tentative non concluante conservée :** `uac-accepter-*` sans `corrige` n’est PAS une preuve d’acceptation ni de 2.12. Elle démarre avant la fermeture des diagnostics du premier refus ; seconde instance 128 et code du vérificateur 1. Le champ `InviteVue=true` est le drapeau de déblocage du pilote, pas la constatation d’une nouvelle UAC dans cette tentative (`uac-accepter-vue.txt` le précise). Seuls les deux cas `*-corrige-*` sont concluants.

La sonde s’arrête avant le moteur et la reprise d’état : pas de preuve de démarrage connecté, de transfert entre comptes ou d’opération AD.

## Contrôles et interface

- `startup-tests.json` / `.txt` : 30/30 sous 5.1. Enveloppe de l’erreur native 2 réellement exercée, distincte de 1223 ; autres cas d’élévation simulés. Vraie UAC prouvée séparément ci-dessus.
- `validate-final.json`, `validate-final-outil-actuel.txt` : 407/407, vrai parseur 5.1, 66 scripts. `validate-final.txt` conserve un premier passage à 409 avec une ancienne copie du validateur (incluait les `.ps1xml`). Seul le rapport à 407 utilise l’outil courant. Copie normalisée LF du JSON dans `DEV/tests/pesto-portable-validation.json`.
- Tests Python ciblés du lot : 7 cas sonde, 9 cas codes de sortie (16/16). Revue Spark sur le diff et les fichiers complets obtenue ; vérification indépendante par Codex et preuves Windows.
- `x5-onglet-actif.png`, `x5-onglet-arbre.txt`, `x5-onglet.txt` : onglet Apparence actif et menu Paramètres bordés en couleur système Highlight ; `x5-onglet-retour.png` montre le retour au thème clair. Flags du contraste restaurés de 127 vers 126.
- `clavier-natif-ctrl1..4.png` et arbres : Un poste, Noms disponibles, Journal, Ajouter au domaine. Les fichiers `clavier-ctrl*` viennent d’un essai perturbé par le ALT simulé du pilote et ne sont pas des preuves d’échec produit. P8 traité en documentant les raccourcis existants, pas en ajoutant Ctrl+Tab.
- `display-arbre.txt`, `dpi-erreur.txt` : tentative de sélection d’échelle Windows non concluante (élément non retrouvé) ; aucune échelle modifiée. Les échelles 125–200 %, RDP et lecteur d’écran ne sont pas validés.

## Mise à jour et interruption (5.5, 5.6)

Archive RC23 originale : SHA-256 `3bc648ae2fde076946895f7fd018dea6ace90d8540d6263d529fb04de5a61699`. Extraction neuve dans chaque copie de test. Les configurations, journaux et reçus sentinelles servent uniquement à mesurer la conservation octet pour octet ; ils ne proviennent pas d’actions AD et ne prouvent pas la lecture métier des schémas.

- `5.5-final-resultat.json` : aperçu sans écriture ; mise à jour depuis RC23 vers l’EXE final ; 38 composants conformes ; configuration et sentinelles conservées, sauvegarde gardée.
- `5.5-preferences-resultat.json` complète le test au vrai chemin `wad/gp.prefs.json`. Clé `HKU\<SID>\Software\GP` absente dans ce profil de démo avant/après (`RegistryValues=0`, attendu par le code démo) : cela ne prouve pas la conservation de valeurs existantes. Première tentative interrompue avant l’aperçu parce qu’elle exigeait une clé présente ; relancée sur une nouvelle extraction en enregistrant cette absence.
- `5.6-final-resultat.json` : arrêt contrôlé du processus de mise à jour après la première copie, code 93 ; lanceur 126 ; `--recover` en aperçu seulement, verrou à empreinte inchangée. Aucun effacement manuel du verrou, aucune récupération appliquée, aucune panne électrique simulée.
- Les fichiers `5.5-*` / `5.6-*` sans `final` ni `preferences` documentent la première passe sur l’ancien EXE ; ils ne prouvent pas le nouvel EXE.

Sauvegardes et copies conservées dans la VM : `C:\PestoTest-avant-correction-UAC-20261004`, `C:\PestoTest-run\recette-update-final-20261004`, `recette-update-prefs-v2-20261004` et leurs `DEV-code-backup-*`. Verrou d’interruption présent seulement dans une copie de recette, jamais dans le pack principal. Instantané froid préalable `03-avant-session-recette-20261004` conservé.

## Archives candidates et fin de session

`packs-resultat.json` : les ZIP PROD et DEV ont été copiés puis extraits sur Windows ; chaque EXE natif rend 0 à `--check-json` (Runtime/Syntax/AuditWriter PASS, 38 composants, 27 scripts, 3 scripts embarqués). PROD ne contient que `Pesto.exe` et `wad/`. Configuration non configurée dans les deux packs. Empreintes des ZIP dans ce rapport. EXE non signé ; aucune diffusion de production annoncée.

`nettoyage.json` : compte et profil temporaires supprimés, AutoAdminLogon=0, retrait du secret LSA réussi, aucune valeur DefaultPassword, aucune tâche PestoPilote restante. Fermeture normale de la session, puis arrêt Windows. `vm-fin.txt` constate l’arrêt de la VM et les trois autres VM toujours en marche.

Reste : configuration et accès AD de test (compte et OU demandés, non reçus), P6, 2.12, phases 3/4, robustesse métier 5.1–5.4, DPI/RDP et lecteur d’écran, contraintes LAB sur l’hôte partagé. La recette complète n’est pas close.
