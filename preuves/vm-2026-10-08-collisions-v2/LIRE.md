# Collisions de noms : audit, correctifs et banc v2 sur l'AD réel (08/10/2026, soir)

Question de David : « avec quelle méthode t'as testé la collision avec le partage, mais on avait aussi l'option random
name et celle de créer l'objet ».

## Ce que le banc v1 ne prouvait pas

Banc v1 (`../vm-2026-10-08-reservations/collisions.ps1`) : 4 processus, registre réel sur `\\localhost\C$`, mais un « AD »
simulé par un dossier, un tirage au hasard réécrit dans le script, une réservation faite avant l'affichage (Pesto affiche
puis réserve 1 à 2 s plus tard) et aucune réservation AD. Audit du code (3 lecteurs, vérification contradictoire de chaque
affirmation, critique de complétude) : `audit-collisions.json` (rapports des lecteurs, verdicts, scénarios manquants).

## Défauts de Pesto trouvés et corrigés (EXE 3ee6ee79, puis 203f0a4c après relecture)

1. Registre : rien n'était réservé pendant la vérification, la confirmation et l'exécution. Un technicien qui cliquait
   dans la seconde suivant l'affichage, ou un nom changé par Pesto en cours de route, n'était jamais réservé. Corrigé :
   réservé au tick suivant, prolongé, jamais libéré pendant l'opération.
2. Registre : la réponse « détenu par un autre poste » arrivée pendant la vérification était ignorée ; l'échec venait après
   la confirmation. Corrigé : nom suivant, revérifié, avant la réservation AD et la confirmation (jonction et renommage).
3. Fermeture : la libération des réservations était lancée puis annulée aussitôt ; le compte AD réservé et jamais utilisé
   restait dans l'AD. Corrigé : libération attendue 3 s au plus, compte AD retiré (8 s au plus).
4. Hasard : graine tirée de l'horloge (mêmes tirages pour deux Pesto ouverts au même instant). Corrigé : graine GUID.
5. Message « premier numéro libre de la série » faux avec le hasard. Corrigé.
6. Poste hors domaine : le registre et le verrou d'opération utilisaient le jeton du compte local, sans droit sur un
   partage du domaine : toute mise au domaine était refusée (« Coordination non préparée ») dès qu'un registre était
   configuré. Corrigé : connexion au partage avec le compte AD saisi dans Pesto (New-PSDrive -Credential, sans lettre ni
   mot de passe enregistré). Test réel avec mot de passe : `registre-hors-domaine.ps1` (voir plus bas).

## Relecture contradictoire du correctif

3 relecteurs (exactitude, sécurité, régressions), chaque point soumis à un vérificateur chargé de le réfuter : 11 points, 7 confirmés et corrigés (EXE 203f0a4c), 4 réfutés.

- Fermeture pendant la création ou le retrait d'un compte réservé dans l'AD : compte orphelin possible. Fermeture refusée pendant ces quelques secondes.
- Nom seulement réservé au registre : écarté pour toute la session et noté « déjà utilisé dans l'AD ». Écarté tant que la réservation dure, Journal exact.
- Connexion au partage ouverte avec le compte AD : active jusqu'à la déconnexion Windows. Fermée à la fermeture de Pesto.
- Worker du registre : connexion tentée avant de lire le registre avec le jeton du processus. Ordre inversé.

## Bancs

| Banc (Windows PowerShell 5.1, PESTO-W11-TEST) | Résultat |
|---|---|
| `noms-correctifs-wpf.ps1` : correctifs 1, 3, 4, 5, 6 sur la vraie vue de jonction WPF | 27/27 |
| `../vm-2026-10-08-reservations/noms-reservations-wpf.ps1` : + correctif 2 | 25/25 |
| Suite habituelle (parseur 66/0, check-json, stabilisation 27/27, noms 25/25, services 14/14, blocage 14/14, registre SMB 15/15, paramètres 15/15, UX 42/44 : 2 mesures sans bureau, comme avant) | verte |
| `collisions-v2.ps1` + `collision-v2-tech.ps1` : banc v2 sur l'AD réel, sous LABO\tech.pesto (Kerberos) | voir ci-dessous |

### Banc v2 (`collisions-v2.txt`, `collisions-v2.json`, rapport `collisions-v2.html`)

Arbitre AD : 4 processus réservent le même nom à la même milliseconde avec le worker de Pesto : un seul compte, trois
« Taken » (3 essais sur 3). Nom existant dans une autre OU : « Taken » aussi. Un nom supprimé peut être recréé.

4 techniciens, 6 tours par réglage, 2 profils (départ simultané ; départs étalés sur 6 s), 108 tours, 432 ajouts :
0 doublon, 0 compte orphelin, 0 erreur, 0 compte restant dans les 112 séries utilisées.

Refus après confirmation (le technicien doit reconfirmer), sur 24 ajouts :

| Réglage | Simultané | Décalé |
|---|---|---|
| Sans protection | 36 (18 techniciens ont reconfirmé, jusqu'à 4 fois) | 29 |
| Hasard (5) | 7 | 6 |
| Registre, ancien comportement | 31 | 30 |
| Registre corrigé | 0 (26 bascules avant confirmation) | 0 |
| Registre + hasard | 0 | 0 |
| Réservation AD | 0 (29 bascules avant confirmation) | 0 |
| Réservation AD + hasard | 0 (6 bascules) | 0 |
| Registre + réservation AD | 0 | 0 |
| Tout | 0 (6 bascules) | 0 |

Durée moyenne d'un ajout : 11,1 s sans protection, 5,9 à 7,7 s avec une protection (moins de reprises).

Méthode : vrai code de Pesto (fonctions et workers extraits des fichiers livrés, empreintes en tête du rapport), runspace
neuf par appel AD ou registre comme Pesto ; sélection du nom, minuterie du registre et enchaînement reproduits sans fenêtre ;
la jonction est remplacée par la création du compte dans l'OU (ce que fait Add-Computer), précédée des relectures et du
verrou du worker de jonction.

Limites : une seule VM (processeur partagé, SMB en boucle locale), un seul DC (réplication non testée), parcours « Ajouter
au domaine » seulement, 6 tours par case (les réglages protégés ne se départagent pas entre eux à ce volume).

### Contrôle du code final (EXE 203f0a4c, `final/`)

Après la relecture : réglages avec registre, départ simultané, 6 tours (`collisions-v2-final.ps1`). Refus après confirmation : 0 pour Registre (27 bascules avant confirmation), Registre + hasard (6), Registre + réservation AD (21), Tout (2). 0 doublon, 0 orphelin, 0 erreur, 0 compte restant dans les 28 séries. Suite Windows sur cet EXE : parseur 66/0, check-json 0, stabilisation 27/27, noms 25/25, services 14/14, blocage 14/14, registre SMB 15/15, jonction 25/25, paramètres 15/15, correctifs 32/32, UX 42/44 (2 mesures sans bureau).

## Test hors domaine avec mot de passe

`registre-hors-domaine.ps1` (lancé par `outils/labo/mac/registre-hors-domaine.sh`, mot de passe de LABO\tech.pesto tapé
par David) : partage de test ouvert au seul compte AD, refus au compte local, registre et verrou d'opération avec le compte
AD, puis partage supprimé. Résultat : voir `registre-hors-domaine.txt` s'il est présent.
