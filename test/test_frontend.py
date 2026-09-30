"""Offset preservation, grouped types, macro arrays and hierarchy regression tests."""
import tempfile
from pathlib import Path
import unittest

from easyconnect.rtl import Design, RTLException, mask


class FrontendTests(unittest.TestCase):
    def design(self, text):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        return Design(temp.name, {"design.v": text})

    def test_ansi_grouped_macro_multidimensional(self):
        raw = """`include "widths.vh"
module A # (parameter W=8) (
 input logic signed [`W-1:0][1:0] a [0:`N-1][2:0], b [4:0],
 output logic [W-1:0] c, d,
 input clk
);
 wire [`LANES-1:0][7:0] internal_a [0:2], internal_b [0:3];
 always_ff @(posedge clk) begin
   c <= a[0];
   d <= b;
 end
endmodule : A
"""
        module = self.design(raw).modules["A"]
        self.assertEqual(module.ports["a"].width, "[`W-1:0][1:0]")
        self.assertEqual(module.ports["a"].unpacked, "[0:`N-1][2:0]")
        self.assertEqual(module.ports["b"].width, "[`W-1:0][1:0]")
        self.assertEqual(module.ports["b"].unpacked, "[4:0]")
        self.assertTrue(module.ports["b"].signed)
        self.assertEqual(module.ports["d"].width, "[W-1:0]")
        self.assertEqual(module.ports["clk"].width, "")
        self.assertEqual(module.signals["internal_b"].unpacked, "[0:3]")
        self.assertEqual(module.parameters, {"W": "8"})
        self.assertTrue({"c", "d"}.issubset(module.driven))
        self.assertEqual(raw[module.name_start:module.name_end], "A")
        self.assertEqual(raw[module.ports_open], "(")
        self.assertEqual(raw[module.ports_close], ")")
        self.assertEqual(raw[module.end - len("endmodule : A"):module.end], "endmodule : A")
        self.assertFalse(module.unsafe)

    def test_nonansi_and_no_parentheses(self):
        modules = self.design("""module A(a,b);
 input signed [7:0] a;
 output [7:0] b;
 reg [7:0] b;
 always @* b = a;
endmodule
module Empty; endmodule
""").modules
        module = modules["A"]
        self.assertFalse(module.ansi)
        self.assertTrue(module.ports["a"].signed)
        self.assertEqual(module.ports["b"].kind, "reg")
        self.assertEqual(module.ports["b"].direction, "output")
        self.assertIn("b", module.driven)
        self.assertIsNone(modules["Empty"].ports_open)

    def test_scopes_instances_parameters_and_connections(self):
        raw = """module A #(parameter N=4) (input logic [3:0] bus);
 genvar i;
 generate
 for (i=0; i<N; i=i+1) begin : lane
   CBB #(.W(`W), .N(N)) first (.a(bus[i]), .b(), .clk), second (.a(bus[i]), .*);
 end
 endgenerate
 begin : outer
   B inst (.bus(bus));
 end
endmodule
module B(input [3:0] bus); endmodule
"""
        module = self.design(raw).modules["A"]
        first, second, third = module.instances
        self.assertEqual(first.full_name, "lane[i].first")
        self.assertEqual(first.parameters, {"W": "`W", "N": "N"})
        self.assertEqual(first.connections, {"a": "bus[i]", "b": "", "clk": "clk"})
        self.assertEqual(first.shorthand, {"clk"})
        self.assertEqual(first.loops[0].lower, "0")
        self.assertEqual(first.loops[0].upper, "N")
        self.assertEqual(first.loops[0].step, 1)
        self.assertEqual(first.scopes, ("lane[i]",))
        self.assertTrue(second.wildcard)
        self.assertEqual(first.type_start, second.type_start)
        self.assertEqual(first.declaration_count, 2)
        self.assertEqual(raw[first.name_start:first.name_end], "first")
        self.assertTrue(raw[first.member_start:first.member_end].startswith("first ("))
        self.assertEqual(raw[first.connection_spans["a"][0]:first.connection_spans["a"][1]], "bus[i]")
        self.assertEqual(third.full_name, "outer.inst")

    def test_loop_inclusive_descending_nested(self):
        module = self.design("""module A;
for (genvar i=3; i>=0; --i) begin : g
 for (genvar j=1; j<=2; j+=1) begin : h
  Unknown u();
 end
end
endmodule""").modules["A"]
        instance = module.instances[0]
        self.assertEqual(instance.full_name, "g[i].h[j].u")
        self.assertEqual(instance.loops[0].upper, "(0)-1")
        self.assertEqual(instance.loops[0].step, -1)
        self.assertEqual(instance.loops[1].upper, "(2)+1")

    def test_ignores_procedural_calls_and_functions(self):
        module = self.design("""module A(input clk);
 function automatic logic f(input logic a);
   f = a;
 endfunction
 always @(posedge clk) begin
   if (clk) $display("looks // like comments");
   else begin task_call(1); end
 end
 initial begin
   for (int i=0;i<2;i++) task_call(i);
 end
 B real_instance();
endmodule
""").modules["A"]
        self.assertEqual([i.name for i in module.instances], ["real_instance"])

    def test_positional_and_instance_arrays(self):
        instance = self.design("module A; B #(4, `N) u[0:3](a,b); endmodule").modules["A"].instances[0]
        self.assertTrue(instance.positional)
        self.assertTrue(instance.positional_parameters)
        self.assertEqual(instance.arrays, "[0:3]")
        self.assertEqual(instance.parameters, {"0": "4", "1": "`N"})

    def test_conditionals_are_unsafe(self):
        module = self.design("""`ifdef ENABLE
module A;
 if (1) begin : yes
   B u();
 end else begin : no
   C v();
 end
endmodule
`endif
""").modules["A"]
        self.assertTrue(any("preprocessing" in x for x in module.unsafe))
        self.assertTrue(any("conditional generate" in x for x in module.unsafe))
        self.assertEqual([i.full_name for i in module.instances], ["yes.u", "no.v"])

    def test_typedef_ports_are_flagged(self):
        module = self.design("module A(input custom_t p, output integer q); endmodule").modules["A"]
        self.assertTrue(module.ports["p"].unsupported)
        self.assertTrue(module.ports["q"].unsupported)

    def test_duplicate_modules_and_unbalanced_rejected(self):
        with self.assertRaisesRegex(RTLException, "duplicate module"):
            self.design("module A; endmodule module A; endmodule")
        with self.assertRaisesRegex(RTLException, "unmatched"):
            self.design("module A(input a; endmodule")

    def test_mask_preserves_crlf_and_macro_dimensions(self):
        raw = '`define W 8\r\nmodule A(input [`W-1:0] a); // c\r\nendmodule\r\n'
        masked = mask(raw)
        self.assertEqual(len(masked), len(raw))
        self.assertEqual([i for i, ch in enumerate(raw) if ch in "\r\n"],
                         [i for i, ch in enumerate(masked) if ch in "\r\n"])
        self.assertIn("[`W-1:0]", masked)
        self.assertEqual(self.design(raw).modules["A"].ports["a"].width, "[`W-1:0]")

    def test_child_output_connections_are_drivers(self):
        module = self.design("""module A(input clk);
 wire [3:0] a,b,c,d,e;
 wire index;
 B one(.source(a[index]), .unused(clk));
 B two({b,c}, clk);
 B three(.source, .unused(clk));
 wire source;
 C four(.*);
endmodule
module B(output source, input unused); endmodule
module C(output d, inout e, input index); endmodule
""").modules["A"]
        self.assertTrue({"a", "b", "c", "d", "e", "source"}.issubset(module.driven))
        self.assertNotIn("index", module.driven)
        self.assertNotIn("clk", module.driven)

    def test_comparison_is_not_a_driver(self):
        module = self.design("""module A(input a,b, output logic c);
 always_comb begin
   if (a <= b) c = 1;
   else c = 0;
 end
endmodule
""").modules["A"]
        self.assertEqual(module.driven, {"c"})

    def test_multiline_comments_and_functionlike_macro_width(self):
        raw = ("module A(\r\n"
               " input /* input declarations */ logic signed\r\n"
               " [`WIDTH(2)-1:0][1:0] // retained dimensions\r\n"
               " a /* memory */ [0:`N-1],\r\n"
               " b [0:`N-1] /* grouped port */\r\n"
               ");\r\nendmodule\r\n")
        module = self.design(raw).modules["A"]
        self.assertEqual(module.ports["b"].width, "[`WIDTH(2)-1:0][1:0]")
        self.assertEqual(module.ports["b"].unpacked, "[0:`N-1]")
        self.assertTrue(module.ports["b"].signed)
        self.assertEqual(module.text, raw)

    def test_unbracketed_macro_type_alias_is_flagged(self):
        module = self.design("module A(input `WIDTH_RANGE value); endmodule").modules["A"]
        self.assertTrue(module.ports["value"].unsupported)


if __name__ == "__main__":
    unittest.main()
