"""Verify a real second process cannot acquire the lifetime coordinator lock."""
import pathlib
import subprocess
import sys
import tempfile
from run import marker, run


with tempfile.TemporaryDirectory(prefix="transit-mcp-guards-") as temporary:
    directory = pathlib.Path(temporary) / "sidecar"
    process = subprocess.Popen([sys.argv[1], "hold", str(directory)], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, text=True, bufsize=1)
    try:
        marker(process, "LOCKED")
        assert run(sys.argv[1], "busy", directory) == "BUSY"
        process.kill()
        process.wait(timeout=10)
        assert run(sys.argv[1], "recover", directory) == "RECOVERED"
        files = list((directory / "guards").glob("*.json"))
        assert len(files) == 1
        files[0].write_text("unreadable guard")
        assert run(sys.argv[1], "corrupt", directory) == "FAIL_CLOSED"
        print("PASS two-process lock, SIGKILL recovery, unresolved binding, fixed expiry and corrupt-store rejection")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=10)
