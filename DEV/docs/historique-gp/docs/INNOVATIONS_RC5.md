# Innovations RC5 : mode d'emploi

## 1. Préparer plusieurs postes sans exécuter leur traitement

Dans l'onglet Actions, préparez le formulaire sur un poste distant : choisissez
le type, l'organisme, le site cible et le service. Cliquez sur **Préparer un lot**.
La fenêtre reprend ce modèle ; elle ne relit pas le réseau en arrière-plan.

Collez les noms courts des ordinateurs, jusqu'à 200. Séparateurs acceptés : espaces,
retours à la ligne, tabulations, virgules ou points-virgules. Pas de FQDN ni de CSV
multicolonnes. Un doublon ou une source inconnue refuse la préparation entière.

La case **Conserver le type du nom source** maintient P ou S pour les noms conformes.
Pour un ancien nom non conventionnel, décochez cette case pour employer le type
choisi dans le formulaire. La convention générée demeure P/S + préfixe de six
chiffres + site de deux lettres + service de trois caractères + numéro 001 à 999.

**Construire le plan** cherche les premiers numéros non présents dans le cache
AD chargé, les cibles déjà réservées dans la file et les autres lignes du lot.
Il ne réserve aucun nom dans l'annuaire et ne crée aucun objet. D'autres opérateurs
peuvent choisir les mêmes noms entre-temps : le contrôle AD et les gardes du moteur
restent nécessaires. Si la plage est épuisée, aucune portion du lot n'est ajoutée.

La référence de lot/ticket est facultative, limitée à 120 caractères. Elle est
reprise sur toutes les lignes et dans les exports ; n'y saisissez aucun secret.
Une modification des sources, de la référence ou du maintien du type invalide
l'aperçu précédent. **Ajouter les lignes décochées** est la seule action qui
insère le lot dans la file. Aucune ligne n'est cochée et aucun reboot n'est demandé.

## 2. Contrôler les intentions avant leur exécution

Cochez les lignes et utilisez **Contrôler (lecture AD)**. La lecture examine la
source, son identité GUID lorsqu'elle est connue, son OU, le périmètre configuré,
le nom cible, l'OU cible effective et la politique de levée de protection.

| État | Sens |
|---|---|
| À CONTRÔLER | Aucun contrôle de cette préparation. |
| VÉRIFIÉ | Les contrôles en lecture effectués n'ont pas relevé de blocage. Pas une garantie de mutation. |
| AVERTISSEMENT | Lecture réalisée, mais point à examiner : ICMP sans réponse, compte désactivé ou levée temporaire de protection prévue. |
| BLOQUÉ | Plan incompatible ou lecture ne permettant pas de le valider : identité modifiée, cible occupée, source ambiguë, OU absente/inaccessible, etc. |
| DÉMO | Données fictives, aucun accès AD. |
| PÉRIMÉ | Observation de plus de cinq minutes, ou changement incohérent d'horloge, constaté lors du rafraîchissement. |
| À REFAIRE | Session nouvelle, intention modifiée ou contrôle interrompu/invalide. |

Un contrôle incomplet ou invalide ne produit pas de faux succès. Une erreur
pendant l'application des résultats supprime les approbations de lecture de la
session. L'annulation n'applique aucun nouveau résultat ; les éventuelles lectures
précédentes restent datées. Les callbacks tardifs sont rejetés par génération.

La sonde ICMP est indicative. Le délai global du contrôle est de 120 secondes,
pas 120 secondes par machine ; un lot lent peut nécessiter d'être scindé. Le délai
ICMP par appel n'est pas une borne de résolution DNS. Le worker est demandé à
l'arrêt à expiration, sans bloquer volontairement le thread WPF sur Stop().
Aucune mutation n'est réalisée par ce worker.

Le précontrôle est facultatif. Sa présence, sa date et les lignes cochées masquées
sont annoncées à la confirmation. Les gardes AD du moteur restent actives même
sans contrôle. Une observation BLOQUÉ connue pour le plan courant interdit son
lancement : corriger la situation puis contrôler à nouveau, ou recréer correctement
une intention différente. Le CSV ne transporte pas une autorisation de session.

## 3. Identifier l'objet et détecter les changements depuis la préparation

Une ligne prépare l'OU source et, lorsqu'il est disponible, le GUID AD. Avant un
renommage et avant un déplacement, le moteur compare ces valeurs à la source
relue. Une dérive refuse l'action au lieu de viser silencieusement un autre objet.
Si le GUID n'était pas disponible dans le cache, une lecture réussie peut l'épingler.
Un GUID absent n'est jamais présenté comme une identité vérifiée auparavant.

Cela réduit le risque d'agir sur un objet changé depuis l'ajout ; ce n'est ni un
verrou distribué AD ni une transaction globale. Un autre administrateur peut agir
entre la lecture et la mutation. Le déplacement continue d'utiliser le GUID.

La décision RC4 reste : même site, renommage seul ; autre site, renommage puis
déplacement après succès. Un déplacement explicite seul reste possible. Un résultat
partiel 89 se reprend avec **Reprendre déplacement**, pas en renommant de nouveau.
Les codes 32/97/98 conservent leur arrêt de sécurité et leur vérification manuelle.

## 4. Lire et filtrer une file volumineuse

Les colonnes initiales deviennent : case de traitement, nom actuel, nouveau nom,
plan, statut et contrôle. Le nom source reste figé horizontalement. Le tri est
activé. L'édition résout la DataRow réelle, pas l'index de la vue filtrée.

La recherche, accessible avec Ctrl+F, porte sur noms, organisme, site, service,
référence et message. Elle est limitée à 128 caractères et différée de 220 ms.
Les caractères de la grammaire RowFilter sont échappés comme du texte.

**Tout cocher / tout décocher agit sur les lignes visibles uniquement.** Les
résultats historiques/sensibles ne sont pas cochés automatiquement. Les lignes
cochées mais masquées restent dans l'exécution ; le compteur et la confirmation
le signalent explicitement. Le filtre n'est pas une sélection d'autorisation.

**Détails** affiche le plan avant/après, la lecture UTC, le GUID, le mode du résultat,
le lot, sa durée, son message et une consigne adaptée au code de résultat.
Le suivi en bas indique l'action courante, les lignes terminées et le temps écoulé,
sans inventer une estimation d'achèvement.

## 5. Conserver un bilan exploitable

**Bilan HTML** exporte TOUTE la file, pas uniquement la vue filtrée. Le fichier est
autonome, imprimable depuis le navigateur et sans JavaScript ni ressource distante.
Les valeurs sont échappées et les motifs de mots de passe sont masqués en défense
supplémentaire. Aucune garantie n'est possible pour un secret placé librement dans
un champ métier : ne saisissez aucun mot de passe dans les références ou messages.

Le rapport distingue la destination prévue du résultat consigné, et le mode de
chaque résultat du mode actif au moment de l'export. Les anciennes données non
qualifiées restent indiquées comme telles. Le rapport est un relevé local modifiable,
ni une preuve signée ni une relecture du poste après redémarrage.

**Historique** liste les 100 derniers lots terminés dans ce profil/installation.
Il ne contient que des synthèses : nombre d'actions, résultats, mode, date, identifiant
et état du verrou. Un arrêt brutal peut empêcher la synthèse ; le journal et le
checkpoint restent prioritaires. Aucun bouton de replay n'est ajouté.

Les exports contiennent des noms de postes et des chemins d'annuaire. Conservez-les
dans un emplacement interne approprié, avec la politique de rétention de l'organisme.
