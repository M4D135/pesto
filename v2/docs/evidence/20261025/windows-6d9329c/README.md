# Campagne Windows native — 6d9329c

Run [40220687266](https://github.com/M4D135/pesto/actions/runs/40220687266), commit `6d9329c0f42f5e4338feb37df0c49b102d3d1cd3`, Windows NT `10.0.26100.0` : **réussi**. Les fichiers sont les octets originaux de l’artefact `12609533623` ; SHA-256 du ZIP téléchargé : `11a93629f33902fc7c5a80e9470caa6b177ad81494020aab74f476a9141620c4`.

Le smoke PROD et DEV prouve le chargement WebView2, la fermeture normale, 21 refus directs d’API réelles, zéro invocation hôte réelle et l’absence de création du profil réel. Le banc PROD prouve une installation suivie d’un rollback explicite, un échec réel de santé suivi d’un rollback automatique et une interruption observée du contrôle de santé suivie d’une reprise. Chaque scénario conserve deux tentatives de santé distinctes. Le pack source et le cfg sentinelle restent identiques.

Les scénarios utilisent des copies complètes du pack PROD et des versions de manifeste synthétiques `2.0.0.100`, `.101`, `.102`, avec le **même EXE**. Ils qualifient la transaction Windows et le cycle des processus sur ces copies ; ils ne prouvent pas le passage entre deux EXE indépendamment compilés, un partage UNC réel, UAC avec un autre utilisateur, les droits de Program Files, ni une opération AD. Les ajouts de code postérieurs à ce commit doivent obtenir leurs propres preuves.

- EXE : `bf91f1d132415efeb1794164306dc9626ff775a4568cacf8e9a56b0e90f12710`.
- Empreinte pack PROD : `65d43c10e8e9687d721cb8d4ca1ea5124aaff7e6f30192bb68aa5e742f82b1a0`.
- Empreinte de l’arbre runtime : `d58a8ea7fa738af0f7f60dfeaeb38e02c55954b0e03f848dd675e63df4850970`.
- ZIP PROD intérieur : `e6a4f2ec7f7d8bcb8e8732607e698a04ffeafbaa6714dfdb8fcab344b496c4e9` ([artefact candidat](https://github.com/M4D135/pesto/actions/runs/40220687266/artifacts/12609119626)).
- ZIP DEV intérieur : `493f5a60765340b41405c0d4315599e4a0637637293b115f97997d2dfc7dc8df` ([artefact candidat](https://github.com/M4D135/pesto/actions/runs/40220687266/artifacts/12608994979)).

Aucune release V1 n’est modifiée ; ces packs restent des candidats non qualifiés globalement. Les preuves sont conservées ici au-delà de la rétention des artefacts GitHub.

## Empreintes des fichiers originaux

| Fichier | SHA-256 |
|---|---|
| [native-demo-PROD.json.txt](native-demo-PROD.json.txt) | `a1b9eb2db251ed0bc4811e93953dc3313cb7cbe1b1e43706ac0b9b1d17f99f2d` |
| [native-demo-DEV.json.txt](native-demo-DEV.json.txt) | `3b1dd1bf96e569b9f1fd57dcc3cd24e05bd853bebc2ed425dd0e4dd3b82008ac` |
| [artifacts.json.txt](artifacts.json.txt) | `a87fd7ef382d2bc0cad44e79158b79754572de2a2a64c35551396de1c622fd4f` |
| [runtime.json.txt](runtime.json.txt) | `7dbc571fe189a2beba71fc609229d4bd8af98af0c0581b1eb17484bd7663458b` |
| [native-update/transaction-evidence/health-failure/fixture.json.txt](native-update/transaction-evidence/health-failure/fixture.json.txt) | `f8d6edb697274b4b77a1445e329d398b45a7d90be59330463b5e86ea814ae3a0` |
| [native-update/transaction-evidence/health-failure/health-4fee95f7930da325c726ab204e87188a53704bb152d11c747e545cbdd0bc1f87.json.txt](native-update/transaction-evidence/health-failure/health-4fee95f7930da325c726ab204e87188a53704bb152d11c747e545cbdd0bc1f87.json.txt) | `f88a125fb4c5fb44a443e99da1bed46e2632afda87ad3ee480053978d3383091` |
| [native-update/transaction-evidence/health-failure/health-7ab913aa60b1d5b8979d4517532c6696c6a2ae736a2f0b33884852522a6bf49a.json.txt](native-update/transaction-evidence/health-failure/health-7ab913aa60b1d5b8979d4517532c6696c6a2ae736a2f0b33884852522a6bf49a.json.txt) | `5b665d4fff03db33c682b8ebc3277fdca6681344e8b8de48df8550c61df03d6f` |
| [native-update/transaction-evidence/health-failure/journal-install.json.txt](native-update/transaction-evidence/health-failure/journal-install.json.txt) | `162b7452828deb415fc332bc883604d22fddf93d8a43b29500bc12335f688e16` |
| [native-update/transaction-evidence/health-failure/launch-install.json.txt](native-update/transaction-evidence/health-failure/launch-install.json.txt) | `cc9c3a37d1c29fee1462f83ea98d74a0ec0ad171aa0b84f37e676502ebdd4366` |
| [native-update/transaction-evidence/health-failure/observation-install.json.txt](native-update/transaction-evidence/health-failure/observation-install.json.txt) | `743b3bd33ccf7ac49bbab58852a5d703921b40dc71ce44ebf7e1bea99a31cc89` |
| [native-update/transaction-evidence/health-failure/proof-install.json.txt](native-update/transaction-evidence/health-failure/proof-install.json.txt) | `2ab931b1a0328eeeb395292ce17b7bd688fb8c4de11d180a6d87c13bf5afa0c1` |
| [native-update/transaction-evidence/health-failure/request-install.json.txt](native-update/transaction-evidence/health-failure/request-install.json.txt) | `75eeaa5e07850d98aaf4f1f1db65b869edbdc23ffa2c838247467993b1cbc164` |
| [native-update/transaction-evidence/interruption/fixture.json.txt](native-update/transaction-evidence/interruption/fixture.json.txt) | `6047c46c9929d8201691e97ef3cb6b67638dcb7fcdc3a6e25537ec05cb9e63f2` |
| [native-update/transaction-evidence/interruption/health-22062e8f22b76946cdf723c6668b7d268fa58a790adfaf3857ceb1e1d8cabe99.json.txt](native-update/transaction-evidence/interruption/health-22062e8f22b76946cdf723c6668b7d268fa58a790adfaf3857ceb1e1d8cabe99.json.txt) | `303b7e70854565d44e13281cd735d3c4f73499e179dd0564954e7f5b1f2eea5b` |
| [native-update/transaction-evidence/interruption/health-cb80c6bb40f202f1f98f737407a423037fbfa8e7fd4591742266b03d1b17817e.json.txt](native-update/transaction-evidence/interruption/health-cb80c6bb40f202f1f98f737407a423037fbfa8e7fd4591742266b03d1b17817e.json.txt) | `b1faa58561f6c715c99dceafb2c3fa17aba6b30dbdceb61c6b51b4dcec8e2db7` |
| [native-update/transaction-evidence/interruption/journal-interrupted.json.txt](native-update/transaction-evidence/interruption/journal-interrupted.json.txt) | `8194199b6a02b9b6a020e24f2dcfb1170fa945cdcbfe78741fa1abef823a882d` |
| [native-update/transaction-evidence/interruption/journal-recovery.json.txt](native-update/transaction-evidence/interruption/journal-recovery.json.txt) | `32a6ee0a3da5a2e79e0ae3e5030db4cd1668565898225370473ddd8a7376a19f` |
| [native-update/transaction-evidence/interruption/launch-install.json.txt](native-update/transaction-evidence/interruption/launch-install.json.txt) | `27bfed43dae83dc1ff2e771a7ce03914a0cefbe0b1607992215719a70b7cf670` |
| [native-update/transaction-evidence/interruption/launch-recovery.json.txt](native-update/transaction-evidence/interruption/launch-recovery.json.txt) | `482371edec6ed9db427455301192f54f6195d0ae43400b24f563d9f9c7851369` |
| [native-update/transaction-evidence/interruption/observation-install.json.txt](native-update/transaction-evidence/interruption/observation-install.json.txt) | `717548f628415d118b21bb199c76d53d7a268de78f8a67a7ea7184efe05500a7` |
| [native-update/transaction-evidence/interruption/observation-recovery.json.txt](native-update/transaction-evidence/interruption/observation-recovery.json.txt) | `88f4f92e6d3ce6f378e5d7d3b8f35a6a11fd61cf4f724e10a98c4d98bac467ca` |
| [native-update/transaction-evidence/interruption/proof-recovery.json.txt](native-update/transaction-evidence/interruption/proof-recovery.json.txt) | `7fc80b23512efd37e84bfbfe17b95b73eb7717db83ccecf402e58ed47a6f1b7d` |
| [native-update/transaction-evidence/interruption/request-install.json.txt](native-update/transaction-evidence/interruption/request-install.json.txt) | `bf4ab6adcab97cbffa7685e7e36ea99f7eb316a2859ba991b4d915fa6abb19d7` |
| [native-update/transaction-evidence/interruption/request-recovery.json.txt](native-update/transaction-evidence/interruption/request-recovery.json.txt) | `0d1195463b90442a059d15dfd7b84aee0d2009f6b429bd546cc77c4d57df9bc3` |
| [native-update/transaction-evidence/normal/fixture.json.txt](native-update/transaction-evidence/normal/fixture.json.txt) | `4397a41dcf7cd5cd07aba21b8e172e953fe068f87815c2cc8d6400b815395ede` |
| [native-update/transaction-evidence/normal/health-096621e3a827532e165e8c9148c5c13fb6a5a487f693e81768d65744efc40ca9.json.txt](native-update/transaction-evidence/normal/health-096621e3a827532e165e8c9148c5c13fb6a5a487f693e81768d65744efc40ca9.json.txt) | `3cec54cc8a34919c350a5b94806ec866fcf00bea87b925e7bc93297a2a6b15b0` |
| [native-update/transaction-evidence/normal/health-b8be4c20331c9af721ac3dfd618b4bda844594b638cd025e79d030f1686f881f.json.txt](native-update/transaction-evidence/normal/health-b8be4c20331c9af721ac3dfd618b4bda844594b638cd025e79d030f1686f881f.json.txt) | `6d43a33c39a3d06a8b6d628dadfd139f37a84f5fe5f8f80fb09bf0cb139be057` |
| [native-update/transaction-evidence/normal/journal-install.json.txt](native-update/transaction-evidence/normal/journal-install.json.txt) | `bb23c90fc6ba413290f7c94ad97c0ff8b34d897398aaa8271fc222ae47b1c2f6` |
| [native-update/transaction-evidence/normal/journal-rollback.json.txt](native-update/transaction-evidence/normal/journal-rollback.json.txt) | `a6830d2c8931a2823bbac8b701dc247cf89919a7e2e7e5c456a2dfb392dbb261` |
| [native-update/transaction-evidence/normal/launch-install.json.txt](native-update/transaction-evidence/normal/launch-install.json.txt) | `94082fad4505cd059a72242234e122addf2c18627e251f4aaa6ec2ac17d31303` |
| [native-update/transaction-evidence/normal/launch-rollback.json.txt](native-update/transaction-evidence/normal/launch-rollback.json.txt) | `c2f1d9afba5414b3d7d31a0cf1cd9a637bca25e868355dd2f9249d4d6efe896b` |
| [native-update/transaction-evidence/normal/observation-install.json.txt](native-update/transaction-evidence/normal/observation-install.json.txt) | `dfea4b2efc324b906a7d1670923fd2673e0fd9f917db6ebc6b6c7429c4bc7691` |
| [native-update/transaction-evidence/normal/observation-rollback.json.txt](native-update/transaction-evidence/normal/observation-rollback.json.txt) | `32f4f76f3c190ece922cc8591e6272a2815c01d2889a3a7ad3c0a9293b35d83e` |
| [native-update/transaction-evidence/normal/proof-install.json.txt](native-update/transaction-evidence/normal/proof-install.json.txt) | `0c89771fea6b231c2ff722ea66960ad10a1cbea899885b716afb671eb78d5c84` |
| [native-update/transaction-evidence/normal/proof-rollback.json.txt](native-update/transaction-evidence/normal/proof-rollback.json.txt) | `7726bf39b2057c26fad30376faeda44d76bfd698a3a35b82f40a5909024c3fe2` |
| [native-update/transaction-evidence/normal/request-install.json.txt](native-update/transaction-evidence/normal/request-install.json.txt) | `91393712beb0df416ce8ddd89ba405a5613adaf9a3116184dfaa3792e80d6af7` |
| [native-update/transaction-evidence/normal/request-rollback.json.txt](native-update/transaction-evidence/normal/request-rollback.json.txt) | `a4ecab74eb430dd6ec8cccf64ef184954e8887154eae5f3ab5928491764151fb` |
| [native-update/transaction-evidence/proof.json.txt](native-update/transaction-evidence/proof.json.txt) | `aad7162890c0d89158cc2fbff01ed53aaca0f4668046e9b941118102f8ed711e` |
| [native-update/transaction-evidence/suite.json.txt](native-update/transaction-evidence/suite.json.txt) | `7f3590431e6347d372462f5398a21f0872b8cff3a71717648d11e1982b141614` |
