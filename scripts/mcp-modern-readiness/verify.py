#!/usr/bin/env python3
"""Fail closed on actual modern negotiation traces; no version/symbol inference."""
import argparse
import json
import urllib.parse

VERSION = "2026-07-28"
SUBSCRIPTION_ID = "io.modelcontextprotocol/subscriptionId"


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def verify(trace, *, installed=False, required_surfaces=()):
    require(isinstance(trace, dict) and trace.get("formatVersion") == 1, "Missing trace format")
    if installed:
        require(trace.get("synthetic") is False, "Synthetic fixture is not installed-client evidence")
        surfaces = trace.get("surfaces", [])
        names = [entry.get("surface") for entry in surfaces]
        require(len(names) == len(set(names)), "Duplicate client surface")
        require(set(names) == set(required_surfaces) and bool(names), "Missing intended client surface")
        for entry in surfaces:
            require(entry.get("runtimeVersion") and entry.get("captureContext"), "Missing actual runtime provenance")
            child = entry.get("trace", {})
            require(child.get("synthetic") is False, "Client trace cannot be fixture evidence")
            verify(child)
            if entry.get("subscriptionOptIn"):
                require(bool(child.get("subscriptionFrames")), "Opted-in client subscription missing")
        return {"verifiedSurfaces": names, "externalEvidence": True}
    endpoint = urllib.parse.urlsplit(trace.get("endpoint", ""))
    require(endpoint.scheme == "http" and endpoint.hostname == "127.0.0.1"
            and endpoint.port and endpoint.port > 1024 and endpoint.port != 3141
            and endpoint.path == "/mcp" and not endpoint.query and not endpoint.fragment
            and not endpoint.username and not endpoint.password, "Unsafe isolated endpoint")
    require(trace.get("persistentStore") is False, "Fixture must not address a persistent store")
    provenance = trace.get("provenance", {})
    require((trace.get("synthetic") is True and provenance.get("producer") == "actual-app-test")
            or (trace.get("synthetic") is False and provenance.get("producer") == "installed-client-runtime"),
            "Fixture/client provenance mismatch")
    require(provenance.get("producer") in ("actual-app-test", "installed-client-runtime")
            and provenance.get("bundleID") == "me.nore.ig.Transit.development", "Missing app/runtime provenance")
    exchanges = trace.get("exchanges", [])
    kinds = [entry.get("kind") for entry in exchanges]
    require(kinds[:3] == ["discovery", "list", "read"], "Missing intended negotiation exchanges")
    if trace.get("synthetic"):
        require(kinds == ["discovery", "list", "read", "wrong-version", "legacy-method", "notification"],
                "Synthetic protocol-negative evidence missing")
        wrong, legacy, notification = exchanges[3:]
        require(wrong.get("status") == 400 and wrong.get("response", {}).get("error", {}).get("code") == -32022,
                "Wrong-version rejection missing")
        require(legacy.get("status") == 404 and legacy.get("response", {}).get("error", {}).get("code") == -32601,
                "Legacy-method rejection missing")
        require(notification.get("status") == 400 and notification.get("response") is None,
                "Notification must be bodyless and rejected")
    for entry in exchanges[:3]:
        request, response, headers = entry.get("request", {}), entry.get("response", {}), entry.get("headers", {})
        require(entry.get("status") == 200 and request.get("jsonrpc") == "2.0"
                and response.get("jsonrpc") == "2.0", "Failed modern exchange")
        require(type(request.get("id")) in (str, int) and type(response.get("id")) is type(request["id"])
                and response.get("id") == request["id"], "Readable ID correlation missing")
        meta = request.get("params", {}).get("_meta", {})
        require(meta.get("io.modelcontextprotocol/protocolVersion") == VERSION
                and isinstance(meta.get("io.modelcontextprotocol/clientCapabilities"), dict), "Missing modern metadata")
        require(headers.get("MCP-Protocol-Version") == VERSION
                and headers.get("Mcp-Method") == request.get("method")
                and headers.get("Content-Type") == "application/json", "Header negotiation mismatch")
        require("application/json" in headers.get("Accept", ""), "JSON acceptance missing")
    require(exchanges[0]["request"].get("method") == "server/discover"
            and exchanges[1]["request"].get("method") == "tools/list", "Negotiation method mismatch")
    discovery = exchanges[0]["response"].get("result", {})
    require(discovery.get("supportedVersions") == [VERSION], "Modern discovery missing")
    identity = discovery.get("_meta", {}).get("io.modelcontextprotocol/serverInfo", {})
    require(identity.get("name") == "transit" and identity.get("version"), "Discovery identity missing")
    require(discovery.get("capabilities", {}).get("tools", {}).get("listChanged") is True, "Subscription capability missing")
    tools = exchanges[1]["response"].get("result", {}).get("tools", [])
    require(tools and all(isinstance(t.get("inputSchema"), dict) and isinstance(t.get("outputSchema"), dict)
                          for t in tools), "Actual tool schemas missing")
    require(any(tool.get("name") == "query_tasks" for tool in tools), "Read tool missing")
    read = exchanges[2]
    require(read["request"].get("method") == "tools/call" and read["headers"].get("Mcp-Name") == "query_tasks"
            and read["request"].get("params", {}).get("name") == "query_tasks", "Read-only tool negotiation missing")
    result = read["response"].get("result", {})
    require(result.get("isError") is not True, "Read failed")
    require(any(item.get("type") == "text" and isinstance(item.get("text"), str)
                for item in result.get("content", [])), "Original text not consumable")
    structured = result.get("structuredContent", {})
    require(structured.get("contractVersion") == 1 and structured.get("source", {}).get("kind") == "json"
            and isinstance(structured.get("presentation"), dict), "Structured result missing")
    consumed = trace.get("structuredConsumption", {})
    require(consumed.get("contractVersion") == 1 and consumed.get("source") == structured["source"],
            "Native parsed structured consumption missing")
    require(isinstance(result.get("content"), list) and bool(result["content"]), "Original text missing")
    frames = trace.get("subscriptionFrames", [])
    if trace.get("synthetic") or frames:
        request = trace.get("subscriptionRequest", {})
        require(len(frames) == 2 and request.get("notifications") == {"toolsListChanged": True}, "Filter evidence missing")
        ack, complete = frames
        require(ack.get("jsonrpc") == "2.0" and ack.get("method") == "notifications/subscriptions/acknowledged",
                "Acknowledgement is not first")
        require(ack.get("params", {}).get("notifications") == request["notifications"]
                and ack.get("params", {}).get("_meta", {}).get(SUBSCRIPTION_ID) == request.get("id"), "ACK correlation/filter mismatch")
        require(complete.get("jsonrpc") == "2.0" and complete.get("id") == request.get("id")
                and complete.get("result", {}).get("resultType") == "complete"
                and complete.get("result", {}).get("_meta", {}).get(SUBSCRIPTION_ID) == request.get("id"), "Completion correlation missing")
        require(trace.get("sessionHeader") is None and trace.get("eventIDs") == [], "Legacy session/event-ID transport")
    return {"verifiedExchanges": len(exchanges), "structuredConsumption": True,
            "synthetic": trace.get("synthetic"), "installedEvidence": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("trace")
    parser.add_argument("--installed", action="store_true")
    parser.add_argument("--surfaces", nargs="*", default=[])
    args = parser.parse_args()
    with open(args.trace, encoding="utf-8") as stream:
        result = verify(json.load(stream), installed=args.installed, required_surfaces=args.surfaces)
    print(json.dumps(result, sort_keys=True))
