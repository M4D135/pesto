# Démarrage et connexion : GP 17.0-RC11

## Périmètre du changement

Le pack RC9 fournissait les lanceurs et les ressources complets. Le moteur utilisé pour cette livraison est le **GP-Core(1).ps1 RC10** retrouvé dans la Bibliothèque : il contient déjà le retrait Entra local/distant préalable au renommage. La RC11 ajoute l'élévation au démarrage et ne réécrit pas ce traitement.

## Parcours normal

```text
GP.cmd
  → GP.ps1 : contrôle Windows PowerShell 5.1 x64 / STA
  → lecture du vrai jeton administrateur
  → si nécessaire : demande UAC Windows avec RunAs
  → nouveau processus élevé, nouveau contrôle du jeton
  → reprise prudente de l'ancienne file si le compte Windows a changé
  → GP-Core.ps1 et formulaire de connexion AD
  → identifiants AD explicitement saisis, conservés en mémoire
  → préparation et confirmation des actions
  → actions locales déjà élevées, sans second dialogue UAC
```

Un processus déjà administrateur ne redemande pas l'UAC. `-Demo` reste sans élévation et sans mutation. Le marqueur interne `-ElevatedLaunch` **ne donne aucun droit** : un relais non administrateur est refusé, sans boucle de tentatives. L'appel direct du moteur non élevé est redirigé vers le lanceur avant l'ouverture d'une fenêtre.

Une annulation UAC produit le code 1223 et aucun moteur n'est chargé. Un autre refus Windows est signalé comme une erreur de démarrage. Les restrictions GPO, WDAC, AppLocker ou antivirus ne sont pas contournées.

## Pourquoi deux saisies peuvent subsister au démarrage

L'UAC et le login AD ne sont pas le même mécanisme. Windows peut demander des identifiants administrateur sur son bureau sécurisé. GP ne récupère pas ce mot de passe. Le cmdlet `Rename-Computer` sur une machine jointe au domaine attend des identifiants de domaine explicites ; la connexion AD de GP les fournit pour les actions suivantes.

Le correctif supprime donc **la demande UAC tardive au milieu de l'opération**, pas toute authentification distincte au lancement. Le nom du compte Windows élevé de domaine est prérempli lorsque possible ; le mot de passe reste à saisir dans GP. Un compte local n'est pas prérempli comme s'il s'agissait d'un compte AD.

Le bouton **Session Windows (sans renommage)** conserve les usages AD qui peuvent employer l'identité intégrée. Une file contenant un renommage ou une jonction est refusée avant toute mutation en l'absence d'un credential explicite. Le moteur possède le même garde-fou avant `dsregcmd`, même lorsqu'il est appelé indépendamment de la file.

La présence d'un jeton administrateur local ne prouve pas que le compte AD dispose des droits sur toutes les machines, les objets ou les OU. Ces refus restent possibles et restent journalisés.

## Fenêtre de connexion

Les corrections de hauteur des champs de la RC7 sont conservées. Le login est désormais non redimensionnable (`ResizeMode=NoResize`) et ne permet plus la maximisation. Le bandeau distingue les droits administrateur locaux déjà acquis du compte AD utilisé pour les actions.

## Identifiants et traces

Le mot de passe du login GP n'est pas placé dans les arguments du relais, dans la configuration ou dans un nouveau fichier de cache. Le démarrage n'utilise ni `-Credential` avec `RunAs`, ni commande encodée. Il transmet uniquement des chemins de configuration/profil et un marqueur anti-boucle.

Le journal `GP-demarrage.log` contient l'heure, les PID, le nom Windows et l'état administrateur. Le nom Windows n'est pas un secret d'authentification, mais le journal reste une donnée interne. Les journaux existants du moteur sont inchangés.

La ligne attendue avant ouverture du moteur est :

```text
Admin=True confirme. Chargement du moteur et du login dans CE processus eleve.
```

## Reprise des files lors du changement de compte UAC

Le moteur existant stocke ses états sous :

```text
%LOCALAPPDATA%\GP\State\<identifiant du chemin cfg>\queue.json
%LOCALAPPDATA%\GP\State\<identifiant du chemin cfg>\history-v1.json
```

L'identifiant est le même calcul SHA-256 tronqué que celui du moteur. Le lanceur normal transmet le dossier LocalAppData du processus appelant avant UAC. Si le processus élevé utilise un autre profil, la RC11 copie les deux fichiers existants vers le nouveau profil.

Garanties et limites de cette reprise :

- Source lue sans modification ; copie par `CreateNew`, aucune substitution silencieuse d'un fichier existant différent.
- Octets et verrous du checkpoint conservés. Le mécanisme existant restaure la file sans relance automatique.
- Reçu identifié par l'empreinte du fichier source pour ne pas réimporter un ancien état déjà traité. Si une ancienne instance produit un nouveau checkpoint, il est réexaminé.
- Chemins réseau et jonctions/liens détectés dans les chemins de reprise refusés. Limite de taille de 16 Mio par fichier. Ce mécanisme ne remplace pas les ACL Windows ni un audit de sécurité contre un attaquant local.
- En cas de conflit, le message donne les deux chemins. **Ne pas supprimer un verrou ou un checkpoint pour forcer la connexion.** Fermer les autres instances, vérifier l'état réel des anciennes opérations et faire examiner les deux fichiers. La RC11 ne fusionne pas automatiquement deux historiques divergents.
- La reprise concerne le même chemin de configuration. Déplacer toute l'installation change son identifiant d'état. Conserver le même emplacement pour la mise à jour.
- Démarrer manuellement sous un autre utilisateur sans passer par l'ancien profil ne permet pas au lanceur de deviner ce profil. Utiliser normalement `GP.cmd` depuis la session opérateur.
- Les préférences visuelles ne sont pas migrées. Un thème peut reprendre sa valeur par défaut sous le nouveau compte.

## Traitement Entra conservé

Les fonctions RC10 `Invoke-GPDsregLeaveLocal`, `Invoke-GPDsregLeaveBeforeRename` et `Invoke-GPSystemTaskScript` sont inchangées. Les précontrôles de cible/domaine, le contrôle de retour et le contrôle d'état Entra sont conservés. À distance, le retrait préalable reste effectué sur **la cible** par une tâche SYSTEM ; ce correctif n'active pas WinRM et ne lance pas un retrait sur le PC opérateur pour une cible distante.

La RC10 exécute le `/leave` avant le premier renommage même si `AzureAdJoined` est déjà à NO. Ce comportement n'a pas été modifié dans la RC11. Après le retrait, le renommage reste conditionné à un résultat valide ; aucune nouvelle tentative Entra automatique n'est ajoutée. Un `/leave` réussi suivi d'un renommage échoué nécessite toujours un contrôle de la réinscription Entra.

Même site : renommage seul. Site différent : renommage puis déplacement si nécessaire après succès confirmé. Aucun redémarrage implicite, aucun déplacement seul transformé en retrait Entra, aucun verrou effacé.

## Recette sans AD, puis sur poste de test

1. `TEST_UAC.cmd` exécute les tests isolés avec processus simulés et parseur PowerShell natif. Il ne déclenche pas la vraie UAC.
2. `VERIFIER_UAC.cmd` copie les vrais fichiers du lanceur dans un dossier temporaire dont le chemin comporte des espaces et des crochets. Il y installe un moteur factice qui affiche seulement `Admin=True/False`, le nom Windows et le PID. **Aucun vrai moteur GP, AD, dsregcmd, renommage, jonction ou redémarrage n'est appelé.** Le dossier temporaire et les preuves sont conservés pour lecture.
3. Depuis une session standard, essayer ce test en acceptant l'UAC. Attendu : une demande Windows avant le message du faux moteur ; résultat `Admin=True`.
4. Refaire le test en annulant l'UAC. Attendu : code 1223, pas de message du faux moteur et pas de seconde tentative automatique.
5. Depuis un PowerShell déjà élevé, refaire le test. Attendu : `Admin=True` sans nouvelle UAC.
6. `TEST_TOUT.cmd` exécute les dix suites isolées. Ces tests ne constituent pas une recette AD réelle.
7. Lancer le vrai `GP.cmd`, vérifier le titre RC11 et les traces, puis tester un poste autorisé en préproduction avec un compte AD explicite. Vérifier les noms Windows et AD, la destination éventuelle et l'état Entra final.

Le test UAC n'essaie pas la mutation métier et ne prouve pas les permissions AD. Les fenêtres, le transport RPC/DCOM, les délais réseau, les politiques d'entreprise et les opérations réelles nécessitent leurs propres essais.

## Références techniques

- Microsoft, fonctionnement UAC : https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/how-it-works
- Microsoft, `Start-Process` Windows PowerShell 5.1 : https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-5.1
- Microsoft, `Rename-Computer` Windows PowerShell 5.1 : https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/rename-computer?view=powershell-5.1

Le comportement propre à GP décrit ci-dessus provient du source livré, pas d'une exécution Windows dans l'environnement de livraison.
