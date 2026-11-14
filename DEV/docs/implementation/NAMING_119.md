# Convention de nommage définissable

Le champ `NamingConvention` de la configuration définit l'ordre et la largeur des
facettes. Il reste facultatif ; son absence conserve le format historique.

```json
{"Schema":1,"Id":"atelier","Tokens":["Service","Number","Type","Prefix","Site"],
 "Widths":{"Prefix":3,"Site":2,"Service":2,"Number":2},"Types":"PSV"}
```

Avec le préfixe `123`, le site `AB` et le service `IT`, le premier portable s'appelle
`IT01P123AB`. Le numéro peut se trouver au milieu. Les largeurs sont fixes, les cinq
facettes obligatoires, le total limité à 15 caractères et le numéro compris entre
1 et `10^largeur - 1`. Préfixe et numéro sont numériques ; site alphabétique ; service
alphanumérique. Adapter aussi `CONF.Prefixe`, `CONF.PreprodSite`, `TAGS` et le catalogue
de sites/services aux largeurs déclarées. Importer et valider la configuration par
le parcours de paramètres existant ; aucune réécriture des anciens noms n'est faite.

La convention atteint le parsing inverse, les disponibilités, la pagination et les
propositions, les réservations, l'index compact, les capacités, la préparation par
lot, les filtres LDAP et la jonction silencieuse. Les workers reçoivent une copie
fermée et revalidée du contexte. Les caches d'index sont invalidés lors d'un changement
de convention ; les plans restent liés à l'empreinte de configuration.

`Run-NamingConvention119Tests.ps1` vérifie chargement, validation et reconfiguration.
`Run-NamingFlows119Tests.ps1` exerce les fonctions réelles, les bornes 01–99, un numéro
au milieu, les champs de longueurs différentes, les réservations et des runspaces
vierges. `Run-WorkerContractTests.ps1` contrôle les dépendances des workers réels.
Aucun test AD ou VM n'est réalisé par ces suites.
