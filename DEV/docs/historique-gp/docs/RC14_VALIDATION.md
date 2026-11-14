# Validation RC14 : exécuté, contrôlé, restant à faire

## Réalisé dans cet environnement

- Compilation du lanceur C avec LLVM pour Windows x64, puis édition de liens en sous-système graphique : `GP.exe`, 98 816 octets.
- Deux compilations séparées ont produit des binaires identiques. L'option reproductible de l'éditeur de liens remplace la date PE par une valeur déterministe ; ce champ ne doit pas être lu comme une date de livraison.
- Inspection de la structure PE32+, des DLL importées (KERNEL32, USER32, SHELL32), du manifeste `asInvoker`, de l'absence de signature Authenticode et de dépendance CLR du **lanceur**. Le moteur reste PowerShell/WPF.
- Icône extraite de l'EXE identique à l'icône fournie ; métadonnées version 17.0.0.14 et 17.0-RC14 présentes.
- Neuf cas exécutés sur Linux sur le code C de construction des arguments : espaces, apostrophe, antislash final, guillemets, contrôle des caractères, séparation des paramètres. Le processus Windows lui-même n'a pas été lancé.
- `tools/checks/validate_rc14.py` : contrôles lexicaux, XML, liaisons, exports des workers et invariants structurels. Le résultat réel figure dans `tests/rc14-portable-validation.json`.
- Comparaison SHA-256 des définitions de quatorze fonctions sensibles RC13 non modifiées : moteur de jonction AddToDomain, Entra, renommage, déplacement, règle de site, connexion Windows et sauvegarde atomique. Le titre du login a changé de version, pas sa disposition ni NoResize.

## NON exécuté ici

Le parseur Windows PowerShell, le chargement WPF sur Windows, UAC, le lanceur Windows en fonctionnement, une connexion AD, une jonction, un renommage et un redémarrage réels. La compilation seule ne prouve pas ces comportements. Les tests Windows fournis ne sont pas présentés comme déjà réussis.

## TESTER.cmd

À lancer sous Windows sur une copie de recette débloquée. Ce lanceur n'ouvre pas GP, ne demande pas d'UAC et n'appelle aucun AD réel.

1. Parseur natif Windows PowerShell sur les fichiers PS1.
2. Chargement isolé des XAML du shell et de la jonction, inspection des ressources et infobulles. Aucune ouverture du moteur.
3. Inspection Windows des en-têtes et métadonnées de GP.exe, sans exécuter le binaire.
4. Tests de jonction isolés avec doubles pour Windows/AD, stockage et Add-Computer : précontrôles, conflits, écritures de reçu, retour incomplet, erreur réseau, résultat tardif, redémarrage attendu, vérification après redémarrage, listes de noms.
5. Suites RC13 de connexion intégrée et démarrage, avec leurs doubles adaptés au lancement masqué.

Le compte rendu Windows est écrit dans `tests\windows-rc14-validation.json`. `TESTER.cmd -IncludeLegacy` ajoute les suites historiques ; des assertions liées aux anciennes interfaces peuvent nécessiter une adaptation. Un rapport ancien dans le projet n'est jamais une preuve d'exécution de la RC14.

## Recette manuelle indispensable

Vérifier sur des VM de test : démarrage EXE depuis un chemin avec espaces ; UAC acceptée/refusée ; compte Windows élevé attendu ; absence de second login en mode domaine ; login hors domaine lisible et sans maximisation ; page jonction ouverte directement hors domaine ; contraste clair/sombre et affichage 100/125/150 % ; champs sous préproduction imposée ; annulation d'une vérification ; confirmation refusée ; conflit de nom ; jonction avec compte autorisé ; échec avec compte non autorisé ; absence de reboot automatique ; reprise après reboot et vérification du canal ; impossibilité d'engager deux jonctions ; comportement d'un délai dépassé sans reprise automatique.

La vérification après redémarrage compare un état réel à un reçu. Elle ne constitue pas une réparation AD/Entra, une suppression de verrou manuelle ou un réenrôlement cloud.

## Limites conservées

La RC14 n'est pas une réécriture native du moteur, ni un contournement des politiques de signature/antivirus, ni une nouvelle méthode de renommage distant sans identifiants. Les droits, le DNS, le réseau, les règles de réutilisation des comptes ordinateur et les politiques du domaine restent ceux de votre environnement.
