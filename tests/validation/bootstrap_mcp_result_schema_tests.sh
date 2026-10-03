#!/bin/sh
# Isolated test-only dependencies; no changes to global Python or Transit runtime.
set -eu
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_directory=$(CDPATH= cd -- "$script_directory/../.." && pwd)
environment_directory="$repository_directory/.codex-cache/schema-tests/venv"
python3 -m venv "$environment_directory"
"$environment_directory/bin/python" -m pip --isolated install --disable-pip-version-check --no-cache-dir \
    -r "$script_directory/mcp-result-schema-requirements.txt"
"$environment_directory/bin/python" "$script_directory/validate_mcp_result_schemas.py" --self-test
