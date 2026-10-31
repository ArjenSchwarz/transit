---
references:
    - specs/developer-account-migration/smolspec.md
---
# Developer account migration setup

- [-] 1. New-team app, test and cloud identities agree while preserving local-only development defaults; verify every configuration and platform entitlement <!-- id:wmi1mem -->

- [ ] 2. All launch modes use isolated new-identity storage and reject legacy/cross-container launches; verify policy and disposable store location behavior <!-- id:wmi1men -->
  - Blocked-by: wmi1mem (New-team app, test and cloud identities agree while preserving local-only development defaults; verify every configuration and platform entitlement)

- [ ] 3. Document the account/provisioning and cutover prerequisites and record focused configuration, policy and unsigned-build validation <!-- id:wmi1meo -->
  - Blocked-by: wmi1men (All launch modes use isolated new-identity storage and reject legacy/cross-container launches; verify policy and disposable store location behavior)
