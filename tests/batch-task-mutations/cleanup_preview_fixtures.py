"""Delete only marked Task7 fixture stores after their pinned run fully drains.

Default is validation/dry-run. Never call this in the test host: its centrally
retained ModelContainers may still hold SQLite files open.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import uuid


MARKER = "T2384_TASK7_PREVIEW_DIRECTORY="
PREFIX = "T2384Task7Preview-"
GUARD = b"preview must not touch reservation evidence"
MAX_DIRECTORIES = 48  # 33 preview bodies plus 15 existing-service controls.
MAX_ENTRIES = 512


def require(condition, message):
    if not condition:
        raise ValueError(message)


def fixture_path(raw, temp_root):
    """Pure validation; exact direct-child path, canonical UUID, no links."""
    path = Path(raw)
    require(path.is_absolute() and str(path) == raw, "Noncanonical marker path")
    require(path.parent == temp_root, "Marker outside exact development temp root")
    suffix = path.name.removeprefix(PREFIX)
    require(path.name.startswith(PREFIX), "Not a Task7 fixture basename")
    require(re.fullmatch(r"[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}", suffix), "Invalid UUID")
    require(str(uuid.UUID(suffix)).upper() == suffix, "Noncanonical fixture UUID")
    require(temp_root.resolve() == temp_root, "Symlinked development temp root")
    require(path.resolve() == path and not path.is_symlink(), "Symlinked fixture path")
    require(path.is_dir(), "Missing fixture directory")
    count = 0
    directories = [path]
    while directories:
        with os.scandir(directories.pop()) as entries:
            for entry in entries:
                mode = entry.stat(follow_symlinks=False).st_mode
                require(stat.S_ISDIR(mode) or stat.S_ISREG(mode), "Nonregular or symlinked fixture entry")
                count += 1
                require(count <= MAX_ENTRIES, "Fixture entry count exceeds bound")
                if stat.S_ISDIR(mode):
                    directories.append(Path(entry.path))
    require((path / "untouched.guard").read_bytes() == GUARD, "Fixture ownership guard mismatch")
    require((path / "preview.store").is_file(), "Missing owned preview store")
    return path


def exact_pid_absence(lines, pids, host, launch, result):
    """No signal is sent. Reject an active recorded PID or exact owned job."""
    for line in lines:
        values = line.strip().split(None, 1)
        if len(values) != 2 or not values[0].isdigit():
            continue
        pid, command = int(values[0]), values[1]
        require(pid not in pids, "Recorded owned PID still exists")
        require(not command.startswith(str(host)), "Owned isolated host is still live")
        owned_runner = "xcodebuild" in command and (str(launch) in command or str(result) in command)
        require(not owned_runner, "Owned test runner is still live")


def marked_directories(text):
    require(text.count("◇ Test run started.") == 1 and "Restarting after unexpected exit" not in text,
            "Automatic replays or incomplete run markers require store preservation")
    markers = []
    for line in text.splitlines():
        if MARKER in line:
            require(line.startswith(MARKER), "Interleaved/noncanonical ownership marker")
            markers.append(line[len(MARKER):])
    require(0 < len(markers) <= MAX_DIRECTORIES, "Missing or excessive fixture markers")
    require(len(markers) == len(set(markers)), "Duplicate fixture ownership marker")
    return markers


def validated_cleanup(repo, evidence_path, drain_path, readiness_path):
    evidence = json.loads(evidence_path.read_text())
    drain = json.loads(drain_path.read_text())
    readiness = json.loads(readiness_path.read_text())
    pin = evidence["sourcePin"]
    require(isinstance(pin, str) and re.fullmatch(r"[0-9a-f]{40}", pin), "Invalid source pin")
    require(pin == readiness["sourcePin"] == drain["sourcePin"], "Source/run/drain pins disagree")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    require(head == pin, "Current source pin differs from run")
    require(not subprocess.check_output(["git", "status", "--porcelain"], cwd=repo, text=True), "Dirty source")
    for section in ("ownedSource", "protectedSource"):
        for relative, digest in readiness[section].items():
            path = repo / relative
            require(path.resolve().is_relative_to(repo), "Source path escapes repository")
            require(hashlib.sha256(path.read_bytes()).hexdigest() == digest, "Source hash mismatch")
    require(evidence["declarations"] == 25 and evidence["bodies"] == 68, "Unexpected focused run inventory")
    log = Path(evidence["logPath"])
    require(log.resolve().is_relative_to(repo / ".codex-cache"), "Run log outside private artifacts")
    require(log.is_file() and not log.is_symlink() and log.stat().st_size <= 16 * 1024 * 1024,
            "Invalid or oversized run log")
    require(hashlib.sha256(log.read_bytes()).hexdigest() == evidence["logSHA256"], "Run log hash mismatch")
    text = log.read_text()
    require(drain["workerHostDrained"] is True and drain["ownedRemaining"] == [], "Drain proof is not clear")
    finished, drained = evidence["finishedAt"], drain["time"]
    require(all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)
                for v in (finished, drained)), "Invalid run/drain times")
    require(drained >= finished, "Drain proof predates run completion")
    pids = [evidence["runnerPID"]] + evidence["hostPIDs"]
    require(pids and len(pids) == len(set(pids)), "Invalid owned PID inventory")
    require(all(type(pid) is int and pid > 1 for pid in pids), "Invalid owned PID")
    derived = repo / "DerivedData/t2384-task3-red-run1"
    host = derived / "Build/Products/Debug/Transit.app/Contents/MacOS/Transit"
    name = evidence["runName"]
    require(isinstance(name, str) and re.fullmatch(r"Task7Red(?:Attempt[1-9][0-9]*)?", name), "Invalid run name")
    launch, result = Path(evidence["launchPath"]), Path(evidence["resultPath"])
    require(launch == derived / "Build/Products" / ("T2384" + name + ".xctestrun"), "Unowned launch path")
    require(result == derived / (name + ".xcresult"), "Unowned result path")
    lines = subprocess.check_output(["ps", "-axo", "pid,command"], text=True).splitlines()
    exact_pid_absence(lines, set(pids), host, launch, result)
    temp_root = Path.home() / "Library/Containers/me.nore.ig.Transit.development/Data/tmp"
    markers = marked_directories(text)
    paths = [fixture_path(marker, temp_root) for marker in markers]
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-evidence", required=True, type=Path)
    parser.add_argument("--drain-proof", required=True, type=Path)
    parser.add_argument("--readiness-hashes", required=True, type=Path)
    parser.add_argument("--delete", action="store_true", help="Otherwise validate without deleting")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    paths = validated_cleanup(repo, args.run_evidence, args.drain_proof, args.readiness_hashes)
    if args.delete:
        require(shutil.rmtree.avoids_symlink_attacks, "Safe fd-based removal is unavailable")
        for path in paths:
            shutil.rmtree(path)
    print(json.dumps({"validatedDirectories": [str(path) for path in paths],
                      "count": len(paths), "deleted": args.delete, "signals": []}, indent=2))


if __name__ == "__main__":
    main()
