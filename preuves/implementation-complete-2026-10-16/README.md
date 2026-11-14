# Implémentation complète — 16 octobre 2026

Demande : intégrer aussi les points précédemment étudiés. Le catalogue garde le développement distinct de la qualification.

## Canal GPO existant (112)

- `optional-baseline.json` : 11/11 ; profils/scénarios préparatoires et contrats GPO/XML, aucune intégration des prototypes déduite de ces tests.
- `config-editor-baseline.json` : 26/26 ; éditeur, préservation des valeurs locales face à la GPO.
- Exécution PowerShell 7.4.20 sur Mac, pas de WPF/AD, aucune GPO appliquée.
- Revue : Core charge ManagedPolicy et ConfigEditor ; Configuration appelle Sync-PestoManagedSettings ; ConvertTo-PestoPolicy fusionne les restrictions, Assert-PestoOperationPolicy les relit avant les effets.

Ces preuves ne qualifient pas les nouveaux compléments encore en développement.
