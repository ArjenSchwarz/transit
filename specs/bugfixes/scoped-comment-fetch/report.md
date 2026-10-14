# T-2455: Scope selected-read comment fetches

## Problem and evidence

Full selected task reads currently fetch every store comment before filtering to selected logical task IDs. A live read timed out on 2026-10-14 after a healthy one-hour baseline; captured stacks later showed the MainActor capture inside this whole-store SwiftData/CoreData comment materialization. This identifies a concrete unnecessary-work path, not proof of an uptime leak, CloudKit causation, or a complete explanation of every historical timeout.

The user explicitly approved implementing this scoped fetch after the read-only investigation. The installed app is not changed by this branch. Existing ticket T-2455 remains the tracking item; no duplicate ticket is needed.

## Scope and invariants

- Move the existing selected-read logical-owner-ID filter into the comment store fetch. Preserve every physical comment owned by any task with a selected logical ID, including duplicate task UUIDs and duplicate comment UUIDs.
- Complete-portfolio reads retain the broad comment domain, including orphan diagnostics and scoped portfolio identity closure.
- includeComments controls output bodies only. Full revisions still require complete selected-task comment state.
- Preserve saved-only reads, persistent history fences, fresh captures after edits/reparenting, revision computation, snapshot identity, frozen replay, typed storage failures, physical worker cleanup and existing deadlines.
- Do not change stores/schema, sync settings, timeouts, permit counts or installed app lifecycle. No live store copies or cloud experiments.

## Investigation checkpoint

The comment-fetch injection now receives its FetchDescriptor so isolated tests can observe actual materialized rows. Before optimization it still receives the original unrestricted descriptor. Existing failure-injection tests are mechanically adapted to the descriptor seam.

Regression fixtures use temporary on-disk stores with all nine entities, CloudKit disabled and production history fencing. The primary regression requires exactly two selected comment rows despite 1,000 unrelated comments. Additional parity checks cover batches, duplicate logical owners/comment IDs, edited/reparented/orphan/pending comments, portfolio coverage, empty/summary reads and concurrent saved changes.

## Resolution and validation

Red checkpoint: six initial regression tests executed; five passed and the selected-row assertion failed as expected (1,002 fetched versus two required). Expanded duplicate-owner/bulk/performance tests are staged for green verification. No long-uptime resolution is claimed from synthetic tests.
