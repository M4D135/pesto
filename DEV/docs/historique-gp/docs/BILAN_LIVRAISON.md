# Livraison actuelle : RC13

Consulter `BILAN_RC13.md` et `CONNEXION_UNIQUE_RC13.md`. Le bilan ci-dessous décrit la RC12, pas la connexion Windows automatique de RC13.

---

# Bilan de livraison GP 17.0-RC12

## Contenu

Connexion compacte modifiée dans le code, avec mémorisation facultative de l'identifiant seul. Le parcours UAC RC11 est repris. La page distincte de jonction est uniquement proposée, pas implémentée.

Le ZIP utilisateur est la base des ressources et de la configuration. Le moteur est repris de RC11 puis modifié uniquement dans cinq fonctions de login, avec sept aides supplémentaires et les libellés de version. Les autres fonctions sont comparées par empreinte après normalisation de la version : aucune fonction métier modifiée.

## Vérifications réellement exécutées

Les dix suites Python source/XML/structure lexicale ont toutes terminé sans erreur : static, async, RC4, pilotage, UX, login, retrait de file, progression, startup et login compact. Le détail horodaté est dans `tests/rc12-validation-summary.json`.

La suite spécifique au login compact comporte **33 contrôles**, tous réussis, et **5 défauts volontairement injectés dans des copies en mémoire**, tous détectés. Ces contrôles vérifient des contrats du source et du XML ; ce ne sont pas des simulations complètes de Windows.

Les tests de conservation vérifient aussi la configuration fournie et les ressources. Le nouveau fichier GP-Startup.ps1 est identique à la RC11. Les archives sont testées par lecture ZIP et par empreintes des fichiers.

## Non exécuté

**Aucun parseur natif PowerShell, lancement Windows, rendu WPF, vrai dialogue UAC ou accès Active Directory n'a été exécuté ici.** Aucun EXE n'a été compilé. Les tests Windows fournis, notamment `TEST_LOGIN_COMPACT.cmd`, restent à exécuter sur un poste de recette.

`APERCU_LOGIN.cmd` est une fixture visuelle locale : elle charge le XAML extrait mais pas le moteur complet, et désactive les connexions. Elle ne valide donc pas le login AD réel. La nouvelle suite de préférences isole six fonctions, utilise un dossier temporaire et n'appelle pas AD.

Les rapports de versions précédentes restent disponibles comme historique. Leur présence n'est pas une preuve d'exécution Windows de la RC12.

## Avertissement de configuration conservé

La configuration jointe indique `o.LOCAL` alors que les OU se terminent par `DC=labo,DC=local`. Le contrôle signale cette incohérence ; il n'a pas remplacé ces valeurs. Le pack complet les conserve et `cfg.original.json` est une copie exacte de ce cfg.json reçu. Remettre une configuration valide si le fichier fourni était anonymisé.

Le correctif séparé ne contient ni fichier cfg, ni gp.prefs.json, ni état de file, ni journal de session. Le pack complet exclut les journaux de la session reçue ; cela ne supprime rien dans l'installation de l'utilisateur.

## Usage

Fermer normalement GP après vérification de l'état des actions, sauvegarder l'installation, extraire le correctif entier à côté de GP.cmd, débloquer, examiner l'aperçu et lancer les tests. Ne pas remplacer uniquement GP-Core.ps1 : les lanceurs et GP-Startup.ps1 doivent être présents pour le démarrage élevé.
