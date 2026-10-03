# Prerequisites: MCP Write Safety

## Before Shipping

- [ ] Using the Transit CloudKit container's Development environment, verify that the additive `MCPWriteReceipt` record type and its fields are present, then publish that schema to Production through CloudKit Console before releasing either platform. Do not remove or rename existing record types or fields. This is a release prerequisite; local implementation tasks and disk-backed tests do not depend on production publication.
