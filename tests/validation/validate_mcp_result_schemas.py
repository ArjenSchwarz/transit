#!/usr/bin/env python3
"""Host-only Draft 2020-12 checks of app-owned exports; never fetch references.

Run with the isolated schema-tests venv. A successful test process exit code must
be supplied explicitly. --self-test exercises only validator plumbing, not Transit.
"""

import argparse
import copy
import json
import tempfile
from decimal import Decimal
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry

DRAFT = "https://json-schema.org/draft/2020-12/schema"
EXPECTED_TOOLS = frozenset("query_tasks get_projects query_milestones create_task update_task "
                           "update_task_status add_comment create_project create_milestone "
                           "update_milestone delete_milestone synthetic_mutate_tasks".split())
EXPECTED_CATEGORIES = "invalid_input not_found ambiguous_identity revision_conflict key_conflict storage_failure " \
    "incoherent_capture admission_busy deadline_exceeded retention_capacity invalid_cursor expired_cursor " \
    "serialization_failure outcome_uncertain unclassified_historical internal_failure"
EXPECTED_FIXTURES = frozenset("object array null boolean string number huge_number historical retained_error text "
                              "empty_text unreadable retry_read restart_read maintenance follow_source linked_record "
                              "escaped_pointer batch batch_fallback".split()) | frozenset(
                                  "category_" + value for value in EXPECTED_CATEGORIES.split())
EXPECTED_NEGATIVES = frozenset("missing_version wrong_version boolean_version missing_source missing_presentation "
                               "unknown_kind missing_kind json_missing_payload text_missing_payload "
                               "text_nonstring_payload unreadable_payload unreadable_established missing_evidence "
                               "invalid_evidence missing_links links_nonarray invalid_category category_null "
                               "invalid_recovery recovery_missing_direction recovery_invalid_tool recovery_invalid_key "
                               "invalid_entity invalid_uuid invalid_pointer invalid_pointer_escape guessed_available "
                               "guessed_uri missing_link_reason wrong_link_reason missing_entity_id missing_entity_type "
                               "batch_negative_index batch_boolean_index batch_fraction_index batch_invalid_target "
                               "batch_missing_original_key".split())


def reject_constant(value):
    raise ValueError("Non-JSON constant: " + value)


def exact_members(pairs):
    result = {}
    for name, value in pairs:
        if name in result:
            raise ValueError("Duplicate JSON member: " + name)
        result[name] = value
    return result


def decode(text):
    return json.loads(text, parse_float=Decimal, parse_int=int,
                      parse_constant=reject_constant, object_pairs_hook=exact_members)


def read_artifact(directory, filename):
    path = (directory / filename).resolve()
    if path.parent != directory.resolve() or not path.is_file():
        raise ValueError("Missing or nonlocal export artifact: " + filename)
    return decode(path.read_text(encoding="utf-8"))


def refuse_retrieval(uri):
    raise ValueError("External schema retrieval prohibited: " + uri)


def check_references(schema):
    # Walk every member, including extension keywords. A future validator must
    # never make those references a route to the network either.
    stack = [schema]
    while stack:
        value = stack.pop()
        if isinstance(value, dict):
            for keyword in ("$ref", "$dynamicRef"):
                if keyword in value:
                    reference = value[keyword]
                    if not isinstance(reference, str) or not reference.startswith("#"):
                        raise ValueError("Only local schema references permitted")
            stack.extend(value.values())
        elif isinstance(value, list):
            stack.extend(value)


def validator(schema):
    if not isinstance(schema, dict) or schema.get("$schema") != DRAFT:
        raise ValueError("Descriptor must explicitly advertise Draft 2020-12")
    check_references(schema)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, format_checker=FormatChecker(),
                               registry=Registry(retrieve=refuse_retrieval))


def mutate(original, case):
    value = copy.deepcopy(original)
    parent = value
    for component in case["path"][:-1]:
        parent = parent[int(component)] if isinstance(parent, list) else parent[component]
    final = case["path"][-1]
    if isinstance(parent, list):
        final = int(final)
    if case["remove"]:
        del parent[final]
    else:
        parent[final] = case["value"]
    return value


def coverage(items, identity, expected, files=False):
    names = [item[identity] for item in items]
    if len(names) != len(expected) or set(names) != expected:
        raise ValueError("Truncated, unexpected or duplicate export coverage: " + identity)
    if files and len({item["file"] for item in items}) != len(items):
        raise ValueError("Duplicate export artifact mapping")


def validate_exports(directory, app_exit_code):
    if app_exit_code != 0:
        raise ValueError("App test did not exit successfully; export is not GREEN evidence")
    manifest = read_artifact(directory, "manifest.json")
    if type(manifest.get("exportVersion")) is not int or manifest["exportVersion"] != 1 \
            or manifest.get("status") != "complete":
        raise ValueError("Incomplete source-generated schema export")
    fixtures, schemas, negatives = (manifest[key] for key in ("fixtures", "schemas", "negativeCases"))
    coverage(fixtures, "name", EXPECTED_FIXTURES, files=True)
    coverage(schemas, "tool", EXPECTED_TOOLS, files=True)
    coverage(negatives, "name", EXPECTED_NEGATIVES)
    instances = {}
    for item in fixtures:
        wire = read_artifact(directory, item["file"])
        if wire.get("jsonrpc") != "2.0" or wire["result"].get("resultType") != "complete":
            raise ValueError("Fixture is not an actual complete RPC result")
        instances[item["name"]] = wire["result"]["structuredContent"]
    count = 0
    for item in schemas:
        check = validator(read_artifact(directory, item["file"]))
        for name, instance in instances.items():
            errors = list(check.iter_errors(instance))
            if errors:
                raise ValueError(item["tool"] + " rejects emitted " + name + ": " + errors[0].message)
            count += 1
        for case in negatives:
            if check.is_valid(mutate(instances[case["base"]], case)):
                raise ValueError(item["tool"] + " accepts malformed " + case["name"])
            count += 1
    print(f"PASS: {len(schemas)} actual descriptors, {len(fixtures)} emitted source cases, "
          f"{len(negatives)} malformed variants; {count} schema assertions")


def self_test():
    # Deliberately tiny nonproduction schema. These controls cannot complete task8/9.
    schema = {"$schema": DRAFT, "type": "object", "required": ["flag", "number"],
              "properties": {"flag": {"type": "boolean"}, "number": {"type": "number"}},
              "additionalProperties": False}
    check = validator(schema)
    for text in ('{"flag":false,"number":1E-9999}', '{"flag":true,"number":1E9999}',
                 '{"flag":false,"number":99999999999999999999999999999999999999}'):
        assert check.is_valid(decode(text)), text
    for text in ('{"flag":0,"number":1}', '{"flag":null,"number":1}',
                 '{"number":1}', '{"flag":false,"number":"1"}'):
        assert not check.is_valid(decode(text)), text
    unicode_keys = decode('{"é":1,"é":2}')
    assert len(unicode_keys) == 2 and unicode_keys["é"] != unicode_keys["é"]
    for text in ('{"same":1,"same":2}', 'NaN', 'Infinity', '-Infinity', '01', '1.'):
        try:
            decode(text)
        except ValueError:
            continue
        raise AssertionError("Accepted invalid JSON: " + text)
    for keyword in ("$ref", "$dynamicRef"):
        for placement in ({keyword: "https://example.invalid/schema"},
                          {"unknownExtension": {keyword: "https://example.invalid/schema"}}):
            try:
                validator({"$schema": DRAFT, **placement})
            except ValueError:
                continue
            raise AssertionError("Accepted external reference")
    local = {"$schema": DRAFT, "$defs": {"flag": {"type": "boolean"}}, "$ref": "#/$defs/flag"}
    assert validator(local).is_valid(False) and not validator(local).is_valid(0)
    # Stock jsonschema treats Decimal as number, but integral Decimal is not its
    # integer type. Owned wrapper/index integers are Int lexemes; arbitrary
    # source.payload numbers remain unconstrained. Never rebuild them to fit this.
    integer = Draft202012Validator({"type": "integer"})
    assert integer.is_valid(decode("1")) and not integer.is_valid(decode("1.0"))
    # Exercise the registry denial independently of the static scanner.
    blocked = Draft202012Validator({"$ref": "https://example.invalid/schema"},
                                  registry=Registry(retrieve=refuse_retrieval))
    try:
        blocked.is_valid({})
    except Exception as error:
        assert "Unresolvable" in str(error), error
    else:
        raise AssertionError("External retrieval registry did not reject")
    with tempfile.TemporaryDirectory(prefix="transit-schema-validator-controls-") as temporary:
        directory = Path(temporary)
        fixtures = [{"name": value, "file": value + ".json"} for value in sorted(EXPECTED_FIXTURES)]
        schemas = [{"tool": value, "file": value + "-schema.json"} for value in sorted(EXPECTED_TOOLS)]
        negatives = [{"name": value} for value in sorted(EXPECTED_NEGATIVES)]
        complete = {"exportVersion": 1, "status": "complete", "fixtures": fixtures,
                    "schemas": schemas, "negativeCases": negatives}
        cases = [(complete, 65, "App test did not exit successfully"),
                 ({**complete, "status": "incomplete"}, 0, "Incomplete source-generated schema export"),
                 (complete, 0, "Missing or nonlocal export artifact"),
                 ({**complete, "fixtures": fixtures[:1]}, 0, "export coverage: name"),
                 ({**complete, "schemas": schemas[:1]}, 0, "export coverage: tool"),
                 ({**complete, "negativeCases": negatives[:1]}, 0, "export coverage: name")]
        duplicate_tools = copy.deepcopy(schemas)
        duplicate_tools[-1] = duplicate_tools[0]
        duplicate_files = [{**item, "file": "shared.json"} for item in schemas]
        cases.extend([({**complete, "schemas": duplicate_tools}, 0, "export coverage: tool"),
                      ({**complete, "schemas": duplicate_files}, 0, "Duplicate export artifact mapping")])
        for manifest, exit_code, reason in cases:
            (directory / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            try:
                validate_exports(directory, exit_code)
            except ValueError as error:
                assert reason in str(error), (reason, str(error))
                continue
            raise AssertionError("Accepted incomplete/truncated/missing/failed export")
    print("PASS: validator-only JSON/Decimal/scalar-key/offline/fail-closed controls; no Transit schema claim")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, nargs="?")
    parser.add_argument("--app-exit-code", type=int)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.directory is not None and args.app_exit_code is not None:
        validate_exports(args.directory, args.app_exit_code)
    else:
        parser.error("Supply an export directory and --app-exit-code, or --self-test")


if __name__ == "__main__":
    main()
