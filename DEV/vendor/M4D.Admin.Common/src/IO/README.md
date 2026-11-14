# IO

API C# 5 / .NET Framework 4.7.2, sans dépendance WPF ou PowerShell.

- `ContentHash.Sha256(path, token)` lit le contenu par blocs de 1 Mio, en lecture partagée sans écrivain autorisé par ce handle. Renvoie SHA256 hexadécimal majuscule. L'annulation est contrôlée avant et après chaque lecture.
- `ContentHash.Sha256(stream, token)` lit de la position courante à la fin et laisse le flux à son propriétaire.
- `FileFootprint.Scan(root, maximumEntries, maximumSeconds, token)` estime le volume logique par métadonnées. Racine absolue obligatoire, 1–3 000 000 entrées, 1–300 secondes. Racine et ancêtres à point d'analyse refusés. Le délai est coopératif entre appels système ; il ne borne pas un appel système bloqué.

`Complete` signifie que le périmètre a été parcouru sans erreur, sans troncature et sans lien de répertoire ordinaire ignoré. Les liens de compatibilité Windows portant **Hidden et System** restent exclus et comptés séparément. Les fichiers à point d'analyse sont comptés par leur taille de métadonnées, sans lire leur contenu. Les 100 premiers incidents au plus sont retournés. Ce résultat n'est ni un instantané, ni une autorisation d'écrire : le produit doit conserver ses contrôles d'identité de volume, chemins, droits, cloud/EFS et ses gardes par handle.

Une surcharge `Scan(..., token, cancellationFile)` conserve l’annulation interprocessus : marqueur local contrôlé au départ, puis au plus toutes les 100 ms entre appels système. Aucun fichier n’est créé par le module.

Aucun cache taille/date ne prouve une empreinte. FILPRO conserve son hachage natif avec lecture anticipée et annulation interprocessus pour les opérations qui l'exigent ; cette API commune n'y est pas substituée aveuglément.

Tests : `IOTests.Run()` sur arbres temporaires, empreintes connues, bornes, annulation immédiate et entre blocs, respect du propriétaire du flux, liens et ancêtres via API de création disponible par réflexion. Les tests de liens sont explicitement omis si API ou permissions absentes. Aucun accès profil Windows ni VM.
