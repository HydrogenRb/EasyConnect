"""UTF-8 RTL snapshots, replay, and recoverable file transactions.

The baseline is never patched incrementally. Every operation replays the active
connection specifications against the original texts, which makes removal exact.
"""

import base64
import difflib
import hashlib
import json
import os
import re
import tempfile
from contextlib import contextmanager
from pathlib import Path

from .diagnostics import step


RTL_SUFFIXES = {".v", ".sv", ".vh", ".svh"}
SKIP_DIRS = {".git", ".hg", ".svn", ".easyconnect", ".validation", "__pycache__",
             "node_modules", ".venv", "venv", "obj_dir", "simv", "simv.daidir", "csrc"}
STATE_VERSION = 1
TOOL_TEST_ROOT = Path(__file__).resolve().parents[1] / "test"


def _root(root):
    result = Path(root).resolve()
    if not result.is_dir():
        raise ValueError("RTL source directory does not exist: {}".format(result))
    return result


def scan_rtl(root):
    """Read RTL without universal-newline conversion or stripping UTF-8 BOMs."""
    root = _root(root)
    texts = {}
    for directory, subdirs, files in os.walk(str(root), followlinks=False):
        subdirs[:] = sorted(d for d in subdirs if d.lower() not in SKIP_DIRS
                           and not Path(directory, d).is_symlink()
                           and Path(directory, d).resolve() != TOOL_TEST_ROOT)
        for filename in sorted(files):
            path = Path(directory, filename)
            if path.suffix.lower() not in RTL_SUFFIXES:
                continue
            if path.is_symlink():
                raise ValueError("Symbolic-link RTL files are not supported: {}".format(path))
            relative = path.relative_to(root).as_posix()
            try:
                texts[relative] = path.read_bytes().decode("utf-8")
            except UnicodeDecodeError:
                raise ValueError("RTL must be UTF-8 (BOM accepted): {}".format(relative))
    return texts


def _hashes(texts):
    return {name: hashlib.sha256(text.encode("utf-8")).hexdigest()
            for name, text in sorted(texts.items())}


def _encode(data):
    return base64.b64encode(data).decode("ascii")


def _decode(data):
    try:
        return base64.b64decode(data.encode("ascii"), validate=True)
    except (ValueError, TypeError, AttributeError, UnicodeError):
        raise ValueError("Invalid EasyConnect snapshot; refusing to modify files")


def _json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def _read_json(path):
    try:
        return json.loads(path.read_bytes().decode("utf-8"))
    except (ValueError, UnicodeError):
        raise ValueError("Cannot read EasyConnect state: {}".format(path))


def _checked_path(root, name, allow_state=False):
    if not isinstance(name, str) or "\\" in name:
        raise ValueError("Invalid path in EasyConnect state")
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts or ":" in name:
        raise ValueError("Unsafe path in EasyConnect state: {}".format(name))
    if allow_state and name == ".easyconnect/state.json":
        pass
    elif relative.suffix.lower() not in RTL_SUFFIXES or any(p in SKIP_DIRS for p in relative.parts):
        raise ValueError("Unexpected file in EasyConnect state: {}".format(name))
    path = root / relative
    try:
        path.resolve().relative_to(root)
    except ValueError:
        raise ValueError("Snapshot path escapes source directory: {}".format(name))
    if path.is_symlink():
        raise ValueError("Refusing to overwrite symbolic link: {}".format(name))
    return path


def _load_state(root):
    path = root / ".easyconnect" / "state.json"
    if not path.exists():
        return None
    state = _read_json(path)
    if not isinstance(state, dict) or state.get("version") != STATE_VERSION:
        raise ValueError("Unsupported EasyConnect state version")
    if not isinstance(state.get("baseline"), dict) or not isinstance(state.get("expected"), dict):
        raise ValueError("Invalid EasyConnect state snapshot")
    if not isinstance(state.get("connections"), list):
        raise ValueError("Invalid EasyConnect connection list")
    ids = set()
    for spec in state["connections"]:
        if not isinstance(spec, dict) or not isinstance(spec.get("id"), str) or spec["id"] in ids:
            raise ValueError("Invalid or duplicate connection ID in EasyConnect state")
        ids.add(spec["id"])
        if any(not isinstance(spec.get(key), str) or not spec[key] for key in ("source", "target")):
            raise ValueError("Invalid connection endpoints in EasyConnect state")
    for name in state["baseline"]:
        _checked_path(root, name)
    return state


def _assert_expected(texts, expected):
    actual = _hashes(texts)
    if actual != expected:
        affected = sorted(name for name in set(actual) | set(expected)
                          if actual.get(name) != expected.get(name))
        raise ValueError("RTL changed outside EasyConnect: {}. No files were overwritten. "
                         "Restore the last generated contents before changing/removing connections. "
                         "The original snapshot is retained in .easyconnect/state.json."
                         .format(", ".join(affected[:8])))


def assert_no_pending(root):
    root = _root(root)
    if (root / ".easyconnect" / "pending.json").exists():
        raise ValueError("An interrupted transaction is pending; run 'recover' before continuing")


def list_connections(root):
    root = _root(root)
    assert_no_pending(root)
    state = _load_state(root)
    return [] if state is None else state["connections"]


def _pid_alive(pid):
    if not isinstance(pid, int) or pid <= 0:
        return True  # A malformed lock must not be stolen.
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
        kernel.GetExitCodeProcess.restype = wintypes.BOOL
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        handle = kernel.OpenProcess(0x1000, False, pid)
        if not handle:
            return ctypes.get_last_error() != 87  # ERROR_INVALID_PARAMETER: PID absent.
        try:
            status = wintypes.DWORD()
            if not kernel.GetExitCodeProcess(handle, ctypes.byref(status)):
                return True
            return status.value == 259  # STILL_ACTIVE
        finally:
            kernel.CloseHandle(handle)
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


@contextmanager
def _lock(root, recover=False):
    directory = root / ".easyconnect"
    if directory.is_symlink():
        raise ValueError(".easyconnect must not be a symbolic link")
    directory.mkdir(exist_ok=True)
    path = directory / "lock"
    if recover and path.exists():
        lock = _read_json(path)
        if not isinstance(lock, dict) or _pid_alive(lock.get("pid")):
            raise ValueError("Another EasyConnect process holds the lock; recovery was not started")
        path.unlink()
    try:
        fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise ValueError("EasyConnect is locked; if its process exited, run 'recover'")
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(_json_bytes({"pid": os.getpid()}))
            handle.flush()
            os.fsync(handle.fileno())
        yield
    finally:
        path.unlink(missing_ok=True)


def _atomic_write(path, data):
    """Replace one file atomically; the journal supplies multi-file recovery."""
    if data is None:
        if path.exists():
            path.unlink()
        return
    if not path.parent.is_dir():
        raise ValueError("Target directory disappeared: {}".format(path.parent))
    mode = path.stat().st_mode if path.exists() else None
    fd, temporary = tempfile.mkstemp(prefix=".easyconnect-", suffix=".tmp", dir=str(path.parent))
    temporary = Path(temporary)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        if mode is not None:
            os.chmod(str(temporary), mode)
        os.replace(str(temporary), str(path))
    finally:
        if temporary.exists():
            temporary.unlink()


def _file_bytes(path):
    return path.read_bytes() if path.exists() else None


def _transaction(root, before, after, new_state):
    records = []
    for name in sorted(before):
        if before[name] != after[name]:
            records.append({"path": name, "old": _encode(before[name].encode("utf-8")),
                            "new": _encode(after[name].encode("utf-8"))})
    state_path = root / ".easyconnect" / "state.json"
    old_state = _file_bytes(state_path)
    new_bytes = None if new_state is None else _json_bytes(new_state)
    records.append({"path": ".easyconnect/state.json",
                    "old": None if old_state is None else _encode(old_state),
                    "new": None if new_bytes is None else _encode(new_bytes)})
    pending = root / ".easyconnect" / "pending.json"
    _assert_expected(scan_rtl(root), _hashes(before))
    step("write transaction journal", _atomic_write, pending,
         _json_bytes({"version": STATE_VERSION, "files": records}))
    written = []
    try:
        for record in records:
            path = _checked_path(root, record["path"], allow_state=True)
            old = None if record["old"] is None else _decode(record["old"])
            if _file_bytes(path) != old:
                raise ValueError("File changed during transaction: {}".format(record["path"]))
            written.append(record)
            step("write file " + record["path"], _atomic_write,
                 path, None if record["new"] is None else _decode(record["new"]))
        pending.unlink()
    except BaseException as error:
        try:
            for record in reversed(written):
                path = _checked_path(root, record["path"], allow_state=True)
                current = _file_bytes(path)
                new = None if record["new"] is None else _decode(record["new"])
                old = None if record["old"] is None else _decode(record["old"])
                if current == old:
                    continue
                if current != new:
                    raise ValueError("File changed during rollback: {}".format(record["path"]))
                _atomic_write(path, old)
            pending.unlink()
        except BaseException:
            raise ValueError("Transaction failed and rollback is incomplete; run 'recover'. "
                             "Original error: {}".format(error)) from error
        raise


def recover(root):
    """Roll back a journal whose files are still either their old or new bytes."""
    root = _root(root)
    with _lock(root, recover=True):
        pending = root / ".easyconnect" / "pending.json"
        if not pending.exists():
            return {"recovered": False, "files": []}
        journal = _read_json(pending)
        if not isinstance(journal, dict) or journal.get("version") != STATE_VERSION:
            raise ValueError("Unsupported EasyConnect transaction journal")
        records = journal.get("files")
        if not isinstance(records, list):
            raise ValueError("Invalid EasyConnect transaction journal")
        checked = []
        names = set()
        for record in records:
            if not isinstance(record, dict) or "old" not in record or "new" not in record:
                raise ValueError("Invalid EasyConnect transaction record")
            name = record.get("path")
            path = _checked_path(root, name, allow_state=True)
            if name in names:
                raise ValueError("Duplicate transaction path")
            names.add(name)
            old = None if record["old"] is None else _decode(record["old"])
            new = None if record["new"] is None else _decode(record["new"])
            if _file_bytes(path) not in (old, new):
                raise ValueError("Recovery refused: {} was edited after interruption".format(name))
            checked.append((path, old))
        for path, old in reversed(checked):
            _atomic_write(path, old)
        pending.unlink()
        return {"recovered": True, "files": sorted(names)}


def _diff(before, after):
    chunks = []
    for name in sorted(before):
        if before[name] == after[name]:
            continue
        # Splitlines avoids embedding CRCRLF in terminal output. Snapshots retain
        # the exact source bytes, including a missing final newline.
        chunks.extend(difflib.unified_diff(before[name].splitlines(), after[name].splitlines(),
                                           fromfile="a/" + name, tofile="b/" + name, lineterm=""))
    return "\n".join(chunks)


def _prepare(root, operation, spec, connection_id, router):
    assert_no_pending(root)
    before = step("scan RTL source directory", scan_rtl, root)
    state = step("load connection state", _load_state, root)
    if state is None:
        state = {"version": STATE_VERSION,
                 "baseline": {name: _encode(text.encode("utf-8")) for name, text in before.items()},
                 "expected": _hashes(before), "connections": [], "next_id": 1}
    step("check external RTL changes", _assert_expected, before, state["expected"])
    try:
        baseline = {name: _decode(data).decode("utf-8") for name, data in state["baseline"].items()}
    except UnicodeError:
        raise ValueError("Invalid UTF-8 in EasyConnect baseline")
    if set(baseline) != set(before):
        raise ValueError("EasyConnect baseline file set is inconsistent")
    connections = [dict(item) for item in state["connections"]]
    next_id = state.get("next_id", 1)
    if not isinstance(next_id, int) or next_id < 1:
        raise ValueError("Invalid next connection ID in state")
    known = {item["id"] for item in connections}
    if operation == "add":
        spec = dict(spec or {})
        connection_id = spec.get("name") or spec.get("id")
        if connection_id is None:
            while "c{:03d}".format(next_id) in known:
                next_id += 1
            connection_id = "c{:03d}".format(next_id)
            next_id += 1
        if not isinstance(connection_id, str) or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", connection_id):
            raise ValueError("Connection name must be a Verilog-style identifier")
        if connection_id in known:
            raise ValueError("Connection ID already exists: {}".format(connection_id))
        spec.update({"id": connection_id, "name": connection_id})
        connections.append(spec)
    elif operation in ("remove", "change"):
        if connection_id not in known:
            raise ValueError("Unknown connection ID: {}".format(connection_id))
        if operation == "remove":
            connections = [item for item in connections if item["id"] != connection_id]
        else:
            for item in connections:
                if item["id"] == connection_id:
                    item.update(spec or {})
                    item["id"] = connection_id
                    item["name"] = connection_id
    else:
        raise ValueError("Unknown state operation: {}".format(operation))
    texts = baseline
    details = []
    for item in connections:
        texts, detail = step("replay connection {} ({} -> {})".format(
            item["id"], item["source"], item["target"]), router, root, texts, item)
        if set(texts) != set(baseline) or not all(isinstance(text, str) for text in texts.values()):
            raise ValueError("Routing engine returned an invalid RTL file set")
        if item.get("top") is None and isinstance(detail, dict) and detail.get("top"):
            item["top"] = detail["top"]
        details.append({"id": item["id"], "detail": detail})
    _assert_expected(scan_rtl(root), _hashes(before))
    new_state = None if not connections else {
        "version": STATE_VERSION, "baseline": state["baseline"], "expected": _hashes(texts),
        "connections": connections, "next_id": next_id,
    }
    result = {"id": connection_id, "operation": operation,
              "files": sorted(name for name in before if before[name] != texts[name]),
              "diff": _diff(before, texts), "details": details, "connections": connections}
    return before, texts, new_state, result


def apply_operation(root, operation, spec=None, connection_id=None, dry_run=False, router=None):
    root = _root(root)
    if router is None:
        from .engine import route
        router = route
    if dry_run:
        _, _, _, result = step("prepare {} preview".format(operation), _prepare,
                               root, operation, spec, connection_id, router)
        result["dry_run"] = True
        return result
    with _lock(root):
        before, texts, new_state, result = step("prepare {} operation".format(operation), _prepare,
                                               root, operation, spec, connection_id, router)
        step("commit RTL and state transaction", _transaction, root, before, texts, new_state)
        result["dry_run"] = False
        return result
