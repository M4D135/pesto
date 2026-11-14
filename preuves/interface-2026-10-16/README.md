# Pesto — interface et recette du 16 octobre 2026

## Candidat

Sources : `f8a531e38f69ae218bf9ef9b1934fdf942e43aaf` (interface `3174181`, collecteur de mesure `0343830`, DCOM `f8a531e`).
EXE livré : `d5d1ab86646fb18136deb07919da9ecf65045e4d4e2ac61cb6ff98bcbe25d631`.
Packs classiques, configuration neutre issue de `tools/cfg.template.json`.
Les guides v1.0 restent applicables ; ce lot corrige la disposition et le collecteur de mesure.

## Corrections et preuves

- La page de jonction remplit la largeur disponible. Le champ service et son état restent groupés lors du passage en une colonne.
- En petite fenêtre, la barre d’outils, les étapes et les avertissements occupent des lignes distinctes.
- Le pilote de recette refuse la session 0, l’écran verrouillé et un bureau autre que le bureau interactif normal. Il conserve une fenêtre maximisée.
- La création des options DCOM utilise le jeu de paramètres natif compatible avec Windows PowerShell 5.1, avec confidentialité des paquets. Le double de test respecte ces jeux exclusifs ; un cas Windows appelle aussi la vraie cmdlet sans connexion réseau.
- Le collecteur ne prend plus un échantillon prématuré quand Windows écourte légèrement le dernier délai. Le test de terminaison du processus est compatible avec les closures de Windows PowerShell 5.1.

| Preuve | Résultat et portée |
| --- | --- |
| `presentation.json` | 54 contrôles portables réussis ; contrats et source, sans WPF ni AD |
| `zoom-wpf.json` | 44 contrôles réussis sous Windows PowerShell 5.1 ; XAML réel, sans mutation AD |
| Régressions avant correctif | Largeur de jonction, chevauchement de l’en-tête et réveil prématuré reproduits |
| `desktop-guard.json` | Session 0 refusée, session verrouillée refusée, bureau visible accepté |
| `session-measure-windows.json` | 9 contrôles réussis, vrais compteurs et fichiers locaux |
| `g17-*.png` | Captures réelles du build interface `a596489…` : plein écran 1920×1200, fenêtre 1024×768 à 120 % ; XAML identique au candidat livré |
| `remote-preparation-windows.json` | 27/27 sous Windows ; ancien appel en échec dans 3 cas, dont la vraie cmdlet |
| `packs-inspection.json` | CRC valides, chaque entrée égale à la source neutre, aucune archive WAD |

Le banc WPF couvre 1920×1200, 1024×768, 760×560 puis le retour à la grande taille, aux zooms 80, 100 et 150 %. Ces dimensions de banc ne certifient ni tous les DPI physiques, ni le multi-écran, ni Narrator. Les captures GUI sont distinctes des tests de layout sans fenêtre affichée.

## Recette réelle

La cliente `PESTO-REMOTE-CLIENT-20261015` a été jointe une seule fois puis redémarrée. Nom actif et configuré : `V111301VA765183`, domaine `labo.local`, OU Paris, canal sécurisé valide. La lecture depuis l’interface confirme l’objet AD `8a34ef81-1275-4718-8ee6-d423b0903b6f`. La confirmation d’une observation fraîche a fait passer le reçu `cd9f2618aa8a4add9315ec2ef1275613` à `Verified`. Une observation périmée a été refusée avant relecture.

La cliente a préparé `P111301VA765480` → `V111301LY765664` avec déplacement de Paris vers Lyon, puis la confirmation a été actionnée. Le moteur a refusé avant toute mutation (code 96) : les paramètres `-Protocol Dcom -PacketPrivacy` étaient incompatibles. Le correctif `-PacketPrivacy` seul est reproduit et validé sous Windows. Une lecture DCOM réelle après ce correctif atteint Windows mais reçoit **Access is denied** pour `LABO\tech.pesto`. Aucun renommage ni déplacement distant n’est annoncé réussi. La cible conserve son nom et son objet AD `b4797c9c-d790-4797-bf71-424a57acb36e`.

À la demande de David de limiter la consommation, le débogage VM s’arrête à ce contrôle ciblé. Il reste à régler les droits distants du compte de recette puis à refaire le parcours GUI, le redémarrage et la vérification du même GUID/OU/canal. Aucune règle de pare-feu n’a été modifiée. Le dernier EXE reconstruit est livré dans les packs ; il n’a pas été relancé dans la GUI des VM. Les installations candidates des VM restent au build interface `a596489…`.

## Revue et limites

La réponse Spark est conservée avec son examen. Le principe d’un contrôle géométrique a été retenu ; sa proposition de marge fixe est remplacée par un conteneur qui fait participer le texte à la disposition. La réponse n’est pas une preuve d’exécution. OpenCode DeepSeek gratuit a refusé l’appel CLI (HTTP 403), sans bascule payante.

Les premières captures verrouillées et les captures antérieures au correctif ne comptent pas comme validation finale. Les archives historiques restent intactes. Aucune restauration de DC01 ni intervention sur les VM voisines n’est comprise dans cette recette. Le nettoyage FILPRO est confié à sa propre session par David. Aucune sauvegarde de disque de VM n’est conservée sur le Mac.

Cette campagne apporte des preuves ciblées aux points 99, 100 et 106. Elle ne transforme pas l’ensemble des 120 points en qualification complète : voir les limites du catalogue et la qualification générale précédente.

## CI finale

La [campagne 38869819782](https://github.com/M4D135/pesto/actions/runs/38869819782) réussit sur Linux, Windows 2022/en-US et Windows 2025/fr-FR, au commit `f8a531e38f69ae218bf9ef9b1934fdf942e43aaf`. Les métadonnées des artefacts, rapports WPF et journaux des suites isolées sont conservés dans `ci-38869819782/`. Cette CI n’effectue aucune mutation AD.
