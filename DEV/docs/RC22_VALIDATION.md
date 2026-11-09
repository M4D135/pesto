# Pesto RC22 : vérifications réellement effectuées

## Binaire et source

Base : archive DEV RC21 fournie. Version : 17.0-RC22 / 17.0.0.22.
EXE natif Windows x64 recompilé, 112128 octets.
SHA-256 : `8ebb438174d06c84d2f914f75e392a11badbeb64b8c2190ee7151d5dcf7ca434`.
Deux compilations séparées produisent le même fichier.
36 composants applicatifs liés aux empreintes incorporées à l'EXE ; cet EXE reste NON SIGNÉ.

Après normalisation des fins de ligne et du seul numéro de version, 23 fonctions sont ajoutées et 35 changées ; 0 supprimées. Les listes et empreintes sont dans RC22_PREUVES/function-changes.json.
Ce décompte décrit une différence de code, pas une preuve de correction de toutes les fonctions.

## Exécuté sous Linux

| Vérification | Résultat |
|---|---|
| Python unittest, tests existants + RC22 | 96 tests réussis |
| Contrôles lexicaux, guillemets, XML, liaisons, ressources, manifestes et PE | 331 réussis |
| Logique C du lanceur avec API Windows simulées | 35 scénarios réussis |
| Construction d'arguments C | 9 cas explicites et 2 000 allers-retours réussis |
| SHA-256 C comparé à Python | 132 cas réussis |
| Compilations indépendantes | Binaire identique |
| Mise à jour : vraie interruption de processus dans une fixture | 37 frontières de copie couvertes dans un test paramétré, restauration exacte |
| Transition depuis les vrais octets de l'archive RC21 | Arrêt après remplacement EXE, retour exact au code RC21 puis mise à jour RC22 ; cfg conservé |

Les 37 frontières ne sont pas 37 tests Python supplémentaires : elles sont incluses dans le total de 96.
Les scénarios de récupération couvrent aussi fichier changé hors mise à jour, sauvegarde altérée, journal traversant, racine de sauvegarde différente, cible liée, exception après remplacement et échec du premier rollback.
Les contrôles de fichiers n'exécutent ni PowerShell ni le binaire Windows.

Un défaut des premiers tests était l'attente de 32 scénarios C au lieu des 35 réellement présents. Une fixture injectait une erreur avant le remplacement de tout fichier différent, donc n'obligeait pas à copier lors du rollback ; l'injection a été déplacée après un fichier réellement différent. Ces premières sorties sont conservées ; les résultats finaux ci-dessus sont ceux du rerun complet.

Le lint a identifié des guillemets typographiques non échappés dans le code et les outils/tests. Leur échappement préserve le texte. Des tests spécifiques couvrent chaînes simples/doubles, échappement, commentaires, here-strings et expressions imbriquées. Ce lint reste limité et ne remplace pas un véritable parseur PowerShell.

## Fourni mais NON exécuté ici

- 33 cas Windows RC22, dont deux cas WPF de palette/tableaux, plus les suites précédentes.
- Parseur Windows PowerShell 5.1, tests comportementaux PowerShell, Pester/ScriptAnalyzer.
- CLR C# du rédacteur de journal, EXE sur Windows, WPF, UAC, ACL/registre et partage réels.
- Jonction, retrait/réinscription Entra, renommage, déplacement, redémarrage et reprise sur VM Windows/AD.
- Lecteur d'écran, DPI, RDP, endurance et mesure de performance sur parc représentatif.

Aucun accès au parc ni identifiant réel de l'utilisateur n'a été utilisé. Un téléchargement d'un moteur de test PowerShell Linux n'a pas abouti ; aucune exécution de ce moteur n'est revendiquée.

## Autorisation de diffusion

Le nom PROD décrit le contenu du pack. Il ne certifie ni l'acceptation des 90 points, ni la recette Windows.
`PublicReleaseAuthorized` reste faux dans les preuves automatiques. Signature approuvée, recette interactive et autorisation de diffusion sont distinctes.
Les anciens rapports RC21 et antérieurs restent historiques ; seul RC22_PREUVES décrit cette itération.
