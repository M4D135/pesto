# Interface GP RC6 : fonctionnement et architecture

## Une refonte du code, pas une maquette

Le XAML principal et les styles se trouvent dans `wad/GP-Core.ps1`. Aucun moteur web,
image de fond faisant office d'interface, composant téléchargé ou dépendance graphique
supplémentaire. Le formulaire et le DataGrid sont de vrais contrôles WPF reliés aux
handlers existants. Les commandes de fenêtre restent celles de Windows.

Les pages initiales conservent leurs index : formulaire 0, noms 1, paramètres 2,
journal 3. Le menu latéral sélectionne ces pages ; accueil 4, historique 5 et aide 6
sont ajoutés. Changer de page ne recrée ni le tableau de données ni les contrôles.

## Hiérarchie des informations

Les quatre étapes sont un guide, pas quatre validations automatiques. L'étape 4
n'est affichée que pendant un traitement effectivement en cours. Le bouton d'ajout
reste soumis au moteur existant et sa raison de blocage est projetée en clair.

L'aperçu est calculé par `Get-GPUxSnapshot`, qui appelle `Get-GPRenameMoveDecision`.
Il n'écrit rien dans AD, ne coche aucune option et ne modifie aucun droit. En
renommage seul, il affiche l'OU actuelle comme emplacement futur, même si une autre
OU a été proposée dans le formulaire. L'emplacement choisi reste consultable en détail.
Le mot « brouillon » empêche de confondre une intention avec un résultat confirmé.

La file conserve ses 17 colonnes et ses objets DataRow. Six sont visibles initialement.
Le bouton de colonnes techniques ne modifie que leur visibilité, en les identifiant
par leurs liaisons, jamais par un index de ligne après tri. Recherche, filtres, cases
à cocher et avertissement sur les lignes masquées gardent le comportement RC5.

## Aides et accessibilité

Les 132 éléments interactifs déclarés hors templates dans les six gabarits XML
possèdent une infobulle, un HelpText et ShowOnDisabled explicite. Cela comprend les
champs et menus des dialogues de préparation et de configuration. Le navigateur OU,
construit en PowerShell, reçoit ses aides séparément.

Les infobulles attendent 450 ms et restent disponibles jusqu'à 30 s. Les styles limitent
leur largeur et activent le retour à la ligne. Les messages de blocage les plus utiles
sont aussi visibles sans survol. Le bouton Exécuter explique notamment l'absence de
sélection, l'édition d'une ligne, un contrôle en cours ou un verrou de sécurité.

F1 lit l'aide du contrôle ayant le focus, sans lire la valeur d'un mot de passe.
Les raccourcis Ctrl+1/2/3 ne déclenchent que de la navigation. Le contraste et le focus
ont été travaillés dans les ressources ; ni audit lecteur d'écran ni certification
d'accessibilité n'ont été réalisés. Vérifier au clavier et avec votre affichage Windows.

## Mise en page et thèmes

Sous 1260 unités de largeur WPF, le panneau d'aperçu passe sous le formulaire et la
barre latérale se réduit. Le contenu devient défilant, le pied d'exécution reste fixe.
Au-delà, les deux colonnes et le séparateur réapparaissent. Les contrôles sont réutilisés.
Les styles conservent les parties WPF obligatoires des ComboBox et TextBox, ainsi que
les paramètres de virtualisation des listes et de la file.

La palette se trouve dans le moteur ; `RC6_UI_TOKENS.json` en est la copie de référence
pour les tests. Le thème, les colonnes techniques et l'ouverture des options sont
conservés dans `gp.prefs.json`, avec ExperienceVersion=6. Aucune réécriture de cfg.json
n'est nécessaire pour changer la présentation. Le thème est relu avant le login.

## Lecture de poste temporisée

La saisie efface immédiatement l'ancien plan, désactive l'ajout et invalide la génération
d'une lecture précédente. Le timer de 350 ms temporise seulement le lancement de la
nouvelle lecture. Le contexte mémorise le nom, le mode local/distant et l'index d'édition :
un changement de contexte abandonne cette demande. Entrée ou Lire le poste déclenche
la lecture explicitement, jamais un ajout ou une mutation.

Les timers de recherche et d'aperçu utilisent des fonctions nommées liées au script,
pas une closure privée `GetNewClosure`. Ils sont arrêtés à la fermeture. Une erreur
sur l'aperçu est journalisée ; les gardes de mutation ne sont pas désactivées.

## Conservation et limites

Le rapport `tests/rc6-preservation-report.json` compare RC5 et RC6. Les 223 fonctions
non adaptées sont identiques ; les 12 fonctions modifiées concernent la présentation,
les préférences ou les demandes de rafraîchissement UI. Les 23 nouvelles fonctions
constituent la couche de présentation. Le code de décision, les workers, les résultats,
les contrôles d'identité, le checkpoint atomique et le verrou de sécurité sont conservés.
Cette égalité de source ne remplace pas une recette d'intégration.

Les fonctions RC5 restent disponibles : lot de 200 postes, contrôle AD en lecture seule,
fiches de résultat, CSV, rapport HTML, reprise du déplacement seul et historique.
L'accueil compte le cache et la file ; il ne prétend pas mesurer les machines en ligne.
L'historique local est limité à 100 entrées, au domaine courant et à 2 Mio, sans relance.

La refonte reprend le style visuel demandé, pas une reproduction pixel à pixel garantie.
Le rendu dépend de la taille, du DPI et de WPF : il doit être vérifié sous Windows.

## Documentation primaire utilisée pour les contrats WPF

Microsoft Learn : styles et modèles de ComboBox (PART_EditableTextBox, PART_Popup),
ToolTipService.ShowOnDisabled et AutomationProperties.HelpText.

- https://learn.microsoft.com/en-us/dotnet/desktop/wpf/controls/combobox-styles-and-templates
- https://learn.microsoft.com/en-us/dotnet/api/system.windows.controls.tooltipservice.showondisabled
- https://learn.microsoft.com/en-us/dotnet/api/system.windows.automation.automationproperties.helptext

Ces références documentent les API ; elles ne valident pas ce projet.
