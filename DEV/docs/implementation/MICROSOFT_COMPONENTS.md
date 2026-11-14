# Composants Microsoft de Pesto 1.0

Le rapport `microsoft-components.json` produit par `tools/release_assurance.py create`
identifie les six fichiers RSAT livrés (DLL, ressource MUI, manifeste et descriptions
PowerShell), avec taille et SHA256 correspondant au manifeste du paquet.
`tools/Test-PestoEnvironment.ps1` relève sous Windows les versions et l’état
Authenticode, les certificats signataires et d’horodatage disponibles. Il ne charge
pas les assemblies et ne modifie aucune politique.

## Justificatifs à joindre

- Paquet Microsoft d’origine, version, provenance du téléchargement et empreinte.
- Conditions de licence applicables à ce paquet et au mode de diffusion prévu.
- Correspondance entre ses fichiers et les six empreintes livrées.
- Inventaire Windows des signatures pour ces mêmes octets.

Les fichiers actuellement présents ne portent pas de justificatif enregistré du
paquet d’origine ni d’autorisation de redistribution. Les champs restent donc
`NOT_DOCUMENTED` et `NOT_ATTESTED`. Un certificat valide ne vaut pas une autorisation
de redistribution. Le point 95 reste partiel tant que ces pièces manquent.

## Sources consultées le 16 octobre 2026

Microsoft documente l’installation de RSAT par les fonctionnalités Windows et,
sur Windows client, par les fonctionnalités à la demande :
[installation RSAT](https://learn.microsoft.com/windows-server/remote/remote-server-administration-tools).
Cette page décrit une installation ; elle ne constitue pas un justificatif pour
les fichiers actuellement embarqués. Les documents contractuels doivent être
rattachés au produit et au paquet d’origine :
[documents de licences Microsoft](https://www.microsoft.com/licensing/docs).

Les DLL restent inchangées. Cette revue ne déduit aucune licence de leur simple
présence dans le dépôt et ne remplace pas la validation des droits de diffusion.
