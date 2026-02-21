---
references:
    - specs/text-filter/smolspec.md
---
# T-180: Text Filter

## Dashboard Search

- [x] 1. Text search filters tasks in DashboardLogic.buildFilteredColumns() <!-- id:53q1716 -->

- [x] 2. Dashboard displays .searchable() bar and passes search text to filter logic <!-- id:53q1717 -->
  - Blocked-by: 53q1716 (Text search filters tasks in DashboardLogic.buildFilteredColumns())

- [x] 3. Active filter count includes non-empty search text and unit tests pass for dashboard text filtering <!-- id:53q1718 -->
  - Blocked-by: 53q1717 (Dashboard displays .searchable() bar and passes search text to filter logic)

## MCP and App Intent

- [ ] 4. MCP query_tasks tool accepts search parameter and filters tasks by name/description substring <!-- id:53q1719 -->
  - Blocked-by: 53q1716 (Text search filters tasks in DashboardLogic.buildFilteredColumns())

- [ ] 5. MCP text search is verified with unit tests covering search-only, combined filters, whitespace trimming, and nil description <!-- id:53q171a -->
  - Blocked-by: 53q1719 (MCP query_tasks tool accepts search parameter and filters tasks by name/description substring)

- [ ] 6. App Intent QueryTasksIntent supports search field in JSON input with same matching behavior <!-- id:53q171b -->
  - Blocked-by: 53q1719 (MCP query_tasks tool accepts search parameter and filters tasks by name/description substring)

- [ ] 7. All tests pass and linter is clean <!-- id:53q171c -->
  - Blocked-by: 53q1718 (Active filter count includes non-empty search text and unit tests pass for dashboard text filtering), 53q171a (MCP text search is verified with unit tests covering search-only, combined filters, whitespace trimming, and nil description), 53q171b (App Intent QueryTasksIntent supports search field in JSON input with same matching behavior)
