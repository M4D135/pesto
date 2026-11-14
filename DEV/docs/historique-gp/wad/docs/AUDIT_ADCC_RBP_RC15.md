# Audit et harmonisation GP / ADCC / RBP

## Périmètre

Base de code modifiée : le GP_17_RC14_COMPLET_EXE(1).zip fourni dans cette conversation. Les choix ADCC/RBP proviennent des décisions retrouvées et des documents de bibliothèque ADCC_Interface_Compacte_R1.10.md, RBP_2.3.0_Nouveautes.md, RBP_2.3.0_Recette_Windows.md et ADCC_Audit_Harmonisation_GP_RBP.md. Il ne s'agit pas d'une lecture exhaustive certifiée de tous les messages, ni d'une revue complète de leurs moteurs ou d'une assertion qu'aucune version ultérieure n'existe.

GP seulement a été modifié. Aucune donnée ADCC/RBP, aucun mot de passe, base d'association ou composant USMT n'est importé. Les moteurs d'identification, de sauvegarde/profil et de jonction n'ont pas été fusionnés.

## Repères repris

| Origine documentée | Application dans GP RC15 |
|---|---|
| ADCC : rail gauche repliable, aide droite masquable et superposée en fenêtre étroite | Navigation/aide avec préférence de présentation, pas de changement de droits ou recherche implicite. |
| ADCC : chemin lisible, DN exact conservé pour la technique | Aperçus et état du poste présentent l'emplacement lisible ; la valeur LDAP utilisée par le moteur reste le DN exact. |
| ADCC/RBP : login compact et non maximisable, informations utiles seulement | Login conservé compact, suppression de la phrase superflue, thème et Verr. Maj, identité effective visible. |
| RBP : thème écrit seulement sur choix explicite, préférence liée à l'utilisateur de départ à travers UAC | Stockage de présentation propre à GP sous HKU SID d'origine, erreur de sauvegarde signalée, pas de partage de secret ou clé RBP. |
| RBP : journal lisible et préférences de lecture | Recherche, suivi suspendable, taille, retour à la ligne et rendu borné ; audit sur disque conservé. |
| GP/ADCC : distinction intention, commande engagée, résultat à vérifier | Worker unitaire avec reçu, étape/durée et rejet des retours tardifs ; reprise guidée uniquement sur preuves suffisantes. |
| RBP/ADCC : EXE + wad, contrôle de présence/cohérence et distribution propre | GP.exe compilé, --check et manifestes de composants ; pack utilisateur séparé du développeur. |
| ADCC : droits et cibles explicites, simple/avancé ne modifie pas les permissions | Les onglets et options de présentation ne changent pas les garde-fous du moteur. |

Les références de présentation servent à uniformiser les repères, pas à prétendre que tous les logiciels utilisent déjà un SDK partagé. Les composants GP portent encore leur espace de noms GP ; une migration commune des trois dépôts demanderait des modifications et recettes séparées.

## Les 15 points demandés

| # | Réalisation dans le source RC15 | Emplacement principal |
|---|---|---|
| 1 | Clair/Sombre/Système séparé du cfg, sauvegarde explicite, origine UAC, avertissement d'écriture | GP-Appearance.ps1, GP-Startup.ps1 |
| 2 | Apparence / Domaine / Options avancées, libellés de thème lisibles | GP-Shell.xaml, GP-Configuration.ps1 |
| 3 | Phrase du logon retirée, login compact, indication du compte et étapes utiles | GP-Authentication.ps1 |
| 4 | Suite native et captures du vrai WPF fournies, scénarios DPI/écrans documentés ; exécution Windows encore à faire | maintenance/Test-GP15.ps1, VALIDATION_RC15.md |
| 5 | Snapshot léger au login ; inventaire complet à la demande Noms/Lots | GP-Directory.ps1 |
| 6 | Plan unitaire, contrôle, confirmation et worker indépendant sans DataRow ni Run-Queue | GP-Direct.ps1 |
| 7 | Paramètres d'affichage sans file vidée ; changements métier invalidant les contrôles, pas les plans | GP-Configuration.ps1 |
| 8 | Filtre de sites local, sélections valides conservées, lecture du poste volontaire, message/focus au champ à corriger | GP-SuiteUI.ps1, GP-Core.ps1 |
| 9 | Observation datée Windows actif/configuré + AD GUID/OU, inconnus conservés | GP-Inspection.ps1 |
| 10 | Étape/durée réelles, pas de faux %, journal lisible et borné | GP-Async.ps1, GP-Journal.ps1 |
| 11 | Observation avant reprise, déplacement seul après partiel, résultat précédent conservé, aucune levée aveugle | GP-Inspection.ps1, GP-Support.ps1 |
| 12 | Erreur résumée, effet connu et prochaine étape, détails séparés | GP-Support.ps1 |
| 13 | Diagnostic en liste blanche, masqué et prévisualisé, pas de logs bruts ni secrets | GP-Support.ps1 |
| 14 | EXE compilé, manifeste de cohérence, trois paquets distincts | GP-Integrity.ps1, tools/launcher |
| 15 | Modules séparés et tests régressifs courants ; fonctions sensibles comparées exactement | GP-Configuration/Authentication/Directory/Async/Journal/Operations.ps1 |

Cette matrice indique l'intégration du code, pas une certification des 15 comportements sous Windows. Le point 4 comporte précisément la suite et le protocole fournis, pas un test Windows déjà exécuté.
