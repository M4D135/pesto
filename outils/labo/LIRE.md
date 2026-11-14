# Outils de labo : pilotage de la VM `PESTO-W11-TEST` depuis le Mac

Outils écrits et utilisés pendant la recette des 2 au 4 octobre 2026. Ils ne font pas partie de Pesto (rien ici n'entre
dans les packs). Aucun secret : SSH par clé, mots de passe jamais stockés.

## Accès

```
Mac ──ssh──> degun@192.168.1.173 (hôte du labo DESKTOP-285EKHU, VirtualBox 7.2)
          └─ rebond ──> 127.0.0.1:2223 (NAT VirtualBox) ──> labadmin@PESTO-W11-TEST (OpenSSH, clé du Mac)
```

- `mac/commun.sh` fixe ces valeurs ; surcharges par `PESTO_SAUT`, `PESTO_PORT`, `PESTO_COMPTE`, `PESTO_KNOWN_HOSTS`
  (par défaut `~/.ssh/known_hosts_pesto`, rempli au premier contact par `accept-new`).
- Une session SSH arrive en **session 0, élevée, sans bureau** : ni WPF, ni UAC, ni capture d'écran utile. Tout ce qui
  touche l'interface passe par `run.sh` / `obs.sh`, qui lancent le script dans la session console de `labadmin`.
- VirtualBox se pilote sur l'hôte : `ssh degun@192.168.1.173 '"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" …'`.

## Domaine du labo

Le vrai domaine n'est pas versionné. Côté Mac, `mac/commun.sh` charge `outils/labo/labo.local.env` (copie de
`labo.local.env.exemple`, ignorée par Git) : `PESTO_LABO_DOMAINE` (ex. `labo.local`) et `PESTO_LABO_NETBIOS` (par
défaut la première étiquette en majuscules) ; des variables déjà posées priment. Sans domaine, les scripts qui en ont
besoin s'arrêtent sur « Domaine du labo absent : copier outils/labo/labo.local.env.exemple vers
outils/labo/labo.local.env ». Côté VM, les scripts prennent `-Domain` (passé par les scripts Mac) ou
`PESTO_LABO_DOMAINE`, et en déduisent compte, DC et OU parente. Les pilotes `v2/tools/qualification` lisent
`lab.local.json` (modèle `lab.local.json.exemple`, ignoré par Git), avec repli sur les mêmes variables et
`PESTO_LABO_MDP_FICHIER` (chemin du fichier de mot de passe, jamais lu).

## Mac (`mac/`)

| Script | Rôle |
|---|---|
| `g.sh <commande>` | Commande sur la VM (cmd.exe ; préfixer `powershell -NoProfile -ExecutionPolicy Bypass -File …`). |
| `envoyer.sh <fichiers>` | Copie dans `C:\PestoTest-run\`. Pour un dossier : `COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -cf - … \| g.sh 'tar -xf - -C C:\…'`. |
| `recuperer.sh <C:/motif> <dossier>` | Rapatrie preuves et sorties. |
| `run.sh <etape.ps1> [délai]` | Exécute `C:\PestoTest-run\<etape.ps1>` dans la session interactive (jeton non élevé) et attend. |
| `obs.sh <id> <motif> [délai] [dossier]` | Observe une fenêtre : titre, UAC (`consent.exe`), connexions au DC, processus, capture, arbre UI Automation. |
| `autologon.sh` | **Réservé à David** : ouverture automatique de `labadmin` (secret LSA) ; `--nouveau`, `--retirer`. |
| `windows_update.sh` | **Réservé à David** : suspend (`NoAutoUpdate=1`) ou rétablit (`--retablir`) les mises à jour. |

Copie du pack sur la VM (depuis la racine du dépôt, EXE et manifeste reconstruits sur le Mac) :

```bash
tar --no-xattrs --no-mac-metadata --exclude='__pycache__' --exclude='.DS_Store' -cf - -C DEV . | outils/labo/mac/g.sh 'tar -xf - -C C:\PestoTest && echo DEV copie'
```

`tar` écrase sans supprimer : un fichier retiré du dépôt reste sur la VM. Arrêter d'abord tout processus qui tient
`C:\PestoTest` (`vm/qui.ps1`) ; comparer ensuite l'empreinte de `Pesto.exe` avec celle du Mac.

## VM (`vm/`, à copier dans `C:\PestoTest-run\`)

| Script | Rôle |
|---|---|
| `pilote.psm1` | `Save-Ecran`, `Get-Fenetres`, `Wait-Fenetre` (ignore consoles et « Initialisation »), `Get-Arbre`, `Find-Element`, `Invoke-Element`, `Send-Touches`, `Get-Focus`. |
| `lancer.ps1` | Tâche planifiée `Interactive` (`Limited`, ou `-Eleve`), `-Attendre`, `-Dossier` (répertoire courant ; par défaut `C:\PestoTest-run`, jamais `C:\PestoTest`). `-Compte` choisit le compte console (défaut `PESTO-W11-TEST\labadmin`). Code 0 après fin réussie avec `-Attendre`, ou démarrage constaté sans attente ; code 1 en échec ou au délai. Une tâche encore active au délai reste nommée et conservée, sans arrêt implicite. |
| `obs.ps1` | Utilisé par `obs.sh`. Écrit dans `C:\PestoTest-preuves\phase2\`. |
| `ecran.ps1` | Capture du bureau et liste des fenêtres (`00-bureau.*`). |
| `eveil.ps1` / `stopeveil.ps1` | Garde l'écran allumé 4 h (`SetThreadExecutionState`), sans modifier de réglage. |
| `qui.ps1`, `stop.ps1`, `stopall.ps1` | Arrêtent les processus lancés depuis `C:\PestoTest` (Pesto, `.cmd`, tests) ; `stop.ps1` vise aussi `PestoProto`, `stopall.ps1` les anciens packs `C:\PestoTest-<hexa>`. Jamais le script appelant. |
| `stoppilote.ps1` | Arrête les étapes de pilotage lancées depuis `C:\PestoTest-run` (`eveil.ps1` compris) et désinscrit les tâches `PestoPilote-*` restantes. Fin de session. |
| `oobe.ps1` | Inspecte l'écran « Microsoft account » (WWAHost). Ne rien accepter : `taskkill /IM WWAHost.exe /F`. |
| `hc126.ps1` | Remet le contraste élevé à son état d'origine (flags 126). |
| `autologon.ps1` | Appelé par `mac/autologon.sh` (David seulement). |
| `e128.ps1`, `ex5.ps1`, `eo7.ps1` | Exemples d'étapes du 04/10 (seconde instance, contraste élevé, `VERIFIER_UAC.cmd`). |

## Pièges vus

- Hyper-V actif sur l'hôte : VirtualBox en mode NEM. Instantanés **à froid seulement** (arrêt propre, `snapshot take`,
  `startvm --type headless`) ; jamais `--live` ni `controlvm pause` pendant un instantané (VM figée le 02/10).
- En session graphique, la VM s'est figée ~30 min après l'ouverture (vCPU 100 %, aucune E/S) : enchaîner vite. Le 04/10
  vers 17 h, elle s'est aussi figée juste après un démarrage, sans session (3 vCPU à 100 %, SSH muet, écran noir). Si le
  SSH ne répond pas 5 min après un démarrage : `controlvm PESTO-W11-TEST screenshotpng <fichier>` sur l'hôte, charge
  CPU du processus de la VM, puis `controlvm PESTO-W11-TEST reset` (VM de test seulement ; SSH revenu en 25 s).
- Premier rendu WPF de Pesto > 1 min sur la VM : attendre 90 s avant de conclure à une fenêtre blanche.
- Après un arrêt brutal, des fichiers récemment écrits peuvent être remplis de zéros (`eveil.ps1` le 04/10) : recopier.
- L’invite UAC est sur le bureau sécurisé : UI Automation de la session ne peut pas la piloter. Le 04/10, avec la délégation explicite de David, `VBoxManage controlvm PESTO-W11-TEST screenshotpng` puis `keyboardputscancode` ont permis d’observer et de répondre Non/Oui depuis la console virtuelle, sans modifier l’UAC. Toujours vérifier l’écran avant la touche ; preuves `preuves/vm-2026-10-04-final/`.
- `LABO-DC01` est partagé avec d'autres sessions (Domenia, FILPRO) : `list runningvms` avant d'y toucher.
- `cmd` via SSH : guillemets fragiles ; `powershell -Command -` ignore les lignes multiples. Envoyer un `.ps1`.
- zsh : ne pas ranger une commande `ssh` dans une variable (pas de découpage) ; passer par ces scripts.

## Régression du pilote (04/10, reprise Codex)

`vm/test-lancer.ps1 -Compte <compte-console-ouvert> -CompteAbsent <compte-sans-session> -Preuves <dossier-neuf>` joue six cas réels : absence de session, fins 0/7, exécutable absent, délai pendant une exécution, lancement sans attente. VM Pesto exclusivement. Il ne change aucun compte ni réglage ; une session console doit déjà exister. Résultats du 04/10 : `preuves/vm-2026-10-04-reprise/pilote/`. Sans `-CompteAbsent`, le cas sans session n'est pas joué.

`-Delai` borne l'attente dans les deux modes (défaut 180 s). En cas de délai avec tâche conservée, observer son état et ses preuves avant de décider de son arrêt ou de sa désinscription. Un code 0 sans `-Attendre` n'est pas le résultat final de la commande.

`vm/test-lancer-retard.ps1 -Lanceur <chemin>` teste, avec des doubles de cmdlets sous PowerShell, qu’une lecture lente revenue après le délai ne produit pas un succès. Ce contrôle n’exécute aucune tâche Windows ; il complète les six cas réels sans les remplacer.
