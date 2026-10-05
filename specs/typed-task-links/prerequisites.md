# Prerequisites for typed task links

Deferred destination: **T-2402 — Set up isolated CloudKit integration testing**, created and freshly verified by the parent through the installed UI (Transit, Idea/Research). No duplicate live ticket write.

## Before implementation

- [ ] Parent confirms compatible merged T-63 read/capture, T-2382 reusable-view, T-2383 result-encoder and T-2384 write-coordinator foundations, their shared-file ownership handoffs and an explicit latest verified base SHA. Refresh the actual running tool schema before coding. Keep the ticket branch isolated and canonical main/`.kiro` intact; task approval alone does not authorize implementation or merges.

## Deferred CloudKit test-isolation ticket

Owner `Sentinel_42e647a603ac81918cbb949ed1ca67bb` explicitly assigns this setup and live verification to a separate ticket and says to proceed without it for now. The items below remain prerequisites for that future live smoke, not blockers of T-1734 task2 or its coordinated local save work. No remote verification is claimed; account/signing/schema/client changes still require separately scoped authorization. Parent owns ticket creation; do not duplicate a live ticket write.

- [ ] Confirm access to the existing Apple developer account and a development CloudKit environment reserved for test records. Before the deferred development-sync fixture, verify the additive `TaskLinkOccurrence` and `TaskLinkRemovalEvidence` record types/fields in that development schema. Obtain parent clearance for the environment and heavy-test slot; do not use the user's production store or ticket records.
- [ ] If the new types are absent, the parent must designate the user or an authorized development operator to initialize the development schema from the real model declarations using Apple's SwiftData/Core Data development-schema procedure, then verify it in CloudKit Console. Do not add schema initialization to normal app launch or promote the production schema as part of this plan.

Production schema promotion is a separate release action, outside this task plan. No account, signing, entitlement, global permission or production configuration change is authorized by spec approval.
