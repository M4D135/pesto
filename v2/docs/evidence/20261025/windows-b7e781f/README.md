# Campagne Windows native — b7e781f

Run [40222575362](https://github.com/M4D135/pesto/actions/runs/40222575362), commit `b7e781f474eb2ce2a9103445ce0169f87f1fbbf0`, Windows NT `10.0.26100.0` : **réussi**. Les fichiers sont les octets originaux de l’artefact `12610730378` ; SHA-256 du ZIP : `cf78d043fd8cca4bd3b77d5a0c3789ab8d1b545bca1f8e5b4e3b2760ec014cdd`.

PROD et DEV : WebView2 prêt, fermeture normale, **29 refus directs** d’API réelles en démo, zéro invocation réelle de l’hôte et aucun profil réel créé. Le nouveau lecteur de reçus passe également ses quatre roundtrips/contrôles de format sous Windows.

PROD : installation avec santé réelle puis rollback explicite ; échec réel de santé du candidat puis rollback automatique ; interruption observée pendant le contrôle WebView2 puis reprise. Chaque scénario conserve deux tentatives distinctes, le pack source et le cfg sentinelle restent identiques. Les versions de manifeste sont synthétiques `2.0.0.100`, `.101`, `.102`, avec le même EXE. Le passage entre deux EXE différents, un vrai partage UNC, UAC avec autre utilisateur et les droits de Program Files restent distincts de cette preuve. **AD reste non qualifié.**

- EXE : `b1c27d677a6a302abeabf5ebec31a513a0bffb39cbb0a8b648f6dba2d3a877af`.
- Empreinte du pack PROD : `7f5d642e704c474858a15571b2b112aba861355e109fdd9534ae41458cd718cb`.
- Empreinte arbre runtime : `d58a8ea7fa738af0f7f60dfeaeb38e02c55954b0e03f848dd675e63df4850970`.
- ZIP PROD intérieur : `715240cc9c4ea2f461a1bf97d2e3c767ef4b2c45f7aae726b8f6b808fc19da48` ([candidat](https://github.com/M4D135/pesto/actions/runs/40222575362/artifacts/12610326292)).
- ZIP DEV intérieur : `0e003f5c8c7c05d2bd6a4c4a9f90b15699d9ecb09b8cd0bba1fb275038e56a24` ([candidat](https://github.com/M4D135/pesto/actions/runs/40222575362/artifacts/12610590749)).

Aucune release publiée, aucune release V1 remplacée. Les ajouts postérieurs à ce commit doivent être reconstruits et ne reçoivent pas cette qualification rétroactivement.

| Fichier | SHA-256 original |
|---|---|
| [native-demo-PROD.json.txt](native-demo-PROD.json.txt) | `fadf3c5a8eb892b56a0bef8c2406beeb87abaefc67b123617b6ff859dd393f49` |
| [native-demo-DEV.json.txt](native-demo-DEV.json.txt) | `23895395c6294c8a3a0e4832289ba78303a27bb5edfb5ddb1dd4f4b1affbcb91` |
| [artifacts.json.txt](artifacts.json.txt) | `7f213587b619d9277e2b1d670d416073dfb75f28f86f466a0a831a6b7a97cd5f` |
| [runtime.json.txt](runtime.json.txt) | `7dbc571fe189a2beba71fc609229d4bd8af98af0c0581b1eb17484bd7663458b` |
| [PolicyReceiptHistoryTests.log.txt](PolicyReceiptHistoryTests.log.txt) | `4736efce4237323f5a6e7d7323fd850383dd58d5e89dd25c6ebfdd7b78a43cb3` |
| [native-update/transaction-evidence/health-failure/fixture.json.txt](native-update/transaction-evidence/health-failure/fixture.json.txt) | `72c0174ad7894888bc7138b65032e92af0d822009547f49dc669bd9e95cb65dd` |
| [native-update/transaction-evidence/health-failure/health-02d6e0983726ce227920430932ec713aaeb556399be027855e0f33c7fb265c29.json.txt](native-update/transaction-evidence/health-failure/health-02d6e0983726ce227920430932ec713aaeb556399be027855e0f33c7fb265c29.json.txt) | `a3de6c2b65974abd711db4970899a6e9bee1df7ac999060b7c569b717f25c046` |
| [native-update/transaction-evidence/health-failure/health-443bdb5ce6e308eccbe66ace5490d342b0e2c88b07df19104d3b3fc8ef448efa.json.txt](native-update/transaction-evidence/health-failure/health-443bdb5ce6e308eccbe66ace5490d342b0e2c88b07df19104d3b3fc8ef448efa.json.txt) | `fdafd0b7d1c6c169c3b9c09e72362cd8191877148c53dd0b39f30e79b5cbd285` |
| [native-update/transaction-evidence/health-failure/journal-install.json.txt](native-update/transaction-evidence/health-failure/journal-install.json.txt) | `ea0578f7449e1ee216bb9e37bd09ac2078b1b2e52a32ff2ef6c73366bd18089e` |
| [native-update/transaction-evidence/health-failure/launch-install.json.txt](native-update/transaction-evidence/health-failure/launch-install.json.txt) | `3f2a3022a8ad6da83ffafb42303075340a2fdf06d71fe5408e176ff8552fa654` |
| [native-update/transaction-evidence/health-failure/observation-install.json.txt](native-update/transaction-evidence/health-failure/observation-install.json.txt) | `37f50b36c8025797f0314f81f427327cd9142431ff9c329a0e55ef7a5a1a537d` |
| [native-update/transaction-evidence/health-failure/proof-install.json.txt](native-update/transaction-evidence/health-failure/proof-install.json.txt) | `57573c9aff27c423d6b7b4cd343d9ad7407a0e08faacebfcdeb61101f7237ac5` |
| [native-update/transaction-evidence/health-failure/request-install.json.txt](native-update/transaction-evidence/health-failure/request-install.json.txt) | `482e30731c4b98a80c50efb44142257e2533675035c33aba0959bc3555145733` |
| [native-update/transaction-evidence/interruption/fixture.json.txt](native-update/transaction-evidence/interruption/fixture.json.txt) | `ec5b68c6fb440ebb56d172d72afa9eec502720a36294ddb7f6f2eea27825d243` |
| [native-update/transaction-evidence/interruption/health-307264e5ce39dcdc68d147f3c65c18e9b0a228235ab964211dcab7b82108b893.json.txt](native-update/transaction-evidence/interruption/health-307264e5ce39dcdc68d147f3c65c18e9b0a228235ab964211dcab7b82108b893.json.txt) | `6b2d78e35007f3213dc5c6d4cbd6d4f302355086e6f06fffa44748324b3c8dfd` |
| [native-update/transaction-evidence/interruption/health-e8df741b98a95b8a038028e53c36b4c9bc8a3ab1b1e78399fcf8d2848e63fafe.json.txt](native-update/transaction-evidence/interruption/health-e8df741b98a95b8a038028e53c36b4c9bc8a3ab1b1e78399fcf8d2848e63fafe.json.txt) | `7ef43eeeb848f5588246f08fa15057b3d0eb31ae81ef918ca100be68c4470bad` |
| [native-update/transaction-evidence/interruption/journal-interrupted.json.txt](native-update/transaction-evidence/interruption/journal-interrupted.json.txt) | `7a0e0cccedc2cc69e70a973d61a79646856d418f39f4c58d7bffefcfa3e822b0` |
| [native-update/transaction-evidence/interruption/journal-recovery.json.txt](native-update/transaction-evidence/interruption/journal-recovery.json.txt) | `2b95185bc45a2aa8c8c879926dc87d8bdb1e837d2c5440d83e82fa5af61e8d6c` |
| [native-update/transaction-evidence/interruption/launch-install.json.txt](native-update/transaction-evidence/interruption/launch-install.json.txt) | `3e9039abc37961a8ac647e8a8bfeab7843bbe3aa490d1f8d6addaa7b4350c4ef` |
| [native-update/transaction-evidence/interruption/launch-recovery.json.txt](native-update/transaction-evidence/interruption/launch-recovery.json.txt) | `1ce8b2f80475aa0e1410032635c1913ef3698964e759bc20e219bd5722e62ce5` |
| [native-update/transaction-evidence/interruption/observation-install.json.txt](native-update/transaction-evidence/interruption/observation-install.json.txt) | `09a900129b191afbfa54db63937db4e7aaab4acad7acfe4827c6f4a10f37dad8` |
| [native-update/transaction-evidence/interruption/observation-recovery.json.txt](native-update/transaction-evidence/interruption/observation-recovery.json.txt) | `53910e285b07ae5896feb9b26d24c5dd6b26894bcda6a67c8f5d2873809319cc` |
| [native-update/transaction-evidence/interruption/proof-recovery.json.txt](native-update/transaction-evidence/interruption/proof-recovery.json.txt) | `b15c2332669d00ed8740e2b271baa411c2b207b460e4d260c5a21bcbde665430` |
| [native-update/transaction-evidence/interruption/request-install.json.txt](native-update/transaction-evidence/interruption/request-install.json.txt) | `7bdff1c9ffb6308da8a3686be70de95d507b08036fc4f7a57faabb5ea1771818` |
| [native-update/transaction-evidence/interruption/request-recovery.json.txt](native-update/transaction-evidence/interruption/request-recovery.json.txt) | `33078050266196cc55825654a093af2e2e572bc74122fb81f4e550027758b8fa` |
| [native-update/transaction-evidence/normal/fixture.json.txt](native-update/transaction-evidence/normal/fixture.json.txt) | `1e0c02326d0d67f5380ba81c0260cb56811001f70c2f992107dda39774eccdfa` |
| [native-update/transaction-evidence/normal/health-63296ceb412ca63baefdb5bd8d8393f7632c0e171189478efd4da2d570b9ff3a.json.txt](native-update/transaction-evidence/normal/health-63296ceb412ca63baefdb5bd8d8393f7632c0e171189478efd4da2d570b9ff3a.json.txt) | `71fe58bdde802a64c545fb94dcdbc247081e78f442e0ee00c138b9ebbf26f7ad` |
| [native-update/transaction-evidence/normal/health-95405977065694668fca7fc7a71583982712fe1686eb55639cf92cfbe27e9cbb.json.txt](native-update/transaction-evidence/normal/health-95405977065694668fca7fc7a71583982712fe1686eb55639cf92cfbe27e9cbb.json.txt) | `18a236bb2778da54a4ebfbc464b7d99d976b37be43ddb2337fdc2b297a059625` |
| [native-update/transaction-evidence/normal/journal-install.json.txt](native-update/transaction-evidence/normal/journal-install.json.txt) | `9d6abf26291c3a4a67e45b193db31019d1fc138c4ffe724b37afd0e4ff717fdb` |
| [native-update/transaction-evidence/normal/journal-rollback.json.txt](native-update/transaction-evidence/normal/journal-rollback.json.txt) | `b0cff95156d1b0b8a7ad1a392aa7ba97c9ac13cff4dc47aef81ff1cf9338ee07` |
| [native-update/transaction-evidence/normal/launch-install.json.txt](native-update/transaction-evidence/normal/launch-install.json.txt) | `c83fabd5d0b9eca121d51b1c440783dfb8f45f0025fd01f32f6c8d59142be704` |
| [native-update/transaction-evidence/normal/launch-rollback.json.txt](native-update/transaction-evidence/normal/launch-rollback.json.txt) | `57caf615b2b509364a024ab0f5878a247b4db3bf5cea69d8af2ce4996b6de547` |
| [native-update/transaction-evidence/normal/observation-install.json.txt](native-update/transaction-evidence/normal/observation-install.json.txt) | `18ede39b8be37913d232fcd0dc5502640c9c1c26a6cf96b052d67c4d37668685` |
| [native-update/transaction-evidence/normal/observation-rollback.json.txt](native-update/transaction-evidence/normal/observation-rollback.json.txt) | `32a07ab043e1982e679ebc1011afe5af7b09a7c7158ce0d3649c475bb6e22cc4` |
| [native-update/transaction-evidence/normal/proof-install.json.txt](native-update/transaction-evidence/normal/proof-install.json.txt) | `a76b3220e626db9b827a9e69d3b15e2f8680f577a7e1b76bdf698e7f59639add` |
| [native-update/transaction-evidence/normal/proof-rollback.json.txt](native-update/transaction-evidence/normal/proof-rollback.json.txt) | `da3805523df5ec035778e5e867d990d1f4fbed582a4539dc0d67365630328b2e` |
| [native-update/transaction-evidence/normal/request-install.json.txt](native-update/transaction-evidence/normal/request-install.json.txt) | `bf72d6299af4535e49a5fbf834934ceefb31f1408650e4e25289b9cf71aa98d7` |
| [native-update/transaction-evidence/normal/request-rollback.json.txt](native-update/transaction-evidence/normal/request-rollback.json.txt) | `1918935d267386924f81fdcd688aa02aa485044930f268ef54bf1f5b130f4fba` |
| [native-update/transaction-evidence/proof.json.txt](native-update/transaction-evidence/proof.json.txt) | `6b7e576c78f2fb337646327056b2ffa97af3d507ceaab905fa0b9677d0852310` |
| [native-update/transaction-evidence/suite.json.txt](native-update/transaction-evidence/suite.json.txt) | `34b1d8cb48078531ecf2e266233697d8f1280a159c69dfab7534a0d06c55072e` |
