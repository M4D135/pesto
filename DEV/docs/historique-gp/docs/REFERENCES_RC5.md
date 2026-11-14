# Références techniques RC5

Références Microsoft consultées pour la conception. Elles documentent les API,
mais ne valident pas l'exécution de GP dans l'environnement cible.

- Get-ADComputer : recherche, ObjectGUID, Server, Properties et ResultSetSize.
  https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adcomputer?view=windowsserver2025-ps
- DataColumn.Expression : grammaire des expressions DataView, littéraux et LIKE.
  https://learn.microsoft.com/en-us/dotnet/api/system.data.datacolumn.expression?view=netframework-4.8.1
- DataView.RowFilter : filtrage d'une vue sur DataTable.
  https://learn.microsoft.com/en-us/dotnet/api/system.data.dataview.rowfilter?view=netframework-4.8.1

Le correctif RC4 de File.Replace/NullString.Value, les décisions de site et le
moteur de callbacks RC3 sont gardés et vérifiés par leurs gardes de source dédiées.
Aucun module téléchargé n'est nécessaire aux nouvelles fonctionnalités.
