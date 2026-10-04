#!/usr/bin/env python3
"""Near-valid evidence doubles test verifier sensitivity; never runtime/client proof."""
import copy
import unittest
from verify import verify


def specimen():
    meta = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientCapabilities": {}}
    source = {"kind": "json", "payload": {"records": [{"id": "synthetic"}]}}
    structured = {"contractVersion": 1, "source": source, "presentation": {}}
    results = [{"supportedVersions": ["2026-07-28"], "capabilities": {"tools": {"listChanged": True}},
                "_meta": {"io.modelcontextprotocol/serverInfo": {"name": "transit", "version": "test"}}},
               {"tools": [{"name": "query_tasks", "inputSchema": {}, "outputSchema": {"type": "object"}}]},
               {"structuredContent": structured, "content": [{"type": "text", "text": "original"}]}]
    exchanges = []
    for index, (kind, method) in enumerate(zip(["discovery", "list", "read"],
                                              ["server/discover", "tools/list", "tools/call"])):
        params = {"_meta": copy.deepcopy(meta)}
        headers = {"MCP-Protocol-Version": "2026-07-28", "Mcp-Method": method,
                   "Content-Type": "application/json", "Accept": "application/json"}
        if kind == "read":
            params.update(name="query_tasks", arguments={"limit": 1})
            headers["Mcp-Name"] = "query_tasks"
        exchanges.append({"kind": kind, "request": {"jsonrpc": "2.0", "id": index,
                          "method": method, "params": params}, "headers": headers, "status": 200,
                          "response": {"jsonrpc": "2.0", "id": index, "result": results[index]}})
    return {"formatVersion": 1, "synthetic": True, "persistentStore": False,
            "endpoint": "http://127.0.0.1:9876/mcp", "exchanges": exchanges,
            "structuredConsumption": {"contractVersion": 1, "source": source},
            "subscriptionRequest": {"id": "subscription", "notifications": {"toolsListChanged": True}},
            "subscriptionFrames": [
                {"jsonrpc": "2.0", "method": "notifications/subscriptions/acknowledged", "params": {
                    "notifications": {"toolsListChanged": True}, "_meta": {"io.modelcontextprotocol/subscriptionId": "subscription"}}},
                {"jsonrpc": "2.0", "id": "subscription", "result": {"resultType": "complete",
                    "_meta": {"io.modelcontextprotocol/subscriptionId": "subscription"}}}],
            "sessionHeader": None, "eventIDs": [],
            "provenance": {"producer": "actual-app-test", "bundleID": "me.nore.ig.Transit.development"}}


class EvidenceTests(unittest.TestCase):
    def test_complete_conforming_fixture_is_accepted(self):
        verify(specimen())

    def test_single_field_negotiation_mutations_reject(self):
        for field in ("protocol", "metadata", "discovery", "schema", "consumption", "correlation", "ack"):
            trace = specimen()
            if field == "protocol": trace["exchanges"][0]["headers"]["MCP-Protocol-Version"] = "legacy"
            if field == "metadata": trace["exchanges"][0]["request"]["params"]["_meta"] = {}
            if field == "discovery": trace["exchanges"][0]["response"]["result"]["supportedVersions"] = []
            if field == "schema": del trace["exchanges"][1]["response"]["result"]["tools"][0]["outputSchema"]
            if field == "consumption": del trace["structuredConsumption"]
            if field == "correlation": trace["exchanges"][2]["response"]["id"] = "different"
            if field == "ack": trace["subscriptionFrames"].reverse()
            with self.subTest(field=field), self.assertRaises(ValueError): verify(trace)

    def test_binary_version_or_legacy_success_is_not_negotiation(self):
        for evidence in ({"binarySymbols": ["2026-07-28"]}, {"version": "latest"}, {"initialize": "succeeded"}):
            with self.assertRaises(ValueError): verify(evidence, installed=True, required_surfaces=("codex-cli",))

    def test_missing_intended_surface_rejects_near_valid_client_evidence(self):
        trace = specimen()
        trace["synthetic"] = False
        trace["surfaces"] = [{"surface": "codex-cli", "trace": specimen()}]
        with self.assertRaises(ValueError):
            verify(trace, installed=True, required_surfaces=("codex-cli", "codex-desktop", "claude-code", "claude-desktop"))

    def test_fixture_cannot_be_installed_client_evidence(self):
        with self.assertRaises(ValueError): verify(specimen(), installed=True, required_surfaces=("codex-cli",))


if __name__ == "__main__":
    unittest.main()
