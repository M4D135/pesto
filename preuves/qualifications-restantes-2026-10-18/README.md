# Compléments de qualification du 18 octobre 2026

Build observé : `155523258fce24e506e1f13e4552f234c2d906485d690573bf5631489a04739a` (sources runtime de `6c23038`, toujours présentes dans `6c95940`). Aucun correctif produit appliqué par cette campagne.

## 98 — matrice observée

GUI réelle sur Windows Server 2025 Standard Evaluation, build 26100, fr-FR, .NET 4.8.1, Windows PowerShell 5.1.26100.7462, compte intégré `LABO\Administrateur` : sept passages de navigation, même processus répondant et fermeture normale. [Rapport](server/q98-server-gui.json), captures dans `server/`. Le passage Noms capture un calcul encore en cours ; il ne certifie pas son résultat final. Le scénario n’exécute aucune mutation sur le DC. Les lectures CLI AD, Windows 11, cultures fr-FR/en-US, compte AD explicite, SYSTEM et la matrice visuelle restent reliées à leurs campagnes antérieures. Aucune combinaison non observée n’est déduite.

Sur la cliente, une nouvelle politique temporaire cible l’empreinte du build actuel, avec contrôle des scripts actif. L’exécutable est autorisé en audit (événement 3076), puis refusé par Windows en mode imposé (3077). La nouvelle console PowerShell est alors réellement `ConstrainedLanguage`. [Événements définitifs](policy/events-final.json), [audit](policy/audit-launch.json), [imposé](policy/enforced-launch.json). L’argument volontairement invalide évite toute demande opérationnelle et ouvre un dialogue natif du lanceur : cette vérification certifie le comportement de la politique, pas une opération métier sous CLM. Le refus fonctionnel dans l’enfant CLM isolé reste une preuve distincte ; aucune prise en charge générale de CLM n’est annoncée.

Les treize politiques de départ sont restaurées exactement, les cinq reçus restent identiques et le processus GUI original 6020 est conservé ([nettoyage](policy/cleanup.json)). Le premier pilote attendait la sortie du dialogue natif et a échoué ; son `finally` a restauré la politique. Le second ferme uniquement son dialogue. Le premier dialogue restant est également fermé. Les codes de sortie et codes natifs `null` ne sont pas présentés comme des codes prouvés ; le champ NativeDialog du résultat imposé est hérité du passage audit et ne prouve aucun lancement en mode imposé. Les événements ont été relus après publication asynchrone du 3077.

Le comportement de CLM avec les politiques UMCI est décrit par [Microsoft](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/design/script-enforcement).

## 101 — périmètre demandé

David retire la qualification Narrator le 18 octobre. Les parcours clavier déjà observés restent acquis : Tab/Maj+Tab, F6/Maj+F6, Entrée/Échap et retour au contrôle d’origine. Aucune recette vocale exhaustive n’est revendiquée et aucune fonction du logiciel n’a été supprimée.

## 107 — évaluation conclue

Le premier brouillon Spark annonçait à tort une fuite confirmée et imitait le pool. Il n’a pas été exécuté ni intégré. Sa proposition de comparaison réutilisation/destruction a été vérifiée avec les vraies fonctions de `Pesto-Async.ps1`, deux processus distincts et 35 lectures AD réelles chacun sur le GUID autorisé. Les erreurs AD ou une fermeture incomplète font échouer le pilote.

Le pool réutilisé conserve effectivement le même runspace : après échauffement/GC, mémoire privée 92 893 184 octets et 658 handles ; après 30 lectures supplémentaires/GC, 97 267 712 et 662 ; après fermeture/GC, 86 937 600 et 622. Le mode destruction reste à 124 747 776 octets et 690 handles en fin de mesure. Ce diagnostic ne confirme pas la fuite native attribuée au pool par Spark et ne justifie pas un recyclage arbitraire toutes les cinq utilisations. Le GC est forcé uniquement dans ces processus de diagnostic, jamais dans la GUI réelle. [Réutilisation](memory/q107-pool-Reuse.json), [destruction](memory/q107-pool-Discard.json), [pilote](pilots/q107-real-pool.ps1). La dernière série dans la vraie GUI conserve le PID6020 lancé à17:32:27Z. Après trois cycles d’échauffement, dix actualisations AD avec fraîcheur vérifiée et 72 échantillons (19:30:44–19:36:41Z) : 417 562 624→453 308 416 octets privés, pic460 644 352 ; handles867→1075, pic1088 ; threads24→23. Le précédent pic484 765 696/1516 n’est pas dépassé malgré la charge supplémentaire ; un reflux naturel est donc observé sur la session de plus de deux heures. Les compteurs CLR relèvent neuf collections Gen2. Aucun GC ni code diagnostique n’a été injecté dans cette GUI. [Session](memory/q107-gui-session.json), [cycles](memory/q107-gui-cycles.json), [charge](memory/q107-gui-workload.json), [CLR](memory/q107-gui-clr.jsonl).

**Décision d’évaluation : conserver le pool actuel.** Les abonnements WPF contrôlés précédemment restent bornés ; les fonctions du pool libèrent effectivement leurs ressources à la fermeture, et l’application complète montre un reflux. La croissance ponctuelle n’est pas une preuve de fuite ; les observations ne justifient pas le recyclage arbitraire proposé. Cette conclusion est bornée à la charge et à la durée observées, sans garantie universelle ni illimitée. Aucun patch de performance spéculatif n’est intégré.

## 102 — encore ouvert

Le brouillon Spark n’injectait aucune panne et n’a pas été exécuté. À la demande de David d’abréger et pousser, le relais OpenCode CLI gratuit est interrompu. Son contexte reste sur le Spark dans `/home/m4d135/pesto/qualifications/2026-10-18-restants` (session `ses_eaf7e8835ffeWEwfIDwz0SJcmg`). Aucun pilote de panne AD n’a été exécuté : le point 102 reste ouvert. La cible a été relue avant essai : GUID attendu, OU Paris, protection initiale désactivée et canal sécurisé valide. Aucune mutation AD nouvelle n’est revendiquée.

## Vérifications de publication

50 contrôles `test_release_120.py` réussis ; manifeste des 67 composants runtime inchangé et vérifié. Dernière CI du commit de départ `6c95940` : trois jobs réussis, run39156928693. Ces résultats ne préjugent pas du nouveau run déclenché par le push.
