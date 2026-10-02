"""Preserve CreateTaskIntent's source-literal invariant outside app runtimes."""
from pathlib import Path
import sys


def validate(source: str) -> None:
    marker = 'title: "Input JSON"'
    start = source.find(marker)
    if start < 0:
        raise ValueError('Could not locate @Parameter(title: "Input JSON") in source')
    end = source.find('var input: String', start)
    if end < 0:
        raise ValueError('Could not locate end of @Parameter block in source')
    parameter_block = source[start + len(marker):end]
    if 'at least one' not in parameter_block.lower():
        raise ValueError('@Parameter(description:) must require at least one project identifier')
    if 'Optional: "projectId"' in parameter_block:
        raise ValueError('@Parameter(description:) still marks projectId as optional')


def main() -> int:
    source_path = Path(__file__).resolve().parents[2] / 'Transit/Transit/Intents/CreateTaskIntent.swift'
    try:
        validate(source_path.read_text(encoding='utf-8'))
    except (OSError, ValueError) as error:
        print(f'CreateTaskIntent schema guard failed: {error}', file=sys.stderr)
        return 1
    print('CreateTaskIntent source-literal schema guard passed.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
