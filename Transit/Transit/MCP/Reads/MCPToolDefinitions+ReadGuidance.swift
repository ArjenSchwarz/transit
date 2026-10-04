#if os(macOS)
extension MCPToolDefinitions {
    nonisolated static let readExecutionDescription = """
        Each covered read describes saved local data. Response deadline is five seconds from original admission.
        Optional readPolicy is cached or refresh_if_needed (default). cached never waits for imports;
        refresh_if_needed observes only positively applicable already-running imports for at most two seconds
        within the original budget. Unsupported import visibility reports unknown freshness and null lastImportedAt;
        recent import evidence is not proof of global freshness or a server round trip. Inactive sync skips waiting.
        Read metadata uses asOf for the saved local capture time and an opaque snapshotId.
        freshness.assessedAt equals asOf.
        Cursor pages retain the original metadata and expiry; a cursor request has its own log correlation.
        Task storage/projection errors use QUERY_FAILED. Project/milestone failures retain their text error message.
        Failure metadata categories are storage_failure, serialization_failure, or incoherent_capture;
        READ_TIMEOUT and READ_BUSY never invent successful asOf or snapshotId metadata.
        No automatic retry occurs. After READ_BUSY or READ_TIMEOUT, use backoff before explicitly retrying;
        timed-out physical work retains its permit until cleanup, so an immediate retry may still be READ_BUSY.
        """

}
#endif
