"""Transaction/replay tests independent of the RTL parser."""

import base64
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from easyconnect import state


def append_route(root, texts, spec):
    result = dict(texts)
    name = sorted(result)[0]
    result[name] += "// {}: {} -> {}\r\n".format(spec["id"], spec["source"], spec["target"])
    return result, {"top": "top", "stages": ["test"]}


class StateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.rtl = self.root / "top.v"
        self.original = b"\xef\xbb\xbfmodule top;\r\nendmodule"  # BOM, CRLF, missing final newline.
        self.rtl.write_bytes(self.original)

    def tearDown(self):
        self.directory.cleanup()

    def operate(self, operation, spec=None, connection_id=None, dry_run=False):
        return state.apply_operation(self.root, operation, spec, connection_id,
                                     dry_run, router=append_route)

    def add(self, name=None):
        spec = {"source": "a.x", "target": "b.y"}
        if name is not None:
            spec["name"] = name
        return self.operate("add", spec)

    def test_exact_round_trip_and_state_clears(self):
        result = self.add("route1")
        self.assertEqual(result["id"], "route1")
        self.assertEqual(state.list_connections(self.root)[0]["top"], "top")
        self.assertNotEqual(self.rtl.read_bytes(), self.original)
        self.operate("remove", connection_id="route1")
        self.assertEqual(self.rtl.read_bytes(), self.original)
        self.assertFalse((self.root / ".easyconnect/state.json").exists())
        self.rtl.write_bytes(b"module top; endmodule\n")
        self.add()  # Once the last connection is removed, a new baseline is permitted.

    def test_dry_run_writes_nothing(self):
        result = self.operate("add", {"source": "a.x", "target": "b.y"}, dry_run=True)
        self.assertIn("+", result["diff"])
        self.assertEqual(self.rtl.read_bytes(), self.original)
        self.assertFalse((self.root / ".easyconnect").exists())

    def test_change_replays_and_remove_retains_other_connections(self):
        self.add("first")
        self.add("second")
        self.operate("change", {"source": "c.z", "target": "d.w"}, "first")
        value = self.rtl.read_bytes().decode("utf-8")
        self.assertIn("first: c.z -> d.w", value)
        self.assertNotIn("first: a.x", value)
        self.operate("remove", connection_id="first")
        value = self.rtl.read_bytes().decode("utf-8")
        self.assertNotIn("first:", value)
        self.assertIn("second:", value)
        self.operate("remove", connection_id="second")
        self.assertEqual(self.rtl.read_bytes(), self.original)

    def test_external_edit_refused_without_overwrite(self):
        self.add()
        changed = self.rtl.read_bytes() + b"// external change\n"
        self.rtl.write_bytes(changed)
        with self.assertRaisesRegex(ValueError, "changed outside"):
            self.operate("remove", connection_id="c001")
        self.assertEqual(self.rtl.read_bytes(), changed)

    def test_new_rtl_file_refused(self):
        self.add()
        (self.root / "new.v").write_text("module new; endmodule\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "changed outside"):
            self.add()

    def test_failed_router_never_changes_rtl(self):
        def failed(root, texts, spec):
            raise ValueError("incompatible widths")
        with self.assertRaisesRegex(ValueError, "incompatible"):
            state.apply_operation(self.root, "add", {"source": "a.x", "target": "b.y"}, router=failed)
        self.assertEqual(self.rtl.read_bytes(), self.original)
        self.assertFalse((self.root / ".easyconnect/state.json").exists())

    def test_write_failure_rolls_back_prior_files(self):
        other = self.root / "z.v"
        other.write_bytes(b"module z; endmodule\n")
        before_other = other.read_bytes()

        def both(root, texts, spec):
            return {name: text + "// connection\n" for name, text in texts.items()}, {}

        real_write = state._atomic_write
        failed = [False]

        def fail_once(path, data):
            if path.name == "z.v" and not failed[0]:
                failed[0] = True
                raise OSError("simulated write failure")
            return real_write(path, data)

        with mock.patch.object(state, "_atomic_write", side_effect=fail_once):
            with self.assertRaisesRegex(OSError, "simulated"):
                state.apply_operation(self.root, "add", {"source": "a.x", "target": "b.y"}, router=both)
        self.assertEqual(self.rtl.read_bytes(), self.original)
        self.assertEqual(other.read_bytes(), before_other)
        self.assertFalse((self.root / ".easyconnect/pending.json").exists())

    def journal(self, old, new, path="top.v"):
        directory = self.root / ".easyconnect"
        directory.mkdir(exist_ok=True)
        encode = lambda value: None if value is None else base64.b64encode(value).decode("ascii")
        journal = {"version": 1, "files": [{"path": path, "old": encode(old), "new": encode(new)}]}
        (directory / "pending.json").write_text(json.dumps(journal), encoding="utf-8")

    def test_recovery_after_interruption(self):
        generated = self.original + b"// generated\n"
        self.journal(self.original, generated)
        self.rtl.write_bytes(generated)
        with self.assertRaisesRegex(ValueError, "interrupted"):
            state.list_connections(self.root)
        self.assertTrue(state.recover(self.root)["recovered"])
        self.assertEqual(self.rtl.read_bytes(), self.original)

    def test_recovery_refuses_external_edits(self):
        generated = self.original + b"// generated\n"
        self.journal(self.original, generated)
        external = generated + b"// user\n"
        self.rtl.write_bytes(external)
        with self.assertRaisesRegex(ValueError, "edited after"):
            state.recover(self.root)
        self.assertEqual(self.rtl.read_bytes(), external)
        self.assertTrue((self.root / ".easyconnect/pending.json").exists())

    def test_recovery_refuses_traversal(self):
        self.journal(b"old", b"new", "../victim.v")
        with self.assertRaisesRegex(ValueError, "Unsafe path"):
            state.recover(self.root)

    def test_live_lock_refused(self):
        directory = self.root / ".easyconnect"
        directory.mkdir()
        lock = directory / "lock"
        lock.write_text(json.dumps({"pid": os.getpid()}), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "holds the lock"):
            state.recover(self.root)
        self.assertTrue(lock.exists())


if __name__ == "__main__":
    unittest.main()
