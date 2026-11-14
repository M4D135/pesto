# Audit dans le journal Windows

L’export facultatif utilise le journal **Application**, source **Pesto**. Un collecteur Windows déjà administré peut ensuite récupérer ces événements. Pesto ne crée ni service ni abonnement de collecte.

L’administrateur prépare la source une fois sur le poste exécutant Pesto, dans Windows PowerShell 5.1 élevé :

```powershell
.\integrations\Initialize-PestoAuditEventLog.ps1 -WhatIf
.\integrations\Initialize-PestoAuditEventLog.ps1
```

Le script refuse une source `Pesto` déjà associée à un autre journal. Il ne la supprime pas. La déclaration de source ne déclenche aucune opération AD.

Dans **Paramètres → Options avancées**, activer **Exporter l’audit dans le journal Windows Application**, enregistrer puis relancer Pesto. La clé `POLICY.AuditEventLogEnabled` est un booléen JSON ; son défaut est `false`.

Les événements portent l’identifiant **1000** et une projection de schéma **1** : `Product`, `OperationId`, `Kind`, `State`, `ResultCode`, `Sequence` et `UpdatedUtc`. `Kind` vaut `Intervention`, `Direct` ou `Join`. Les valeurs absentes de code et de séquence restent `null`, sans déduction de succès. Les réservations de noms ne sont pas exportées.

`UpdatedUtc` reprend le dernier horodatage disponible dans le reçu : mise à jour centrale, observation/fin/démarrage direct, ou horodatage du reçu de jonction. Il peut donc précéder la transition observée ; la date de l’événement Windows indique séparément l’émission.

L’export intervient après l’enregistrement durable du reçu. Il contient une projection technique limitée aux identifiants et à l’état de l’opération. Il ne transporte ni nom de poste, ni compte, ni message libre, ni contenu complet du reçu, ni secret.

Si l’export échoue, le reçu reste la preuve principale et le résultat de l’opération n’est pas remplacé par un échec d’audit. Le journal Pesto signale l’incident sans reprendre le message brut du fournisseur Windows. Corriger la source ou les autorisations de collecte ; ne pas relancer une mutation pour recréer un événement.

La désactivation du réglage arrête les prochains exports et conserve les événements déjà écrits. Leur accès et leur rétention dépendent de la configuration Windows de l’organisation.

Le contrôle isolé du transport avec un fournisseur doublé ne qualifie pas une collecte Windows réelle. Cette qualification reste distincte des tests de code.
