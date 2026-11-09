# 8 octobre 2026 (soir) — plusieurs techniciens, réservations de noms, reprise après redémarrage, Paramètres

Demandes de David : registre partagé (chemin réglable dans le cfg et dans le logiciel), réservation dans l'AD à la mise au
domaine (option), numéro au hasard (option), « un bon menu config bien chargé », et « voir les fois où il y a eu collision
ou pas ». La reprise après redémarrage (RunOnce) a été faite puis retirée à sa demande.

| Banc (Windows PowerShell 5.1, PESTO-W11-TEST) | Résultat | Fichiers |
|---|---|---|
| Registre partagé sur partage SMB réel (`\\localhost\C$`), 6 processus réservant le même nom au même instant, expiration, verrou, nom invalide | 15/15 | `registre-partage.ps1`, `.txt` |
| Collisions : 4 techniciens (processus), 8 tours, 4 réglages | sans protection 8/8 tours en collision (46 essais) ; hasard 8/8 (13) ; registre 0/8 ; registre + hasard 0/8 | `collisions.ps1`, `collision-tech.ps1`, `collisions.txt`, `collisions.json`, `collisions.html` |
| Vue de jonction WPF : noms réservés ailleurs sautés, réservation après stabilité, nom suivant, libération, simulation, hasard, réservation AD (réserver, revérifier, annuler, pris entre-temps, formulaire modifié) | 23/23 | `noms-reservations-wpf.ps1` |
| Page Paramètres (vrais contrôles de Pesto-Shell.xaml) : chargement, enregistrement typé, valeurs invalides, pas de redémarrage sans changement | 16/16 | `parametres-wpf.ps1` |
| Reprise après redémarrage | banc 16/16 joué, puis option retirée le même soir (décision de David) ; banc supprimé | — |
| Réservation dans l'AD sur l'AD réel du labo (worker de Pesto, `demo-reelle.ps1 -Joindre`) | créé dans Paris avec la description « Réservé par Pesto… », doublon refusé (Taken), retrait (Released), compte absent ensuite | `C:\PestoTest-preuves\demo-reelle\demo-reelle-joindre.txt` (VM) |
| Parseur, check-json DEV et PROD, RC23, stabilisation, bancs noms, services, blocage, UX | 66/0 ; 0 et 0 ; vert ; 27/27 ; 25/25 ; 14/14 ; 14/14 ; 42/44 (2 KO sans bureau, identiques avant) | `controles-windows.txt` |

EXE `cbb0b008…`. Non joué : jonction par Pesto avec réservation AD en session (mot de passe à taper dans Pesto), plusieurs
contrôleurs avec réplication réelle.
