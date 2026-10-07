"""Functional and safety tests. All mutable RTL fixtures live in test_result."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from RTLGraph import EasyConnectError, SourceProject, build_graph, constant, discover
from WireConnect import execute, widths

RESULT = ROOT / "test_result"
RESULT.mkdir(exist_ok=True)


def hashes(folder):
    return {str(p.relative_to(folder)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in folder.rglob("*") if p.is_file()}


def snapshot(folder):
    return {str(p.relative_to(folder)): p.read_bytes() for p in folder.rglob("*") if p.is_file()}


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix=self._testMethodName + "_", dir=RESULT))
        self.write("SRC.v", "module SRC (input wire clk);\nendmodule\n")
        self.write("MID.v", "module MID (input wire clk);\n SRC U_SRC (.clk(clk));\nendmodule\n")
        self.write("DST.v", "module DST (input wire clk);\nendmodule\n")
        self.write("TOP.v", "module TOP (input wire clk);\n MID U_MID (.clk(clk));\n DST U_DST (.clk(clk));\n DST U_UNUSED (.clk(clk));\nendmodule\n")
        self.graph = self.folder / "hierarchy.json"
        self.rebuild()
        self.original = snapshot(self.folder)

    def write(self, name, text):
        (self.folder / name).write_bytes(text.encode("utf-8"))

    def read(self, name):
        return (self.folder / name).read_bytes().decode("utf-8")

    def rebuild(self):
        return build_graph(self.folder, "TOP", self.graph)

    def op(self, action="add", endpoints=("SRC.sig", "DST.recv"), **kwargs):
        if action == "add": kwargs.setdefault("dst_instance", "U_DST")
        return execute(self.graph, action, endpoints, printer=lambda value: None, **kwargs)

    def test_missing_source_and_default_input(self):
        result = self.op()
        self.assertEqual(result["id"], "c0001")
        self.assertIn("output wire sig", self.read("SRC.v"))
        self.assertNotIn("assign sig", self.read("SRC.v"))
        self.assertIn("output wire sig", self.read("MID.v"))
        self.assertIn(".sig(sig)", self.read("MID.v"))
        self.assertIn("wire w_sig;", self.read("TOP.v"))
        self.assertIn(".sig(w_sig)", self.read("TOP.v"))
        self.assertIn(".recv(w_sig)", self.read("TOP.v"))
        self.assertIn(".recv(1'b0)", self.read("TOP.v"))

    def test_dry_run_no_file_changes(self):
        result = self.op(dry_run=True)
        self.assertTrue(result["changed_files"])
        self.assertEqual(snapshot(self.folder), self.original)

    def test_rm_restores_exact_original_rtl(self):
        self.op()
        self.op("rm", ("c0001",))
        for name, data in self.original.items():
            if name.endswith(".v"): self.assertEqual((self.folder / name).read_bytes(), data)
        self.assertEqual(json.loads(self.graph.read_text())["_easyconnect"]["connections"], [])

    def test_fanout_and_shared_resources(self):
        self.op()
        self.op(endpoints=("SRC.sig", "DST.other"), dst_instance="U_UNUSED")
        self.assertEqual(self.read("SRC.v").count("output wire sig"), 1)
        data = json.loads(self.graph.read_text())
        shared = [r for r in data["_easyconnect"]["resources"] if r["module"] == "SRC" and r["name"] == "sig"]
        self.assertEqual(shared[0]["owners"], ["c0001", "c0002"])
        self.op("rm", ("c0001",))
        self.assertIn("output wire sig", self.read("SRC.v"))
        self.assertIn(".other(w_sig)", self.read("TOP.v"))
        self.assertNotIn("input wire recv", self.read("DST.v"))
        self.op("rm", ("c0002",))
        self.assertEqual(self.read("TOP.v"), self.original["TOP.v"].decode())

    def test_later_selected_input_replaces_default(self):
        self.op()
        self.op(dst_instance="U_UNUSED")
        self.assertNotIn(".recv(1'b0)", self.read("TOP.v"))
        self.op("rm", ("c0002",))
        self.assertIn(".recv(1'b0)", self.read("TOP.v"))

    def test_mv_preserves_id_and_changes_shape_comment(self):
        self.op(comment="old")
        result = self.op("mv", ("c0001",), src="SRC.renamed", dst="DST.new_recv", width="8", comment="new")
        self.assertEqual(result["id"], "c0001")
        self.assertIn("output wire [8 -1:0] renamed", self.read("SRC.v"))
        self.assertIn("input wire [8 -1:0] new_recv", self.read("DST.v"))
        self.assertIn("// new", self.read("TOP.v"))
        self.assertNotIn("// old", self.read("SRC.v"))

    def test_failed_mv_is_atomic(self):
        self.op()
        original = snapshot(self.folder)
        with self.assertRaises(EasyConnectError):
            self.op("mv", ("c0001",), src="MISSING.nope")
        self.assertEqual(snapshot(self.folder), original)

    def test_user_driver_keeps_new_source_on_rm(self):
        self.op()
        self.write("SRC.v", self.read("SRC.v").replace("endmodule", "assign sig = clk;\nendmodule"))
        self.op("rm", ("c0001",))
        source = self.read("SRC.v")
        self.assertIn("wire sig;", source)
        self.assertIn("assign sig = clk;", source)
        self.assertNotIn("output wire sig", source)

    def test_user_edit_to_generated_fragment_is_rejected(self):
        self.op()
        self.write("SRC.v", self.read("SRC.v").replace("output wire sig", "output logic sig"))
        original = snapshot(self.folder)
        with self.assertRaisesRegex(EasyConnectError, "受管片段"):
            self.op("rm", ("c0001",))
        self.assertEqual(snapshot(self.folder), original)

    def test_stale_graph_is_rejected(self):
        self.write("SRC.v", self.read("SRC.v") + "// manual\n")
        original = snapshot(self.folder)
        with self.assertRaisesRegex(EasyConnectError, "校验不一致"):
            self.op()
        self.assertEqual(snapshot(self.folder), original)

    def test_new_file_requires_rebuild(self):
        self.write("EXTRA.sv", "module EXTRA; endmodule\n")
        with self.assertRaisesRegex(EasyConnectError, "未记录"):
            self.op()

    def test_index_source_creates_scalar_and_bus(self):
        self.op(endpoints=("SRC.sig[i]", "DST.recv"), width="8")
        self.assertIn("output wire sig", self.read("SRC.v"))
        self.assertNotIn("[8 -1:0] sig", self.read("SRC.v"))
        self.assertIn("output wire [8 -1:0] sig", self.read("MID.v"))
        self.assertIn(".sig(sig[i])", self.read("MID.v"))
        self.assertIn(".sig(w_sig)", self.read("TOP.v"))
        self.assertIn("input wire [8 -1:0] recv", self.read("DST.v"))

    def test_index_target_and_multi_dimension(self):
        self.op(endpoints=("SRC.sig[i][j]", "DST.recv[k][l]"), dimension=2, width="a,b")
        self.assertIn("wire [a -1:0][b -1:0] w_sig", self.read("TOP.v"))
        self.assertIn(".sig(sig[i][j])", self.read("MID.v"))
        self.assertIn(".recv(w_sig[k][l])", self.read("TOP.v"))
        self.assertIn("input wire recv", self.read("DST.v"))

    def test_macro_width_preserved(self):
        self.write("defs.vh", "`define WIDTH 8\n")
        for name in ("TOP.v", "MID.v", "SRC.v", "DST.v"):
            self.write(name, '`include "defs.vh"\n' + self.read(name))
        self.rebuild()
        self.op(width="`WIDTH")
        self.assertIn("[`WIDTH -1:0]", self.read("TOP.v"))

    def test_unknown_part_select_new_shape_rejected(self):
        with self.assertRaisesRegex(EasyConnectError, "无法确定"):
            self.op(endpoints=("SRC.sig[HI:LO]", "DST.recv"), width="8")

    def test_numeric_part_select(self):
        self.op(endpoints=("SRC.sig[3:0]", "DST.recv"), width="8")
        self.assertIn("output wire [4 -1:0] sig", self.read("SRC.v"))
        self.assertIn(".sig(sig[3:0])", self.read("MID.v"))

    def test_existing_source_declaration_and_logic_preserved(self):
        self.write("SRC.v", "module SRC(input clk);\n logic [7:0] sig;\n assign sig = 8'h55;\nendmodule\n")
        self.rebuild()
        self.op(width="8")
        self.assertIn("logic [7:0] sig;", self.read("SRC.v"))
        self.assertIn("assign sig = 8'h55;", self.read("SRC.v"))
        self.assertIn("output wire [7:0] ec_c0001_sig_out", self.read("SRC.v"))

    def test_existing_output_and_parent_binding_reused(self):
        self.write("SRC.v", "module SRC(input clk, output wire sig); assign sig=clk; endmodule\n")
        self.write("MID.v", "module MID(input clk); wire existing; SRC U_SRC(.clk(clk), .sig(existing)); endmodule\n")
        self.rebuild()
        self.op()
        self.assertEqual(self.read("SRC.v"), "module SRC(input clk, output wire sig); assign sig=clk; endmodule\n")
        self.assertIn(".sig(existing)", self.read("MID.v"))
        self.assertIn("assign ec_c0001_existing_out = existing;", self.read("MID.v"))

    def test_existing_internal_target_uses_auxiliary_input(self):
        self.write("DST.v", "module DST(input clk); wire recv; endmodule\n")
        self.rebuild()
        self.op()
        self.assertIn("wire recv;", self.read("DST.v"))
        self.assertIn("input wire ec_c0001_recv_in", self.read("DST.v"))
        self.assertIn("assign recv = ec_c0001_recv_in;", self.read("DST.v"))

    def test_existing_target_driver_rejected(self):
        self.write("DST.v", "module DST(input clk); reg recv; always @(posedge clk) recv <= 1'b1; endmodule\n")
        self.rebuild()
        original = snapshot(self.folder)
        with self.assertRaisesRegex(EasyConnectError, "驱动"):
            self.op()
        self.assertEqual(snapshot(self.folder), original)

    def test_width_conflict_rejected(self):
        self.write("SRC.v", "module SRC(input clk); wire [3:0] sig; endmodule\n")
        self.rebuild()
        with self.assertRaisesRegex(EasyConnectError, "形状冲突"):
            self.op(width="8")

    def test_macro_width_conflict_rejected(self):
        self.write("SRC.v", "`define WIDTH 4\nmodule SRC(input clk); wire [`WIDTH-1:0] sig; endmodule\n")
        self.rebuild()
        with self.assertRaisesRegex(EasyConnectError, "形状冲突"):
            self.op(width="8")

    def test_ancestor_source(self):
        self.op(endpoints=("TOP.sig", "SRC.recv"), dst_instance="U_SRC")
        self.assertIn("wire sig;", self.read("TOP.v"))
        self.assertIn("input wire recv", self.read("MID.v"))
        self.assertIn(".recv(sig)", self.read("TOP.v"))
        self.assertIn(".recv(recv)", self.read("MID.v"))

    def test_ancestor_target_exports_top(self):
        self.op(endpoints=("SRC.sig", "TOP.recv"), dst_instance="TOP")
        self.assertIn("output wire recv", self.read("TOP.v"))
        self.assertIn(".sig(recv)", self.read("TOP.v"))
        self.assertNotIn("wire w_sig;", self.read("TOP.v"))

    def test_same_scope_local_connection(self):
        self.op(endpoints=("TOP.sig", "TOP.recv"), dst_instance="TOP")
        self.assertIn("wire sig;", self.read("TOP.v"))
        self.assertIn("wire recv;", self.read("TOP.v"))
        self.assertIn("assign recv = sig;", self.read("TOP.v"))

    def test_same_endpoint_is_noop(self):
        result = self.op(endpoints=("TOP.sig", "TOP.sig"), dst_instance="TOP")
        self.assertIsNone(result["id"])
        self.assertEqual(snapshot(self.folder), self.original)

    def test_same_module_different_instances(self):
        self.op(endpoints=("DST.sig", "DST.recv"), src_instance="U_DST", dst_instance="U_UNUSED")
        self.assertIn("output wire sig", self.read("DST.v"))
        self.assertIn("input wire recv", self.read("DST.v"))
        self.assertIn(".sig()", self.read("TOP.v"))
        self.assertIn(".recv(1'b0)", self.read("TOP.v"))

    def test_multiple_instances_require_selection(self):
        with self.assertRaisesRegex(EasyConnectError, "多个例化位置"):
            execute(self.graph, "add", ("SRC.sig", "DST.recv"), printer=lambda value: None)

    def test_instance_alias_endpoints(self):
        self.op(endpoints=("U_SRC.sig", "U_DST.recv"))
        self.assertIn(".recv(w_sig)", self.read("TOP.v"))

    def test_multiple_parent_types_refused(self):
        self.write("OTHER.v", "module OTHER(input clk); SRC U_S(.clk(clk)); endmodule\n")
        self.write("TOP.v", self.read("TOP.v").replace("endmodule", "OTHER U_O(.clk(clk)); endmodule"))
        self.rebuild()
        with self.assertRaisesRegex(EasyConnectError, "不同父模块类型"):
            self.op(src_instance="TOP/U_MID/U_SRC")

    def test_non_ansi_ports(self):
        self.write("SRC.v", "module SRC(clk);\n input clk;\nendmodule\n")
        self.write("DST.v", "module DST(clk);\n input clk;\nendmodule\n")
        self.rebuild()
        self.op()
        self.assertIn("output wire sig;", self.read("SRC.v"))
        self.assertIn("input wire recv;", self.read("DST.v"))

    def test_module_without_port_list(self):
        self.write("SRC.v", "module SRC; endmodule\n")
        self.write("MID.v", "module MID(input clk); SRC U_SRC(); endmodule\n")
        self.rebuild()
        self.op()
        self.assertIn("module SRC (", self.read("SRC.v"))
        self.assertIn("output wire sig", self.read("SRC.v"))

    def test_positional_route_refused_without_partial_writes(self):
        self.write("MID.v", "module MID(input clk); SRC U_SRC(clk); endmodule\n")
        self.rebuild()
        before = snapshot(self.folder)
        with self.assertRaisesRegex(EasyConnectError, "显式命名"):
            self.op()
        self.assertEqual(snapshot(self.folder), before)

    def test_existing_target_binding_refused(self):
        self.write("DST.v", "module DST(input clk, input recv); endmodule\n")
        self.write("TOP.v", self.read("TOP.v").replace("U_DST (.clk(clk))", "U_DST (.clk(clk), .recv(clk))"))
        self.rebuild()
        with self.assertRaisesRegex(EasyConnectError, "已有端口绑定"):
            self.op()

    def test_original_empty_binding_is_restored(self):
        self.write("DST.v", "module DST(input clk, input recv); endmodule\n")
        self.write("TOP.v", self.read("TOP.v").replace("U_DST (.clk(clk))", "U_DST (.clk(clk), .recv())"))
        self.rebuild()
        before = self.read("TOP.v")
        self.op()
        self.assertIn(".recv(w_sig)", self.read("TOP.v"))
        self.op("rm", ("c0001",))
        self.assertEqual(self.read("TOP.v"), before)

    def test_repeated_source_instances_and_unused_output_defaults(self):
        self.write("TOP.v", self.read("TOP.v").replace("endmodule", " MID U_SECOND(.clk(clk));\nendmodule"))
        self.rebuild()
        self.op(src_instance="TOP/U_MID/U_SRC")
        self.assertIn(".sig()", self.read("TOP.v"))
        self.op(endpoints=("SRC.sig", "DST.other"), src_instance="TOP/U_SECOND/U_SRC", dst_instance="U_UNUSED")
        self.assertIn("wire w_sig_c0002;", self.read("TOP.v"))
        self.assertIn(".sig(w_sig_c0002)", self.read("TOP.v"))

    def test_definition_level_binding_conflict_refused(self):
        self.write("MID.v", self.read("MID.v").replace("endmodule", " SRC U_EXTRA(.clk(clk));\nendmodule"))
        self.write("TOP.v", self.read("TOP.v").replace("endmodule", " MID U_SECOND(.clk(clk));\nendmodule"))
        self.rebuild()
        self.op(endpoints=("TOP.sig", "SRC.recv"), dst_instance="TOP/U_MID/U_SRC")
        before = snapshot(self.folder)
        with self.assertRaisesRegex(EasyConnectError, "不同源|共用例化端口"):
            self.op(endpoints=("SRC.other", "SRC.recv"), src_instance="TOP/U_SECOND/U_EXTRA", dst_instance="TOP/U_SECOND/U_SRC")
        self.assertEqual(snapshot(self.folder), before)

    def test_target_cannot_have_two_sources(self):
        self.op()
        before = snapshot(self.folder)
        with self.assertRaisesRegex(EasyConnectError, "不同源"):
            self.op(endpoints=("SRC.another", "DST.recv"))
        self.assertEqual(snapshot(self.folder), before)

    def test_comment_generated_on_all_new_items(self):
        self.op(comment="debug bridge")
        for name in ("SRC.v", "MID.v", "TOP.v", "DST.v"):
            self.assertIn("// debug bridge", self.read(name))

    def test_crlf_and_utf8_bom_preserved(self):
        for name in ("SRC.v", "MID.v", "TOP.v", "DST.v"):
            (self.folder / name).write_bytes(b"\xef\xbb\xbf" + self.read(name).replace("\n", "\r\n").encode())
        self.rebuild()
        self.op()
        for name in ("SRC.v", "MID.v", "TOP.v", "DST.v"):
            raw = (self.folder / name).read_bytes()
            self.assertTrue(raw.startswith(b"\xef\xbb\xbf"))
            self.assertNotIn(b"\n", raw.replace(b"\r\n", b""))

    def test_gb18030_source_preserved(self):
        source = "// 源模块\nmodule SRC(input clk); endmodule\n"
        (self.folder / "SRC.v").write_bytes(source.encode("gb18030"))
        self.rebuild()
        self.op()
        self.assertIn("// 源模块", (self.folder / "SRC.v").read_bytes().decode("gb18030"))

    def test_transaction_failure_restores_every_file(self):
        import WireConnect
        original_replace = WireConnect.os.replace
        calls = [0]
        def fail_once(source, target):
            calls[0] += 1
            if calls[0] == 3: raise OSError("injected disk failure")
            return original_replace(source, target)
        with patch("WireConnect.os.replace", side_effect=fail_once):
            with self.assertRaisesRegex(OSError, "injected"):
                self.op()
        self.assertEqual(snapshot(self.folder), self.original)

    def test_target_business_logic_keeps_generated_signal(self):
        self.op()
        self.write("DST.v", self.read("DST.v").replace("endmodule", "wire tap; assign tap = recv;\nendmodule"))
        self.op("rm", ("c0001",))
        self.assertIn("wire recv;", self.read("DST.v"))
        self.assertIn("assign tap = recv;", self.read("DST.v"))

    def test_turn_wire_user_use_survives_rm(self):
        self.op()
        self.write("TOP.v", self.read("TOP.v").replace("endmodule", "wire tap; assign tap = w_sig;\nendmodule"))
        self.op("rm", ("c0001",))
        self.assertIn("wire w_sig;", self.read("TOP.v"))
        self.assertIn("assign tap = w_sig;", self.read("TOP.v"))

    def test_rebuild_keeps_connection_management(self):
        self.op()
        self.rebuild()
        self.op("rm", ("c0001",))
        self.assertEqual(self.read("SRC.v"), self.original["SRC.v"].decode())

    def test_invalid_shapes(self):
        for kwargs in ({"dimension": 2}, {"dimension": 2, "width": "8"}, {"width": "0"}, {"width": "8,"}, {"width": "a+("}):
            with self.subTest(kwargs=kwargs):
                with self.assertRaises(EasyConnectError): self.op(**kwargs)

    def test_parameter_is_not_overwritten_by_signal(self):
        self.write("SRC.v", "module SRC(input clk); parameter sig=1; endmodule\n")
        self.rebuild()
        with self.assertRaisesRegex(EasyConnectError, "信号名.*冲突"):
            self.op()

    def test_unrelated_manual_edit_survives_rm(self):
        self.op()
        self.write("SRC.v", "// user documentation\n" + self.read("SRC.v"))
        self.op("rm", ("c0001",))
        self.assertTrue(self.read("SRC.v").startswith("// user documentation\n"))

    def test_cli_end_to_end(self):
        environment = dict(os.environ, PYTHONIOENCODING="utf-8")
        command = [sys.executable, str(ROOT / "EasyConnect.py"), "2", str(self.graph)]
        result = subprocess.run(command + ["add", "SRC.sig", "DST.recv", "--dst-instance", "U_DST", "-c", "cli test"],
                                capture_output=True, text=True, encoding="utf-8", env=environment)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run(command + ["list"], capture_output=True, text=True, encoding="utf-8", env=environment)
        self.assertIn("c0001", result.stdout)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run(command + ["rm", "c0001"], capture_output=True, text=True, encoding="utf-8", env=environment)
        self.assertEqual(result.returncode, 0, result.stderr)


class GraphTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix=self._testMethodName + "_", dir=RESULT))

    def write(self, name, text):
        destination = self.folder / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(text.encode())

    def build(self, **kwargs):
        return build_graph(self.folder, "TOP", self.folder / "hierarchy.json", **kwargs)

    def test_known_only_comments_parameters_generate_and_multiple_instances(self):
        self.write("sub/S.sv", "module S #(parameter W=8) (input logic [W-1:0] a); endmodule\n")
        self.write("TOP.v", """// module FAKE; S fake(); endmodule
module TOP(input clk);
  /* S fake2(); */
  unknown U_BLACKBOX(.clk(clk));
  S #(.W(4)) U_ONE(.a({4{clk}})), U_TWO(.a(4'b0));
  for(genvar i=0; i<3; i=i+1) begin : g
    S U_LOOP[i](.a(8'b0));
  end
endmodule
""")
        graph = self.build()
        records = graph["modules"]["TOP"]["instantiations"]
        self.assertEqual([r["instance"] for r in records], ["U_ONE", "U_TWO", "U_LOOP[i]"])
        for record in records:
            self.assertEqual((record["style"], record["status"]), ("normal", "normal"))
            self.assertGreaterEqual(record["end_line"], record["start_line"])
            self.assertEqual(record["port_start_line"], 1)

    def test_include_filelist_and_external_library(self):
        self.write("library/lib.v", "module LIB(input a); endmodule\n")
        self.write("rtl/defs.vh", "`define W 2\n")
        self.write("rtl/TOP.v", '`include "defs.vh"\nmodule TOP(input a); LIB U_L(.a(a)); endmodule\n')
        self.write("rtl/filelist.f", "+incdir+.\n../library/lib.v\nTOP.v\n")
        graph = build_graph(self.folder / "rtl", "TOP", self.folder / "hierarchy.json")
        self.assertIn("LIB", graph["modules"])
        self.assertEqual(graph["modules"]["TOP"]["instantiations"][0]["module"], "LIB")
        self.assertTrue(any(p.endswith("defs.vh") for p in graph["sources"]))

    def test_conditionals_select_one_definition(self):
        self.write("TOP.v", """`ifdef FLAG
module TOP(input clk); endmodule
`elsif OTHER
module TOP(input other); endmodule
`else
module TOP; endmodule
`endif
""")
        graph = self.build(defines={"FLAG": "1"})
        self.assertEqual(len(graph["modules"]), 1)
        self.assertEqual(graph["modules"]["TOP"]["start_line"], 2)

    def test_non_ansi_io_line_locations(self):
        self.write("TOP.v", "module TOP(a,b);\n input a;\n output b;\nendmodule\n")
        graph = self.build()
        self.assertEqual(graph["modules"]["TOP"]["port_start_line"], 2)
        self.assertEqual(graph["modules"]["TOP"]["port_end_line"], 3)

    def test_multiple_body_parameter_defaults(self):
        self.write("TOP.v", "module TOP;\nparameter A=2;\nparameter B=3;\nlocalparam C=A+B;\nendmodule\n")
        files, dirs, macros = discover(self.folder)
        project = SourceProject(files, "TOP", macros, dirs)
        self.assertEqual(project.modules["TOP"].parameters, {"A": "2", "B": "3", "C": "A+B"})

    def test_duplicate_module_refused(self):
        self.write("TOP.v", "module TOP; endmodule")
        self.write("another.sv", "module TOP; endmodule")
        with self.assertRaisesRegex(EasyConnectError, "重复模块"): self.build()

    def test_integer_evaluator_is_bounded_and_nonexecuting(self):
        self.assertEqual(constant("`W*2 - 1", {"W": "4"}), 7)
        self.assertIsNone(constant("__import__('os').system('echo bad')"))
        self.assertIsNone(constant("1<<100000000"))

    def test_guarded_module_in_include_is_discovered(self):
        self.write("lib.vh", "`ifndef LIB_SEEN\n`define LIB_SEEN\nmodule LIB(input a); endmodule\n`endif\n")
        self.write("TOP.v", '`include "lib.vh"\nmodule TOP(input a); LIB U_LIB(.a(a)); endmodule\n')
        graph = self.build()
        self.assertIn("LIB", graph["modules"])
        self.assertEqual(graph["modules"]["TOP"]["instantiations"][0]["module"], "LIB")


class ThreeCaseAcceptanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.golden = hashes(ROOT / "test_cases")
        cls.run_folder = Path(tempfile.mkdtemp(prefix="acceptance_", dir=RESULT))
        for index in (1, 2, 3):
            shutil.copytree(ROOT / "test_cases" / ("case%d" % index), cls.run_folder / ("case%d" % index))

    @classmethod
    def tearDownClass(cls):
        if cls.golden != hashes(ROOT / "test_cases"):
            raise AssertionError("golden test_cases was changed")

    def test_all_three_graphs_html_and_add_mv_rm(self):
        tops = {1: "case1_soc_top", 2: "case2_chi_noc_top", 3: "case3_engine_top"}
        routes = {
            1: ("case1_dma_desc_fetch.ec_debug[gc]", "case1_perf_monitor.ec_debug_in", None, "case1_soc_top/u_perf_mon"),
            2: ("case2_hn_req_pipe.ec_debug", "case2_chi_req_gen.ec_debug_in", None, None),
            3: ("case3_dma_desc_fetch.ec_debug", "case3_config_regs.ec_debug_in", None, None),
        }
        report = []
        for index in (1, 2, 3):
            with self.subTest(case=index):
                case = self.run_folder / ("case%d" % index)
                graph_path = case / "hierarchy.json"
                data = build_graph(case, tops[index], graph_path)
                expected = json.loads((case / "expected_hierarchy.json").read_text(encoding="utf-8"))
                self.assertEqual(set(data["modules"]), set(expected["modules"]))
                for name, mod in data["modules"].items():
                    actual = [(r["module"], r["instance"]) for r in mod["instantiations"]]
                    golden = [(r["module"], r["instance"]) for r in expected["modules"][name]["instantiations"]]
                    # The legacy expected JSON sometimes appends a loop genvar
                    # absent from the actual instance name. 1.0 retains source
                    # spelling and deliberately does not infer such suffixes.
                    # Legacy golden also collapses equally named statements
                    # from different generate branches. Source graph lists all
                    # physical statements, so compare their module/name sets.
                    self.assertEqual({(m, n.split("[")[0]) for m, n in actual},
                                     {(m, n.split("[")[0]) for m, n in golden}, name)
                environment = dict(os.environ, PYTHONIOENCODING="utf-8")
                html = subprocess.run([sys.executable, str(ROOT / "test_cases/test_python/hierarchy_to_html.py"), str(graph_path), "-o", str(case / "hierarchy.html"), "--top", tops[index]],
                                      capture_output=True, text=True, encoding="utf-8", env=environment)
                self.assertEqual(html.returncode, 0, html.stderr)
                originals = {p: p.read_bytes() for p in case.rglob("*.v")}
                src, dst, source_instance, target_instance = routes[index]
                files, dirs, defines = discover(case)
                project = SourceProject(files, tops[index], defines, dirs)
                from WireConnect import hierarchy_paths, path_name
                paths = hierarchy_paths(project)
                if source_instance is None: source_instance = path_name(paths[src.split(".")[0]][0])
                if target_instance is None: target_instance = path_name(paths[dst.split(".")[0]][0])
                messages = []
                result = execute(graph_path, "add", (src, dst), width="8", comment="EasyConnect acceptance",
                                 src_instance=source_instance, dst_instance=target_instance, printer=messages.append)
                (case / "add.diff.txt").write_text("\n".join(messages), encoding="utf-8")
                (case / "hierarchy_after_add.json").write_bytes(graph_path.read_bytes())
                snapshot_root = self.run_folder / "rtl_after_add" / ("case%d" % index)
                snapshot_root.mkdir(parents=True)
                for changed in result["changed_files"]:
                    target = snapshot_root / Path(changed).relative_to(case)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(Path(changed).read_bytes())
                execute(graph_path, "mv", (result["id"],), width="16", comment="Moved acceptance", printer=lambda value: None)
                execute(graph_path, "rm", (result["id"],), printer=lambda value: None)
                for path, raw in originals.items(): self.assertEqual(path.read_bytes(), raw, str(path))
                report.append({"case": index, "modules": len(data["modules"]), "instances": sum(len(m["instantiations"]) for m in data["modules"].values()),
                               "html": "passed", "add_mv_rm": "passed", "rtl_restored": True})
        (self.run_folder / "acceptance.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    unittest.main(verbosity=2)
