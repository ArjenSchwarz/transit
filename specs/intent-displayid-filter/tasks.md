---
references:
    - specs/intent-displayid-filter/smolspec.md
---
# Intent DisplayId Filter

## Implementation

- [ ] 1. Add displayId field to QueryFilters and update @Parameter description
  - QueryFilters Codable struct gains displayId: Int?. The @Parameter description documents displayId for single-task lookup. Verify: project builds and existing tests pass.

- [ ] 2. Add displayId lookup path in execute() with direct FetchDescriptor
  - When filters.displayId is set fetch via FetchDescriptor with permanentDisplayId predicate on modelContext. Wrap result in array and pass through applyFilters() for uniform filtering. Return [] if not found or filtered out; return detailed taskToDict output if found. Verify: build succeeds.

- [ ] 3. Extend taskToDict with detailed parameter for description and metadata
  - Add detailed: Bool = false parameter to taskToDict. When true include description and metadata fields (matching MCPToolHandler.taskToDict). Existing call site uses default false. Verify: build succeeds and existing response format unchanged.

## Testing

- [ ] 4. Test displayId lookup returns task with description and metadata
  - Create task with description and metadata then query by displayId. Verify response contains description and metadata alongside all standard fields. Verify: make test-quick passes.

- [ ] 5. Test displayId not found returns empty array
  - Query with a displayId that does not exist. Verify response is empty JSON array not an error. Verify: make test-quick passes.

- [ ] 6. Test displayId with non-matching filter returns empty array
  - Create task in idea status then query with its displayId plus status=done filter. Verify empty array returned. Verify: make test-quick passes.

- [ ] 7. Verify existing QueryTasksIntent tests still pass
  - Run full QueryTasksIntentTests suite. All existing tests must still pass including noFilters statusFilter projectFilter typeFilter and responseFormat. Verify: make test-quick passes.
