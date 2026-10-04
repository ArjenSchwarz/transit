# T63 task17 package findings

Read-only review of task17-ordinary-binding package/localcommit47cfb48270599b36b18e0f7e12d03c7b6908140e. RecipientproductionpatchSHA256bf02b746a70158be41cb84a60eca4441f1d807fa5a65f0a50f04fc5b439d1458 and fixturespatchSHA25624737309434f7234122c4f752bdab9d82729df2b8c8e7416b6c97090288450b6. Both applychecks pass against0af0bfc common implementation. No patch imported. Manifest status was empty at review; owner finaldelivery pending.

Two findings require owner coordination before the one combined GREEN build, not a newuserapprovalgate:

1. `MCPReadService.preparePrivatePages` verifies original versus prepared source with full `.utf8.elementsEqual`, checking originaloperation only before eachpair. Largepage traversal must check the same originaloperation in bounded chunks or use a source-preserving owner proof with bounded validation. No fresh clock or deadline reset.
2. `prepareRetainedPage` returns sealed ordinarycontinuation with publications empty. `retainedPage(for:)` validates root/version/expiry only duringlookup. If expiry/retirement occurs after lookup but before finaloffer, attachedfrozenbytes can be selected successfully with no retainedroot guard at terminalgate. Add owner scalarreadpin/lookup+attachment through existing MCPPreparedPublication/domain (like existing reusablepin), revalidating exact originalroot/cursor/deadline with no parse/traversal/destruction undergate. No newpublicationengine. Include actual afterlookup-beforeoffer expiry/retirement race evidence with distinct preencodedfailure, operation stilladmitted, no expiredsuccess.

Other reviewed boundaries are aligned: opaque sealedcarrier avoids legacymetadata decode, allprivatepages callback precedes reservation, first+continuationowners retained, rawcompatibilitymetadata added exactlyonce to rootcharge, originalexpiry/policy preserved, typedcapacity mapping present. New3declarations/4bodies are focusedownercoverage, not runtimeverified; exactfixturedependencies exist locally. Existing late-only sharedroot rejectionfixture need not force that stage if safeearlier rejection is chosen.

T2383 common source0af0bfc exact ABI/patch is in `.codex-cache/task17-common-source/owner-handoff.json` and `common-factory-read-binding.patch`. T63 retains all6sourcepaths and newordinary helpers; T2383 will import exact revisedownerpatch without duplicating writers.
