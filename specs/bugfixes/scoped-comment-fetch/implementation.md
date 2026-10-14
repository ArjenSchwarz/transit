# Scoped comment-fetch implementation

## Beginner

Reading one task previously loaded comments for every task and discarded unrelated ones. The capture now asks storage for comments whose owners share the selected task IDs. It still loads all comments needed to calculate the selected tasks' revisions, even when comment text is hidden from the response.

## Intermediate

`MCPReadCaptureBuilder.commentEvidence` resolves body tasks inside the existing saved capture boundary. Selected reads pass their unique logical UUIDs to `MCPReadCommentFetch.descriptor`; complete portfolios pass nil and retain the unrestricted fetch. The descriptor filters the optional owner relationship before SwiftData materializes comments. The existing post-filter/indexing and record/revision creation remain in place. The injection seam receives the descriptor so fixtures can count fetched rows and compare with the former unrestricted query.

## Expert

The predicate intentionally uses logical UUIDs rather than physical task IDs: canonical revision inputs group by logical owner, while physical comment keys remain indexed separately. A foreign duplicate owner must remain included even when its physical task is outside the selected body/project. Orphan evidence remains available to complete-portfolio diagnostics. New contexts, disabled autosave, explicit saved-only descriptor, persistent-history before/after checks, selected body resolution, frozen replay, failure categories, budget and physical cleanup remain unchanged. A synchronous fetch may continue after timeout selection; this patch reduces unnecessary materialization rather than promising preemption.

## Completeness assessment

The implementation removes unrelated comment materialization for selected captures and preserves the old query's retained evidence in the isolated fixtures. It does not optimize whole-store task identity/graph capture or the independent empty-originals task refetch. It does not prove that CloudKit overlap or process uptime caused the observed incident. Deployed long-uptime verification remains a separate user-controlled step.
