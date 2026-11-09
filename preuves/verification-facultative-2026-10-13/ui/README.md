# Suivi facultatif — présentation et parcours

Validation locale du 13 octobre 2026 : reçus synthétiques privés, fonctions réelles extraites par AST, aucun accès AD/Windows/registre ni lancement de l’application.

- OptionalFollowupUi : 16 contrôles, 0 échec. Une commande acceptée laisse préparer une nouvelle opération ; l’ancien reçu reste inchangé. La jonction exige toujours un démarrage ultérieur et un état local cohérent avec canal sûr. Les états Running, Uncertain, Partial et Protection conservent leur action de contrôle.
- HomeDashboard : 46 contrôles, 0 échec. Le suivi facultatif reste visible dans les opérations récentes sans alerte obligatoire.
- InterventionView : 21 contrôles, 0 échec. Les reçus restent dans le filtre À suivre ; les effets incohérents ne sont pas présentés comme facultatifs.
- UiPresentation : 43 contrôles, 0 échec.

Le banc OptionalFollowupUi dispose d’une variante explicite `-Wpf` à exécuter sous Windows PowerShell 5.1 en STA. Elle ajoute deux clics RoutedEvent sur le vrai bouton du XAML ; les mutations sont remplacées par le point d’arrêt au précontrôle. Ce rapport local ne prétend pas avoir exécuté cette variante ni la fenêtre complète.

`manifest.json` attribue les empreintes des sources et des rapports. La restauration de file au lancement n’est pas modifiée. Aucun reçu n’est marqué Verified automatiquement.
