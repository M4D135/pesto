# Candidat C8 — qualification Windows du 26 octobre 2026

**Campagne entièrement réussie : [40323591018](https://github.com/M4D135/pesto/actions/runs/40323591018).** Source testée : `483a8a3a4a02914e77db611f8d1cf83fb7979c6f`,
branche `codex/pesto-v2-20261023`. Le commit documentaire suivant ne reconstruit pas ces ZIP.
Voir le [rapport des corrections et limites](../../../VALIDATION-C8-20261026.md).

## Télécharger et lancer

| Canal | Artefact GitHub Actions | Archive interne |
|---|---|---|
| PROD | [Télécharger PROD](https://github.com/M4D135/pesto/actions/runs/40323591018/artifacts/12650149351) | `Pesto_V2_PROD_candidate.zip` |
| DEV | [Télécharger DEV](https://github.com/M4D135/pesto/actions/runs/40323591018/artifacts/12650763434) | `Pesto_V2_DEV_candidate.zip` |

Extraire l’enveloppe GitHub puis le ZIP interne. Garder **Pesto.exe** et **wad** ensemble,
dans le dossier PROD ou DEV. .NET, WebView2 fixe et le module Microsoft ActiveDirectory
épinglé sont inclus. Sans configuration, le lancement ouvre les Paramètres locaux.
DEV ajoute les sources et outils, sans les caches ni `node_modules` du banc.

Les artefacts sont conservés jusqu’au 25 novembre 2026. Ce sont des candidats
`official=false`, `distribution=candidate`, `qualification=unqualified`, sans release publiée.

## Identités vérifiées

| Contenu | SHA-256 |
|---|---|
| EXE commun PROD/DEV | `c6792ea530e9159abc00a94d676fa313a8b8d7607e39e7a59e4154999c93a859` |
| ZIP PROD | `3d1fd5a69dffc8ac1d61db2460c3b8c8ed8ef2111e398e517cb41d0849d4e846` |
| ZIP DEV | `ce940515b400d65b90f1fe4dac79b013a253761850041435fdb7b3005b1d3ec8` |
| Baseline A, reconstruite depuis `de52731` | `62c1786a7ec3b5321520943740699ceece6c4a39ceae11c9d1c93bcb170d4a6c` |

Les deux compilations gardent leur version réelle `2.0.0`. SDK Windows **10.0.302**,
WebView2 fixe **156.0.4314.42**. Les enveloppes Actions ont leurs propres empreintes :

| Enveloppe | Octets | SHA-256 |
|---|---:|---|
| [PROD](https://github.com/M4D135/pesto/actions/runs/40323591018/artifacts/12650149351) | 369803925 | `ada3c09dd54f976461f2a427978415c36fa136a3b86d33b3d08db152b40ad710` |
| [DEV](https://github.com/M4D135/pesto/actions/runs/40323591018/artifacts/12650763434) | 383947022 | `5af34ddfb97c485cfc1a63ed5d3043150342198f88d3f3f110358d948576d57f` |
| [preuves](https://github.com/M4D135/pesto/actions/runs/40323591018/artifacts/12650951979) | 1157846 | `0ec89a2fecbd3490e23c7f899869d7655aa62008002a874eb806bd8f1ed53990` |

Les trois enveloppes ont été téléchargées et vérifiées. Les ZIP internes, le manifeste,
le canal, le commit et l’EXE ont été recoupés ; aucun ZIP n’a été reconstruit après les essais.

## Résultats et portée

| Contrôle Windows | Résultat |
|---|---|
| Compilations | Sans avertissement ni erreur |
| Moteur ciblé sur fixtures | 201/201 ; pont 15/15 ; compagnon 30/30 |
| PowerShell 5.1 | 18 variantes métier et script du banc analysés sans erreur |
| Chromium avec ponts déclarés | Maintenance 33/33 ; opérateur 41/41 ; démo DOM 8/8 ; statique 149/149 |
| Démo native PROD/DEV | 44 refus d’API par canal ; six transitions fraîches, trois profils/deux instances/trois reçus ; contexte parent conservé |
| Configuration native PROD/DEV | 14 contrôles par canal : export/import, octets exacts, encodage invalide, annulations, pack personnalisé et profils temporaires |
| Mise à jour native PROD | ZIP/rollback, santé négative/restauration, interruption/reprise |
| Mise à jour native DEV | ZIP/rollback |
| Recoupements | Quatre transactions, huit reçus santé, sept lancements du helper ; sources, ZIP et sentinelle inchangés |

Les 14 contrôles de configuration utilisent le même Pesto.exe : vrais dialogues de fichier,
puis service de configuration et pack complet dans une arborescence temporaire. Aucun accès
au profil ordinaire ni adaptateur AD. Le choix positif du dossier, la récupération native d’un
cfg invalide, les ACL réelles, UAC sous autre identité et DPAPI restent distincts.

Les transactions se terminent à `rolledBack`. La reprise prouve le retour à A, pas une
installation réussie de B. Leurs copies sont isolées ; UNC et acquisition GitHub officielle
ne sont pas qualifiés par les ZIP locaux. Les preuves JSON détaillées sont dans l’artefact.

## Laboratoire autorisé

Le pack PROD exact de `483a8a3` a été installé sur la seule VM autorisée : SHA du ZIP et de l’EXE vérifiés dans l’invité, 500 entrées de l’inventaire conformes. L’identité BIOS, l’appartenance au domaine et la session console ont été relues. Le banc a tourné en session interactive 1, sans élévation et sans adaptateur AD.

La **démo du candidat final réussit** (code 0, reçu SHA-256 `1e278e1f9f2c584d221837c262cd7719c966d89ca05431f647b630b32e192453`). Le banc de configuration échoue ensuite avec `qualification.configuration.dialog-path`, au stade export : seul `parentReady` est acquis. Ce refus constate un écart entre le chemin envoyé et la relecture immédiate du contrôle natif ; sa cause précise n’a pas été déterminée. Les 14 contrôles CI réussis ne remplacent pas cet échec VM. Le reçu d’échec porte le SHA-256 `f3816b8784c9089fdd5832786372d00708245f91ccea635085965bf9179fdffd`.

À **13:11:04 UTC**, VirtualBox passe cette VM à **aborted**. Le journal du processus `VBoxHeadless.exe` associé à cette VM contient une exception dans `VBoxC.dll`, offset `0x00030c46`. Le déclencheur précis reste inconnu. Le reçu du banc et les deux hashes avaient été relus à 13:10:48 UTC ; la collecte complète des preuves invitées est ensuite refusée parce que la VM est arrêtée. Aucun nouvel essai ni redémarrage en boucle n’a suivi ce crash.

Le premier passage sur `e70692c` avait validé la démo et l’export exact, puis révélé le contrôle trop large des temporaires, corrigé par `483a8a3`. Ses quatre captures et sa preuve complète sont conservées séparément. Il ne vaut pas réussite de la configuration sur le candidat final.

Un problème distinct d’affichage a été corrigé : la GUI lancée depuis SSH appartenait à la session 0 de l’hôte. Après arrêt forcé de la seule VM, autorisé par David, le démarrage headless avec VRDE toujours désactivé lui a permis de confirmer l’ouverture de la console par Afficher. L’instantané à froid reste conservé ; aucune restauration ni intervention sur les VM voisines.

L’inspection AD préparée utilise un harnais distinct compilé depuis les sources courantes et une configuration de laboratoire créée sans lire le cfg privé. La première tentative atteint la saisie native sous élévation, sans identifiant saisi, et ne produit que la demande et l’identité locale ; la tentative suivante ne produit pas de nouvelle preuve. Aucun appel AD métier ni mutation n’est qualifié. Les essais AD restent bloqués par l’instabilité de la VM. Reprise : stabiliser cet environnement, relire son identité et les reçus, reproduire le dialogue d’export puis reprendre l’inspection et le canari réversible, sans restauration de DC ni sortie de domaine improvisée.

[Reçus VM finaux normalisés](vm-483a8a3-summary.json) ; [premier passage distinct](vm-e70692c-summary.json).
