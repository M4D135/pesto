# Bilan de livraison GP 17.0-RC7

Date : 22 septembre 2026. Base : archive GP_17_WAD_RC6.zip fournie.
Objet : corriger la saisie tronquée dans la connexion et les styles partagés.

## Réalisé ici

| Contrôle | Résultat | Portée |
|---|---:|---|
| Structure générale | 56/56 | Encodages, liaisons, six gabarits XML, ressources, chemins. |
| Callbacks hérités | 25/25 | Contrats lexicaux des timers et callbacks. |
| Régression RC4 | 28/28 | Contrats de file et règle de changement de site. |
| Pilotage RC5 | 53/53 | Contrats de lots, contrôles, reprise et suivi. |
| Interface RC6 | 49/49 | Ressources, navigation, aides et présentation. |
| Saisie RC7 | 29/29 | Pas de double marge, hauteurs extensibles, styles et test ciblé. |

Total : **240 contrôles statiques réussis**. Le contrôle général conserve un
avertissement sur la configuration historique (domaine `o.LOCAL` et OU `labo.local`).
Le correctif n'embarque aucune configuration.

Quatre régressions ciblées ont été injectées dans des copies en mémoire et détectées.
Le validateur ciblé échoue sur dix contrats de la RC6 d'origine, notamment le double
padding et les champs de connexion de hauteur fixe. Il ne s'agit pas d'un test WPF.

Comparaison du moteur : **256 fonctions identiques sur 258**, aucune ajoutée ni
supprimée. `Show-GPStartupWindow` change uniquement de titre de version ;
`Show-LoginWindow` change de titre et de propriétés XAML de présentation.
Les autres changements du moteur sont ses styles XAML partagés, titres et version.
Les 11 fichiers wad autres que GP-Core.ps1 sont identiques à la RC6, y compris les
configurations, les DLL, le module AD et l'icône.

## Non exécuté ici

Aucun parseur PowerShell natif n'est disponible dans cet environnement Linux.
Aucun chargement WPF, rendu Windows, test AD, opération distante ni compilation EXE
n'a été exécuté. Les suites PowerShell fournies ne sont donc pas annoncées comme passées.

Le nouveau `TEST_LOGIN.cmd` prévoit 15 cas Windows ciblés, avec mesures de layout et
contrôle négatif. `APERCU_LOGIN.cmd` fournit un aperçu de saisie manuel, sans
connexion. Ils chargent le XAML extrait, pas le corps applicatif du moteur.
Les tests de taille de police ne remplacent pas une recette à différents DPI réels.

## Traces et documents

- `tests/login-static-report.json` : 29 contrats ciblés et quatre contrôles négatifs.
- `tests/rc6-login-defect-detection.json` : défauts signalés dans le source RC6.
- `tests/rc7-preservation-report.json` : comparaison des fonctions et des ressources.
- `tests/*static-report.json` : rapports des familles statiques héritées.
- `changes/GP17-RC6-to-RC7.patch` : diff du moteur réellement livré.
- `docs/CORRECTIF_LOGIN_RC7.md` : installation et portée exacte.
- `SHA256SUMS.txt` : empreintes du pack complet à sa livraison.

Les rapports RC1 à RC6 conservés sont historiques. Leurs nombres de tests ou leurs
mentions de non-exécution décrivent ces livraisons, pas de nouvelles validations.
