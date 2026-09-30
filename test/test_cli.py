"""End-to-end tests. Run with: python -m unittest discover -s test -v."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

from svcheck import SLANG, check_files


PROJECT = Path(__file__).resolve().parents[1]
CLI = PROJECT / "EasyConnect.py"
FIXTURES = Path(__file__).resolve().parent / "fixtures"


class EasyConnectTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="easyconnect_test_")
        self.addCleanup(self.tmp.cleanup)
        self.src = Path(self.tmp.name) / "rtl"
        self.src.mkdir()
        self.compiler = shutil.which("iverilog")

    def fixture(self, name="basic"):
        shutil.copytree(FIXTURES / name, self.src, dirs_exist_ok=True)
        return self.snapshot()

    def design(self, text):
        (self.src / "design.v").write_text(text, encoding="utf-8")
        return self.snapshot()

    def snapshot(self):
        return {
            path.relative_to(self.src).as_posix(): path.read_bytes()
            for path in self.src.rglob("*")
            if path.is_file()
        }

    def rtl_snapshot(self):
        return {
            name: contents
            for name, contents in self.snapshot().items()
            if Path(name).suffix in {".v", ".sv", ".vh", ".svh"}
            and not any(part.startswith(".") for part in Path(name).parts)
        }

    def rtl(self):
        return "\n".join(data.decode("utf-8") for data in self.rtl_snapshot().values())

    def run_cli(self, *args, ok=True, src=True):
        command = [sys.executable, str(CLI), *map(str, args)]
        if src:
            command.extend(["--src", str(self.src)])
        environment = dict(os.environ, PYTHONIOENCODING="utf-8")
        result = subprocess.run(
            command, cwd=self.src, capture_output=True, text=True,
            encoding="utf-8", errors="replace", env=environment, timeout=30,
        )
        diagnostic = f"{command!r}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        self.assertNotIn("Traceback (most recent call last)", result.stderr, diagnostic)
        if ok:
            self.assertEqual(result.returncode, 0, diagnostic)
        else:
            self.assertNotEqual(result.returncode, 0, diagnostic)
        return result

    def add(self, source="top.U_B.U_C.fifo_rd", destination="top.U_D.fifo_rd_in", name="route", **kwargs):
        extra = kwargs.pop("extra", ())
        return self.run_cli("add", source, destination, "--name", name, "--top", "top", *extra, **kwargs)

    def compile_if_available(self, *, extra_files=()):
        """Use an actual SV compiler when installed, without adding a dependency."""
        sources = [str(self.src / name) for name in self.rtl_snapshot() if Path(name).suffix in {".v", ".sv"}]
        check_files(self, sources + list(map(str, extra_files)), self.src)
        if not self.compiler:
            return
        output = Path(self.tmp.name) / "simulation.out"
        result = subprocess.run(
            [self.compiler, "-g2012", "-s", "top", "-I", str(self.src), "-o", str(output), *sources, *map(str, extra_files)],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_version_and_help(self):
        version = self.run_cli("--version", src=False)
        self.assertRegex(version.stdout + version.stderr, r"\d+\.\d+\.\d+")
        help_result = self.run_cli("--help", src=False)
        for command in ("add", "remove", "change", "map", "list"):
            self.assertIn(command, help_result.stdout)

    def test_map_recurses_subdirectories(self):
        baseline = self.fixture()
        result = self.run_cli("map", "--top", "top")
        for instance in ("U_B", "U_C", "U_D"):
            self.assertIn(instance, result.stdout)
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_ansi_add_list_remove_restores_exact_original_bytes(self):
        baseline = self.fixture()
        self.add(name="fifo")
        self.assertNotEqual(self.rtl_snapshot(), baseline)
        self.assertIn("fifo", self.run_cli("list").stdout)
        self.assertRegex(self.rtl(), r"assign\s+[^;]*fifo_rd\s*;")
        self.assertRegex(self.rtl(), r"assign\s+fifo_rd_in\s*=")
        self.compile_if_available()
        self.run_cli("remove", "fifo")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_nonansi_add_and_remove(self):
        baseline = self.fixture("nonansi")
        self.add(name="legacy")
        self.assertRegex(self.rtl(), r"(?s)output\s+(?:wire\s+)?\[7:0\]")
        self.assertRegex(self.rtl(), r"(?s)input\s+(?:wire\s+)?\[7:0\]")
        self.compile_if_available()
        self.run_cli("remove", "legacy")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_dry_run_does_not_create_or_change_any_file(self):
        self.fixture()
        baseline = self.snapshot()
        result = self.add(name="preview", extra=("--dry-run",))
        self.assertTrue(result.stdout.strip())
        self.assertEqual(self.snapshot(), baseline)

    def test_remove_dry_run_keeps_connection(self):
        self.fixture()
        self.add(name="preview")
        baseline = self.snapshot()
        self.run_cli("remove", "preview", "--dry-run")
        self.assertEqual(self.snapshot(), baseline)

    def test_invalid_endpoint_fails_without_partial_edits(self):
        self.fixture()
        baseline = self.snapshot()
        self.add(destination="top.DOES_NOT_EXIST.signal", ok=False)
        self.assertEqual(self.snapshot(), baseline)

    def test_duplicate_id_is_rejected_or_idempotent_without_new_edits(self):
        self.fixture()
        self.add(name="once")
        baseline = self.snapshot()
        command = [sys.executable, str(CLI), "add", "top.U_B.U_C.fifo_rd", "top.U_D.fifo_rd_in", "--name", "once", "--src", str(self.src), "--top", "top"]
        subprocess.run(command, cwd=self.src, capture_output=True, timeout=30)
        self.assertEqual(self.snapshot(), baseline)

    def test_unique_short_instance_paths(self):
        baseline = self.fixture()
        self.add("U_C.fifo_rd", "U_D.fifo_rd_in", name="short")
        self.compile_if_available()
        self.run_cli("remove", "short")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_current_directory_and_unique_top_are_default(self):
        baseline = self.fixture()
        self.run_cli("add", "U_C.fifo_rd", "U_D.fifo_rd_in", "--name", "defaults", src=False)
        self.assertIn("defaults", self.run_cli("list", src=False).stdout)
        self.compile_if_available()
        self.run_cli("remove", "defaults", src=False)
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_windows_newlines_and_utf8_bom_are_restored(self):
        self.fixture()
        for path in self.src.rglob("*.v"):
            content = path.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            path.write_bytes(b"\xef\xbb\xbf" + content)
        baseline = self.rtl_snapshot()
        self.add(name="encoding")
        self.run_cli("remove", "encoding")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_ambiguous_short_path_rejected_without_edits(self):
        self.design("""
module top(); Bridge U_B0(); Bridge U_B1(); Sink U_D(); endmodule
module Bridge(); Producer U_C(); endmodule
module Producer(); wire data; endmodule
module Sink(); wire data; endmodule
""")
        baseline = self.snapshot()
        self.add("U_C.data", "U_D.data", name="ambiguous", ok=False)
        self.assertEqual(self.snapshot(), baseline)

    def test_new_destination_port(self):
        baseline = self.fixture()
        self.add(destination="top.U_D.new_input", name="newport")
        self.assertRegex(self.rtl(), r"input\s+(?:wire\s+)?\[7:0\]\s+new_input")
        self.compile_if_available()
        self.run_cli("remove", "newport")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_top_level_input_to_descendant(self):
        baseline = self.fixture()
        self.add("top.clk", "top.U_B.U_C.enable", name="enable")
        self.assertRegex(self.rtl(), r"input\s+(?:wire\s+)?enable")
        self.compile_if_available()
        self.run_cli("remove", "enable")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_descendant_to_new_top_level_output(self):
        baseline = self.fixture()
        self.add(destination="top.observed", name="observe")
        self.assertRegex(self.rtl(), r"output\s+(?:wire\s+)?\[7:0\]\s+observed")
        self.compile_if_available()
        self.run_cli("remove", "observe")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_same_module_connection(self):
        baseline = self.design("""
module top();
    wire [3:0] source_data;
    wire [3:0] target_data;
    assign source_data = 4'hA;
endmodule
""")
        self.add("top.source_data", "top.target_data", name="local")
        self.assertRegex(self.rtl(), r"assign\s+target_data\s*=")
        self.compile_if_available()
        self.run_cli("remove", "local")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_repeated_module_instances_are_isolated(self):
        baseline = self.design("""
module top();
    Producer U_C0();
    Producer U_C1();
    Consumer U_D0();
    Consumer U_D1();
endmodule
module Producer(); wire [7:0] data; assign data = 8'h42; endmodule
module Consumer(); wire [7:0] received; endmodule
""")
        self.add("top.U_C0.data", "top.U_D0.received", name="isolated")
        output = self.rtl()
        self.assertRegex(output, r"\bProducer\s+U_C1\s*\(")
        self.assertRegex(output, r"\bConsumer\s+U_D1\s*\(")
        producer_body = re.search(r"\bmodule\s+Producer\b.*?\bendmodule\b", output, re.S).group(0)
        consumer_body = re.search(r"\bmodule\s+Consumer\b.*?\bendmodule\b", output, re.S).group(0)
        self.assertNotIn("__ec_", producer_body)
        self.assertNotIn("__ec_", consumer_body)
        self.compile_if_available()
        self.run_cli("remove", "isolated")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_two_distinct_routes_and_remove_oldest_first(self):
        baseline = self.design("""
module top(); Producer U_C0(); Producer U_C1(); Consumer U_D0(); Consumer U_D1(); endmodule
module Producer(); wire [7:0] data; endmodule
module Consumer(); wire [7:0] received; endmodule
""")
        self.add("top.U_C0.data", "top.U_D0.received", name="first")
        self.add("top.U_C1.data", "top.U_D1.received", name="second")
        self.compile_if_available()
        self.run_cli("remove", "first")
        self.assertIn("second", self.run_cli("list").stdout)
        self.compile_if_available()
        self.run_cli("remove", "second")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_fanout_same_source_to_two_repeated_instances(self):
        baseline = self.design("""
module top(input wire clk); Consumer U_D0(); Consumer U_D1(); endmodule
module Consumer(); wire enable; endmodule
""")
        self.add("top.clk", "top.U_D0.enable", name="fanout0")
        self.add("top.clk", "top.U_D1.enable", name="fanout1")
        self.compile_if_available()
        self.run_cli("remove", "fanout1")
        self.run_cli("remove", "fanout0")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_change_replaces_route_and_remove_restores_baseline(self):
        baseline = self.fixture()
        self.add(name="editable")
        self.run_cli("change", "editable", "top.U_B.U_C.fifo_rd", "top.new_output")
        self.assertRegex(self.rtl(), r"output\s+(?:wire\s+)?\[7:0\]\s+new_output")
        self.compile_if_available()
        self.run_cli("remove", "editable")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_failed_change_preserves_existing_route(self):
        self.fixture()
        self.add(name="editable")
        baseline = self.snapshot()
        self.run_cli("change", "editable", "top.U_B.U_C.fifo_rd", "top.UNKNOWN.new_output", ok=False)
        self.assertEqual(self.snapshot(), baseline)

    def test_external_edit_is_not_overwritten_by_remove(self):
        self.fixture()
        self.add(name="protected")
        path = self.src / "top.v"
        with path.open("ab") as handle:
            handle.write(b"\n// An independent user edit.\n")
        baseline = self.snapshot()
        self.run_cli("remove", "protected", ok=False)
        self.assertEqual(self.snapshot(), baseline)

    def test_macro_packed_and_unpacked_dimensions_are_preserved(self):
        baseline = self.fixture("macro_arrays")
        self.add("top.U_B.U_C.payload", "top.U_D.received", name="matrix")
        output = self.rtl()
        packed = r"\[`EC_DATA_W-1:0\]\s*\[1:0\]"
        unpacked = r"\[0:`EC_ROWS-1\]\s*\[0:`EC_COLS-1\]"
        self.assertRegex(output, rf"output\s+(?:wire\s+)?signed\s+{packed}\s+\w+\s*{unpacked}")
        self.assertRegex(output, rf"input\s+(?:wire\s+)?signed\s+{packed}\s+\w+\s*{unpacked}")
        self.assertGreater(output.count("`EC_DATA_W"), 2)
        self.assertGreater(output.count("`EC_ROWS"), 2)
        self.compile_if_available()
        self.run_cli("remove", "matrix")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_macro_generate_fixture_packed_controls_and_multidimensional_payload(self):
        baseline = self.fixture("indexed_macros")
        self.add("top.lane_enable", "top.g_lane[i].U_LANE.enable", name="enable",
                 extra=("--mode", "indexed", "--lane-kind", "packed"))
        self.add("top.lane_data", "top.g_lane[i].U_LANE.payload", name="payload",
                 extra=("--mode", "indexed"))
        self.compile_if_available()
        self.run_cli("remove", "enable")
        self.compile_if_available()
        self.run_cli("remove", "payload")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_explicit_macro_width_for_new_ports(self):
        baseline = self.design("""
`define MY_WIDTH 6
`define MY_COUNT 2
module top(); Producer U_C(); Consumer U_D(); endmodule
module Producer(); wire signed [`MY_WIDTH-1:0][1:0] new_output [0:`MY_COUNT-1]; endmodule
module Consumer(); endmodule
""")
        self.add("top.U_C.new_output", "top.U_D.new_input", name="explicit", extra=(
            "--width", "[`MY_WIDTH-1:0][1:0]", "--unpacked", "[0:`MY_COUNT-1]", "--signed",
        ))
        output = self.rtl()
        self.assertIn("[`MY_WIDTH-1:0][1:0]", output)
        self.assertIn("[0:`MY_COUNT-1]", output)
        self.assertIn("signed", output)
        self.compile_if_available()
        self.run_cli("remove", "explicit")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_existing_input_port_is_bound(self):
        baseline = self.design("""
module top(); Producer U_C(); Consumer U_D(.data_in()); endmodule
module Producer(); wire [7:0] data; endmodule
module Consumer(input wire [7:0] data_in); endmodule
""")
        self.add("top.U_C.data", "top.U_D.data_in", name="port")
        self.assertRegex(self.rtl(), r"\.data_in\(\s*\w+\s*\)")
        self.compile_if_available()
        self.run_cli("remove", "port")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_occupied_input_rejected_unless_replace(self):
        baseline = self.design("""
module top(); Producer U_C(); Consumer U_D(.data_in(8'h00)); endmodule
module Producer(); wire [7:0] data; endmodule
module Consumer(input wire [7:0] data_in); endmodule
""")
        self.add("top.U_C.data", "top.U_D.data_in", name="port", ok=False)
        self.assertEqual(self.rtl_snapshot(), baseline)
        self.add("top.U_C.data", "top.U_D.data_in", name="port", extra=("--replace",))
        self.compile_if_available()
        self.run_cli("remove", "port")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_cbb_ports_use_metadata_without_source_file(self):
        baseline = self.design("""
module top(); Producer U_C(); ExternalIP U_IP(.data_in()); endmodule
module Producer(); wire [7:0] data; endmodule
""")
        metadata = {"modules": {"ExternalIP": {"ports": {"data_in": {"direction": "input", "width": "[7:0]", "unpacked": ""}}}}}
        config = Path(self.tmp.name) / "cbb.json"
        config.write_text(json.dumps(metadata), encoding="utf-8")
        self.add("top.U_C.data", "top.U_IP.data_in", name="cbb", extra=("--cbb", config))
        self.assertRegex(self.rtl(), r"\.data_in\(\s*\w+\s*\)")
        self.assertNotRegex(self.rtl(), r"module\s+ExternalIP\b")
        if self.compiler or SLANG:
            stub = Path(self.tmp.name) / "external_ip.v"
            stub.write_text("module ExternalIP(input wire [7:0] data_in); endmodule\n", encoding="utf-8")
            self.compile_if_available(extra_files=(stub,))
        self.run_cli("remove", "cbb")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_missing_source_rejected_without_edits(self):
        self.fixture()
        baseline = self.snapshot()
        self.add(source="top.U_B.U_C.unknown_source", name="missing", ok=False)
        self.assertEqual(self.snapshot(), baseline)

    def test_incompatible_destination_shape_fails_atomically(self):
        self.design("""
module top(); Producer U_C(); Consumer U_D(); endmodule
module Producer(); wire [7:0] data [0:2]; endmodule
module Consumer(); wire [3:0] received [0:2]; endmodule
""")
        baseline = self.snapshot()
        self.add("top.U_C.data", "top.U_D.received", name="mismatch", ok=False)
        self.assertEqual(self.snapshot(), baseline)

    def test_existing_destination_driver_is_not_duplicated(self):
        self.design("""
module top(); Producer U_C(); Consumer U_D(); endmodule
module Producer(); wire [7:0] data; endmodule
module Consumer(); wire [7:0] received; assign received = 8'hFF; endmodule
""")
        baseline = self.snapshot()
        self.add("top.U_C.data", "top.U_D.received", name="driven", ok=False)
        self.assertEqual(self.snapshot(), baseline)

    def test_cbb_as_source_uses_existing_output(self):
        baseline = self.design("""
module top(); ExternalIP U_IP(.data_out()); Consumer U_D(); endmodule
module Consumer(); wire [7:0] received; endmodule
""")
        metadata = {"modules": {"ExternalIP": {"ports": {"data_out": {"direction": "output", "width": "[7:0]"}}}}}
        config = Path(self.tmp.name) / "cbb.json"
        config.write_text(json.dumps(metadata), encoding="utf-8")
        self.add("top.U_IP.data_out", "top.U_D.received", name="cbb_source", extra=("--cbb", config))
        self.assertRegex(self.rtl(), r"\.data_out\(\s*\w+\s*\)")
        self.assertNotRegex(self.rtl(), r"module\s+ExternalIP\b")
        if self.compiler or SLANG:
            stub = Path(self.tmp.name) / "external_ip.v"
            stub.write_text("module ExternalIP(output wire [7:0] data_out); assign data_out = 8'hA5; endmodule\n", encoding="utf-8")
            self.compile_if_available(extra_files=(stub,))
        self.run_cli("remove", "cbb_source")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_generate_shared_broadcast(self):
        baseline = self.design("""
`define NUM_LANES 3
module top(input wire clk);
    genvar i;
    generate for (i = 0; i < `NUM_LANES; i = i + 1) begin : g
        Consumer u();
    end endgenerate
endmodule
module Consumer(); wire enable; endmodule
""")
        self.add("top.clk", "top.g[i].u.enable", name="broadcast", extra=("--mode", "shared"))
        self.compile_if_available()
        self.run_cli("remove", "broadcast")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_generate_indexed_parent_array(self):
        baseline = self.design("""
`define NUM_LANES 3
`define DATA_W 8
module top();
    wire [`DATA_W-1:0] data [0:`NUM_LANES-1];
    genvar i;
    generate for (i = 0; i < `NUM_LANES; i = i + 1) begin : g
        Consumer u();
    end endgenerate
endmodule
module Consumer(); wire [`DATA_W-1:0] received; endmodule
""")
        self.add("top.data", "top.g[i].u.received", name="lanes", extra=("--mode", "indexed"))
        self.assertRegex(self.rtl(), r"\.\w+\([^)]*\[i\][^)]*\)")
        self.compile_if_available()
        self.run_cli("remove", "lanes")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_generate_source_to_sink_uses_independent_lanes(self):
        baseline = self.design("""
`define NUM_LANES 3
module top();
    genvar i;
    generate for (i = 0; i < `NUM_LANES; i = i + 1) begin : g
        Producer source_inst();
        Consumer sink_inst();
    end endgenerate
endmodule
module Producer(); wire [7:0] data; assign data = 8'h11; endmodule
module Consumer(); wire [7:0] received; endmodule
""")
        self.add("top.g[i].source_inst.data", "top.g[i].sink_inst.received", name="independent", extra=("--mode", "indexed"))
        self.assertRegex(self.rtl(), r"\.\w+\([^)]*\[i\][^)]*\)")
        self.compile_if_available()
        self.run_cli("remove", "independent")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_generate_source_shared_mode_rejects_multiple_drivers(self):
        self.design("""
module top();
    genvar i;
    generate for (i = 0; i < 3; i = i + 1) begin : g
        Producer source_inst();
    end endgenerate
    Consumer U_D();
endmodule
module Producer(); wire [7:0] data; endmodule
module Consumer(); wire [7:0] received; endmodule
""")
        baseline = self.snapshot()
        self.add("top.g[i].source_inst.data", "top.U_D.received", name="drivers", extra=("--mode", "shared"), ok=False)
        self.assertEqual(self.snapshot(), baseline)

    def test_nested_generate_indexes_multidimensional_parent_array(self):
        baseline = self.design("""
`define ROWS 2
`define COLS 3
`define DATA_W 8
module top();
    wire [`DATA_W-1:0] data [0:`ROWS-1][0:`COLS-1];
    genvar i, j;
    generate for (i = 0; i < `ROWS; i = i + 1) begin : rows
        for (j = 0; j < `COLS; j = j + 1) begin : cols
            Consumer u();
        end
    end endgenerate
endmodule
module Consumer(); wire [`DATA_W-1:0] received; endmodule
""")
        self.add("top.data", "top.rows[i].cols[j].u.received", name="grid", extra=("--mode", "indexed"))
        self.assertRegex(self.rtl(), r"\.\w+\([^)]*\[i\]\s*\[j\][^)]*\)")
        self.compile_if_available()
        self.run_cli("remove", "grid")
        self.assertEqual(self.rtl_snapshot(), baseline)

    def test_concrete_generate_selection_rejected_without_partial_edits(self):
        self.design("""
module top(input wire clk);
    genvar i;
    generate for (i = 0; i < 3; i = i + 1) begin : g
        Consumer u();
    end endgenerate
endmodule
module Consumer(); wire enable; endmodule
""")
        baseline = self.snapshot()
        self.add("top.clk", "top.g[0].u.enable", name="concrete", ok=False)
        self.assertEqual(self.snapshot(), baseline)


if __name__ == "__main__":
    unittest.main(verbosity=2)
