# Task 2 amendment: parser container cap RED

Owner approval `Sentinel_9536d4df532c81919792e70801f128fb` establishes a maximum parser input depth of 32 object/array containers. Root containers count as one; scalars count as zero. Width is independent of depth. Excess depth is a resource limit, not malformed JSON.

The declaration adds `MCPResultBoundaryError.resourceLimit`. New RED fixtures require mixed object/array depth 31 and 32 to be accepted, depth 33 to throw the distinct error, and a 2,000-record array to be admitted. Generated depth-33 source throws; retained depth-33 source keeps exact raw text and optional nil/false/true isError as unreadable/unestablished evidence. Original worker checkpoint failure still propagates instead of being swallowed as retained evidence.

Status: drafted; focused cap RED execution is pending the next explicit heavy-slot grant. Baseline task 2 RED remains demonstrated in `source-red.md`; no claim is made that the new cap assertions have run. Task 3 GREEN has not started.

Queued command:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPJSONDocumentTests TransitTests/MCPResultSourceTests'
```
