# Reprise Pesto du 4 octobre 2026

Sources : `549a4aa`, branche `cloud/points-suite`. Exécution sur **PESTO-W11-TEST**, Windows PowerShell 5.1.26100.6584 Desktop, session SSH. Aucune opération AD.

## Recette 1.8

Le 04/10/2026 à 17:47 (heure de la VM), `validate_pesto.py --require-parser` : **407 contrôles réussis, aucun échec, code 0**, parseur PowerShell 5.1 Desktop. Copie isolée des fichiers versionnés de `DEV/` dans `C:\PestoTest-run\python-549a4aa\DEV`, complétée avec l'EXE du Mac et la configuration modèle.

- EXE : `8fd5bd8cf914058f1f0b84a95f43536ff91c4dc2718c6c67f411bb24b7fd7ca0`.
- [Python 3.14.7 embarqué x64 officiel](https://www.python.org/downloads/release/python-3147/), sans installation ni modification du PATH permanent. Archive SHA-256 `d297e5ff019966817ad8502465176139f2d3d840fa4ed84b13bed399a6ab1f15`, conforme à python.org ; signature Authenticode de `python.exe` valide, Python Software Foundation.
- Preuves : `python-environnement.txt`, `1.8-validate.txt`, `1.8-rapport.json`, `1.8-code.txt`. Le champ historique `windowsExecuted: false` du rapport signifie que ce contrôleur ne prouve pas une exécution native du produit (WPF/UAC/AD) ; son parseur a bien tourné sous Windows 5.1.

## Pilote de labo : défaut reproduit avant correction

Sans session interactive, `lancer.ps1 -Exe cmd.exe -Arguments "/c exit 7" -Attendre -Delai 5` rend **0** au shell, alors que la tâche reste `Ready`, résultat `267011`. L'action attendue n'a pas été exécutée. Source : `outils/labo/vm/lancer.ps1` de `549a4aa`. Preuve : `lancer-avant-sans-session.txt`.

## Point de retour

VM arrêtée proprement avant l'instantané à froid `03-avant-session-recette-20261004` (UUID `e34260ea-2ff8-4466-86b2-9ab7b9ae5a25`), pris vers 18:00. Il précède la création du compte temporaire autorisée par David dans cette conversation. Aucun instantané à chaud.

La première passe des tests Python a produit des échecs, mais le collecteur PowerShell (`$ErrorActionPreference=Stop` avec `*>`) a interrompu la capture sur la sortie stderr normale d'unittest. Aucun résultat global annoncé pour cette passe ; rejeu nécessaire avec stdout/stderr natifs dans deux fichiers séparés.

## Console (compte temporaire standard PestoRecette, session 1)

Ouverture automatique retirée dès la session ouverte ; mot de passe de labadmin inchangé. Écrans de confidentialité : options facultatives refusées.

- **2.11 PASS** : lancement `Pesto.exe --inconnu` à 18:06, message contenant « Code de sortie du lanceur : 120. », fermeture à 18:08, **ExitCode=120**. Le menu Démarrer masquait la première capture et empêchait Entrée ; fermeture par clic sur OK après avoir fermé ce menu. Preuves : `2.11-erreur-120.txt`, `2.11-erreur-120-visible.png`, `2.11-completion.txt`. Aucun défaut produit déduit de cette difficulté de pilotage.
- **2.3 PASS** : `APERCU_LOGIN.cmd`, saisie fictive `TEST\PestoRecette`, boutons de connexion inactifs, champ de mot de passe marqué masqué (aucun vrai secret saisi), fenêtre non maximisable, fermeture avec **ExitCode=0**. Configuration inchangée ; `%LOCALAPPDATA%\GP` et `HKCU:\Software\GP` absents avant/après. Capture relue : `2.3-login.png` ; UI Automation et résultats : `2.3-login.txt` ; sortie du CMD : `2.3-cmd-stdout.txt`, stderr vide. Le pilote ouvre le handle du CMD avant d'attendre sa fin, pour conserver son code de sortie.

## Tests Python sous Windows

Passe complète : 229 tests, 225 réussis, 2 échecs, 1 erreur et 1 ignoré (`python-tests.txt`, `python-tests-code.txt`). Les trois défauts concernent la préparation du banc :

- `test_parser_passes_keep_only_ps1_extension` : `outils/parse_all.ps1` absent de la copie DEV seule ; ajout du dossier `outils/` versionné de `549a4aa`.
- Deux tests CLI de `test_update_queues` : le Python embarqué isole `sys.path` et ne trouve pas `refresh_manifest` voisin de `update_installation.py`. Son fichier `python314._pth` est conservé sous `python314._pth-isole-original` dans ce seul environnement jetable ; Python retrouve ensuite son comportement normal (`isolated=0`, `ignore_environment=0`, `ctypes` importable). Aucun réglage système ni installation.

Rejeu **des trois cas seulement : 3/3 réussis, code 0** (`python-rejeu*`). Bilan cumulé sur ces mêmes sources : **228 réussis, 1 ignoré**. Il ne s'agit pas d'une nouvelle passe complète entièrement verte. Cas ignoré : fichier rendu illisible par les modes POSIX, que cette session Windows peut encore lire ; aucune preuve d'ACL restrictive déduite de ce cas. Ces tests exercent les outils Python et le système de fichiers Windows sur des copies temporaires ; ils ne remplacent pas la recette d'une vraie installation RC23 ni les mutations AD.

## Correctif du pilote

`outils/labo/vm/lancer.ps1` signale maintenant les erreurs et les résultats enfant non nuls, attend une exécution constatée, utilise un chronomètre monotone et refuse le succès sur dépassement de délai. Une tâche encore active est conservée et nommée, sans être tuée. Le compte console se choisit par `-Compte` (défaut historique labadmin).

**6/6 scénarios réels sous Windows 5.1**, avec tâches planifiées réelles : sans session labadmin (échec attendu, régression de `549a4aa`), fin 0, fin 7, exécutable absent, dépassement de délai alors que le test continue puis finit normalement, mode sans attente. `pilote/resultats.json` et les sorties par cas conservent les résultats. Les états Queued prolongé, erreur RPC et échec de désinscription n'ont pas été provoqués. Le lanceur Pesto et son manifeste sont inchangés ; aucun rebuild n'est nécessaire pour ce correctif de labo.

Les scripts de campagne utilisés sont dans `scripts/` ; la fermeture du premier test 2.11 reprend volontairement le PID 3816 de cette campagne (exemple de preuve, pas un script générique à relancer tel quel).

## Vérifications finales

- Régression sans session, commande identique : ancien pilote `549a4aa` code **0** (test échoue), pilote corrigé code **1** (test passe), `regression-sans-session.json`.
- Après les six cas réels, la relecture a durci la borne du délai : un résultat 0 découvert après le délai ne doit pas réussir. Double de lecture Planificateur retardée de 1,5 s pour un délai de 1 s, exécuté sous Windows PowerShell 5.1 : test en échec avant durcissement, réussi après (`regression-resultat-tardif.json`, source antérieure dans `scripts/lancer-avant-borne.ps1`). Ce cas utilise des doubles, aucune tâche Windows réelle. L'absence de session a aussi été rejouée sur le code final : code 1 (`absence-session-code-final.json`).
- Deux demandes Spark n'ont fourni aucun texte public exploitable ; collectes annulées, achèvement distant inconnu. Aucun brouillon Spark intégré et aucune revue indépendante du Spark revendiquée. Relecture du correctif par Codex et preuves d'exécution ci-dessus.

## Fin de campagne

Compte temporaire et profil supprimés, ouverture automatique à 0, aucune valeur DefaultPassword en clair, aucune tâche PestoPilote restante, EXE inchangé : `nettoyage.json` (18:29, heure VM). VM éteinte proprement : `vm-fin.txt`. LABO-DC01, LABO-W11-01 et FILPRO-W11-TEST toujours en marche, comme au début ; aucune modification effectuée sur ces VM. Environnement Python isolé conservé dans `C:\PestoTest-run\python-549a4aa` pour la prochaine campagne ; aucun installateur ni service ajouté.
