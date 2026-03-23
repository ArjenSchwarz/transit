---
references:
    - specs/parse-comment-newlines/smolspec.md
---
# Parse Comment Newlines

## Implementation

- [x] 1. MCP comment content has literal \n sequences replaced with actual newlines before storage <!-- id:p4kcyd9 -->

- [x] 2. MCP add_comment with literal \n stores and returns actual newlines <!-- id:p4kcyda -->
  - Blocked-by: p4kcyd9 (MCP comment content has literal \n sequences replaced with actual newlines before storage)

- [x] 3. MCP update_task_status comment with literal \n stores actual newlines <!-- id:p4kcydb -->
  - Blocked-by: p4kcyd9 (MCP comment content has literal \n sequences replaced with actual newlines before storage)

- [x] 4. Existing real newlines in MCP comments are preserved without double-conversion <!-- id:p4kcydc -->
  - Blocked-by: p4kcyd9 (MCP comment content has literal \n sequences replaced with actual newlines before storage)

- [x] 5. Build succeeds and all existing comment tests still pass <!-- id:p4kcydd -->
  - Blocked-by: p4kcyd9 (MCP comment content has literal \n sequences replaced with actual newlines before storage), p4kcyda (MCP add_comment with literal \n stores and returns actual newlines), p4kcydb (MCP update_task_status comment with literal \n stores actual newlines), p4kcydc (Existing real newlines in MCP comments are preserved without double-conversion)
