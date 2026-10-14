# T-2455 scoped comment-fetch tasks

- [x] Preserve live failure journal and stack evidence without restarting Transit.
- [x] Record selected logical-ID, physical ownership, saved revision and portfolio/orphan invariants.
- [x] Establish a red materialization regression: 1,002 rows fetched instead of two.
- [x] Apply a selected-read comment predicate without changing budgets or capture fences.
- [x] Add isolated duplicate-owner, bulk/summary, edited/reparented/orphan/pending-change and history-fence fixtures.
- [x] Compare scoped and former whole-store capture output and deterministic materialization work.
- [x] Complete four targeted source review areas; no blockers found.
- [x] Record final verification (78 targeted tests, zero failures/skips; lint clean).
- [ ] Publish a feature PR.
- [ ] User-controlled deployment and long-uptime observation; no resolution claim from fixtures alone.

Ticket updates are intentionally omitted in this implementation turn because its authorisation excludes live data mutation. Existing T-2455 remains the tracking item.
