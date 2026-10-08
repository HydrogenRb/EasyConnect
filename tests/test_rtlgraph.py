"""Parser regressions independent of the three sample projects."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from RTLGraph import EasyConnectError, SourceProject, build_graph, discover


class RTLGraphTests(unittest.TestCase):
    def setUp(self):
        (ROOT / "test_result").mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="regex_graph_", dir=ROOT / "test_result")
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.write("leaf.v", "module CHILD(input a, output b); endmodule\n")

    def write(self, name, text):
        (self.folder / name).write_bytes(text.encode("utf-8"))

    def build(self, **options):
        return build_graph(self.folder, "TOP", self.folder / "graph.json", **options)

    def records(self):
        return self.build()["modules"]["TOP"]["instantiations"]

    def test_offline_without_site_packages(self):
        self.write("top.v", "module TOP; CHILD u(.a(1'b0), .b()); endmodule\n")
        with patch("socket.socket", side_effect=AssertionError("network access")):
            self.assertEqual(len(self.records()), 1)
        process = subprocess.run([sys.executable, "-S", str(ROOT / "EasyConnect.py"), "1",
                                  str(self.folder), "TOP", "-o", str(self.folder / "cli.json")],
                                 input="", capture_output=True, encoding="utf-8")
        self.assertEqual(process.returncode, 0, process.stderr)

    def test_multiple_modules_and_nested_connection_lists(self):
        self.write("top.v", """module UNUSED; endmodule
module TOP(input a);
 CHILD #(.W(fn(2, 3))) u0(.a(fn(a, {2{a}})), .b()), u1(.a(a), .b());
endmodule
""")
        graph = self.build()
        records = graph["modules"]["TOP"]["instantiations"]
        self.assertEqual([r["instance"] for r in records], ["u0", "u1"])
        self.assertEqual(records[0]["connections"], {"a": "fn(a, {2{a}})", "b": ""})
        self.assertEqual(graph["modules"]["CHILD"]["ports"], ["a", "b"])

    def test_names_in_comments_strings_and_longer_identifiers_are_not_instances(self):
        self.write("top.v", """module TOP;
 // CHILD comment(); module FAKE; endmodule
 /* CHILD comment2(); */
 initial $display("module FAKE; CHILD fake(); endmodule ]");
 CHILD_SUFFIX u_no();
 CHILD u_yes(.a("broken ) ] { text"), .b());
endmodule
""")
        records = self.records()
        self.assertEqual([r["instance"] for r in records], ["u_yes"])
        self.assertEqual(records[0]["connections"]["a"], '"broken ) ] { text"')

    def test_macro_continuation_and_inactive_branch_do_not_need_balanced_brackets(self):
        self.write("top.v", r"""`define OPEN(x) (x \
  + (1
`ifdef UNUSED
module BAD(];
`endif
module TOP;
 CHILD u(.a(0), .b());
endmodule
""")
        self.assertEqual([r["instance"] for r in self.records()], ["u"])

    def test_escaped_identifiers_containing_keywords(self):
        self.write("escaped.v", r"module \box.module (input a); endmodule" + "\n")
        self.write("top.v", r"module TOP; \box.module \u.endmodule (.a(0)); endmodule" + "\n")
        record = self.records()[0]
        self.assertEqual((record["module"], record["instance"]), (r"\box.module", r"\u.endmodule"))

    def test_unrelated_body_is_not_compiled(self):
        self.write("top.v", "module TOP;\n `OPEN(foo\n CHILD u(.a(0), .b());\nendmodule\n")
        self.assertEqual(len(self.records()), 1)

    def test_attributes_array_suffix_and_wildcard_event(self):
        self.write("top.v", """(* keep = "true" *) module TOP((* keep = "true" *) input a);
 always @(*) begin end
 (* keep = 1 *) CHILD u [0:fn(2,3)] (.a(a), .b());
endmodule
""")
        graph = self.build()
        self.assertEqual(graph["modules"]["TOP"]["ports"], ["a"])
        self.assertEqual(graph["modules"]["TOP"]["instantiations"][0]["instance"], "u[0:fn(2,3)]")

    def test_positional_and_implicit_bindings_are_not_editable_named_bindings(self):
        self.write("top.v", "module TOP; CHILD u0(fn(1,2), {2{1'b0}}); CHILD u1(.a, .*); endmodule\n")
        records = self.records()
        self.assertEqual(records[0]["connections"], ["fn(1,2)", "{2{1'b0}}"])
        self.assertFalse(records[0]["named_ports"])
        self.assertFalse(records[1]["named_ports"])

    def test_error_names_the_file_module_line_column_and_character(self):
        self.write("padding.v", "//" + "x" * 514046 + "\nmodule PADDING; endmodule\n")
        self.write("top.v", "// first line\r\nmodule TOP;\r\n CHILD u(.a({1]), .b());\r\nendmodule\r\n")
        with self.assertRaises(EasyConnectError) as caught:
            self.build()
        message = str(caught.exception)
        self.assertIn(str(self.folder / "top.v") + ":3:15 [module TOP]", message)
        self.assertIn("括号不匹配: ]", message)
        self.assertIn("CHILD u(.a({1])", message)
        self.assertIn("^", message)
        self.assertFalse((self.folder / "graph.json").exists())

    def test_unclosed_header_and_duplicate_connection_are_located(self):
        for text, expected in (("module TOP(input a; endmodule", "括号未闭合"),
                               ("module TOP; CHILD u(.a(0), .a(1)); endmodule", "重复例化端口"),
                               ("module TOP; CHILD u(.a(0)), ; endmodule", "缺少实例名"),
                               ("module TOP; CHILD u(.a(0)) endmodule", "缺少逗号或分号")):
            with self.subTest(expected=expected):
                self.write("top.v", text)
                with self.assertRaisesRegex(EasyConnectError, expected) as caught:
                    self.build()
                self.assertIn("[module TOP]", str(caught.exception))

    def test_missing_include_and_bad_directive_are_located(self):
        for text, expected in (('`include "absent.vh"\nmodule TOP; endmodule', "include"),
                               ('`ifdef\nmodule TOP; endmodule', "缺少宏名"),
                               ('`else\nmodule TOP; endmodule', "不匹配")):
            with self.subTest(expected=expected):
                self.write("top.v", text)
                with self.assertRaisesRegex(EasyConnectError, expected) as caught:
                    self.build()
                self.assertIn(str(self.folder / "top.v") + ":1:1", str(caught.exception))

    def test_string_parameters_and_function_local_declarations(self):
        self.write("top.v", """module TOP #(parameter LABEL="semi; module FAKE", W=8)(input a);
 function automatic f(input hidden); logic local_only; f=hidden; endfunction
 wire [W-1:0] bus;
 CHILD u(.a(a), .b());
endmodule
""")
        files, dirs, defines = discover(self.folder)
        mod = SourceProject(files, "TOP", defines, dirs).modules["TOP"]
        self.assertEqual(mod.parameters, {"LABEL": '"semi; module FAKE"', "W": "8"})
        self.assertEqual(set(mod.declarations), {"a", "bus"})


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    unittest.main(verbosity=2)
