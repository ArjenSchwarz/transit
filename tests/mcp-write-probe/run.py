"""Terminate actual SwiftData writers around save, then reopen in new processes."""
import pathlib
import selectors
import subprocess
import sys
import tempfile
import time


def marker(process, expected):
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if selector.select(timeout=1):
            line = process.stdout.readline().strip()
            if line == expected:
                selector.close()
                return
            if not line and process.poll() is not None:
                raise RuntimeError(f"child exited before {expected}: {process.returncode}")
    process.kill()
    raise TimeoutError(f"child did not reach {expected}")


def run(binary, mode, store):
    output = subprocess.check_output([binary, mode, str(store)], text=True, timeout=30).strip().splitlines()
    return output[-1] if output else ""


def main():
    binary = sys.argv[1]
    with tempfile.TemporaryDirectory(prefix="transit-mcp-disk-") as temporary:
        root = pathlib.Path(temporary)
        for index, boundary in enumerate(["before", "after"] + ["during"] * 12):
            store = root / f"probe-{index}.store"
            run(binary, "seed-old", store)
            process = subprocess.Popen([binary, "stage", str(store)], stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, text=True, bufsize=1)
            try:
                marker(process, "STAGED")
                if boundary != "before":
                    process.stdin.write("commit\n")
                    process.stdin.flush()
                    marker(process, "SAVED" if boundary == "after" else "SAVING")
                    if boundary == "during":
                        time.sleep(index * 0.002)
                process.kill()
                process.wait(timeout=10)
                outcome = run(binary, "verify", store)
                if boundary == "before":
                    assert outcome == "ACCEPTED", outcome
                elif boundary == "after":
                    assert outcome == "COMMITTED", outcome
                print(f"PASS {boundary} save: {outcome}")
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=10)
        cleanup_store = root / "cleanup.store"
        run(binary, "seed-old", cleanup_store)
        assert run(binary, "cleanup", cleanup_store) == "CLEAN"
        print("PASS additive old-store reopen and rollback without ghost effects")
        readonly_store = root / "readonly.store"
        run(binary, "seed-old", readonly_store)
        # Migrate before opening read-only; otherwise opening attempts migration.
        assert run(binary, "verify-clean", readonly_store) == "CLEAN"
        assert run(binary, "readonly", readonly_store) == "FAILED_AS_EXPECTED"
        assert run(binary, "verify-clean", readonly_store) == "CLEAN"
        print("PASS actual read-only save failure and later unrelated save")


if __name__ == "__main__":
    main()
