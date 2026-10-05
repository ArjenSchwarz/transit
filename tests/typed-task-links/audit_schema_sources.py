"""Source inventory/RED guard only; no compilation, store, or CloudKit access.

python3 tests/typed-task-links/audit_schema_sources.py
python3 tests/typed-task-links/audit_schema_sources.py --check

--check requires source registrations in the audited current-schema factories.
It deliberately fails while task2 models/registrations are absent. A source PASS
cannot prove migration, SwiftData inferred schema, or server record registration.
"""

import argparse
import json
import pathlib
import re


CURRENT = {
    "Transit/Transit/TransitApp.swift",
    "Transit/TransitTests/TestModelContainer.swift",
    "Transit/TransitTests/MCPWritePersistenceProbeTests.swift",
    "tests/mcp-write-probe/ServiceProbe.swift",
    "tests/mcp-write-probe/CoordinatorProbe.swift",
    "tests/mcp-write-probe/FoundationProbe.swift",
}
LINKS = {"TaskLinkOccurrence", "TaskLinkRemovalEvidence"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[2]
    inventory = []
    missing = []
    seen = set()
    for base in (root / "Transit", root / "tests/mcp-write-probe", root / "tests/development-isolation"):
        for path in sorted(base.rglob("*.swift")):
            source = path.read_text()
            relative = str(path.relative_to(root))
            for match in re.finditer(r"(?<!\w)Schema\s*\(\s*\[([\s\S]*?)\]\s*\)", source):
                models = sorted(set(re.findall(r"(?:\w+\.)?(\w+)\.self", match.group(1))))
                current = relative in CURRENT
                seen.add(relative)
                absent = sorted(LINKS - set(models)) if current else []
                inventory.append(dict(path=relative, line=source.count("\n", 0, match.start()) + 1,
                                      models=models, scope="current parity" if current else "limited/control",
                                      missingLinkSourceRegistrations=absent))
                if absent:
                    missing.append(relative)
    dynamic = root / "tests/mcp-write-probe/Probe.swift"
    source = dynamic.read_text()
    registrations = sorted(set(re.findall(r"(?:\w+\.)?(\w+)\.self", source)))
    # Dynamic mode-specific registration needs owner review as well as presence:
    # seed-old intentionally remains pre-receipt/pre-link; current modes add links.
    inventory.append(dict(path=str(dynamic.relative_to(root)), scope="dynamic current modes / seed-old legacy",
                          modelsMentioned=registrations, manualModeBranchReviewRequired=True,
                          missingLinkSourceRegistrations=sorted(LINKS - set(registrations))))
    if not LINKS.issubset(registrations):
        missing.append(str(dynamic.relative_to(root)))
    missing.extend(sorted(CURRENT - seen))
    result = dict(evidence="static source tokens only", inventory=inventory,
                  containerFactory="receives caller schema; no model registration",
                  productionModelFilesPresent=all((root / "Transit/Transit/Models" / (name + ".swift")).is_file()
                                                  for name in LINKS),
                  currentSourceParityMissing=sorted(set(missing)),
                  excluded="JSONSchema; custom limited/control schemas do not mint graph coverage",
                  developmentIsolation="MigrationProbe historical/current isolation fixture remains graph-free",
                  cloudKitServerEvidence=False)
    print(json.dumps(result, indent=2))
    if args.check and (missing or not result["productionModelFilesPresent"]):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
