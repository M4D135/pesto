# 8 octobre 2026 — services en quelques secondes, « Vérifier » grisé (signalé par David sur le réseau réel)

Signalement : « ça met 30 s mini pour afficher un service alors qu'avant non. et le bouton vérification est grisé ».

Cause (code relu, enquête multi-agents contre-vérifiée) : depuis S1 (05/10), la liste des services et les numéros déjà
pris venaient seulement de l'inventaire complet (tous les postes de l'OU racine et du périmètre des noms), lu en
arrière-plan ; sur un grand domaine, 30 s et plus. Sans service, aucun nom proposé : « Vérifier » grisé (jonction : plan
incomplet ; « Un poste » : « Compléter le formulaire » actif, « Vérifier » grisé, sans dire ce qui manque).

Correctif : `Request-PestoSiteLookup` (`Pesto-Directory.ps1`), au choix du site dans « Ajouter au domaine » et « Un poste » :
deux requêtes ciblées en arrière-plan (noms `P|S|V` + préfixe + code site dans tout le domaine ; noms conformes de l'OU du
site), lecture seule, résultat mis en cache pour la session et effacé après une intervention ; listes complétées sans
effacer la saisie. L'inventaire complet reste lu en arrière-plan mais n'est plus attendu. « Un poste » : le texte sous le
bouton dit ce qui manque (type, organisme, site, service, nom, options).

| Contrôle | Résultat | Preuve |
|---|---|---|
| Mac : tests Python, contrôles portables, UX statiques, connexion compacte, banc C | 259 OK ; 344/344 ; 50/50 ; 33/33 ; 48 scénarios | — |
| Windows PowerShell 5.1 (`PESTO-W11-TEST`, sans bureau) : parseur, `--check-json` DEV et PROD, RC23, stabilisation, banc noms | 66/0 ; 0 et 0 ; vert ; 27/27 ; 25/25 | `controles-windows.txt` |
| Vrai worker de recherche ciblée (runspace séparé, AD simulé : 3 005 postes, 300 ms par requête) + vraie vue de jonction WPF | 14/14 ; services CPT, INF, RH0 et nom libre 003 affichés en 1,1 s ; aucune lecture complète ; échec AD sans effet | `services-rapides-wpf.ps1`, `services-rapides-wpf.txt` |
| Tests UX Windows (`Run-UxTests.ps1`) | 42/44 ; les 2 KO (mise en page réelle 1460 x 940) sont identiques sur la version précédente : bureau absent | `ux-windows.txt`, `ux-windows-version-precedente.txt` |
| AD réel du labo : recherche ciblée mesurée dans `banc-noms-serie.sh` | en attente du mot de passe de David | — |

EXE `c5fb8ba6…`. Non mesuré sur le réseau réel de David.
