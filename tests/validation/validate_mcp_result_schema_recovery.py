#!/usr/bin/env python3
"""Host-only supplemental conformance after copying three app-owned exports.

The directory must contain batch/, maintenance/ and protected/, each with the
actual result.json and schema.json exported by MCPResultSchemaRecoveryTests.
Use the pinned schema-tests venv and the actual process exit code. Pure source
exports can exercise this checker, but are not app Swift Testing GREEN evidence.
"""

import argparse
from pathlib import Path

from validate_mcp_result_schemas import decode, read_artifact, validator

EXPECTED = {
    "batch": "reconcile_original_write",
    "maintenance": "reconcile_maintenance",
    "protected": "follow_source",
}


def validate_recovery_exports(directory, app_exit_code):
    if app_exit_code != 0:
        raise ValueError("App test did not exit successfully; recovery export is not GREEN evidence")
    if {path.name for path in directory.iterdir() if path.is_dir()} != set(EXPECTED):
        raise ValueError("Recovery export must contain exactly batch, maintenance and protected")
    for name, direction in EXPECTED.items():
        artifact_directory = directory / name
        wire = read_artifact(artifact_directory, "result.json")
        schema = read_artifact(artifact_directory, "schema.json")
        if wire.get("jsonrpc") != "2.0" or wire.get("id") != name:
            raise ValueError("Wrong recovery fixture correlation: " + name)
        result = wire["result"]
        structured = result["structuredContent"]
        if result.get("resultType") != "complete" or result.get("isError") is not True:
            raise ValueError("Recovery fixture lost original result facts: " + name)
        content = result["content"]
        if len(content) != 1 or content[0].get("type") != "text":
            raise ValueError("Recovery fixture lost original text: " + name)
        payload = structured["source"]["payload"]
        if structured["source"]["kind"] != "json" or payload != decode(content[0]["text"]):
            raise ValueError("Recovery fixture altered original logical evidence: " + name)
        if payload.get("outcome") != "rejected" or payload.get("accepted") is not False \
                or payload.get("retryAction") != "new_request_new_key":
            raise ValueError("Recovery fixture altered saved acceptance/retry facts: " + name)
        presentation = structured["presentation"]
        recovery = presentation["recovery"]
        if presentation.get("evidence") != "established" or presentation.get("errorCategory") != "invalid_input" \
                or recovery.get("direction") != direction:
            raise ValueError("Unexpected recovery presentation: " + name)
        if name == "batch":
            expected_item = {"index": 0, "operation": "update_task", "tool": "update_task",
                             "idempotencyKey": "original-item-key", "itemId": "saved item",
                             "targetTaskId": "AA000000-0000-0000-0000-000000000001"}
            if recovery.get("items") != [expected_item]:
                raise ValueError("Batch recovery lost original ordered item identity")
        elif name == "maintenance":
            if recovery != {"direction": direction, "tool": "maintenance_fixture"}:
                raise ValueError("Maintenance recovery invented a key or changed its original tool")
        elif recovery != {"direction": direction, "tool": "update_task",
                          "idempotencyKey": "original-protected-key"}:
            raise ValueError("Protected recovery lost original tool/key")
        errors = list(validator(schema).iter_errors(structured))
        if errors:
            raise ValueError("Actual schema rejects " + name + ": " + errors[0].message)
    print("PASS: 3 actual recovery descriptors/results; original identities and saved evidence preserved")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--app-exit-code", type=int, required=True)
    args = parser.parse_args()
    validate_recovery_exports(args.directory, args.app_exit_code)


if __name__ == "__main__":
    main()
