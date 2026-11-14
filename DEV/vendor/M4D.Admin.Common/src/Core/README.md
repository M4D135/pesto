# Core

`RandomSelection.NextIndex(count)` renvoie un indice uniforme dans `[0,count)`.
Le générateur cryptographique du système fournit des octets indépendants d'une
graine fixe, du nom du poste ou de son horloge. Une méthode de rejet supprime le
biais du modulo ; un tampon synchronisé évite une allocation et un appel système
par candidat. Deux postes peuvent légitimement tirer le même nom : aucune méthode
aléatoire ne remplace une vérification de disponibilité ni une réservation.

`Sample<T>(candidates,count[,cancellation])` parcourt **tous** les candidats fournis
et réalise un échantillonnage uniforme sans remise par réservoir. La mémoire dépend
du nombre demandé. L'appelant fournit une séquence déjà filtrée et sans doublons ;
les filtres, droits et réservations restent sa responsabilité. Aucune pagination
ou limite aux premiers candidats n'est appliquée par ce module.

Les surcharges `IRandomSource` rendent les tests déterministes. Une entrée
incomplète, un débordement du compteur ou une annulation lèvent une exception ;
aucun échantillon partiel n'est retourné comme résultat complet. La sélection
ne réserve rien et n'exécute aucune mutation.
