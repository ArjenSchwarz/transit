---
references:
    - specs/developer-account-migration/smolspec.md
---
# Developer account migration setup

- [x] 1. New-team app, test and cloud identities agree while preserving local-only development defaults; verify every configuration and platform entitlement <!-- id:wmi1mem -->

- [x] 2. All launch modes use isolated new-identity storage and reject legacy/cross-container launches; verify policy and disposable store location behavior <!-- id:wmi1men -->
  - Blocked-by: wmi1mem (New-team app, test and cloud identities agree while preserving local-only development defaults; verify every configuration and platform entitlement)

- [x] 3. Document the account/provisioning and cutover prerequisites and record focused configuration, policy and unsigned-build validation <!-- id:wmi1meo -->
  - Configuration, policy and actual SwiftData configuration checks pass. The owner-approved cache retry and signed Mac/iOS builds pass; see implementation.md for the subsequent compile fix and source-only counter-readiness follow-up.
  - Blocked-by: wmi1men (All launch modes use isolated new-identity storage and reject legacy/cross-container launches; verify policy and disposable store location behavior)

Counter-readiness follow-up: explicit destination/floor inputs, read-only paginated inspection, CAS/read-back gate, account-bound receipt and import-bound checks implemented. Fake-only core tests and signed platform compilation are recorded in implementation.md. No operational migration step has been executed.
